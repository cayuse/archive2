#!/bin/bash
# Archive Slave Environment Template
# 
# USAGE:
# 1. Copy this file: cp slave_exports_template.sh ../my_slave_exports.sh
# 2. Edit the copied file with your specific values (IPs, passwords, etc.)
# 3. Source before deployment: source ../my_slave_exports.sh
# 4. Deploy: ./deploy_slave.sh && ./after_deploy_slave.sh
#
# IMPORTANT: Never commit real passwords/keys to git!

# =============================================================================
# BASE EXPORTS (Required for ALL deployments)
# =============================================================================

# Rails encryption key - REQUIRED - Generate with: openssl rand -hex 16
export RAILS_MASTER_KEY=your_32_character_rails_master_key_here

# PostgreSQL database password - REQUIRED - Use a strong password
export POSTGRES_PASSWORD=your_secure_database_password

# Host storage paths - REQUIRED - Must exist and be writable
export HOST_STORAGE_PATH=/home/shared/psql_storage
export POSTGRES_DATA_PATH=/home/shared/psql_data

# Application port - REQUIRED
export ARCHIVE_PORT=3000

# =============================================================================
# SLAVE CONFIGURATION (Replication target - connects to master)
# =============================================================================

# Role identifier
export ARCHIVE_ROLE=slave

# Application configuration (this slave's IP address or hostname)
export APP_HOST=192.168.1.XXX                 # CHANGE: Your slave's IP address
export APP_PROTOCOL=http
export FORCE_SSL=false
export ASSUME_SSL=false
export FORGERY_ORIGIN_CHECK=false             # disable strict CSRF origin for IP testing
export ALLOW_ALL_HOSTS=true                   # accept any Host header during testing

# Docker Compose files (base only)
export COMPOSE_FILE="docker-compose.yml"

# Master database connection (must be reachable from this slave via VPN/LAN)
export MASTER_DB_HOST=192.168.1.XXX           # CHANGE: Your master's IP address
export MASTER_DB_PORT=5432
export MASTER_DB_NAME=archive_production
export MASTER_DB_USER=postgres
export MASTER_DB_PASS=$POSTGRES_PASSWORD      # Should match master's password

# =============================================================================
# LOGICAL REPLICATION CONFIGURATION
# =============================================================================

# Replication mode (always logical for new deployments)
export REPLICATION_MODE=logical

# Master-side publication and replication user (must exist on master)
export REPL_USER=archive_replicator            # CHANGE: If different on master
export REPL_PASS=change-me                     # CHANGE: Use actual replication password
export PUB_NAME=pub_archive                    # CHANGE: If different on master

# Slave-side subscription names (created on this slave)
export SUB_NAME=sub_archive                    # Can customize per slave
export SUB_SLOT_NAME=sub_archive_slot          # Can customize per slave

# =============================================================================
# AWS SES EXPORTS (Email service configuration - OPTIONAL)
# =============================================================================

# AWS SES settings (SMTP configuration for email sending)
# Leave empty if not using email features
export AWS_SES_SMTP_USERNAME=""                # CHANGE: Your AWS SES username
export AWS_SES_SMTP_PASSWORD=""                # CHANGE: Your AWS SES password  
export AWS_SES_SMTP_HOST="email-smtp.us-east-2.amazonaws.com"
export AWS_SES_SMTP_PORT="587"
export AWS_SES_SMTP_DOMAIN="yourdomain.com"    # CHANGE: Your domain
export MAILER_FROM_EMAIL="noreply@yourdomain.com"  # CHANGE: Your from email

# =============================================================================
# SUMMARY
# =============================================================================
echo "Environment configured for SLAVE deployment:"
echo "  - Slave IP: $APP_HOST"  
echo "  - Master IP: $MASTER_DB_HOST"
echo "  - Compose files: $COMPOSE_FILE"
echo "  - Replication mode: $REPLICATION_MODE"
echo ""
echo "To deploy:"
echo "  cd archive"
echo "  docker compose down"
echo "  docker compose build --no-cache"
echo "  docker compose up -d"
echo ""
echo "After deployment, run replication setup:"
echo "  ./after_deploy_slave.sh"
