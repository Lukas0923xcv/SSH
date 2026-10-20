#!/usr/bin/env bash

# Restrict file creation permissions (owner read/write only)
umask 077

# Resolve application version number
VERSION="1.4.1"
if [ -f "/etc/webssh-version" ]; then
  VERSION="$(tr -d '\r\n' < "/etc/webssh-version")"
elif [ -f "$(dirname "$0")/VERSION" ]; then
  VERSION="$(tr -d '\r\n' < "$(dirname "$0")/VERSION")"
fi
VERSION="${VERSION//[^a-zA-Z0-9.+-]/}"

HOSTS_FILE="/data/hosts.txt"
KNOWN_HOSTS_FILE="/data/known_hosts"
SSH_DIR="/data/.ssh"
KEY_FILE="$SSH_DIR/id_ed25519"
mkdir -p /data 2>/dev/null || true
chmod 700 /data 2>/dev/null || true
touch "$HOSTS_FILE" "$KNOWN_HOSTS_FILE" 2>/dev/null || true
chmod 600 "$HOSTS_FILE" "$KNOWN_HOSTS_FILE" 2>/dev/null || true

# Link /data/.ssh to ~/.ssh so ssh picks up mounted keys and config
link_ssh_dir() {
  if [ ! -e "$HOME/.ssh" ]; then
    ln -s "$SSH_DIR" "$HOME/.ssh" 2>/dev/null || true
  fi
}

# Support mounted custom SSH keys and config if available
if [ -d "$SSH_DIR" ]; then
  link_ssh_dir
  # Fix permissions: 700 on directories, 600 on files, 644 on public keys/configs
  chmod 700 "$SSH_DIR" 2>/dev/null || true
  find "$SSH_DIR" -type d -exec chmod 700 {} + 2>/dev/null || true
  find "$SSH_DIR" -type f -exec chmod 600 {} + 2>/dev/null || true
  chmod 644 "$SSH_DIR"/*.pub "$SSH_DIR/config" 2>/dev/null || true
  chmod 600 "$KNOWN_HOSTS_FILE" 2>/dev/null || true
fi

# Hardened options shared by ssh and ssh-copy-id
SSH_OPTS=(
  -o StrictHostKeyChecking=accept-new
  -o HashKnownHosts=yes
  -o PermitLocalCommand=no
  -o ForwardAgent=no
  -o ForwardX11=no
  -o ClearAllForwardings=yes
  -o EnableEscapeCommandline=no
  -o ConnectTimeout=15
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=3
  -o "UserKnownHostsFile=$KNOWN_HOSTS_FILE"
)

# ANSI colors, used sparingly: errors in red, confirmations in green
C_RESET=$'\033[0m'
C_RED=$'\033[31m'
C_GREEN=$'\033[32m'

info() { printf '%s\n' "$*"; }
ok()   { printf '%s%s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
err()  { printf '%sError: %s%s\n' "$C_RED" "$*" "$C_RESET"; }
hint() { printf '%s\n' "$*"; }

# Signal handling:
# - Ignore Ctrl+C and Ctrl+Z in menu to prevent crashing or freezing web session
# - Clean exit on HUP/TERM
menu_traps() {
  trap 'continue' INT
  trap '' TSTP
}
# While a child (ssh, ssh-keygen, ...) runs, Ctrl+C must reach the child but must not
# kill the launcher itself. A no-op handler (not '' and not '-') achieves exactly that.
child_traps() {
  trap ':' INT
}
menu_traps
trap 'exit 0' TERM HUP

# Safe prompt reader:
# Returns 0 on valid input
# Returns 130 on SIGINT (Ctrl+C), allowing caller to cleanly cancel back to menu without terminating session
# Exits 0 on EOF (client disconnected / closed tab)
prompt_read() {
  local prompt="$1"
  local var_name="$2"
  local val=""
  local rc=0

  read -rp "$prompt" val || rc=$?

  if [ "$rc" -eq 0 ]; then
    printf -v "$var_name" '%s' "$val"
    return 0
  elif [ "$rc" -gt 128 ]; then
    echo ""
    return 130
  else
    echo ""
    exit 0
  fi
}

pause() {
  echo ""
  prompt_read "Press Enter to return to menu..." _ || true
}

confirm() {
  local answer=""
  prompt_read "$1 (y/N): " answer || return 1
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# Trim leading/trailing whitespace without spawning subprocesses
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# Validate and parse target into PARSED_USER, PARSED_HOST, PARSED_PORT
validate_and_parse_target() {
  local input="$1"
  PARSED_USER=""
  PARSED_HOST=""
  PARSED_PORT=""

  # Trim leading/trailing whitespace and an optional leading "ssh " (pasted commands)
  input="$(trim "$input")"
  input="${input#ssh }"
  input="$(trim "$input")"

  [ -z "$input" ] && return 1

  # Reject any characters outside allowed safe set:
  # Allowed: alphanumeric, '.', '-', '_', '@', ':', '[', ']'
  local invalid_chars="[^]a-zA-Z0-9._@:[-]"
  if [[ "$input" =~ $invalid_chars ]]; then
    err "Target contains forbidden characters."
    return 1
  fi

  # Extract user if present
  local rest="$input"
  if [[ "$input" == *"@"* ]]; then
    PARSED_USER="${input%%@*}"
    rest="${input#*@}"

    # Ensure user is valid: alphanumeric/underscore/dot/dash, 1-64 chars, cannot start with hyphen
    if [ -z "$PARSED_USER" ] || [[ "$PARSED_USER" == *"@"* ]] || [[ "$PARSED_USER" =~ ^- ]] || [[ ! "$PARSED_USER" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,63}$ ]]; then
      err "Invalid username in target."
      return 1
    fi
  fi

  # Parse host and optional port from rest
  if [[ "$rest" =~ ^\[([0-9a-fA-F:]+)\]:([0-9]{1,5})$ ]]; then
    # Bracketed IPv6 with port: [::1]:2222
    PARSED_HOST="${BASH_REMATCH[1]}"
    PARSED_PORT="${BASH_REMATCH[2]}"
  elif [[ "$rest" =~ ^\[([0-9a-fA-F:]+)\]$ ]]; then
    # Bracketed IPv6 without port: [::1]
    PARSED_HOST="${BASH_REMATCH[1]}"
  elif [[ "$rest" =~ ^([a-zA-Z0-9.-]+):([0-9]{1,5})$ ]]; then
    # Hostname / IPv4 with port: host:2222 or 1.2.3.4:2222
    PARSED_HOST="${BASH_REMATCH[1]}"
    PARSED_PORT="${BASH_REMATCH[2]}"
  elif [[ "$rest" =~ ^[0-9a-fA-F:]+$ ]] && [[ "$rest" == *:* ]]; then
    # Unbracketed IPv6 without port: 2001:db8::1
    PARSED_HOST="$rest"
  elif [[ "$rest" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    # Regular hostname or IPv4 without port
    PARSED_HOST="$rest"
  else
    err "Malformed host format."
    return 1
  fi

  # Validate host: must not start with '-' or '.', must not end with '.', must not contain adjacent dots, must not be empty
  if [ -z "$PARSED_HOST" ] || [[ "$PARSED_HOST" =~ ^- ]] || [[ "$PARSED_HOST" =~ ^\. ]] || [[ "$PARSED_HOST" =~ \.$ ]] || [[ "$PARSED_HOST" == *..* ]]; then
    err "Invalid hostname."
    return 1
  fi

  # Validate port if present (1 - 65535)
  if [ -n "$PARSED_PORT" ]; then
    PARSED_PORT="$(( 10#$PARSED_PORT ))"
    if [ "$PARSED_PORT" -lt 1 ] || [ "$PARSED_PORT" -gt 65535 ]; then
      err "Port must be between 1 and 65535."
      return 1
    fi
  fi

  return 0
}

# Build SSH_DEST (user@host for ssh) and CANONICAL_TARGET (user@host[:port] for storage)
# from PARSED_*. IPv6 hosts are bracketed so a stored port survives re-parsing.
build_target_strings() {
  SSH_DEST="$PARSED_HOST"
  [ -n "$PARSED_USER" ] && SSH_DEST="${PARSED_USER}@${PARSED_HOST}"

  local host_part="$PARSED_HOST"
  [[ "$PARSED_HOST" == *:* ]] && host_part="[${PARSED_HOST}]"
  CANONICAL_TARGET="$host_part"
  [ -n "$PARSED_USER" ] && CANONICAL_TARGET="${PARSED_USER}@${host_part}"
  [ -n "$PARSED_PORT" ] && CANONICAL_TARGET="${CANONICAL_TARGET}:${PARSED_PORT}"

  PORT_ARGS=()
  [ -n "$PARSED_PORT" ] && PORT_ARGS=(-p "$PARSED_PORT")
}

# Sanitize nickname: allow only alphanumeric, space, dot, underscore, hyphen (max 32 chars, cannot start with hyphen)
sanitize_nickname() {
  local nick="$1"
  nick="${nick//[^a-zA-Z0-9 _.-]/}"
  while [[ "$nick" == [-\ ]* ]]; do
    nick="${nick:1}"
  done
  nick="${nick:0:32}"
  trim "$nick"
}

# Strip anything that is not a valid target character before echoing file content to the terminal
sanitize_display() {
  printf '%s' "${1//[^]a-zA-Z0-9._@:[-]/}"
}

# Read saved entries into ENTRIES cleanly in memory (avoiding race-prone sed -i)
load_entries() {
  ENTRIES=()
  [ -f "$HOSTS_FILE" ] || return 0
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [[ -z "${line//[[:space:]]/}" ]] && continue
    ENTRIES+=("$line")
  done < "$HOSTS_FILE"
}

# Split a "nickname|target" line into ENTRY_NICK / ENTRY_TARGET
split_entry() {
  IFS="|" read -r ENTRY_NICK ENTRY_TARGET <<< "$1"
  [ -z "$ENTRY_TARGET" ] && ENTRY_TARGET="$ENTRY_NICK"
  ENTRY_NICK="$(sanitize_nickname "$ENTRY_NICK")"
}

# Atomically replace hosts file with the given lines
write_entries() {
  local tmp_hosts
  if ! tmp_hosts="$(mktemp "${HOSTS_FILE}.XXXXXX" 2>/dev/null)"; then
    err "Could not write $HOSTS_FILE."
    return 1
  fi
  if [ $# -gt 0 ]; then
    printf "%s\n" "$@" > "$tmp_hosts"
  else
    : > "$tmp_hosts"
  fi
  chmod 600 "$tmp_hosts" 2>/dev/null || true
  if ! mv -f "$tmp_hosts" "$HOSTS_FILE"; then
    rm -f "$tmp_hosts" 2>/dev/null || true
    err "Could not write $HOSTS_FILE."
    return 1
  fi
}

# Is a number a valid 1-based index into ENTRIES?
is_entry_number() {
  [[ "$1" =~ ^[1-9][0-9]{0,4}$ ]] && [ "$1" -le "${#ENTRIES[@]}" ]
}

# Ask for a saved host number; sets PICKED_IDX and ENTRY_NICK / ENTRY_TARGET
pick_entry() {
  local num=""
  if [ ${#ENTRIES[@]} -eq 0 ]; then
    err "No saved hosts yet."
    sleep 1
    return 1
  fi
  prompt_read "$1" num || return 1
  if ! is_entry_number "$num"; then
    err "Invalid selection."
    sleep 1
    return 1
  fi
  PICKED_IDX=$(( 10#$num - 1 ))
  split_entry "${ENTRIES[$PICKED_IDX]}"
}

# Ask for a saved host number or a new target, then validate it into PARSED_*
read_target() {
  local input=""
  prompt_read "$1" input || return 1
  input="$(trim "$input")"
  if is_entry_number "$input"; then
    split_entry "${ENTRIES[$(( 10#$input - 1 ))]}"
    input="$ENTRY_TARGET"
  fi
  if ! validate_and_parse_target "$input"; then
    sleep 2
    return 1
  fi
  build_target_strings
}

connect_to_target() {
  local display_name="$1"

  # Target is already parsed into PARSED_USER, PARSED_HOST, PARSED_PORT
  build_target_strings

  echo ""
  if [ "$display_name" = "$CANONICAL_TARGET" ]; then
    printf 'Connecting to %s...\n\n' "$display_name"
  else
    printf 'Connecting to %s (%s)...\n\n' "$display_name" "$CANONICAL_TARGET"
  fi

  local rc=0
  child_traps
  ssh "${SSH_OPTS[@]}" "${PORT_ARGS[@]}" -- "$SSH_DEST" || rc=$?
  menu_traps

  echo ""
  if [ "$rc" -eq 130 ]; then
    info "Connection cancelled."
  elif [ "$rc" -eq 255 ]; then
    err "Connection failed (ssh exit code 255)."
    hint "Host key changed after a reinstall? Use [f] to forget the old key."
    hint "Using keys? Use [k] to create one and [i] to install it on the host."
  else
    info "Session closed."
  fi
  pause
}

# Connect to a new target (optionally pre-filled) and offer to save it
connect_new() {
  local target="$1"
  if [ -z "$target" ]; then
    prompt_read "Target (user@host or user@host:port): " target || return
  fi

  if ! validate_and_parse_target "$target"; then
    sleep 2
    return
  fi
  build_target_strings

  local entry already_saved=0
  for entry in "${ENTRIES[@]}"; do
    split_entry "$entry"
    if [ "$ENTRY_TARGET" = "$CANONICAL_TARGET" ]; then
      already_saved=1
      break
    fi
  done

  if [ "$already_saved" -eq 1 ]; then
    hint "Already saved as '$ENTRY_NICK'."
    connect_to_target "$ENTRY_NICK"
    return
  fi

  local display_name="$CANONICAL_TARGET"
  if confirm "Save this host for quick access?"; then
    local new_nickname=""
    prompt_read "Nickname (empty = use target): " new_nickname || return
    new_nickname="$(sanitize_nickname "$new_nickname")"
    [ -z "$new_nickname" ] && new_nickname="$CANONICAL_TARGET"

    printf "%s|%s\n" "$new_nickname" "$CANONICAL_TARGET" >> "$HOSTS_FILE"
    chmod 600 "$HOSTS_FILE" 2>/dev/null || true
    ok "Saved as '$new_nickname'."
    display_name="$new_nickname"
  fi

  connect_to_target "$display_name"
}

rename_entry() {
  pick_entry "Number of the host to rename: " || return
  local new_nickname=""
  prompt_read "New nickname for '$ENTRY_NICK': " new_nickname || return
  new_nickname="$(sanitize_nickname "$new_nickname")"
  if [ -z "$new_nickname" ]; then
    err "Nickname must not be empty."
    sleep 1
    return
  fi
  ENTRIES[PICKED_IDX]="${new_nickname}|${ENTRY_TARGET}"
  write_entries "${ENTRIES[@]}" && ok "Renamed to '$new_nickname'."
  sleep 1
}

delete_entry() {
  pick_entry "Number of the host to forget: " || return
  confirm "Really forget '$ENTRY_NICK' ($(sanitize_display "$ENTRY_TARGET"))?" || return
  local new_entries=() i
  for i in "${!ENTRIES[@]}"; do
    [ "$i" -ne "$PICKED_IDX" ] && new_entries+=("${ENTRIES[$i]}")
  done
  write_entries "${new_entries[@]}" && ok "Removed '$ENTRY_NICK'."
  sleep 1
}

# Create (if missing) and show the launcher's own SSH key
manage_key() {
  mkdir -p "$SSH_DIR" 2>/dev/null && chmod 700 "$SSH_DIR" 2>/dev/null
  link_ssh_dir

  if [ ! -f "$KEY_FILE" ]; then
    echo ""
    info "No key found – generating a new ed25519 key at $KEY_FILE."
    hint "A passphrase is optional; with one you will be asked for it on every connect."
    echo ""
    child_traps
    ssh-keygen -q -t ed25519 -a 64 -C "webssh@${HOSTNAME:-container}" -f "$KEY_FILE"
    menu_traps
    chmod 644 "$KEY_FILE.pub" 2>/dev/null || true
  fi

  echo ""
  if [ -f "$KEY_FILE.pub" ]; then
    printf 'Public key (select to copy):\n\n'
    printf '%s\n\n' "$(cat "$KEY_FILE.pub")"
    hint "Add it to ~/.ssh/authorized_keys on your servers, or use [i] to install it automatically."
  else
    err "No key was created."
  fi
  pause
}

# Install the launcher's public key on a host via ssh-copy-id
install_key() {
  if [ ! -f "$KEY_FILE.pub" ]; then
    err "No key yet. Use [k] to create one first."
    sleep 2
    return
  fi
  read_target "Host number or user@host[:port]: " || return

  echo ""
  local rc=0
  child_traps
  ssh-copy-id -i "$KEY_FILE.pub" "${SSH_OPTS[@]}" "${PORT_ARGS[@]}" -- "$SSH_DEST" || rc=$?
  menu_traps

  echo ""
  if [ "$rc" -eq 0 ]; then
    ok "Key installed on $CANONICAL_TARGET – future logins will not ask for a password."
  else
    err "ssh-copy-id failed (exit code $rc)."
  fi
  pause
}

# Remove a host's (changed) key from known_hosts
forget_host_key() {
  read_target "Host number or host[:port]: " || return

  local key_host="$PARSED_HOST"
  if [ -n "$PARSED_PORT" ] && [ "$PARSED_PORT" -ne 22 ]; then
    key_host="[${PARSED_HOST}]:${PARSED_PORT}"
  fi

  local out=""
  out="$(ssh-keygen -R "$key_host" -f "$KNOWN_HOSTS_FILE" 2>&1)"
  rm -f "${KNOWN_HOSTS_FILE}.old" 2>/dev/null || true
  chmod 600 "$KNOWN_HOSTS_FILE" 2>/dev/null || true

  if [[ "$out" == *"found"* ]]; then
    ok "Forgot stored key for $key_host. It will be re-learned on the next connect."
  else
    info "No stored key for $key_host."
  fi
  sleep 2
}

MENU_RULE="================================================="

draw_header() {
  local title="WEB SSH CENTER  v$VERSION"
  echo "$MENU_RULE"
  printf "%*s\n" $(( (${#MENU_RULE} + ${#title}) / 2 )) "$title"
  echo "$MENU_RULE"
  echo ""
}

draw_hosts() {
  echo "Saved Hosts:"
  if [ ${#ENTRIES[@]} -eq 0 ]; then
    echo "  (none yet - use [ c ] and choose to save the host)"
    echo ""
    return
  fi
  local index=1 entry
  for entry in "${ENTRIES[@]}"; do
    split_entry "$entry"
    printf "  [%2d] %-20s %s\n" "$index" "$ENTRY_NICK" "$(sanitize_display "$ENTRY_TARGET")"
    ((index++))
  done
  echo ""
}

draw_actions() {
  echo "Options:"
  echo "  [ c ] Connect to a new host"
  echo "  [ e ] Rename   [ d ] Delete   [ f ] Forget host key"
  echo "  [ k ] SSH key  [ i ] Install key on host"
  echo "  [ q ] Quit"
  echo ""
}

while true; do
  clear
  # Set terminal window title including version number
  printf '\033]0;Web SSH Center v%s\007' "$VERSION"

  load_entries
  draw_header
  draw_hosts
  draw_actions

  choice=""
  if ! prompt_read "Select an option: " choice; then
    continue
  fi
  choice="$(trim "$choice")"

  if [[ "$choice" =~ ^[0-9]+$ ]]; then
    if is_entry_number "$choice"; then
      split_entry "${ENTRIES[$(( 10#$choice - 1 ))]}"
      if ! validate_and_parse_target "$ENTRY_TARGET"; then
        err "Saved target contains invalid characters or format."
        sleep 2
        continue
      fi
      connect_to_target "$ENTRY_NICK"
    else
      err "Invalid selection."
      sleep 1
    fi
    continue
  fi

  case "$choice" in
    "")
      ;;
    [cC])
      connect_new ""
      ;;
    [eE])
      rename_entry
      ;;
    [dD])
      delete_entry
      ;;
    [kK])
      manage_key
      ;;
    [iI])
      install_key
      ;;
    [fF])
      forget_host_key
      ;;
    [qQ])
      exit 0
      ;;
    *[@.:]*)
      # Quick connect: user@host typed directly at the menu prompt
      connect_new "$choice"
      ;;
    *)
      err "Invalid input."
      sleep 1
      ;;
  esac
done
