#!/usr/bin/env bash
HOSTS_FILE="/data/hosts.txt"
touch "$HOSTS_FILE"

# Support mounted custom SSH keys and config if available
if [ -d "/data/.ssh" ] && [ ! -L "$HOME/.ssh" ] && [ ! -d "$HOME/.ssh" ]; then
  ln -s /data/.ssh "$HOME/.ssh"
fi

# Trap SIGINT in menu so pressing Ctrl+C does not crash the web session
trap 'continue' INT

connect_to_target() {
  local display_name="$1"
  local raw_target="$2"

  # Parse optional port (e.g. user@host:2222)
  local host_part="$raw_target"
  local port_part=""
  if [[ "$raw_target" =~ ^(.*):([0-9]+)$ ]]; then
    host_part="${BASH_REMATCH[1]}"
    port_part="${BASH_REMATCH[2]}"
  fi

  echo "Connecting to $display_name ($raw_target)..."

  # Reset SIGINT trap so Ctrl+C works normally during the SSH session
  trap - INT

  local ssh_opts=(-o StrictHostKeyChecking=accept-new)
  if [ -d "/data" ]; then
    ssh_opts+=(-o "UserKnownHostsFile=/data/known_hosts")
  fi

  if [ -n "$port_part" ]; then
    ssh "${ssh_opts[@]}" -p "$port_part" -- "$host_part"
  else
    ssh "${ssh_opts[@]}" -- "$host_part"
  fi

  # Restore SIGINT trap for the menu
  trap 'continue' INT

  echo ""
  read -rp "Session closed. Press Enter to return to menu..."
}

while true; do
  clear
  echo "========================================="
  echo "           SSH PROXY LAUNCHER            "
  echo "========================================="
  echo ""

  # Clean carriage returns and empty lines in-place
  sed -i 's/\r$//' "$HOSTS_FILE"
  sed -i '/^[[:space:]]*$/d' "$HOSTS_FILE"

  # Read saved entries into an array
  mapfile -t ENTRIES < "$HOSTS_FILE"
  INDEX=1

  if [ ${#ENTRIES[@]} -gt 0 ]; then
    echo "Saved Hosts:"
    for entry in "${ENTRIES[@]}"; do
      IFS="|" read -r NICKNAME TARGET <<< "$entry"
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
  read -rp "Select an option: " choice

  case "$choice" in
    [0-9]*)
      if [ "$choice" -ge 1 ] && [ "$choice" -le "${#ENTRIES[@]}" ]; then
        SELECTED_ENTRY="${ENTRIES[$((choice-1))]}"
        IFS="|" read -r NICKNAME TARGET <<< "$SELECTED_ENTRY"
        [ -z "$TARGET" ] && TARGET="$NICKNAME"

        # Validate stored target before execution
        if [[ "$TARGET" =~ ^- ]] || [[ "$TARGET" =~ [[:space:]] ]]; then
          echo "Error: Saved target contains invalid characters."
          sleep 2
          continue
        fi

        connect_to_target "$NICKNAME" "$TARGET"
      else
        echo "Invalid selection."
        sleep 1
      fi
      ;;
    [cC])
      read -rp "Enter target (user@host or user@host:port): " NEW_TARGET
      NEW_TARGET="${NEW_TARGET#ssh }"
      NEW_TARGET="$(echo "$NEW_TARGET" | tr -d '|\r\n' | xargs)"

      if [ -z "$NEW_TARGET" ]; then
        continue
      fi

      # Prevent argument injection or malformed targets
      if [[ "$NEW_TARGET" =~ ^- ]] || [[ "$NEW_TARGET" =~ [[:space:]] ]]; then
        echo "Error: Target cannot start with a hyphen (-) or contain spaces."
        sleep 2
        continue
      fi

      read -rp "Save this host for future quick access? (y/n): " SAVE_CHOICE
      if [[ "$SAVE_CHOICE" =~ ^[Yy]$ ]]; then
        read -rp "Enter a nickname (or leave empty to use target): " NEW_NICKNAME
        NEW_NICKNAME="$(echo "$NEW_NICKNAME" | tr -d '|\r\n' | xargs)"
        [ -z "$NEW_NICKNAME" ] && NEW_NICKNAME="$NEW_TARGET"

        echo "${NEW_NICKNAME}|${NEW_TARGET}" >> "$HOSTS_FILE"
      fi

      connect_to_target "$NEW_TARGET" "$NEW_TARGET"
      ;;
    [dD])
      if [ ${#ENTRIES[@]} -eq 0 ]; then
        echo "No saved hosts to delete."
        sleep 1
      else
        read -rp "Enter the number of the host to forget: " DEL_NUM
        if [[ "$DEL_NUM" =~ ^[0-9]+$ ]] && [ "$DEL_NUM" -ge 1 ] && [ "$DEL_NUM" -le "${#ENTRIES[@]}" ]; then
          # Delete precisely by line number
          sed -i "${DEL_NUM}d" "$HOSTS_FILE"
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

