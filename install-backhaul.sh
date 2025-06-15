#!/bin/bash

set -e

echo "🔧 Backhaul Installer / Uninstaller"
echo "-----------------------------------"
read -p "Do you want to install or uninstall backhaul? (install/uninstall): " ACTION
ACTION=$(echo "$ACTION" | tr '[:upper:]' '[:lower:]')

if [[ "$ACTION" == "uninstall" ]]; then
    echo "🗑 Uninstalling Backhaul..."
    sudo systemctl stop backhaul || true
    sudo systemctl disable backhaul || true
    sudo rm -f /etc/systemd/system/backhaul.service
    sudo rm -f /usr/local/bin/backhaul
    sudo rm -rf /etc/backhaul
    sudo rm -rf /var/log/backhaul
    sudo userdel backhaul 2>/dev/null || true
    sudo systemctl daemon-reload
    echo "✅ Backhaul completely uninstalled."
    exit 0
fi

if [[ "$ACTION" != "install" ]]; then
    echo "❌ Invalid action. Exiting."
    exit 1
fi

echo "📦 Installing Backhaul..."

# Create user and directory
sudo useradd -r -s /bin/false backhaul 2>/dev/null || true
sudo mkdir -p /etc/backhaul
sudo mkdir -p /var/log/backhaul
sudo chown backhaul: /etc/backhaul /var/log/backhaul

# Download latest release
cd /tmp
LATEST=$(curl -s https://api.github.com/repos/Musixal/Backhaul/releases/latest | grep browser_download_url | grep linux_amd64 | cut -d '"' -f 4)
curl -L "$LATEST" -o backhaul.zip
unzip backhaul.zip -d backhaul_bin
sudo mv backhaul_bin/backhaul /usr/local/bin/backhaul
sudo chmod +x /usr/local/bin/backhaul

# === Ask for user input ===
read -p "Select role (server/client): " ROLE
ROLE=$(echo "$ROLE" | tr '[:upper:]' '[:lower:]')

read -p "Enter transport (e.g. tcp, ws, wss, kcp): " TRANSPORT
read -p "Enter shared token: " TOKEN
read -p "Enter port to listen on (server) or connect to (client): " PORT

CONFIG_PATH="/etc/backhaul/config.toml"

# Start writing config
echo "[$ROLE]" > "$CONFIG_PATH"
echo "transport = \"$TRANSPORT\"" >> "$CONFIG_PATH"
echo "token = \"$TOKEN\"" >> "$CONFIG_PATH"

if [ "$ROLE" = "server" ]; then
    echo "bind_addr = \"0.0.0.0:$PORT\"" >> "$CONFIG_PATH"
    echo "accept_udp = false" >> "$CONFIG_PATH"
    echo "keepalive_period = 75" >> "$CONFIG_PATH"
    echo "nodelay = true" >> "$CONFIG_PATH"
    echo "heartbeat = 40" >> "$CONFIG_PATH"
    echo "channel_size = 2048" >> "$CONFIG_PATH"
    echo "sniffer = false" >> "$CONFIG_PATH"
    echo "web_port = 2060" >> "$CONFIG_PATH"
    echo "sniffer_log = \"/var/log/backhaul/sniffer.json\"" >> "$CONFIG_PATH"
    echo "log_level = \"info\"" >> "$CONFIG_PATH"

    # Ask for ports
    echo "Enter port mappings in format local=remote (e.g. 443=443). Type 'done' when finished:"
    PORTS=()
    while true; do
        read -p "> " MAP
        [[ "$MAP" == "done" ]] && break
        PORTS+=("\"$MAP\"")
    done
    JOINED=$(IFS=, ; echo "${PORTS[*]}")
    echo "ports = [$JOINED]" >> "$CONFIG_PATH"

else
    read -p "Enter remote server address (e.g. 1.2.3.4:$PORT): " REMOTE
    echo "remote_addr = \"$REMOTE\"" >> "$CONFIG_PATH"
    echo "connection_pool = 8" >> "$CONFIG_PATH"
    echo "aggressive_pool = false" >> "$CONFIG_PATH"
    echo "keepalive_period = 75" >> "$CONFIG_PATH"
    echo "dial_timeout = 10" >> "$CONFIG_PATH"
    echo "nodelay = true" >> "$CONFIG_PATH"
    echo "retry_interval = 3" >> "$CONFIG_PATH"
    echo "sniffer = false" >> "$CONFIG_PATH"
    echo "web_port = 2060" >> "$CONFIG_PATH"
    echo "sniffer_log = \"/var/log/backhaul/sniffer.json\"" >> "$CONFIG_PATH"
    echo "log_level = \"info\"" >> "$CONFIG_PATH"
fi

# === Create systemd service ===
echo "🔧 Setting up systemd service..."

cat <<EOF | sudo tee /etc/systemd/system/backhaul.service > /dev/null
[Unit]
Description=Backhaul Tunnel
After=network.target

[Service]
ExecStart=/usr/local/bin/backhaul -c /etc/backhaul/config.toml
User=backhaul
Restart=on-failure
RestartSec=5
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable backhaul
sudo systemctl start backhaul

echo "✅ Backhaul installed and running as systemd service."
