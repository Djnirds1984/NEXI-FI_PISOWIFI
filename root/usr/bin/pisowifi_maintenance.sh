#!/bin/sh

DB_FILE="/etc/pisowifi/pisowifi.db"

case "$1" in
    reboot)
        /sbin/reboot
        ;;
    cleanup_devices)
        NOW=$(date +%s)
        sqlite3 "$DB_FILE" "DELETE FROM devices WHERE mac NOT IN (SELECT mac FROM users WHERE (session_end > $NOW) OR (paused_time > 0));" 2>/dev/null || true
        ;;
esac
