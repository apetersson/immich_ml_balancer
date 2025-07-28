# Use a minimal Nginx image
FROM nginx:alpine

# Copy the Nginx template and entrypoint script
COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Make the entrypoint script executable
RUN chmod +x /usr/local/bin/entrypoint.sh

# Remove default Nginx configuration and link our template
RUN rm /etc/nginx/conf.d/default.conf     && ln -sf /etc/nginx/nginx.conf.template /etc/nginx/nginx.conf

# Expose the port Nginx listens on
EXPOSE 80

# Set the entrypoint script to run when the container starts
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
