#!/bin/bash
# PostgreSQL Logical Replication Management Script
# 
# This script helps manage multiple slaves connected to a master database
# Run from the MASTER server to monitor and manage replication

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_help() {
    echo "PostgreSQL Logical Replication Management"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  list          List all replication slots and active subscriptions"
    echo "  status        Show detailed replication status"
    echo "  cleanup       Remove inactive/dead replication slots"
    echo "  remove SLOT   Remove a specific replication slot"
    echo "  limits        Show replication limits and usage"
    echo "  help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 list                    # Show all connected slaves"
    echo "  $0 remove slave_001_slot   # Remove a specific dead slave"
    echo "  $0 cleanup                 # Remove all inactive slots"
}

list_replication() {
    info "📋 Current Replication Slots and Subscriptions"
    echo ""
    
    # Check if we're in docker environment
    if command -v docker >/dev/null 2>&1 && docker compose ps | grep -q "db.*Up"; then
        DB_CMD="docker compose exec -T db psql -U postgres -d archive_production"
    else
        DB_CMD="psql -U postgres -d archive_production"
    fi
    
    echo "🔌 REPLICATION SLOTS (on master):"
    $DB_CMD -c "
    SELECT 
        slot_name,
        plugin,
        slot_type,
        active,
        CASE WHEN active THEN '✅ ACTIVE' ELSE '❌ INACTIVE' END as status,
        restart_lsn,
        confirmed_flush_lsn
    FROM pg_replication_slots 
    ORDER BY slot_name;
    " 2>/dev/null || warning "Could not connect to database"
    
    echo ""
    echo "📊 REPLICATION STATISTICS:"
    $DB_CMD -c "
    SELECT 
        COUNT(*) as total_slots,
        COUNT(*) FILTER (WHERE active = true) as active_slots,
        COUNT(*) FILTER (WHERE active = false) as inactive_slots
    FROM pg_replication_slots;
    " 2>/dev/null || true
    
    echo ""
    echo "💾 WAL FILES AND LAG:"
    $DB_CMD -c "
    SELECT 
        slot_name,
        pg_size_pretty(
            pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)
        ) as wal_lag_size,
        CASE 
            WHEN active THEN 'Streaming'
            ELSE 'Disconnected'
        END as connection_status
    FROM pg_replication_slots 
    ORDER BY pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) DESC;
    " 2>/dev/null || true
}

show_status() {
    info "📈 Detailed Replication Status"
    echo ""
    
    if command -v docker >/dev/null 2>&1 && docker compose ps | grep -q "db.*Up"; then
        DB_CMD="docker compose exec -T db psql -U postgres -d archive_production"
    else
        DB_CMD="psql -U postgres -d archive_production"
    fi
    
    echo "⚙️  MASTER CONFIGURATION:"
    $DB_CMD -c "
    SELECT 
        name, 
        setting, 
        CASE name 
            WHEN 'wal_level' THEN CASE WHEN setting = 'logical' THEN '✅ OK' ELSE '❌ NEEDS logical' END
            WHEN 'max_replication_slots' THEN CASE WHEN setting::int >= 10 THEN '✅ OK' ELSE '⚠️  LOW' END
            WHEN 'max_wal_senders' THEN CASE WHEN setting::int >= 10 THEN '✅ OK' ELSE '⚠️  LOW' END
            ELSE '📊 INFO'
        END as status
    FROM pg_settings 
    WHERE name IN ('wal_level', 'max_replication_slots', 'max_wal_senders', 'max_worker_processes')
    ORDER BY name;
    " 2>/dev/null || warning "Could not get master configuration"
    
    echo ""
    echo "📋 PUBLICATIONS:"
    $DB_CMD -c "
    SELECT 
        pubname,
        puballtables,
        pubinsert,
        pubupdate,
        pubdelete,
        pubtruncate
    FROM pg_publication;
    " 2>/dev/null || true
    
    echo ""
    echo "📄 PUBLISHED TABLES:"
    $DB_CMD -c "
    SELECT 
        pubname,
        schemaname,
        tablename
    FROM pg_publication_tables 
    ORDER BY pubname, schemaname, tablename;
    " 2>/dev/null || true
}

cleanup_inactive() {
    info "🧹 Cleaning up inactive replication slots"
    
    if command -v docker >/dev/null 2>&1 && docker compose ps | grep -q "db.*Up"; then
        DB_CMD="docker compose exec -T db psql -U postgres -d archive_production"
    else
        DB_CMD="psql -U postgres -d archive_production"
    fi
    
    # Get inactive slots
    INACTIVE_SLOTS=$($DB_CMD -t -c "SELECT slot_name FROM pg_replication_slots WHERE active = false;" 2>/dev/null | tr -d ' ' | grep -v '^$' || true)
    
    if [ -z "$INACTIVE_SLOTS" ]; then
        success "No inactive slots found"
        return
    fi
    
    echo "Inactive slots found:"
    echo "$INACTIVE_SLOTS"
    echo ""
    
    read -p "Remove all inactive slots? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        while IFS= read -r slot; do
            if [ -n "$slot" ]; then
                info "Removing slot: $slot"
                $DB_CMD -c "SELECT pg_drop_replication_slot('$slot');" 2>/dev/null || warning "Failed to remove $slot"
            fi
        done <<< "$INACTIVE_SLOTS"
        success "Cleanup complete"
    else
        info "Cleanup cancelled"
    fi
}

remove_slot() {
    local slot_name="$1"
    if [ -z "$slot_name" ]; then
        error "Slot name required. Usage: $0 remove SLOT_NAME"
        exit 1
    fi
    
    if command -v docker >/dev/null 2>&1 && docker compose ps | grep -q "db.*Up"; then
        DB_CMD="docker compose exec -T db psql -U postgres -d archive_production"
    else
        DB_CMD="psql -U postgres -d archive_production"
    fi
    
    info "Removing replication slot: $slot_name"
    
    # Check if slot exists
    SLOT_EXISTS=$($DB_CMD -t -c "SELECT COUNT(*) FROM pg_replication_slots WHERE slot_name = '$slot_name';" 2>/dev/null | tr -d ' ')
    
    if [ "$SLOT_EXISTS" = "0" ]; then
        warning "Slot '$slot_name' does not exist"
        return
    fi
    
    # Check if slot is active
    SLOT_ACTIVE=$($DB_CMD -t -c "SELECT active FROM pg_replication_slots WHERE slot_name = '$slot_name';" 2>/dev/null | tr -d ' ')
    
    if [ "$SLOT_ACTIVE" = "t" ]; then
        warning "Slot '$slot_name' is currently ACTIVE!"
        echo "This means a slave is actively using this slot."
        read -p "Are you sure you want to remove it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Removal cancelled"
            return
        fi
    fi
    
    $DB_CMD -c "SELECT pg_drop_replication_slot('$slot_name');" 2>/dev/null && success "Slot '$slot_name' removed" || error "Failed to remove slot '$slot_name'"
}

show_limits() {
    info "📊 Replication Limits and Current Usage"
    
    if command -v docker >/dev/null 2>&1 && docker compose ps | grep -q "db.*Up"; then
        DB_CMD="docker compose exec -T db psql -U postgres -d archive_production"
    else
        DB_CMD="psql -U postgres -d archive_production"
    fi
    
    echo ""
    $DB_CMD -c "
    WITH limits AS (
        SELECT 
            (SELECT setting::int FROM pg_settings WHERE name = 'max_replication_slots') as max_slots,
            (SELECT setting::int FROM pg_settings WHERE name = 'max_wal_senders') as max_senders,
            (SELECT COUNT(*) FROM pg_replication_slots) as used_slots,
            (SELECT COUNT(*) FROM pg_stat_replication) as active_senders
    )
    SELECT 
        'Replication Slots' as resource,
        used_slots as current_usage,
        max_slots as maximum,
        ROUND((used_slots::float / max_slots) * 100, 1) || '%' as usage_percent,
        CASE 
            WHEN (used_slots::float / max_slots) > 0.8 THEN '⚠️  HIGH'
            WHEN (used_slots::float / max_slots) > 0.6 THEN '🟡 MEDIUM'
            ELSE '✅ OK'
        END as status
    FROM limits
    UNION ALL
    SELECT 
        'WAL Senders' as resource,
        active_senders as current_usage,
        max_senders as maximum,
        ROUND((active_senders::float / max_senders) * 100, 1) || '%' as usage_percent,
        CASE 
            WHEN (active_senders::float / max_senders) > 0.8 THEN '⚠️  HIGH'
            WHEN (active_senders::float / max_senders) > 0.6 THEN '🟡 MEDIUM'
            ELSE '✅ OK'
        END as status
    FROM limits;
    " 2>/dev/null || warning "Could not get limit information"
    
    echo ""
    info "💡 Tips:"
    echo "  - Each slave uses 1 replication slot and 1 WAL sender"
    echo "  - Current limits allow for $(docker compose exec -T db psql -U postgres -t -c "SELECT setting FROM pg_settings WHERE name = 'max_replication_slots';" 2>/dev/null | tr -d ' ') concurrent slaves"
    echo "  - Increase limits in docker-compose.yml if needed (PG_MAX_REPLICATION_SLOTS, PG_MAX_WAL_SENDERS)"
}

# Main script logic
case "${1:-help}" in
    "list")
        list_replication
        ;;
    "status")
        show_status
        ;;
    "cleanup")
        cleanup_inactive
        ;;
    "remove")
        remove_slot "$2"
        ;;
    "limits")
        show_limits
        ;;
    "help"|*)
        show_help
        ;;
esac
