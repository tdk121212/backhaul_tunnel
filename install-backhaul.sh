#!/bin/bash

set -e

echo "-----------------------------------"
read -p "Do you want to install or uninstall backhaul? (install/uninstall): " ACTION

if [[ "$ACTION" == "uninstall" ]]; then
  echo "🧹 Uninstalling Backhaul..."
  sudo systemctl stop backhaul || true
  sudo systemctl disable backhaul || true
  sudo rm -f /etc/systemd/system/backhaul.service
  sudo rm -f /etc/backhaul/config.toml
  sudo rm -f /usr/local/bin/backhaul
  echo "✅ Backhaul has been removed."
  exit 0
elif [[ "$ACTION" != "install" ]]; then
  echo "❌ Invalid option. Use 'install' or 'uninstall'."
  exit 1
fi

echo "📦 Installing Backhaul..."

# Ensure dependencies
sudo apt update
sudo apt install -y curl tar

# Ask user for role
read -p "Choose role (server/client): " ROLE
if [[ "$ROLE" != "server" && "$ROLE" != "client" ]]; then
  echo "❌ Invalid role. Must be 'server' or 'client'."
  exit 1
fi

read -p "Enter bind/remote address (e.g., 0.0.0.0:3080): " ADDRESS
read -p "Enter token (shared between server and client): " TOKEN
read -p "Enter web panel port (e.g., 2060): " WEB_PORT
read -p "Enter path for sniffer log (e.g., /root/backhaul.json): " LOG_PATH
read -p "Enter log level (info/debug/warn/error): " LOG_LEVEL

# If server, ask for port forwards
FORWARD_PORTS=""
if [[ "$ROLE" == "server" ]]; then
  read -p "Enter ports to forward (e.g., 443=443,5566=9766). Leave blank for none: " FORWARD_PORTS
fi

# Download latest release
cd /tmp
LATEST=$(curl -s https://api.github.com/repos/Musixal/Backhaul/releases/latest \
  | grep browser_download_url \
  | grep linux_amd64.tar.gz \
  | cut -d '"' -f 4)

echo "⬇ Downloading: $LATEST"
curl -L "$LATEST" -o backhaul.tar.gz
mkdir -p backhaul_bin
tar -xzf backhaul.tar.gz -C backhaul_bin
sudo mv backhaul_bin/backhaul /usr/local/bin/backhaul
sudo chmod +x /usr/local/bin/backhaul

# Create config directory
sudo mkdir -p /etc/backhaul

# Generate config.toml
CONFIG_PATH="/etc/backhaul/config.toml"
echo "🛠 Generating config at $CONFIG_PATH"

if [[ "$ROLE" == "server" ]]; then
sudo tee $CONFIG_PATH > /dev/null <<EOF
[server]
bind_addr = "$ADDRESS"
transport = "tcp"
accept_udp = false
token = "$TOKEN"
keepalive_period = 75
nodelay = true
heartbeat = 40
channel_size = 2048
sniffer = false
web_port = $WEB_PORT
sniffer_log = "$LOG_PATH"
log_level = "$LOG_LEVEL"
ports = [$(echo "$FORWARD_PORTS" | sed 's/,/","/g' | sed 's/^/"/;s/$/"/')]
EOF
else
sudo tee $CONFIG_PATH > /dev/null <<EOF
[client]
remote_addr = "$ADDRESS"
transport = "tcp"
token = "$TOKEN"
connection_pool = 8
aggressive_pool = false
keepalive_period = 75
dial_timeout = 10
nodelay = true
retry_interval = 3
sniffer = false
web_port = $WEB_PORT
sniffer_log = "$LOG_PATH"
log_level = "$LOG_LEVEL"
EOF
fi

# Create systemd service
sudo tee /etc/systemd/system/backhaul.service > /dev/null <<EOF
[Unit]
Description=Backhaul Tunnel
After=network.target

[Service]
ExecStart=/usr/local/bin/backhaul -c /etc/backhaul/config.toml
Restart=on-failure
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

# Reload and enable service
sudo systemctl daemon-reload
sudo systemctl enable backhaul
sudo systemctl restart backhaul

echo "✅ Backhaul installed and running as a service."
