# Nginx image that can query the host’s Avahi daemon
FROM nginx:alpine

# avahi-tools → avahi-resolve-host-name
# dbus        → libavahi needs libdbus
RUN apk add --no-cache avahi-tools dbus

# Copy template and entrypoint
COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY entrypoint.sh       /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Replace default conf
RUN rm /etc/nginx/conf.d/default.conf \
    && ln -sf /etc/nginx/nginx.conf.template /etc/nginx/nginx.conf

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
