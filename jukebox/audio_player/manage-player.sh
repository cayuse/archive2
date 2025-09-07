#!/bin/bash

# Jukebox Player Management Script
# Simple script to start/stop/restart the Python player

SERVICE_NAME="jukebox-player"

case "$1" in
    start)
        echo "🚀 Starting Jukebox Player..."
        sudo systemctl start ${SERVICE_NAME}
        sudo systemctl status ${SERVICE_NAME}
        ;;
    stop)
        echo "⏹️ Stopping Jukebox Player..."
        sudo systemctl stop ${SERVICE_NAME}
        sudo systemctl status ${SERVICE_NAME}
        ;;
    restart)
        echo "🔄 Restarting Jukebox Player..."
        sudo systemctl restart ${SERVICE_NAME}
        sudo systemctl status ${SERVICE_NAME}
        ;;
    status)
        echo "📊 Jukebox Player Status:"
        sudo systemctl status ${SERVICE_NAME}
        ;;
    logs)
        echo "📝 Jukebox Player Logs (press Ctrl+C to exit):"
        sudo journalctl -u ${SERVICE_NAME} -f
        ;;
    install)
        echo "📥 Installing Jukebox Player Service..."
        ./install-service.sh
        ;;
    *)
        echo "Jukebox Player Management Script"
        echo "===================================="
        echo ""
        echo "Usage: $0 {start|stop|restart|status|logs|install}"
        echo ""
        echo "Commands:"
        echo "  start   - Start the player service"
        echo "  stop    - Stop the player service"
        echo "  restart - Restart the player service"
        echo "  status  - Show service status"
        echo "  logs    - Show service logs (follow mode)"
        echo "  install - Install the systemd service"
        echo ""
        echo "Examples:"
        echo "  $0 start    # Start the player"
        echo "  $0 status   # Check if running"
        echo "  $0 logs     # View logs"
        echo "  $0 install  # Install service"
        exit 1
        ;;
esac
