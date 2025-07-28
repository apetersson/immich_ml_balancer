#!/bin/sh
set -e

CONF=/etc/nginx/conf.d/immich_ml_backends.conf

generate_conf() {
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
      if printf '%s\n' "$host" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        echo "    server $host:$port;"
        continue
      fi

      # DNS first
      ip="$(getent hosts "$host" | awk '{print $1; exit}' || true)"

      # Fallback to host Avahi via socket
      [ -z "$ip" ] && ip="$(avahi-resolve-host-name -4 "$host" 2>/dev/null | awk '{print $2}' || true)"

      if [ -n "$ip" ]; then
        echo "    server $ip:$port; # $host"
      else
        # Leave hostname for Nginx resolver (works for DNS names)
        echo "    server $host:$port resolve;"
      fi
    done

    echo "}"
  }
}

# initial start
generate_conf > "$CONF"
nginx -g "daemon off;" &
NGINX_PID=$!

# watch every 60 s
while true; do
  sleep 60
  TMP=$(mktemp)
  generate_conf > "$TMP"
  if ! cmp -s "$TMP" "$CONF"; then
    mv "$TMP" "$CONF"
    nginx -s reload
    echo "[$(date)] upstream list changed – nginx reloaded"
  else
    rm "$TMP"
  fi
done &

wait $NGINX_PID
