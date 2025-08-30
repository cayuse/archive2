# Bucardo Configuration Fixes Required

## Problem Analysis
Bucardo is working perfectly, but the CLI tool defaults to localhost instead of reading .bucardorc properly.

## Solutions Needed

### 1. Fix Dockerfile.bucardo
Add a bucardo command wrapper that automatically uses correct connection parameters:

```dockerfile
# Add at end of Dockerfile.bucardo before CMD
RUN echo '#!/bin/bash' > /usr/local/bin/bucardo-cli && \
    echo 'exec /usr/bin/bucardo --dbhost=${BUCARDO_LOCAL_DB_HOST:-db} --dbport=${BUCARDO_LOCAL_DB_PORT:-5432} --dbname=${BUCARDO_LOCAL_DB_NAME:-bucardo} --dbuser=${BUCARDO_LOCAL_DB_USER:-bucardo} "$@"' >> /usr/local/bin/bucardo-cli && \
    chmod +x /usr/local/bin/bucardo-cli && \
    ln -sf /usr/local/bin/bucardo-cli /usr/local/bin/bucardo
```

### 2. Alternative: Update .bashrc in container
Add to bucardo-force-config.sh:

```bash
# Create alias for bucardo user
cat >> /var/lib/bucardo/.bashrc << 'EOF'
alias bucardo='/usr/bin/bucardo --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo'
EOF
```

### 3. Alternative: Environment Variable Fix
Set BUCARDO_CONFIG_FILE environment variable:

```bash
export BUCARDO_CONFIG_FILE=/var/lib/bucardo/.bucardorc
```

### 4. Test Commands After Fix
```bash
# These should work without explicit parameters:
docker compose exec bucardo bucardo status
docker compose exec bucardo bucardo list databases
docker compose exec bucardo bucardo add database local dbname=archive_production host=db port=5432 user=postgres pass=password
```

## Current Working Commands (explicit parameters)
```bash
docker compose exec bucardo bucardo --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo status
docker compose exec bucardo bucardo --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo add database local dbname=archive_production host=db port=5432 user=postgres pass=password
```

## Implementation Priority
1. Fix wrapper script approach (cleanest)
2. Test with corrected exports
3. Verify automatic replication setup
