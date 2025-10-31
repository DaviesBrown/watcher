#!/bin/sh
set -e

# Determine backup pool based on active pool
if [ "$ACTIVE_POOL" = "blue" ]; then
    export BACKUP_POOL="green"
else
    export BACKUP_POOL="blue"
fi

echo "Configuring Nginx with ACTIVE_POOL=$ACTIVE_POOL and BACKUP_POOL=$BACKUP_POOL"

# Generate nginx.conf from template using envsubst
envsubst '${ACTIVE_POOL} ${BACKUP_POOL}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# Validate the configuration
nginx -t

# Display the generated configuration for debugging
echo "Generated Nginx Configuration:"
cat /etc/nginx/nginx.conf

# Start Nginx in foreground
exec nginx -g 'daemon off;'
