#!/bin/bash
set -uo pipefail

#######################################
# llama.cpp Server Management Utility
# Manage, monitor, and troubleshoot your LLM server
#######################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo -e "${RED}Error: Configuration file not found${NC}"
    exit 1
fi

#######################################
# Helper Functions
#######################################
print_header() {
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}=========================================${NC}"
}

print_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

check_service() {
    if systemctl is-active --quiet "$1"; then
        echo -e "${GREEN}✓ Running${NC}"
        return 0
    else
        echo -e "${RED}✗ Stopped${NC}"
        return 1
    fi
}

#######################################
# Status Command
#######################################
cmd_status() {
    print_header "Server Status"

    print_section "Service Status"
    echo -n "llama-server: "
    check_service llama-server

    if [ "$SETUP_NGINX" = true ]; then
        echo -n "nginx: "
        check_service nginx
    fi

    if [ "$SETUP_CLOUDFLARE" = true ] && systemctl list-unit-files | grep -q cloudflared; then
        echo -n "cloudflared: "
        check_service cloudflared
    fi

    print_section "Resource Usage"

    # GPU usage
    if command -v rocm-smi &> /dev/null; then
        echo -e "\n${YELLOW}GPU Usage:${NC}"
        rocm-smi --showuse 2>/dev/null || echo "Unable to get GPU stats"
    elif command -v radeontop &> /dev/null; then
        echo -e "\n${YELLOW}GPU Usage (radeontop):${NC}"
        echo "Run: radeontop -d - -l 1"
    fi

    # Memory usage
    echo -e "\n${YELLOW}Memory Usage:${NC}"
    free -h

    # CPU usage
    echo -e "\n${YELLOW}CPU Usage:${NC}"
    top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print "CPU Usage: " 100 - $1"%"}'

    # Disk usage
    echo -e "\n${YELLOW}Disk Usage:${NC}"
    df -h / | tail -1

    print_section "Active Connections"
    if [ "$SETUP_NGINX" = true ]; then
        CONNECTIONS=$(ss -tn | grep ":${NGINX_PORT}" | wc -l)
        echo "Active HTTPS connections: ${CONNECTIONS}"
    fi

    SERVER_CONNECTIONS=$(ss -tn | grep ":${SERVER_PORT}" | wc -l)
    echo "Active server connections: ${SERVER_CONNECTIONS}"

    print_section "Recent Activity"
    if [ -f "${INSTALL_DIR}/logs/server.log" ]; then
        echo -e "\n${YELLOW}Last 5 server log entries:${NC}"
        tail -5 "${INSTALL_DIR}/logs/server.log"
    fi

    if [ "$SETUP_NGINX" = true ] && [ -f "/var/log/nginx/llama-access.log" ]; then
        echo -e "\n${YELLOW}Last 5 access log entries:${NC}"
        sudo tail -5 /var/log/nginx/llama-access.log
    fi
}

#######################################
# Logs Command
#######################################
cmd_logs() {
    local service=${1:-llama-server}
    local lines=${2:-50}

    print_header "Service Logs: ${service}"

    case $service in
        llama-server|server|llama)
            echo -e "${YELLOW}=== Server Logs (last ${lines} lines) ===${NC}"
            if [ -f "${INSTALL_DIR}/logs/server.log" ]; then
                tail -n "$lines" "${INSTALL_DIR}/logs/server.log"
            else
                echo "Log file not found"
            fi

            echo -e "\n${YELLOW}=== Error Logs (last ${lines} lines) ===${NC}"
            if [ -f "${INSTALL_DIR}/logs/error.log" ]; then
                tail -n "$lines" "${INSTALL_DIR}/logs/error.log"
            else
                echo "No errors logged"
            fi
            ;;

        nginx)
            echo -e "${YELLOW}=== Nginx Access Logs (last ${lines} lines) ===${NC}"
            sudo tail -n "$lines" /var/log/nginx/llama-access.log 2>/dev/null || echo "Log file not found"

            echo -e "\n${YELLOW}=== Nginx Error Logs (last ${lines} lines) ===${NC}"
            sudo tail -n "$lines" /var/log/nginx/llama-error.log 2>/dev/null || echo "No errors logged"
            ;;

        cloudflared|tunnel)
            sudo journalctl -u cloudflared -n "$lines" --no-pager
            ;;

        *)
            echo "Unknown service: ${service}"
            echo "Available: llama-server, nginx, cloudflared"
            exit 1
            ;;
    esac
}

#######################################
# Follow Logs Command
#######################################
cmd_follow() {
    local service=${1:-llama-server}

    print_header "Following Logs: ${service}"

    case $service in
        llama-server|server|llama)
            tail -f "${INSTALL_DIR}/logs/server.log"
            ;;

        nginx)
            sudo tail -f /var/log/nginx/llama-access.log
            ;;

        cloudflared|tunnel)
            sudo journalctl -u cloudflared -f
            ;;

        *)
            echo "Unknown service: ${service}"
            exit 1
            ;;
    esac
}

#######################################
# Start/Stop/Restart Commands
#######################################
cmd_start() {
    print_header "Starting Services"
    sudo systemctl start llama-server
    echo -e "${GREEN}llama-server started${NC}"

    if [ "$SETUP_NGINX" = true ]; then
        sudo systemctl start nginx
        echo -e "${GREEN}nginx started${NC}"
    fi
}

cmd_stop() {
    print_header "Stopping Services"
    sudo systemctl stop llama-server
    echo -e "${YELLOW}llama-server stopped${NC}"

    if [ "$SETUP_NGINX" = true ]; then
        sudo systemctl stop nginx
        echo -e "${YELLOW}nginx stopped${NC}"
    fi
}

cmd_restart() {
    print_header "Restarting Services"
    sudo systemctl restart llama-server
    echo -e "${GREEN}llama-server restarted${NC}"

    if [ "$SETUP_NGINX" = true ]; then
        sudo systemctl restart nginx
        echo -e "${GREEN}nginx restarted${NC}"
    fi

    sleep 2
    cmd_status
}

#######################################
# Test Command
#######################################
cmd_test() {
    print_header "Running Server Tests"

    print_section "Health Check"
    if curl -s http://${SERVER_HOST}:${SERVER_PORT}/health > /dev/null; then
        echo -e "${GREEN}✓ Server health check passed${NC}"
    else
        echo -e "${RED}✗ Server health check failed${NC}"
    fi

    if [ "$SETUP_NGINX" = true ]; then
        print_section "Nginx Health Check"
        if curl -k -s https://localhost:${NGINX_PORT}/health > /dev/null; then
            echo -e "${GREEN}✓ Nginx proxy health check passed${NC}"
        else
            echo -e "${RED}✗ Nginx proxy health check failed${NC}"
        fi

        print_section "Simple Completion Test"
        echo "Testing with authenticated request..."
        echo "Enter username for test:"
        read -r username

        RESPONSE=$(curl -k -u "${username}" -s -X POST https://localhost:${NGINX_PORT}/completion \
            -H "Content-Type: application/json" \
            -d '{
                "prompt": "Hello, what is 2+2?",
                "n_predict": 50,
                "temperature": 0.7
            }')

        if [ -n "$RESPONSE" ]; then
            echo -e "${GREEN}✓ Completion request successful${NC}"
            echo -e "\nResponse preview:"
            echo "$RESPONSE" | head -c 500
        else
            echo -e "${RED}✗ Completion request failed${NC}"
        fi
    fi
}

#######################################
# GPU Monitor Command
#######################################
cmd_gpu() {
    print_header "GPU Monitoring"

    if command -v rocm-smi &> /dev/null; then
        echo -e "${YELLOW}ROCm SMI:${NC}"
        rocm-smi
    fi

    if command -v radeontop &> /dev/null; then
        echo -e "\n${YELLOW}Starting radeontop (Ctrl+C to exit)...${NC}"
        sleep 2
        radeontop
    else
        echo "radeontop not installed. Install with: sudo apt install radeontop"
    fi
}

#######################################
# Users Command
#######################################
cmd_users() {
    print_header "User Management"

    print_section "Current Users"
    if [ -f /etc/nginx/.htpasswd ]; then
        echo "Registered users:"
        cut -d: -f1 /etc/nginx/.htpasswd | nl
    else
        echo "No users configured"
        return
    fi

    echo ""
    echo "Actions:"
    echo "1. Add user"
    echo "2. Remove user"
    echo "3. Change password"
    echo "4. Exit"
    read -p "Select action: " action

    case $action in
        1)
            read -p "Enter new username: " username
            sudo htpasswd /etc/nginx/.htpasswd "$username"
            echo -e "${GREEN}User added${NC}"
            ;;
        2)
            read -p "Enter username to remove: " username
            sudo htpasswd -D /etc/nginx/.htpasswd "$username"
            echo -e "${YELLOW}User removed${NC}"
            ;;
        3)
            read -p "Enter username: " username
            sudo htpasswd /etc/nginx/.htpasswd "$username"
            echo -e "${GREEN}Password updated${NC}"
            ;;
        4)
            return
            ;;
        *)
            echo "Invalid action"
            ;;
    esac
}

#######################################
# Model Switch Command
#######################################
cmd_model() {
    print_header "Model Management"

    print_section "Current Model"
    echo "Active model: ${MODEL_NAME}"

    print_section "Available Models"
    if [ -d "${INSTALL_DIR}/models" ]; then
        ls -lh "${INSTALL_DIR}/models/"*.gguf 2>/dev/null || echo "No models found"
    fi

    echo ""
    read -p "Enter path to new model file (or press Enter to skip): " new_model

    if [ -n "$new_model" ]; then
        if [ -f "$new_model" ]; then
            MODEL_BASENAME=$(basename "$new_model")
            cp "$new_model" "${INSTALL_DIR}/models/"
            echo -e "${GREEN}Model copied to ${INSTALL_DIR}/models/${MODEL_BASENAME}${NC}"
            echo -e "${YELLOW}Update config.env and restart service to use new model${NC}"
        else
            echo -e "${RED}Model file not found${NC}"
        fi
    fi
}

#######################################
# Benchmark Command
#######################################
cmd_benchmark() {
    print_header "Running Benchmark"

    if [ ! -f "${INSTALL_DIR}/models/${MODEL_NAME}" ]; then
        echo -e "${RED}Model not found${NC}"
        exit 1
    fi

    print_section "Configuration"
    echo "Model: ${MODEL_NAME}"
    echo "GPU Layers: ${GPU_LAYERS}"
    echo "Context Size: ${CONTEXT_SIZE}"
    echo "Threads: ${SERVER_THREADS}"

    print_section "Running llama-bench"

    if command -v llama-bench &> /dev/null; then
        llama-bench \
            -m "${INSTALL_DIR}/models/${MODEL_NAME}" \
            -ngl ${GPU_LAYERS} \
            -t ${SERVER_THREADS}
    else
        echo "llama-bench not found"
        echo "Run: ${SCRIPT_DIR}/llama.cpp/build/bin/llama-bench -m ${INSTALL_DIR}/models/${MODEL_NAME}"
    fi
}

#######################################
# Diagnostics Command
#######################################
cmd_diagnostics() {
    print_header "System Diagnostics"

    print_section "ROCm Information"
    if command -v rocminfo &> /dev/null; then
        rocminfo | grep -E "Name|gfx|VRAM"
    else
        echo "ROCm not installed"
    fi

    print_section "GPU Detection"
    lspci | grep -i vga

    print_section "Environment Variables"
    echo "HSA_OVERRIDE_GFX_VERSION: ${HSA_OVERRIDE_GFX_VERSION:-not set}"
    echo "HSA_ENABLE_SDMA: ${HSA_ENABLE_SDMA:-not set}"
    echo "PATH: ${PATH}"

    print_section "Service Files"
    echo "llama-server service:"
    systemctl cat llama-server 2>/dev/null | head -20

    print_section "Port Listeners"
    echo "Ports in use:"
    sudo ss -tulpn | grep -E ":(${SERVER_PORT}|${NGINX_PORT})"

    print_section "System Load"
    uptime

    print_section "Recent Errors"
    if [ -f "${INSTALL_DIR}/logs/error.log" ]; then
        tail -10 "${INSTALL_DIR}/logs/error.log"
    else
        echo "No errors logged"
    fi
}

#######################################
# Backup Command
#######################################
cmd_backup() {
    print_header "Creating Backup"

    BACKUP_DIR="${SCRIPT_DIR}/backups"
    mkdir -p "$BACKUP_DIR"

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="${BACKUP_DIR}/llama-server-backup-${TIMESTAMP}.tar.gz"

    print_section "Backing up configuration and logs"

    tar -czf "$BACKUP_FILE" \
        -C / \
        etc/systemd/system/llama-server.service \
        etc/nginx/sites-available/llama-server \
        etc/nginx/.htpasswd \
        "${INSTALL_DIR}/logs" \
        2>/dev/null

    if [ -f "$BACKUP_FILE" ]; then
        echo -e "${GREEN}Backup created: ${BACKUP_FILE}${NC}"
        ls -lh "$BACKUP_FILE"
    else
        echo -e "${RED}Backup failed${NC}"
    fi
}

#######################################
# Help Command
#######################################
cmd_help() {
    cat << EOF
llama.cpp Server Management Utility

Usage: $0 <command> [options]

Commands:
  status              Show server status and resource usage
  logs [service] [n]  Show logs (default: llama-server, 50 lines)
  follow [service]    Follow logs in real-time
  start               Start all services
  stop                Stop all services
  restart             Restart all services
  test                Run server tests
  gpu                 Monitor GPU usage
  users               Manage user accounts
  model               Manage models
  benchmark           Run performance benchmark
  diagnostics         Run system diagnostics
  backup              Create configuration backup
  help                Show this help message

Services:
  llama-server        Main LLM server
  nginx               Reverse proxy
  cloudflared         Cloudflare tunnel (if configured)

Examples:
  $0 status                    # Show full status
  $0 logs nginx 100            # Show last 100 nginx log lines
  $0 follow llama-server       # Follow server logs
  $0 restart                   # Restart all services
  $0 test                      # Run health checks

EOF
}

#######################################
# Main Command Router
#######################################
main() {
    local command=${1:-help}
    shift || true

    case $command in
        status)
            cmd_status "$@"
            ;;
        logs)
            cmd_logs "$@"
            ;;
        follow|tail)
            cmd_follow "$@"
            ;;
        start)
            cmd_start
            ;;
        stop)
            cmd_stop
            ;;
        restart)
            cmd_restart
            ;;
        test)
            cmd_test
            ;;
        gpu)
            cmd_gpu
            ;;
        users)
            cmd_users
            ;;
        model|models)
            cmd_model
            ;;
        benchmark|bench)
            cmd_benchmark
            ;;
        diagnostics|diag)
            cmd_diagnostics
            ;;
        backup)
            cmd_backup
            ;;
        help|--help|-h)
            cmd_help
            ;;
        *)
            echo "Unknown command: $command"
            echo "Run '$0 help' for usage"
            exit 1
            ;;
    esac
}

main "$@"
