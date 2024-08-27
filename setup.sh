#!/bin/bash

# Function to check if a command is available
command_exists() {
  command -v "$1" &> /dev/null
}

# Install Git if not installed
if ! command_exists git; then
  if command_exists apt-get; then
    sudo apt-get update
    sudo apt-get install -y git
  elif command_exists yum; then
    sudo yum install -y git
  elif command_exists pacman; then
    sudo pacman -Sy --noconfirm git
  else
    echo "Unsupported package manager. Exiting."
    exit 1
  fi
else
  echo "Git is already installed."
fi

# Install nvm if not installed
if ! command_exists nvm; then
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.38.0/install.sh | bash
  source ~/.bashrc
else
  echo "nvm is already installed."
fi

# Load NVM environment
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Install Node.js 16.20.2 if not installed
if ! command_exists node; then
  nvm install 20.11.0
  nvm use 20.11.0
else
  echo "Node.js 20.11.0 is already installed."
fi

# Install nodemon if not installed
if ! command_exists nodemon; then
  npm install -g nodemon
else
  echo "nodemon is already installed."
fi

# Install pm2 if not installed
if ! command_exists pm2; then
  npm install -g pm2
else
  echo "pm2 is already installed."
fi

# Install Nginx if not installed
if ! command_exists nginx; then
  if command_exists apt-get; then
    sudo apt-get install -y nginx
    sudo systemctl enable nginx
  elif command_exists yum; then
    sudo yum install -y nginx
    sudo systemctl enable nginx
  elif command_exists pacman; then
    sudo pacman -Sy --noconfirm nginx
    sudo systemctl enable nginx
  else
    echo "Unsupported package manager. Exiting."
    exit 1
  fi
else
  echo "Nginx is already installed."
fi

# Install Certbot using Certbot instructions if not installed
if ! command_exists certbot; then
  if command_exists apt-get; then
    sudo apt-get update
    sudo apt-get install -y certbot python3-certbot-nginx
  elif command_exists yum; then
    # Attempt to install using yum, if unsuccessful, use manual installation
    sudo yum install -y certbot python3-certbot-nginx || {
      # Manual installation
      sudo python3 -m venv /opt/certbot/
      sudo /opt/certbot/bin/pip install --upgrade pip
      sudo /opt/certbot/bin/pip install certbot certbot-nginx
      sudo ln -s /opt/certbot/bin/certbot /usr/bin/certbot

      # Install cronie if not installed
      if ! command_exists cronie; then
        sudo yum install -y cronie
      else
        echo "cronie is already installed."
      fi

      # Configure and start certbot renewal cron job
      sudo crontab -l | { cat; echo "0 3 * * * sudo certbot renew >/dev/null 2>&1"; } | sudo crontab -
    }
  elif command_exists pacman; then
    sudo pacman -Sy --noconfirm certbot
  else
    echo "Unsupported package manager. Exiting."
    exit 1
  fi
else
  echo "Certbot is already installed."
fi

# Get the current user's home directory
USER_HOME=$(eval echo ~$USER)

# Configure pm2 to autostart on system boot
sudo env PATH=$PATH:$USER_HOME/.nvm/versions/node/v20.11.0/bin $USER_HOME/.nvm/versions/node/v20.11.0/lib/node_modules/pm2/bin/pm2 startup systemd -u $USER --hp $USER_HOME

# Save the current pm2 state to restart on boot
pm2 save

# Source the .bashrc file to simulate a reload
source ~/.bashrc
