#!/bin/bash
set -uo pipefail

#######################################
# Pre-flight System Requirements Checker
# Validates system before deployment
#######################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
PASSED=0
FAILED=0
WARNINGS=0

#######################################
# Check Functions
#######################################
check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

check_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

#######################################
# System Checks
#######################################
echo "========================================="
echo "System Requirements Check"
echo "========================================="
echo ""

# Load config if available
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    check_pass "Configuration file found"
else
    check_warn "Configuration file not found (using defaults)"
fi

echo ""
echo "=== Operating System ==="

# Check OS
if [ -f /etc/os-release ]; then
    source /etc/os-release
    check_info "OS: ${PRETTY_NAME}"

    if [[ "$ID" == "ubuntu" ]]; then
        check_pass "Ubuntu detected"

        if [[ "$VERSION_ID" == "24.04" ]]; then
            check_pass "Ubuntu 24.04 LTS"
        else
            check_warn "Ubuntu version is ${VERSION_ID}, expected 24.04"
        fi
    else
        check_warn "OS is ${ID}, script optimized for Ubuntu"
    fi
else
    check_fail "Cannot determine OS version"
fi

# Check kernel version
KERNEL_VERSION=$(uname -r)
check_info "Kernel: ${KERNEL_VERSION}"

# Check architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    check_pass "Architecture: ${ARCH}"
else
    check_fail "Architecture ${ARCH} not supported (need x86_64)"
fi

echo ""
echo "=== Hardware ==="

# CPU Info
CPU_MODEL=$(lscpu | grep "Model name" | cut -d':' -f2 | xargs)
check_info "CPU: ${CPU_MODEL}"

CPU_CORES=$(nproc)
if [ "$CPU_CORES" -ge 4 ]; then
    check_pass "CPU cores: ${CPU_CORES}"
else
    check_warn "Only ${CPU_CORES} CPU cores available (recommended: 4+)"
fi

# Check for AMD CPU
if echo "$CPU_MODEL" | grep -qi "AMD"; then
    check_pass "AMD CPU detected"

    # Check for Zen architecture
    if echo "$CPU_MODEL" | grep -qi "Ryzen"; then
        check_pass "AMD Ryzen processor"
    fi
else
    check_warn "Non-AMD CPU detected (ROCm requires AMD GPUs)"
fi

# Memory
TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
if [ "$TOTAL_MEM" -ge 16 ]; then
    check_pass "Total RAM: ${TOTAL_MEM}GB"
elif [ "$TOTAL_MEM" -ge 8 ]; then
    check_warn "Total RAM: ${TOTAL_MEM}GB (16GB+ recommended)"
else
    check_fail "Total RAM: ${TOTAL_MEM}GB (minimum 8GB required)"
fi

# Disk space
DISK_AVAIL=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$DISK_AVAIL" -ge 50 ]; then
    check_pass "Available disk space: ${DISK_AVAIL}GB"
elif [ "$DISK_AVAIL" -ge 20 ]; then
    check_warn "Available disk space: ${DISK_AVAIL}GB (50GB+ recommended)"
else
    check_fail "Available disk space: ${DISK_AVAIL}GB (minimum 20GB required)"
fi

echo ""
echo "=== GPU Detection ==="

# Check for AMD GPU
if lspci | grep -i vga | grep -qi "amd"; then
    GPU_INFO=$(lspci | grep -i vga | grep -i amd)
    check_pass "AMD GPU detected"
    check_info "GPU: ${GPU_INFO}"

    # Check for Radeon 780M specifically
    if echo "$GPU_INFO" | grep -qi "780M"; then
        check_pass "Radeon 780M Graphics detected"
    fi
else
    check_fail "No AMD GPU detected"
fi

# Check if GPU is visible to system
if [ -d "/sys/class/drm" ]; then
    GPU_COUNT=$(ls /sys/class/drm/card* 2>/dev/null | grep -c "card[0-9]$" || echo "0")
    check_info "DRM devices found: ${GPU_COUNT}"
fi

# Check render group
if groups | grep -q render; then
    check_pass "User is in 'render' group"
else
    check_warn "User not in 'render' group (required for ROCm)"
fi

if groups | grep -q video; then
    check_pass "User is in 'video' group"
else
    check_warn "User not in 'video' group (required for ROCm)"
fi

echo ""
echo "=== ROCm Installation Status ==="

# Check if ROCm is installed
if command -v rocminfo &> /dev/null; then
    check_pass "ROCm tools installed"

    # Check ROCm version
    ROCM_VERSION=$(apt list --installed 2>/dev/null | grep rocm-core | head -1 | awk '{print $2}' || echo "unknown")
    check_info "ROCm version: ${ROCM_VERSION}"

    # Run rocminfo
    if rocminfo &> /dev/null; then
        check_pass "rocminfo runs successfully"

        # Check for gfx target
        GFX_TARGET=$(rocminfo | grep -o "gfx[0-9]*" | head -1 || echo "unknown")
        if [ "$GFX_TARGET" != "unknown" ]; then
            check_pass "GPU compute target: ${GFX_TARGET}"

            if [ "$GFX_TARGET" == "gfx1103" ]; then
                check_pass "Correct target for Radeon 780M (gfx1103)"
            else
                check_info "GPU target is ${GFX_TARGET}"
            fi
        else
            check_warn "Could not determine GPU compute target"
        fi
    else
        check_fail "rocminfo fails to run"
    fi

    # Check clinfo
    if command -v clinfo &> /dev/null; then
        if clinfo &> /dev/null; then
            check_pass "OpenCL available"
            OPENCL_DEVICES=$(clinfo 2>/dev/null | grep -c "Device Name" || echo "0")
            check_info "OpenCL devices: ${OPENCL_DEVICES}"
        else
            check_warn "clinfo fails to run"
        fi
    fi
else
    check_warn "ROCm not installed (will be installed during deployment)"
fi

echo ""
echo "=== Required Tools ==="

# Check for required commands
declare -a REQUIRED_TOOLS=("wget" "curl" "git" "gcc" "g++" "make" "cmake")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$tool" &> /dev/null; then
        VERSION=$($tool --version 2>/dev/null | head -1 || echo "installed")
        check_pass "${tool} is installed"
    else
        check_warn "${tool} not found (will be installed)"
    fi
done

echo ""
echo "=== Network Connectivity ==="

# Check internet connectivity
if ping -c 1 8.8.8.8 &> /dev/null; then
    check_pass "Internet connectivity"
else
    check_fail "No internet connectivity"
fi

# Check specific URLs
declare -a URLS=(
    "https://github.com"
    "https://huggingface.co"
    "https://repo.radeon.com"
)

for url in "${URLS[@]}"; do
    if curl -s --head --request GET "$url" | grep "200\|301\|302" > /dev/null; then
        check_pass "Can reach ${url}"
    else
        check_warn "Cannot reach ${url}"
    fi
done

echo ""
echo "=== Port Availability ==="

# Check if required ports are available
check_port() {
    local port=$1
    local service=$2

    if ss -tuln | grep -q ":${port} "; then
        check_warn "Port ${port} (${service}) is already in use"
    else
        check_pass "Port ${port} (${service}) is available"
    fi
}

check_port 8080 "llama-server"
check_port 8443 "nginx"

echo ""
echo "=== Existing Services ==="

# Check if services already exist
if systemctl list-unit-files | grep -q "llama-server.service"; then
    SERVICE_STATUS=$(systemctl is-active llama-server 2>/dev/null || echo "inactive")
    check_info "llama-server service exists (status: ${SERVICE_STATUS})"
else
    check_info "llama-server service not installed"
fi

if command -v nginx &> /dev/null; then
    NGINX_STATUS=$(systemctl is-active nginx 2>/dev/null || echo "inactive")
    check_info "nginx installed (status: ${NGINX_STATUS})"
else
    check_info "nginx not installed"
fi

echo ""
echo "=== Security ==="

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    check_fail "Running as root (please run as regular user)"
else
    check_pass "Running as non-root user"
fi

# Check sudo access
if sudo -n true 2>/dev/null; then
    check_pass "Passwordless sudo available"
else
    if sudo -v 2>/dev/null; then
        check_pass "Sudo access available"
    else
        check_fail "No sudo access"
    fi
fi

# Check firewall status
if command -v ufw &> /dev/null; then
    UFW_STATUS=$(sudo ufw status 2>/dev/null | head -1 || echo "unknown")
    check_info "UFW status: ${UFW_STATUS}"
fi

echo ""
echo "========================================="
echo "Summary"
echo "========================================="
echo -e "${GREEN}Passed:${NC}   ${PASSED}"
echo -e "${YELLOW}Warnings:${NC} ${WARNINGS}"
echo -e "${RED}Failed:${NC}   ${FAILED}"
echo ""

if [ $FAILED -eq 0 ]; then
    if [ $WARNINGS -eq 0 ]; then
        echo -e "${GREEN}✓ System is ready for deployment!${NC}"
        exit 0
    else
        echo -e "${YELLOW}⚠ System is mostly ready, but there are warnings to review.${NC}"
        exit 0
    fi
else
    echo -e "${RED}✗ System has critical issues that must be resolved before deployment.${NC}"
    exit 1
fi
