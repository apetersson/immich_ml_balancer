#!/bin/sh

# Generate the Nginx upstream configuration dynamically
echo "upstream immich_ml_backends {" > /etc/nginx/conf.d/immich_ml_backends.conf
echo "    least_conn;" >> /etc/nginx/conf.d/immich_ml_backends.conf # Add least_conn here

# Save original IFS
OLDIFS=$IFS
# Set IFS to comma for splitting
IFS=','

# Iterate over the IMML_BACKENDS string, which will be split by IFS
for i in $IMML_BACKENDS; do
    # Remove leading/trailing whitespace from 'i' if any
    i=$(echo "$i" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # Split each address by colon to check for a custom port
    HOST=$(echo "$i" | cut -d':' -f1)
    PORT=$(echo "$i" | cut -d':' -s -f2)

    # If no port is specified, use the default 3003
    if [ -z "$PORT" ]; then
        PORT="3003"
    fi

    echo "    server $HOST:$PORT;" >> /etc/nginx/conf.d/immich_ml_backends.conf
done

# Restore original IFS
IFS=$OLDIFS

echo "}" >> /etc/nginx/conf.d/immich_ml_backends.conf

# Start Nginx
exec nginx -g "daemon off;"