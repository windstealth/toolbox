#!/bin/bash

# ================================
# Secretive SSH Setup (macOS only)
# ================================

set -e
# If running with sudo, determine the original user
if [ "$SUDO_USER" ]; then
  TARGET_USER="$SUDO_USER"
else
  TARGET_USER="$(whoami)"
fi
TARGET_GROUP=$(id -gn "$TARGET_USER")
HOME_DIR=$(eval echo "~$TARGET_USER")
HOST_NAME=$(hostname)
SSH_CONFIG="$HOME_DIR/.ssh/config"

# Ensure SSH config file exists with correct permissions
if [ ! -f "$SSH_CONFIG" ]; then
  echo "📁 SSH config not found. Creating..."
  sudo touch "$SSH_CONFIG"
  sudo chown "$TARGET_USER":"$TARGET_GROUP" "$SSH_CONFIG"
fi
echo "🔐 Setting correct permissions..."
sudo chmod 600 "$SSH_CONFIG"


# ================================
# Ensure Global Block is at the Top
# ================================

if ! grep -q "Host *" "$SSH_CONFIG"; then
  echo "🧱 Adding global SSH settings at top..."
  GLOBAL_BLOCK="Host *
    ServerAliveCountMax 3
    ServerAliveInterval 60
"
  TEMP_CONFIG=$(mktemp)
  # Prepend global block + rest of config
  echo "$GLOBAL_BLOCK" | cat - "$SSH_CONFIG" > "$TEMP_CONFIG"
  sudo cp "$TEMP_CONFIG" "$SSH_CONFIG"
  sudo chmod 600 "$SSH_CONFIG"
  rm "$TEMP_CONFIG"
else
  echo "✅ Global SSH settings already exist."
fi


# ================================
# Host selection prompt
# ================================

# Host selection prompt
echo "🔧 What type of host do you want to configure?"
echo "1) SSH Server (with Secretive)"
echo "2) GitHub (with Secretive)"
echo "3) SSH Server (without Secretive)"
echo "4) GitHub (without Secretive)"
read -p "Enter 1, 2, 3 or 4: " HOST_TYPE

if [[ "$HOST_TYPE" == "1" ]]; then
  HOST_KIND="ssh"
  USE_SECRETIVE=true
elif [[ "$HOST_TYPE" == "2" ]]; then
  HOST_KIND="github"
  USE_SECRETIVE=true
elif [[ "$HOST_TYPE" == "3" ]]; then
  HOST_KIND="ssh"
  USE_SECRETIVE=false
elif [[ "$HOST_TYPE" == "4" ]]; then
  HOST_KIND="github"
  USE_SECRETIVE=false
else
  echo "❌ Invalid selection. Exiting."
  exit 1
fi

# Friendly alias prompt
echo "🆔 Server name:"
read SERVER_NAME
HOST_ALIAS="$HOST_KIND.$SERVER_NAME.com"

# Secretive public key or non-Secretive setup
if [ "$USE_SECRETIVE" = true ]; then
  echo "🔑 Path to Secretive public key:"
  read IDENTITY_FILE
else
  # Non-Secretive setup, generate SSH key
  echo "🔑 Generating SSH key (no Secretive used)..."
  ssh-keygen -t ed25519 -C "$HOST_ALIAS@$HOST_NAME.local ([$SERVER_NAME] Server Key - $(date +%Y-%m-%d))" -f "$HOME_DIR/.ssh/id_ed25519_${HOST_KIND}_${SERVER_NAME}"
  IDENTITY_FILE="$HOME_DIR/.ssh/id_ed25519_${HOST_KIND}_${SERVER_NAME}"
  echo "✅ SSH key generated at $IDENTITY_FILE.pub"
fi

# ================================
# Configure Host Blocks
# ================================

# Setup GitHub Host
if [[ "$HOST_KIND" == "github" ]]; then
  if [ "$USE_SECRETIVE" = false ]; then
     CONFIG_BLOCK=$(cat <<EOF
Host $HOST_ALIAS
    HostName github.com
    IdentityFile $IDENTITY_FILE
    PreferredAuthentications publickey
EOF
    )
  else
     CONFIG_BLOCK=$(cat <<EOF
Host $HOST_ALIAS
    HostName github.com
    IdentitiesOnly yes
    IdentityAgent $HOME_DIR/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh
    IdentityFile $IDENTITY_FILE
EOF
    )
  fi
# Setup SSH Host (non-Secretive or Secretive)
else

  echo "🌐 Hostname or IP:"
  read IP

  echo "📦 SSH User:"
  read SSH_USER

  echo "📦 SSH Port [default 22]:"
  read PORT
  PORT=${PORT:-22}

  if [ "$USE_SECRETIVE" = false ]; then
    CONFIG_BLOCK=$(cat <<EOF
Host $HOST_ALIAS
    HostName $IP
    Port $PORT
    User $SSH_USER
EOF
)
  else
    CONFIG_BLOCK=$(cat <<EOF
Host $HOST_ALIAS
    HostName $IP
    IdentitiesOnly yes
    IdentityAgent $HOME_DIR/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh
    IdentityFile $IDENTITY_FILE
    Port $PORT
    User $SSH_USER
EOF
)
  fi
fi

# ================================
# Check for Duplicate Entries and Append Config
# ================================

# Check for duplicate
if grep -q "Host $HOST_ALIAS" "$SSH_CONFIG"; then
  echo -e "\n⚠️  SSH config already contains an entry for $HOST_ALIAS — skipping append."
else
  echo -e "\n$CONFIG_BLOCK" | sudo tee -a "$SSH_CONFIG" > /dev/null
  sudo chown "$TARGET_USER":"$TARGET_GROUP" "$SSH_CONFIG"
  echo "✅ SSH config block added for $HOST_ALIAS."
fi

# ================================
# Upload public key for SSH hosts (if SSH setup was selected)
# ================================

# Optional: Upload public key for SSH hosts (if SSH setup was selected and not using Secretive)
if [[ "$HOST_KIND" == "ssh" && "$USE_SECRETIVE" = true ]]; then
  echo -e "\n📤 Upload public key to server for passwordless login? [y/N]"
  read SHOULD_UPLOAD_KEY
  if [[ "$SHOULD_UPLOAD_KEY" =~ ^[Yy]$ ]]; then
    echo "🚀 Uploading key to $HOST_ALIAS..."
    ssh "$HOST_ALIAS" "
      mkdir -p ~/.ssh && chmod 700 ~/.ssh
      touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
      echo \"$(cat $IDENTITY_FILE) $HOST_ALIAS@$HOST_NAME.secretive.local ([$SERVER_NAME] Server Key - $(date +%Y-%m-%d))\" >> ~/.ssh/authorized_keys
    "
    echo "✅ Public key uploaded successfully!"
  else
    echo "⏭️  Skipping key upload."
  fi
fi

# Optional: Upload public key for SSH hosts (if SSH setup without Secretive)
if [[ "$HOST_KIND" == "ssh" && "$USE_SECRETIVE" = false ]]; then
  echo -e "\n📤 Do you want to upload the public key using ssh-copy-id for passwordless login? [y/N]"
  read SHOULD_UPLOAD_KEY
  if [[ "$SHOULD_UPLOAD_KEY" =~ ^[Yy]$ ]]; then
    echo "🚀 Uploading key to $HOST_ALIAS using ssh-copy-id..."
    ssh-copy-id -i $IDENTITY_FILE.pub "$HOST_ALIAS"
    echo "✅ Public key uploaded successfully using ssh-copy-id!"
  else
    echo "⏭️  Skipping key upload."
  fi
fi

# ================================
# 🔀 Call Node.js Script to Clean & Sort SSH Config File
# ================================
echo -e "\n🧼 Sorting SSH config with Node.js..."

# URL to your Node.js script on GitHub (raw version)
NODE_SCRIPT_URL="https://raw.githubusercontent.com/windstealth/toolbox/refs/heads/main/script/js/sort-ssh-config.js"

# Download the Node.js script from GitHub
curl -fsSL "$NODE_SCRIPT_URL" -o /tmp/sort-ssh-config.js

# Run the Node.js script
node /tmp/sort-ssh-config.js "$SSH_CONFIG"

# Ensuring correct ownership and permissions for SSH config file
echo "🔐 Ensuring correct ownership and permissions..."
sudo chown "$TARGET_USER":"$TARGET_GROUP" "$SSH_CONFIG"
sudo chmod 600 "$SSH_CONFIG"
echo "✅ Ownership and permissions updated for $SSH_CONFIG."

# Optionally, remove the downloaded script
rm /tmp/sort-ssh-config.js

echo "✅ SSH config sorted and updated using Node.js!"
