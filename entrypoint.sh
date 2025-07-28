#!/bin/ash
set -e

# ------------------------------------------------------------------
# 1.  Build the upstream block
# ------------------------------------------------------------------
CONF=/etc/nginx/conf.d/immich_ml_backends.conf

build_conf() {
  {
    echo "upstream immich_ml_backends {"
    echo "    zone immich_ml_backends 64k;"
    echo "    least_conn;"
    IFS=','

    for raw in $IMML_BACKENDS; do
      backend="$(echo "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      host="$(echo "$backend" | cut -d':' -f1)"
      port="$(echo "$backend" | cut -d':' -s -f2)"
      [ -z "$port" ] && port=3003

      # literal IP?
      if printf '%s\n' "$host" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        echo "    server $host:$port;"
        continue
      fi

      case "$host" in
        *.local)
          # Resolve via host Avahi *once*; later updates come from D‑Bus watcher
          ip="$(avahi-resolve-host-name -4 "$host" 2>/dev/null | awk '{print $2}' || true)"
          [ -n "$ip" ] && echo "    server $ip:$port; # $host"
          ;;
        *)
          # Normal DNS → let Nginx refresh itself
          echo "    server $host:$port resolve;"
          ;;
      esac
    done
    echo "}"
  }
}

# ------------------------------------------------------------------
# 2.  Install the initial config and start Nginx
# ------------------------------------------------------------------
build_conf > "$CONF"
nginx -g "daemon off;" &
NGINX_PID=$!

# ------------------------------------------------------------------
# 3.  Subscribe to Avahi for each *.local backend
# ------------------------------------------------------------------
watch_mdns() {
  local host=$1 port=$2

  # Convert ".local" to Avahi’s D‑Bus style: "mybox.local"
  dbus-monitor --system                                                     \
    "type='signal',sender='org.freedesktop.Avahi',                          \
     interface='org.freedesktop.Avahi.HostNameResolver',member='Found',     \
     arg2='$host'" | while read -r _; do
        # $5 is the address field in the signal’s argument list
        ip=$(echo "$REPLY" | awk '{print $6}')
        [ -z "$ip" ] && continue

        # Re‑write only the line for this host
        sed -i "s#^[[:space:]]*server.*$host.*#    server $ip:$port; # $host#" "$CONF"
        nginx -s reload
        echo "[$(date)] Avahi update: $host → $ip (Nginx reloaded)"
      done &
}

IFS=','

for raw in $IMML_BACKENDS; do
  backend="$(echo "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  host="$(echo "$backend" | cut -d':' -f1)"
  port="$(echo "$backend" | cut -d':' -s -f2)"
  [ -z "$port" ] && port=3003

  case "$host" in
    *.local) watch_mdns "$host" "$port" ;;
  esac
done

unset IFS
wait $NGINX_PID
