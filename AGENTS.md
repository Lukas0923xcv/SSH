# AI Agent Guidelines & Development Rules

## ⚠️ MANDATORY RULE: Version Number Increment

Whenever ANY changes, bug fixes, security updates, or feature additions are made to this repository by an AI assistant:
1. **You MUST increment the version number** in the [VERSION](file:///VERSION) file according to Semantic Versioning (e.g., `1.1.0` -> `1.1.1` for bug fixes/patches, `1.2.0` for features, `2.0.0` for major overhauls).
2. Ensure the fallback version string in [launcher.sh](file:///launcher.sh) matches the new version in `VERSION`.
3. If applicable, mention the version bump in [README.md](file:///README.md).

The version number is loaded dynamically by [launcher.sh](file:///launcher.sh) from `/etc/webssh-version` (mounted from `./VERSION`) and displayed in the Web UI terminal banner and window title.

---

## Security Invariants (DO NOT VIOLATE)

1. **CSWSH Protection**:
   - In [nginx/default.conf](file:///nginx/default.conf), origin validation must compare the origin's host against `$http_host` using dynamic concatenation and backreference regexes.
   - Do NOT use variables directly in `map` keys (e.g. `~*^https?://$http_host$`), as Nginx `map` keys do not interpolate runtime variables.
   - Always forward `proxy_set_header Host $http_host;` so that backend origin checks (like `ttyd -O`) receive the correct port.
   - Disallow `Origin: null` (cross-origin sandboxed iframe attacks).

2. **Input Validation & Sanitization**:
   - In [launcher.sh](file:///launcher.sh), all target inputs must pass `validate_and_parse_target` before any SSH connection is attempted.
   - Hostnames must never start with a hyphen (`-`) or dot (`.`), end with a dot, or contain consecutive dots (`..`).
   - Usernames must be validated against `^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,63}$`.
   - Ports must be strictly numeric between 1 and 65535.
   - Nicknames stored in `/data/hosts.txt` must be strictly sanitized using `sanitize_nickname`.

3. **SSH Security Options**:
   - When invoking `ssh`, always use `--` before the target argument to prevent flag injection.
   - Keep `-o PermitLocalCommand=no`, `-o ForwardAgent=no`, `-o ForwardX11=no`, `-o ClearAllForwardings=yes`, `-o EnableEscapeCommandline=no`, and `-o HashKnownHosts=yes`.

4. **Permissions & Least Privilege**:
   - Keep `umask 077` in [launcher.sh](file:///launcher.sh).
   - Ensure sensitive files (`hosts.txt`, `known_hosts`, private keys) are set to `0600` and directories to `0700`.
   - Never remove `no-new-privileges:true` from container security options.
   - Maintain [.dockerignore](file:///.dockerignore) to prevent leaking keys and secrets into build contexts.
