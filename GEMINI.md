# Antigravity Rules for Web SSH Center

## ⚠️ MANDATORY RULE: Version Number Increment

Whenever ANY changes, bug fixes, security updates, or feature additions are made to this repository:
1. **You MUST increment the version number** in `VERSION` following SemVer (e.g. `1.1.0` -> `1.1.1` or `1.2.0`).
2. Keep the fallback `VERSION` constant in `launcher.sh` matching `VERSION`.
3. Keep `README.md` updated with relevant version notes.

The version number is loaded by `launcher.sh` from `/etc/webssh-version` (mounted from `./VERSION`) and displayed in the Web UI terminal banner and browser tab title.

---

## Security Invariants

- **CSWSH, DNS-Rebinding & Authentication**:
  - In `nginx/default.conf.template`, keep the exact `Host` allowlist (`localhost`, `127.0.0.1`, `[::1]`, `${WEBSSH_PUBLIC_HOST}`) and the exact full-`Origin` allowlist (scheme, host and port).
  - Never compare Origin against the request's own Host, never compare hostnames only, never allow private-LAN Host ranges, and never trust `X-Forwarded-Host` or `CF-Ray`.
  - Never use runtime Nginx variables inside `map` keys. Keep `NGINX_ENVSUBST_FILTER=^WEBSSH_`.
  - Keep `auth_basic` on `location /` (fail closed, `nginx/htpasswd` never committed).
  - Forward `$http_host` and strip `Authorization` toward ttyd. Block `Origin: null`.
  - Never document LAN-IP or `0.0.0.0` binds.
- **Input Sanitization**: Maintain `validate_and_parse_target` in `launcher.sh`. Prevent leading hyphens, leading/trailing dots, adjacent dots, and illegal characters in host/user/port.
- **Safe SSH Execution**: Always pass `--` to `ssh`, keep `-o EnableEscapeCommandline=no`, `-o ClearAllForwardings=yes`, `-o PermitLocalCommand=no`, `-o ForwardAgent=no`, and `-o HashKnownHosts=yes`.
- **Permissions**: Preserve `umask 077`, `0700` directories, and `0600` on credentials and data files.
- **Container Hardening**: Keep `no-new-privileges:true` on all services in `docker-compose.yml` and keep `.dockerignore` updated to prevent leaking private keys and `.env` secrets into the build context.
