#!/usr/bin/env bash
set -e

HOSTS_FILE="/data/hosts.txt"
mkdir -p /data 2>/dev/null || true
touch "$HOSTS_FILE" 2>/dev/null || true

# Support mounted custom SSH keys and config if available
if [ -d "/data/.ssh" ]; then
  if [ ! -e "$HOME/.ssh" ]; then
    ln -s /data/.ssh "$HOME/.ssh" 2>/dev/null || true
  fi
  # Fix key permissions if writable to avoid OpenSSH refusal
  chmod 700 /data/.ssh 2>/dev/null || true
  chmod 600 /data/.ssh/* 2>/dev/null || true
  chmod 644 /data/.ssh/*.pub /data/.ssh/known_hosts /data/.ssh/config 2>/dev/null || true
fi

# Signal handling:
# - Ignore Ctrl+C and Ctrl+Z in menu to prevent crashing or freezing web session
# - Clean exit on HUP/TERM
trap 'continue' INT
trap '' TSTP
trap 'exit 0' TERM HUP

# Validate and parse target into PARSED_USER, PARSED_HOST, PARSED_PORT
validate_and_parse_target() {
  local input="$1"
  PARSED_USER=""
  PARSED_HOST=""
  PARSED_PORT=""

  # Trim leading/trailing whitespace
  input="$(printf '%s' "$input" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  input="${input#ssh }"

  [ -z "$input" ] && return 1

  # Reject any characters outside allowed safe set:
  # Allowed: alphanumeric, '.', '-', '_', '@', ':', '[', ']'
  if [[ "$input" =~ [^a-zA-Z0-9._@:\[\]\-] ]]; then
    echo "Error: Target contains forbidden characters."
    return 1
  fi

  # Extract user if present
  local rest="$input"
  if [[ "$input" == *"@"* ]]; then
    PARSED_USER="${input%%@*}"
    rest="${input#*@}"

    # Ensure user is valid: alphanumeric/underscore/dot/dash, 1-64 chars, cannot start with hyphen
    if [ -z "$PARSED_USER" ] || [[ "$PARSED_USER" == *"@"* ]] || [[ "$PARSED_USER" =~ ^- ]] || [[ ! "$PARSED_USER" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,63}$ ]]; then
      echo "Error: Invalid username in target."
      return 1
    fi
  fi

  # Parse host and optional port from rest
  if [[ "$rest" =~ ^\[([0-9a-fA-F:]+)\]:([0-9]+)$ ]]; then
    # Bracketed IPv6 with port: [::1]:2222
    PARSED_HOST="${BASH_REMATCH[1]}"
    PARSED_PORT="${BASH_REMATCH[2]}"
  elif [[ "$rest" =~ ^\[([0-9a-fA-F:]+)\]$ ]]; then
    # Bracketed IPv6 without port: [::1]
    PARSED_HOST="${BASH_REMATCH[1]}"
  elif [[ "$rest" =~ ^([a-zA-Z0-9.-]+):([0-9]+)$ ]]; then
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
    echo "Error: Malformed host format."
    return 1
  fi

  # Validate host: must not start with '-', must not contain adjacent dots, must not be empty
  if [ -z "$PARSED_HOST" ] || [[ "$PARSED_HOST" =~ ^- ]] || [[ "$PARSED_HOST" == *..* ]]; then
    echo "Error: Invalid hostname."
    return 1
  fi

  # Validate port if present (1 - 65535)
  if [ -n "$PARSED_PORT" ]; then
    if [ "$PARSED_PORT" -lt 1 ] || [ "$PARSED_PORT" -gt 65535 ]; then
      echo "Error: Port must be between 1 and 65535."
      return 1
    fi
  fi

  return 0
}

# Sanitize nickname: allow only alphanumeric, space, dot, underscore, hyphen (max 32 chars)
sanitize_nickname() {
  local nick="$1"
  nick="$(printf '%s' "$nick" | tr -d '\r\n\t|' | tr -cd '[:alnum:] _.-')"
  printf '%.32s' "$nick"
}

connect_to_target() {
  local display_name="$1"

  # Target is already parsed into PARSED_USER, PARSED_HOST, PARSED_PORT
  local ssh_target="$PARSED_HOST"
  if [ -n "$PARSED_USER" ]; then
    ssh_target="${PARSED_USER}@${PARSED_HOST}"
  fi

  local full_display="$ssh_target"
  [ -n "$PARSED_PORT" ] && full_display="${ssh_target}:${PARSED_PORT}"

  echo "Connecting to $display_name ($full_display)..."

  # Reset SIGINT trap so Ctrl+C works normally during the SSH session
  trap - INT

  local ssh_opts=(
    -o StrictHostKeyChecking=accept-new
    -o HashKnownHosts=yes
    -o PermitLocalCommand=no
    -o ForwardAgent=no
    -o ForwardX11=no
    -o ConnectTimeout=15
    -o ServerAliveInterval=30
    -o ServerAliveCountMax=3
  )
  if [ -d "/data" ]; then
    ssh_opts+=(-o "UserKnownHostsFile=/data/known_hosts")
  fi

  if [ -n "$PARSED_PORT" ]; then
    ssh "${ssh_opts[@]}" -p "$PARSED_PORT" -- "$ssh_target" || true
  else
    ssh "${ssh_opts[@]}" -- "$ssh_target" || true
  fi

  # Restore traps for menu
  trap 'continue' INT
  trap '' TSTP

  echo ""
  if ! read -rp "Session closed. Press Enter to return to menu..."; then
    echo ""
    exit 0
  fi
}

while true; do
  clear
  echo "========================================="
  echo "           SSH PROXY LAUNCHER            "
  echo "========================================="
  echo ""

  # Read saved entries into an array cleanly in memory (avoiding race-prone sed -i)
  ENTRIES=()
  if [ -f "$HOSTS_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"
      [[ -z "${line//[[:space:]]/}" ]] && continue
      ENTRIES+=("$line")
    done < "$HOSTS_FILE"
  fi

  INDEX=1
  if [ ${#ENTRIES[@]} -gt 0 ]; then
    echo "Saved Hosts:"
    for entry in "${ENTRIES[@]}"; do
      IFS="|" read -r NICKNAME TARGET <<< "$entry"
      NICKNAME="$(sanitize_nickname "$NICKNAME")"
      if [ -n "$TARGET" ]; then
        printf "  [%2d] %-20s (%s)\n" "$INDEX" "$NICKNAME" "$TARGET"
      else
        printf "  [%2d] %s\n" "$INDEX" "$NICKNAME"
      fi
      ((INDEX++))
    done
    echo ""
  fi

  echo "Options:"
  echo "  [ c ] Connect to a new host (user@host or user@host:port)"
  echo "  [ d ] Delete / forget a saved host"
  echo "  [ q ] Quit / Restart terminal"
  echo ""
  if ! read -rp "Select an option: " choice; then
    echo ""
    exit 0
  fi

  case "$choice" in
    [1-9]*)
      if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [ "$choice" -le "${#ENTRIES[@]}" ]; then
        SELECTED_ENTRY="${ENTRIES[$(( 10#$choice - 1 ))]}"
        IFS="|" read -r NICKNAME TARGET <<< "$SELECTED_ENTRY"
        [ -z "$TARGET" ] && TARGET="$NICKNAME"

        if ! validate_and_parse_target "$TARGET"; then
          echo "Error: Saved target contains invalid characters or format."
          sleep 2
          continue
        fi

        connect_to_target "$NICKNAME"
      else
        echo "Invalid selection."
        sleep 1
      fi
      ;;
    [cC])
      if ! read -rp "Enter target (user@host or user@host:port): " NEW_TARGET; then
        echo ""
        exit 0
      fi

      if ! validate_and_parse_target "$NEW_TARGET"; then
        sleep 2
        continue
      fi

      # Construct canonical target string
      CANONICAL_TARGET="$PARSED_HOST"
      [ -n "$PARSED_USER" ] && CANONICAL_TARGET="${PARSED_USER}@${PARSED_HOST}"
      [ -n "$PARSED_PORT" ] && CANONICAL_TARGET="${CANONICAL_TARGET}:${PARSED_PORT}"

      if ! read -rp "Save this host for future quick access? (y/n): " SAVE_CHOICE; then
        echo ""
        exit 0
      fi

      if [[ "$SAVE_CHOICE" =~ ^[Yy]$ ]]; then
        if ! read -rp "Enter a nickname (or leave empty to use target): " NEW_NICKNAME; then
          echo ""
          exit 0
        fi
        NEW_NICKNAME="$(sanitize_nickname "$NEW_NICKNAME")"
        [ -z "$NEW_NICKNAME" ] && NEW_NICKNAME="$CANONICAL_TARGET"

        printf "%s|%s\n" "$NEW_NICKNAME" "$CANONICAL_TARGET" >> "$HOSTS_FILE"
      fi

      connect_to_target "$CANONICAL_TARGET"
      ;;
    [dD])
      if [ ${#ENTRIES[@]} -eq 0 ]; then
        echo "No saved hosts to delete."
        sleep 1
      else
        if ! read -rp "Enter the number of the host to forget: " DEL_NUM; then
          echo ""
          exit 0
        fi
        if [[ "$DEL_NUM" =~ ^[1-9][0-9]*$ ]] && [ "$DEL_NUM" -le "${#ENTRIES[@]}" ]; then
          del_idx=$(( 10#$DEL_NUM - 1 ))
          new_entries=()
          for i in "${!ENTRIES[@]}"; do
            if [ "$i" -ne "$del_idx" ]; then
              new_entries+=("${ENTRIES[$i]}")
            fi
          done
          if [ ${#new_entries[@]} -gt 0 ]; then
            printf "%s\n" "${new_entries[@]}" > "$HOSTS_FILE"
          else
            : > "$HOSTS_FILE"
          fi
          echo "Removed host #$DEL_NUM."
          sleep 1
        else
          echo "Invalid selection."
          sleep 1
        fi
      fi
      ;;
    [qQ])
      exit 0
      ;;
    *)
      echo "Invalid input."
      sleep 1
      ;;
  esac
done

