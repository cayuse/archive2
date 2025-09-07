#!/bin/bash

# Jukebox Player Service Installer
# This script installs and manages the systemd service for the Python player

set -e

SERVICE_NAME="jukebox-player"
SERVICE_FILE="jukebox-player.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_FILE}"
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Jukebox Player Service Installer"
echo "===================================="

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo "❌ This script should not be run as root"
   exit 1
fi

# Check if service file exists
if [[ ! -f "${CURRENT_DIR}/${SERVICE_FILE}" ]]; then
    echo "❌ Service file not found: ${SERVICE_FILE}"
    exit 1
fi

# Check if virtual environment exists
if [[ ! -d "${CURRENT_DIR}/venv" ]]; then
    echo "❌ Virtual environment not found. Please run: python -m venv venv && source venv/bin/activate && pip install -r requirements.txt"
    exit 1
fi

# Check if player.py exists
if [[ ! -f "${CURRENT_DIR}/player.py" ]]; then
    echo "❌ Player script not found: player.py"
    exit 1
fi

echo "✅ Prerequisites check passed"

# Install the service
echo "📥 Installing systemd service..."
sudo cp "${CURRENT_DIR}/${SERVICE_FILE}" "${SERVICE_PATH}"

# Update the service file with correct paths
sudo sed -i "s|/home/cayuse|${HOME}|g" "${SERVICE_PATH}"
sudo sed -i "s|cayuse|cayuse|g" "${SERVICE_PATH}"

# Reload systemd
echo "🔄 Reloading systemd..."
sudo systemctl daemon-reload

# Enable the service
echo "✅ Enabling service..."
sudo systemctl enable "${SERVICE_NAME}"

echo ""
echo "🎉 Service installed successfully!"
echo ""
echo "📋 Service Management Commands:"
echo "  Start:   sudo systemctl start ${SERVICE_NAME}"
echo "  Stop:    sudo systemctl stop ${SERVICE_NAME}"
echo "  Restart: sudo systemctl restart ${SERVICE_NAME}"
echo "  Status:  sudo systemctl status ${SERVICE_NAME}"
echo "  Logs:    sudo journalctl -u ${SERVICE_NAME} -f"
echo ""
echo "🚀 To start the service now, run:"
echo "  sudo systemctl start ${SERVICE_NAME}"
echo ""
echo "🔍 To check the status, run:"
echo "  sudo systemctl status ${SERVICE_NAME}"
