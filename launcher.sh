#!/usr/bin/env bash
HOSTS_FILE="/data/hosts.txt"
touch "$HOSTS_FILE"

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
  echo "  [ c ] Connect to a new host (user@host)"
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

        echo "Connecting to $NICKNAME ($TARGET)..."
        ssh -o StrictHostKeyChecking=no "$TARGET"
        read -rp "Session closed. Press Enter to return to menu..."
      else
        echo "Invalid selection."
        sleep 1
      fi
      ;;
    [cC])
      read -rp "Enter target (user@host): " NEW_TARGET
      NEW_TARGET="${NEW_TARGET#ssh }"
      NEW_TARGET="$(echo "$NEW_TARGET" | xargs)"

      if [ -n "$NEW_TARGET" ]; then
        read -rp "Save this host for future quick access? (y/n): " SAVE_CHOICE
        if [[ "$SAVE_CHOICE" =~ ^[Yy]$ ]]; then
          read -rp "Enter a nickname (or leave empty to use target): " NEW_NICKNAME
          NEW_NICKNAME="$(echo "$NEW_NICKNAME" | tr -d '|' | xargs)"
          [ -z "$NEW_NICKNAME" ] && NEW_NICKNAME="$NEW_TARGET"

          echo "${NEW_NICKNAME}|${NEW_TARGET}" >> "$HOSTS_FILE"
        fi

        echo "Connecting to $NEW_TARGET..."
        ssh -o StrictHostKeyChecking=no "$NEW_TARGET"
        read -rp "Session closed. Press Enter to return to menu..."
      fi
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
