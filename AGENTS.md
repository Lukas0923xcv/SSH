# AI Agent Guidelines & Development Rules

## ⚠️ MANDATORY RULE: Version Number Increment

Whenever ANY changes, bug fixes, security updates, or feature additions are made to this repository by an AI assistant:
1. **You MUST increment the version number** in the [VERSION](VERSION) file according to Semantic Versioning (e.g., `1.1.0` -> `1.1.1` for bug fixes/patches, `1.2.0` for features, `2.0.0` for major overhauls).
2. Ensure the fallback version string in [launcher.sh](launcher.sh) matches the new version in `VERSION`.
3. If applicable, mention the version bump in [README.md](README.md).

The version number is loaded dynamically by [launcher.sh](launcher.sh) from `/etc/webssh-version` (mounted from `./VERSION`) and displayed in the Web UI terminal banner and window title.

---

## Security Invariants (DO NOT VIOLATE)

1. **CSWSH, DNS-Rebinding & Authentication**:
   - [nginx/default.conf.template](nginx/default.conf.template) is rendered by the nginx image's envsubst entrypoint. Keep `NGINX_ENVSUBST_FILTER=^WEBSSH_` in `docker-compose.yml` so only `${WEBSSH_*}` values are substituted and Nginx variables stay intact.
   - The `Host` header (port stripped) must match an exact allowlist: `localhost`, `127.0.0.1`, `[::1]` and `${WEBSSH_PUBLIC_HOST}`. Never compare Origin against the request's own `Host`, because a rebound attacker domain controls both. Never allow private-LAN Host ranges.
   - The `Origin` header must match the FULL origin exactly (scheme + host + port): `https://${WEBSSH_PUBLIC_HOST}` or `http://<localhost|127.0.0.1|[::1]>:${WEBSSH_PORT}`. An absent Origin is allowed. Never compare hostnames only, never cross-allow loopback names on arbitrary ports, and never trust client-supplied headers such as `X-Forwarded-Host` or `CF-Ray`.
   - Do NOT use runtime Nginx variables in `map` keys; they are not interpolated. Template `${WEBSSH_*}` values are literal after rendering and are fine.
   - Keep `auth_basic` with `auth_basic_user_file /etc/nginx/webssh.htpasswd` on `location /`. It must fail closed when the file is missing, and the password must never be committed (`nginx/htpasswd` is ignored by git and docker).
   - Always forward `proxy_set_header Host $http_host;`, and strip `Authorization` before proxying to ttyd.
   - Disallow `Origin: null` (cross-origin sandboxed iframe attacks).
   - Never suggest binding to a LAN IP or `0.0.0.0` in documentation; tunnels must target `localhost:8888` on the same host.

2. **Input Validation & Sanitization**:
   - In [launcher.sh](launcher.sh), all target inputs must pass `validate_and_parse_target` before any SSH connection is attempted.
   - Hostnames must never start with a hyphen (`-`) or dot (`.`), end with a dot, or contain consecutive dots (`..`).
   - Usernames must be validated against `^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,63}$`.
   - Ports must be strictly numeric between 1 and 65535.
   - Nicknames stored in `/data/hosts.txt` must be strictly sanitized using `sanitize_nickname`.

3. **SSH Security Options**:
   - When invoking `ssh`, always use `--` before the target argument to prevent flag injection.
   - Keep `-o PermitLocalCommand=no`, `-o ForwardAgent=no`, `-o ForwardX11=no`, `-o ClearAllForwardings=yes`, `-o EnableEscapeCommandline=no`, and `-o HashKnownHosts=yes`.

4. **Permissions & Least Privilege**:
   - Keep `umask 077` in [launcher.sh](launcher.sh).
   - Ensure sensitive files (`hosts.txt`, `known_hosts`, private keys) are set to `0600` and directories to `0700`.
   - Never remove `no-new-privileges:true` from container security options.
   - Maintain [.dockerignore](.dockerignore) to prevent leaking keys and secrets into build contexts.
