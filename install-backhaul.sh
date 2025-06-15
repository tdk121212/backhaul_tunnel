#!/bin/bash

set -e

echo "==== Backhaul Tunnel Installer for Ubuntu ===="

# Check if script is run as root
if [[ "$EUID" -ne 0 ]]; then
  echo "❌ Please run this script as root (e.g. with sudo)"
  exit 1
fi

# Prompt user for setup details
read -p "Enter the role (server/client): " ROLE
ROLE=$(echo "$ROLE" | tr '[:upper:]' '[:lower:]')
if [[ "$ROLE" != "server" && "$ROLE" != "client" ]]; then
  echo "❌ Invalid role. Must be 'server' or 'client'."
  exit 1
fi

read -p "Enter the protocol (tcp/ws/wss/udp-tcp): " PROTOCOL
read -p "Enter the listen port (e.g. 8080): " PORT
read -p "Enter a name for the systemd service (e.g. backhaul): " SERVICE_NAME

# Install Go and Git if not already installed
echo "🔧 Installing dependencies..."
apt update -y
apt install -y golang-go git

# Set install paths
INSTALL_DIR="/opt/backhaul"
BIN_PATH="/usr/local/bin/backhaul"
CONFIG_DIR="/etc/backhaul"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

# Clone Backhaul repo
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
if [[ -d "Backhaul" ]]; then
  echo "📦 Updating Backhaul repository..."
  cd Backhaul && git pull
else
  echo "📥 Cloning Backhaul repository..."
  git clone https://github.com/Musixal/Backhaul.git
  cd Backhaul
fi

# Build the binary
echo "🔨 Building Backhaul..."
go build -o "$BIN_PATH" ./cmd

# Create configuration file
mkdir -p "$CONFIG_DIR"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
cat > "$CONFIG_FILE" <<EOF
type: $ROLE
transport: $PROTOCOL
listen: :$PORT
EOF

echo "📝 Config created at: $CONFIG_FILE"

# Create systemd service
echo "⚙️ Creating systemd service..."
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Backhaul $ROLE Service
After=network.target

[Service]
ExecStart=$BIN_PATH -c $CONFIG_FILE
Restart=on-failure
User=root
WorkingDirectory=$INSTALL_DIR/Backhaul

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"

# Done
echo "✅ Installation complete!"
echo "------------------------------------------"
echo "🔹 Role      : $ROLE"
echo "🔹 Protocol  : $PROTOCOL"
echo "🔹 Port      : $PORT"
echo "🔹 Config    : $CONFIG_FILE"
echo "🔹 Service   : $SERVICE_NAME"
echo "📡 Check service: systemctl status $SERVICE_NAME"
echo "📄 Logs: journalctl -u $SERVICE_NAME -f"
