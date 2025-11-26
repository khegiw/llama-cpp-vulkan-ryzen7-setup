#!/bin/bash
set -euo pipefail

#######################################
# llama.cpp ROCm Server Deployment Script
# Automated deployment for AMD GPU-accelerated LLM server
#
# FIXES APPLIED:
# - Removed unsupported --log-format parameter from systemd service
# - Fixed MODEL_NAME to use filename only (not repo path)
# - Added check to skip service setup if already running
# - Added smart user management for nginx (check existing users, prompt for changes)
# - Verified model URL points to correct quantization variant
#######################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"
LOG_FILE="${SCRIPT_DIR}/deployment.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#######################################
# Logging Functions
#######################################
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*" | tee -a "$LOG_FILE"
}

#######################################
# Error Handling
#######################################
error_exit() {
    log_error "$1"
    log_error "Deployment failed. Check ${LOG_FILE} for details."
    exit 1
}

check_exit_status() {
    if [ $? -ne 0 ]; then
        error_exit "$1"
    fi
}

#######################################
# Load Configuration
#######################################
if [ ! -f "$CONFIG_FILE" ]; then
    error_exit "Configuration file not found: ${CONFIG_FILE}"
fi

source "$CONFIG_FILE"
log "Configuration loaded from ${CONFIG_FILE}"

#######################################
# Pre-flight Checks
#######################################
preflight_checks() {
    log "=== Running Pre-flight Checks ==="

    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        error_exit "Please do not run this script as root. Use your regular user account."
    fi

    # Check Ubuntu version
    if [ ! -f /etc/os-release ]; then
        error_exit "Cannot determine OS version"
    fi

    source /etc/os-release
    if [[ "$VERSION_ID" != "24.04" ]]; then
        log_warning "This script is designed for Ubuntu 24.04. You are running $VERSION_ID"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    # Check for required commands
    for cmd in wget curl git cmake gcc g++; do
        if ! command -v $cmd &> /dev/null; then
            log_warning "$cmd not found. Will be installed."
        fi
    done

    # Check available disk space (need at least 20GB)
    available_space=$(df / | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 20000000 ]; then
        log_warning "Less than 20GB available disk space"
    fi

    log "Pre-flight checks completed"
}

#######################################
# Phase 1: Install ROCm
#######################################
install_rocm() {
    if [ "$SKIP_ROCM_INSTALL" = true ]; then
        log "Skipping ROCm installation (SKIP_ROCM_INSTALL=true)"
        return
    fi

    log "=== Phase 1: Installing ROCm ${ROCM_VERSION} ==="

    # Check if ROCm SDK is properly installed (not just rocminfo)
    if command -v rocminfo &> /dev/null; then
        # Check if we have the full SDK or just basic tools
        if [ -d "/opt/rocm" ] && [ -f "/opt/rocm/lib/cmake/hip/hip-config.cmake" ]; then
            log_info "Full ROCm SDK detected at /opt/rocm"
            log_warning "ROCm SDK appears to be already installed"
            read -p "Reinstall ROCm? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log "Skipping ROCm installation"
                return
            fi
        else
            log_warning "Found rocminfo but missing full ROCm SDK"
            log_info "Removing basic ROCm package and installing full SDK..."
            sudo apt remove -y rocminfo 2>/dev/null || true
        fi
    fi

    # Download and add ROCm GPG key
    log_info "Adding ROCm repository..."
    wget -q -O - https://repo.radeon.com/rocm/rocm.gpg.key | \
        gpg --dearmor | sudo tee /etc/apt/keyrings/rocm.gpg > /dev/null
    check_exit_status "Failed to add ROCm GPG key"

    # Add ROCm repository
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/${ROCM_VERSION} ${UBUNTU_CODENAME} main" | \
        sudo tee /etc/apt/sources.list.d/rocm.list
    check_exit_status "Failed to add ROCm repository"

    # Update package list
    log_info "Updating package list..."
    sudo apt update
    check_exit_status "Failed to update package list"

    # Install ROCm packages
    log_info "Installing ROCm packages (this may take several minutes)..."
    sudo apt install -y \
        rocm-hip-sdk \
        rocm-dev \
        rocm-libs \
        rocm-hip-runtime-dev \
        clinfo \
        radeontop \
        rocminfo
    check_exit_status "Failed to install ROCm packages"

    # Add user to required groups
    log_info "Adding user to render and video groups..."
    sudo usermod -a -G render,video $USER

    # Configure environment
    log_info "Configuring ROCm environment..."
    cat >> ~/.bashrc << 'EOF'

# ROCm Environment Configuration
export HSA_OVERRIDE_GFX_VERSION=__HSA_GFX_VERSION__
export HSA_ENABLE_SDMA=0
export PATH=/opt/rocm/bin:$PATH
export LD_LIBRARY_PATH=/opt/rocm/lib:$LD_LIBRARY_PATH
EOF

    sed -i "s/__HSA_GFX_VERSION__/${HSA_GFX_VERSION}/g" ~/.bashrc
    source ~/.bashrc

    log "ROCm installation completed"
    log_warning "A system reboot is recommended for ROCm to work properly"
    log_warning "After reboot, run: rocminfo | grep gfx"
}

#######################################
# Phase 2: Build llama.cpp
#######################################
build_llama_cpp() {
    log "=== Phase 2: Building llama.cpp with ROCm support ==="

    # Install build dependencies
    log_info "Installing build dependencies..."
    sudo apt install -y build-essential cmake git curl
    check_exit_status "Failed to install build dependencies"

    # Clone llama.cpp
    LLAMA_SRC="${SCRIPT_DIR}/llama.cpp"
    if [ -d "$LLAMA_SRC" ]; then
        log_warning "llama.cpp directory already exists"
        read -p "Remove and re-clone? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$LLAMA_SRC"
        else
            log_info "Using existing llama.cpp directory"
        fi
    fi

    if [ ! -d "$LLAMA_SRC" ]; then
        log_info "Cloning llama.cpp repository..."
        git clone https://github.com/ggerganov/llama.cpp.git "$LLAMA_SRC"
        check_exit_status "Failed to clone llama.cpp"
    fi

    cd "$LLAMA_SRC"

    # Build with hardware-specific optimizations
    log_info "Configuring build with optimizations for ${CPU_ARCH} and ${GPU_TARGET}..."

    # Set ROCm environment for build
    export ROCM_PATH=/opt/rocm
    export HIP_PATH=/opt/rocm

    cmake -B build \
        -DCMAKE_PREFIX_PATH=/opt/rocm \
        -DCMAKE_C_FLAGS="-march=${CPU_ARCH}" \
        -DCMAKE_CXX_FLAGS="-march=${CPU_ARCH}" \
        -DGGML_HIP=ON \
        -DAMDGPU_TARGETS=${GPU_TARGET} \
        -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
        -DGGML_HIPBLAS=ON
    check_exit_status "CMake configuration failed"

    log_info "Building llama.cpp (this may take several minutes)..."
    cmake --build build --config ${BUILD_TYPE} -j${BUILD_JOBS}
    check_exit_status "Build failed"

    # Verify build
    if [ ! -f "build/bin/llama-server" ]; then
        error_exit "llama-server binary not found after build"
    fi

    log "llama.cpp built successfully"
    cd "$SCRIPT_DIR"
}

#######################################
# Phase 3: Download Model
#######################################
download_model() {
    if [ "$SKIP_MODEL_DOWNLOAD" = true ]; then
        log "Skipping model download (SKIP_MODEL_DOWNLOAD=true)"
        return
    fi

    log "=== Phase 3: Downloading Model ==="

    sudo mkdir -p "${INSTALL_DIR}/models"
    sudo chown -R $USER:$USER "${INSTALL_DIR}"

    MODEL_PATH="${INSTALL_DIR}/models/${MODEL_NAME}"

    if [ -f "$MODEL_PATH" ]; then
        log_warning "Model already exists: ${MODEL_PATH}"
        read -p "Re-download? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Using existing model"
            return
        fi
    fi

    log_info "Downloading ${MODEL_NAME}..."
    log_info "This may take a while depending on your connection..."
    wget --progress=bar:force -O "$MODEL_PATH" "$MODEL_URL"
    check_exit_status "Model download failed"

    log "Model downloaded successfully to ${MODEL_PATH}"
}

#######################################
# Phase 4: Setup Server Service
#######################################
setup_server_service() {
    log "=== Phase 4: Setting up llama-server systemd service ==="

    # Check if service is already running
    if systemctl is-active --quiet llama-server 2>/dev/null; then
        log_info "llama-server service is already running"
        read -p "Reconfigure and restart service? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Skipping service setup (already running)"
            return
        fi
        log_info "Stopping service for reconfiguration..."
        sudo systemctl stop llama-server
    fi

    # Create directories
    sudo mkdir -p "${INSTALL_DIR}"/{models,logs,config}
    sudo chown -R $USER:$USER "${INSTALL_DIR}"

    # Copy server binary
    log_info "Installing server binary..."
    sudo cp "${SCRIPT_DIR}/llama.cpp/build/bin/llama-server" /usr/local/bin/
    sudo chmod +x /usr/local/bin/llama-server

    # Create systemd service
    log_info "Creating systemd service..."
    sudo tee /etc/systemd/system/llama-server.service > /dev/null << EOF
[Unit]
Description=llama.cpp Server with ROCm GPU Acceleration
After=network.target
Documentation=https://github.com/ggerganov/llama.cpp

[Service]
Type=simple
User=${USER}
Group=${USER}
WorkingDirectory=${INSTALL_DIR}

# ROCm Environment
Environment="HSA_OVERRIDE_GFX_VERSION=${HSA_GFX_VERSION}"
Environment="HSA_ENABLE_SDMA=0"
Environment="PATH=/opt/rocm/bin:/usr/local/bin:/usr/bin:/bin"
Environment="LD_LIBRARY_PATH=/opt/rocm/lib"

# Server Command
ExecStart=/usr/local/bin/llama-server \\
  --model ${INSTALL_DIR}/models/${MODEL_NAME} \\
  --host ${SERVER_HOST} \\
  --port ${SERVER_PORT} \\
  --threads ${SERVER_THREADS} \\
  --n-gpu-layers ${GPU_LAYERS} \\
  --ctx-size ${CONTEXT_SIZE} \\
  --parallel ${PARALLEL_REQUESTS} \\
  --metrics

# Restart policy
Restart=always
RestartSec=10

# Resource limits
MemoryMax=${MAX_MEMORY}
CPUQuota=800%

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=${INSTALL_DIR}/logs

# Logging
StandardOutput=append:${INSTALL_DIR}/logs/server.log
StandardError=append:${INSTALL_DIR}/logs/error.log

[Install]
WantedBy=multi-user.target
EOF
    check_exit_status "Failed to create systemd service"

    # Reload systemd
    sudo systemctl daemon-reload

    # Enable service
    log_info "Enabling llama-server service..."
    sudo systemctl enable llama-server

    # Start service
    log_info "Starting llama-server service..."
    sudo systemctl start llama-server

    # Wait a moment and check status
    sleep 3
    if sudo systemctl is-active --quiet llama-server; then
        log "llama-server service started successfully"
    else
        log_error "llama-server service failed to start"
        sudo systemctl status llama-server --no-pager
        error_exit "Service startup failed"
    fi
}

#######################################
# Phase 5: Setup Nginx Reverse Proxy
#######################################
setup_nginx() {
    if [ "$SETUP_NGINX" != true ]; then
        log "Skipping nginx setup (SETUP_NGINX=false)"
        return
    fi

    log "=== Phase 5: Setting up Nginx reverse proxy ==="

    # Install nginx
    log_info "Installing nginx..."
    sudo apt install -y nginx apache2-utils
    check_exit_status "Failed to install nginx"

    # Create user accounts
    log_info "Setting up user authentication..."

    # Check if .htpasswd exists
    htpasswd_exists=false
    if [ -f /etc/nginx/.htpasswd ]; then
        htpasswd_exists=true
    fi

    for i in "${!USERS[@]}"; do
        username="${USERS[$i]}"

        # Check if user already exists
        user_exists=false
        if [ "$htpasswd_exists" = true ] && sudo grep -q "^${username}:" /etc/nginx/.htpasswd 2>/dev/null; then
            user_exists=true
        fi

        if [ "$user_exists" = true ]; then
            log_info "User '${username}' already exists"
            echo "Options: (c)hange password, (s)kip, (d)elete and recreate"
            read -p "Action for ${username}? (c/s/d): " -n 1 -r
            echo

            case $REPLY in
                [Cc])
                    log_info "Changing password for user: ${username}"
                    sudo htpasswd /etc/nginx/.htpasswd "$username"
                    ;;
                [Ss])
                    log_info "Skipping user: ${username}"
                    ;;
                [Dd])
                    log_info "Deleting and recreating user: ${username}"
                    sudo htpasswd -D /etc/nginx/.htpasswd "$username" 2>/dev/null || true
                    sudo htpasswd /etc/nginx/.htpasswd "$username"
                    ;;
                *)
                    log_warning "Invalid option, skipping user: ${username}"
                    ;;
            esac
        else
            log_info "Creating password for user: ${username}"

            # Create file with -c flag if this is the first user and file doesn't exist
            if [ "$htpasswd_exists" = false ] && [ $i -eq 0 ]; then
                sudo htpasswd -c /etc/nginx/.htpasswd "$username"
                htpasswd_exists=true
            else
                sudo htpasswd /etc/nginx/.htpasswd "$username"
            fi
        fi
    done

    # Generate SSL certificate
    log_info "Generating self-signed SSL certificate..."
    sudo mkdir -p /etc/nginx/ssl
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/llama-server.key \
        -out /etc/nginx/ssl/llama-server.crt \
        -subj "/C=US/ST=State/L=City/O=LLaMA-Server/CN=${NGINX_SERVER_NAME}" \
        2>&1 | tee -a "$LOG_FILE"
    check_exit_status "Failed to generate SSL certificate"

    # Create nginx configuration
    log_info "Creating nginx configuration..."
    sudo tee /etc/nginx/sites-available/llama-server > /dev/null << 'EOF'
upstream llama_backend {
    server __SERVER_HOST__:__SERVER_PORT__;
    keepalive 32;
}

# Rate limiting zones
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=__RATE_LIMIT__;
limit_conn_zone $binary_remote_addr zone=conn_limit:10m;

server {
    listen __NGINX_PORT__ ssl http2;
    server_name __NGINX_SERVER_NAME__;

    # SSL Configuration
    ssl_certificate /etc/nginx/ssl/llama-server.crt;
    ssl_certificate_key /etc/nginx/ssl/llama-server.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Logging
    access_log /var/log/nginx/llama-access.log;
    error_log /var/log/nginx/llama-error.log;

    # Basic Authentication
    auth_basic "LLaMA Server Access";
    auth_basic_user_file /etc/nginx/.htpasswd;

    # Main API endpoint
    location / {
        # Rate limiting
        limit_req zone=api_limit burst=__RATE_LIMIT_BURST__ nodelay;
        limit_conn conn_limit 10;

        proxy_pass http://llama_backend;
        proxy_http_version 1.1;

        # Headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Timeouts for long-running LLM requests
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;

        # WebSocket support
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # Disable buffering for streaming responses
        proxy_buffering off;
    }

    # Health check endpoint (no auth)
    location /health {
        proxy_pass http://llama_backend/health;
        auth_basic off;
        access_log off;
    }

    # Metrics endpoint (authenticated)
    location /metrics {
        proxy_pass http://llama_backend/metrics;
    }
}
EOF

    # Replace placeholders
    sudo sed -i "s|__SERVER_HOST__|${SERVER_HOST}|g" /etc/nginx/sites-available/llama-server
    sudo sed -i "s|__SERVER_PORT__|${SERVER_PORT}|g" /etc/nginx/sites-available/llama-server
    sudo sed -i "s|__NGINX_PORT__|${NGINX_PORT}|g" /etc/nginx/sites-available/llama-server
    sudo sed -i "s|__NGINX_SERVER_NAME__|${NGINX_SERVER_NAME}|g" /etc/nginx/sites-available/llama-server
    sudo sed -i "s|__RATE_LIMIT__|${RATE_LIMIT}|g" /etc/nginx/sites-available/llama-server
    sudo sed -i "s|__RATE_LIMIT_BURST__|${RATE_LIMIT_BURST}|g" /etc/nginx/sites-available/llama-server

    # Enable site
    sudo ln -sf /etc/nginx/sites-available/llama-server /etc/nginx/sites-enabled/

    # Test configuration
    log_info "Testing nginx configuration..."
    sudo nginx -t
    check_exit_status "Nginx configuration test failed"

    # Restart nginx
    log_info "Restarting nginx..."
    sudo systemctl restart nginx
    check_exit_status "Failed to restart nginx"

    log "Nginx configured successfully"
}

#######################################
# Phase 6: Setup Cloudflare Tunnel (Optional)
#######################################
setup_cloudflare_tunnel() {
    if [ "$SETUP_CLOUDFLARE" != true ]; then
        log "Skipping Cloudflare Tunnel setup (SETUP_CLOUDFLARE=false)"
        return
    fi

    log "=== Phase 6: Setting up Cloudflare Tunnel ==="

    # Install cloudflared
    if ! command -v cloudflared &> /dev/null; then
        log_info "Installing cloudflared..."
        wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
        sudo dpkg -i cloudflared-linux-amd64.deb
        rm cloudflared-linux-amd64.deb
        check_exit_status "Failed to install cloudflared"
    else
        log_info "cloudflared already installed"
    fi

    # Authenticate
    log_info "Please authenticate with Cloudflare (browser will open)..."
    cloudflared tunnel login
    check_exit_status "Cloudflare authentication failed"

    # Create tunnel
    log_info "Creating tunnel: ${TUNNEL_NAME}..."
    cloudflared tunnel create "$TUNNEL_NAME" || log_warning "Tunnel may already exist"

    # Get tunnel ID
    TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    if [ -z "$TUNNEL_ID" ]; then
        error_exit "Failed to get tunnel ID"
    fi
    log_info "Tunnel ID: ${TUNNEL_ID}"

    # Ask for hostname
    read -p "Enter your tunnel hostname (e.g., llama.yourdomain.com): " TUNNEL_HOSTNAME

    # Create config
    log_info "Creating tunnel configuration..."
    sudo mkdir -p /etc/cloudflared
    sudo tee /etc/cloudflared/config.yml > /dev/null << EOF
tunnel: ${TUNNEL_ID}
credentials-file: /root/.cloudflared/${TUNNEL_ID}.json

ingress:
  - hostname: ${TUNNEL_HOSTNAME}
    service: https://localhost:${NGINX_PORT}
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF

    # Route DNS
    log_info "Creating DNS record..."
    cloudflared tunnel route dns "$TUNNEL_NAME" "$TUNNEL_HOSTNAME"
    check_exit_status "Failed to create DNS record"

    # Install as service
    log_info "Installing cloudflared as service..."
    sudo cloudflared service install
    sudo systemctl start cloudflared
    sudo systemctl enable cloudflared

    log "Cloudflare Tunnel configured successfully"
    log_info "Your server will be accessible at: https://${TUNNEL_HOSTNAME}"
}

#######################################
# Phase 7: Post-deployment Verification
#######################################
post_deployment_checks() {
    log "=== Phase 7: Post-deployment Verification ==="

    # Check llama-server status
    log_info "Checking llama-server status..."
    if sudo systemctl is-active --quiet llama-server; then
        log "✓ llama-server is running"
    else
        log_error "✗ llama-server is not running"
    fi

    # Check nginx status
    if [ "$SETUP_NGINX" = true ]; then
        log_info "Checking nginx status..."
        if sudo systemctl is-active --quiet nginx; then
            log "✓ nginx is running"
        else
            log_error "✗ nginx is not running"
        fi
    fi

    # Check cloudflared status
    if [ "$SETUP_CLOUDFLARE" = true ]; then
        log_info "Checking cloudflared status..."
        if sudo systemctl is-active --quiet cloudflared; then
            log "✓ cloudflared is running"
        else
            log_error "✗ cloudflared is not running"
        fi
    fi

    # Test health endpoint
    log_info "Testing health endpoint..."
    sleep 2
    if curl -s http://${SERVER_HOST}:${SERVER_PORT}/health > /dev/null; then
        log "✓ Server health check passed"
    else
        log_warning "✗ Server health check failed"
    fi

    log "Post-deployment verification completed"
}

#######################################
# Main Deployment Flow
#######################################
main() {
    log "========================================="
    log "llama.cpp ROCm Server Deployment"
    log "========================================="
    log "Started at: $(date)"
    log ""

    preflight_checks

    log ""
    log "Deployment will proceed with the following phases:"
    log "1. Install ROCm ${ROCM_VERSION}"
    log "2. Build llama.cpp with ${GPU_TARGET} support"
    log "3. Download model: ${MODEL_NAME}"
    log "4. Setup systemd service"
    [ "$SETUP_NGINX" = true ] && log "5. Setup nginx reverse proxy"
    [ "$SETUP_CLOUDFLARE" = true ] && log "6. Setup Cloudflare Tunnel"
    log ""

    read -p "Continue with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user"
        exit 0
    fi

    install_rocm
    build_llama_cpp
    download_model
    setup_server_service
    setup_nginx
    setup_cloudflare_tunnel
    post_deployment_checks

    log ""
    log "========================================="
    log "Deployment completed successfully!"
    log "========================================="
    log "Finished at: $(date)"
    log ""
    log "Next steps:"
    log "1. Reboot your system: sudo reboot"
    log "2. After reboot, verify ROCm: rocminfo | grep gfx"
    log "3. Check service status: sudo systemctl status llama-server"

    if [ "$SETUP_NGINX" = true ]; then
        log "4. Test locally: curl -k -u user1 https://localhost:${NGINX_PORT}/health"
    fi

    log ""
    log "Deployment log saved to: ${LOG_FILE}"
}

# Run main deployment
main "$@"
