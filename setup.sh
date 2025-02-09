#!/bin/bash

# Function to check if a command is available
command_exists() {
    command -v "$1" &> /dev/null
}

# Function to create Nginx configuration
create_nginx_conf() {
    local conf_file="/etc/nginx/conf.d/api.example.com.conf"
    local is_new_file=false

    if [ ! -f "$conf_file" ]; then
        is_new_file=true
        sudo tee "$conf_file" > /dev/null <<EOL
server {
    listen 80;
    listen [::]:80;
    server_name api.example.com;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;

    # Optimization
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;

    # Proxy settings
    location / {
        proxy_pass http://127.0.0.1:2468;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        
        # Additional proxy optimizations
        proxy_buffering on;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
        proxy_read_timeout 300;
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
        
        # Client optimization
        client_max_body_size 50M;
        client_body_buffer_size 128k;
        
        # WebSocket support
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Error pages
    error_page 404 /404.html;
    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }
}
EOL
        echo "Created Nginx configuration file: $conf_file"
    else
        echo "Nginx configuration file already exists: $conf_file"
    fi

    # Return the status of file creation
    echo "$is_new_file"
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
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
else
    echo "nvm is already installed."
fi

# Load NVM environment
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Install latest LTS version of Node.js if not installed
if ! command_exists node; then
    nvm install --lts
    nvm use --lts
else
    echo "Node.js is already installed."
fi

# Get Node.js path for PM2 startup
NODE_PATH=$(which node)
NODE_VERSION=$(node -v)

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

# Create Nginx configuration
create_nginx_conf

# Test Nginx configuration
sudo nginx -t

# Reload Nginx configuration if test passes
if [ $? -eq 0 ]; then
    sudo systemctl reload nginx
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
            fi
            # Configure and start certbot renewal cron job
            sudo crontab -l | { cat; echo "0 3 * * * sudo certbot renew --quiet"; } | sudo crontab -
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
sudo env PATH=$PATH:$USER_HOME/.nvm/versions/node/$NODE_VERSION/bin $USER_HOME/.nvm/versions/node/$NODE_VERSION/lib/node_modules/pm2/bin/pm2 startup systemd -u $USER --hp $USER_HOME

# Save the current pm2 state to restart on boot
pm2 save

# Create a temporary script to reload the environment
TMP_SCRIPT=$(mktemp)
cat > "$TMP_SCRIPT" << 'EOL'
#!/bin/bash
source ~/.bashrc
source ~/.profile
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
EOL

# Make the temporary script executable
chmod +x "$TMP_SCRIPT"

# Execute the temporary script in the current shell
. "$TMP_SCRIPT"

# Clean up
rm "$TMP_SCRIPT"

# Store the result of create_nginx_conf
is_new_conf=$(create_nginx_conf)

echo "Installation and configuration completed successfully!"
echo "Node.js version: $(node -v)"
echo "NPM version: $(npm -v)"
echo -e "To ensure all changes are applied, please run:"
echo -e "\n\033[1;36msource ~/.bashrc && exec bash\033[0m\n"

# Only show the configuration check message if the file was just created
if [ "$is_new_conf" = "true" ]; then
    echo -e "\nNginx Configuration Notice:"
    echo "A new Nginx configuration file has been created at: /etc/nginx/conf.d/api.example.com.conf"
    echo "Please review the configuration file and make any necessary adjustments for your specific needs."
    echo "You can edit the file using: sudo nano /etc/nginx/conf.d/api.example.com.conf"
fi
