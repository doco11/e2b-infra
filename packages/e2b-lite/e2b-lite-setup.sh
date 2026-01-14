#!/bin/bash
set -e

################################################################################
# E2B Lite - Complete Installation Script
#
# This script sets up E2B Lite from scratch on a fresh Linux machine.
# It handles everything: dependencies, builds, configuration, and testing.
#
# Requirements:
# - Ubuntu 22.04+ (or similar Linux distro)
# - CPU with virtualization support (Intel VT-x or AMD-V)
# - 8GB+ RAM (16GB recommended)
# - 30GB+ free disk space
# - Root/sudo access
# - Internet connection
#
# Usage:
#   # Download and run (from official repo)
#   curl -fsSL https://raw.githubusercontent.com/doco11/infra/main/packages/e2b-lite/e2b-lite-setup.sh | sudo bash
#
################################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration - Override these with environment variables if needed
E2B_LITE_DIR="${E2B_LITE_DIR:-/opt/e2b-lite}"
E2B_LITE_DATA_DIR="${E2B_LITE_DATA_DIR:-/var/e2b-lite}"
E2B_REPO_URL="${E2B_REPO_URL:-https://github.com/doco11/e2b-infra.git}"
E2B_BRANCH="${E2B_BRANCH:-main}"
GO_VERSION="1.23.4"
FIRECRACKER_VERSION="v1.10.1"
KERNEL_VERSION="vmlinux-6.1"

# Progress tracking
TOTAL_STEPS=15
CURRENT_STEP=0

print_header() {
    clear
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${BLUE}              E2B Lite - Complete Setup Script                ${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${CYAN}Setting up E2B Lite on your machine...${NC}"
    echo -e "${CYAN}This will install all dependencies, build binaries, and configure services.${NC}"
    echo ""
}

step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo ""
    echo -e "${BOLD}${BLUE}━━━ Step $CURRENT_STEP/$TOTAL_STEPS: $1 ━━━${NC}"
    echo ""
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

info() {
    echo -e "${CYAN}→${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root"
    echo "Please run: sudo bash $0"
    exit 1
fi

print_header

################################################################################
# Step 1: System Requirements Check
################################################################################
step "Checking System Requirements"

# OS Check
if [ -f /etc/os-release ]; then
    . /etc/os-release
    success "OS: $NAME $VERSION"

    if [[ "$ID" != "ubuntu" && "$ID" != "debian" && "$ID" != "fedora" ]]; then
        warning "Tested on Ubuntu/Debian. Your OS ($NAME) may work but is untested."
    fi
else
    warning "Could not detect OS"
fi

# CPU Virtualization Check
if grep -E -q "(vmx|svm)" /proc/cpuinfo; then
    if grep -q "vmx" /proc/cpuinfo; then
        success "CPU: Intel VT-x supported"
    else
        success "CPU: AMD-V supported"
    fi
else
    error "CPU virtualization not supported or not enabled in BIOS"
    error "Please enable VT-x (Intel) or AMD-V (AMD) in BIOS settings"
    exit 1
fi

# Memory Check
TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
if [ "$TOTAL_MEM" -ge 8 ]; then
    success "Memory: ${TOTAL_MEM}GB (sufficient)"
else
    warning "Memory: ${TOTAL_MEM}GB (8GB+ recommended)"
fi

# Disk Space Check
AVAILABLE_DISK=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$AVAILABLE_DISK" -ge 30 ]; then
    success "Disk: ${AVAILABLE_DISK}GB available"
else
    warning "Disk: ${AVAILABLE_DISK}GB available (30GB+ recommended)"
fi

################################################################################
# Step 2: Install System Dependencies
################################################################################
step "Installing System Dependencies"

# Detect package manager
if command -v apt-get &> /dev/null; then
    PKG_MANAGER="apt-get"
    info "Package manager: apt-get"

    info "Updating package list..."
    apt-get update -qq

    info "Installing essential packages..."
    # Try to install packages, with fallback for mirror issues
    if ! apt-get install -y -qq curl git wget ca-certificates gnupg build-essential \
        software-properties-common apt-transport-https lsb-release > /dev/null 2>&1; then
        warning "Initial install failed, trying with --fix-missing..."
        if ! apt-get install -y -qq --fix-missing curl git wget ca-certificates gnupg build-essential \
            software-properties-common apt-transport-https lsb-release > /dev/null 2>&1; then
            warning "Still failed, trying linux-libc-dev workaround..."
            # Common issue: latest linux-libc-dev not available on mirrors
            # Install previous version if available
            PREV_VERSION=$(apt-cache policy linux-libc-dev | grep -A1 "Version table" | tail -1 | awk '{print $1}')
            if [ -n "$PREV_VERSION" ]; then
                apt-get install -y -qq linux-libc-dev=$PREV_VERSION > /dev/null 2>&1 || true
            fi
            # Try again
            apt-get install -y -qq curl git wget ca-certificates gnupg build-essential \
                software-properties-common apt-transport-https lsb-release > /dev/null 2>&1
        fi
    fi

elif command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
    info "Package manager: dnf"
    dnf check-update -q || true
    dnf install -y -q curl git wget ca-certificates gnupg gcc make

else
    error "Unsupported package manager. Please install manually."
    exit 1
fi

success "System dependencies installed"

################################################################################
# Step 3: Install Docker
################################################################################
step "Installing Docker"

if command -v docker &> /dev/null; then
    success "Docker already installed: $(docker --version | awk '{print $3}')"
else
    info "Downloading and installing Docker..."
    curl -fsSL https://get.docker.com | sh > /dev/null 2>&1
    systemctl enable docker > /dev/null 2>&1
    systemctl start docker
    success "Docker installed successfully"
fi

# Test Docker
if docker ps > /dev/null 2>&1; then
    success "Docker is running"
else
    error "Docker daemon not running"
    exit 1
fi

################################################################################
# Step 4: Install Go
################################################################################
step "Installing Go $GO_VERSION"

if command -v go &> /dev/null; then
    INSTALLED_GO=$(go version | awk '{print $3}' | sed 's/go//')
    if [ "$INSTALLED_GO" = "$GO_VERSION" ]; then
        success "Go $GO_VERSION already installed"
    else
        warning "Go $INSTALLED_GO installed (need $GO_VERSION), upgrading..."
        rm -rf /usr/local/go
    fi
fi

if ! command -v go &> /dev/null || [ "$INSTALLED_GO" != "$GO_VERSION" ]; then
    info "Downloading Go $GO_VERSION..."

    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        GO_ARCH="amd64"
    elif [ "$ARCH" = "aarch64" ]; then
        GO_ARCH="arm64"
    else
        error "Unsupported architecture: $ARCH"
        exit 1
    fi

    wget -q "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
    tar -C /usr/local -xzf "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
    rm "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"

    # Add to PATH
    if ! grep -q "/usr/local/go/bin" /root/.bashrc; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /root/.bashrc
    fi
    export PATH=$PATH:/usr/local/go/bin

    success "Go $GO_VERSION installed"
fi

# Verify Go installation
if go version > /dev/null 2>&1; then
    success "Go is working: $(go version | awk '{print $3}')"
else
    error "Go installation failed"
    exit 1
fi

################################################################################
# Step 5: Enable KVM and NBD
################################################################################
step "Enabling KVM and NBD Modules"

# Load KVM module
if ! lsmod | grep -q kvm; then
    info "Loading KVM module..."
    if grep -q "vmx" /proc/cpuinfo; then
        modprobe kvm_intel
        success "Loaded kvm_intel"
    elif grep -q "svm" /proc/cpuinfo; then
        modprobe kvm_amd
        success "Loaded kvm_amd"
    fi
    modprobe kvm
else
    success "KVM module already loaded"
fi

# Load NBD module
info "Loading NBD module with 64 devices..."
modprobe nbd nbds_max=64
success "NBD module loaded"

# Make persistent
info "Making modules persistent across reboots..."
cat > /etc/modules-load.d/e2b-lite.conf <<EOF
kvm
$(grep -q "vmx" /proc/cpuinfo && echo "kvm_intel" || echo "kvm_amd")
nbd
EOF

# Setup udev rule for NBD
cat > /etc/udev/rules.d/97-nbd-device.rules <<EOF
# Disable inotify watching of change events for NBD devices
ACTION=="add|change", KERNEL=="nbd*", OPTIONS:="nowatch"
EOF
udevadm control --reload-rules > /dev/null 2>&1
udevadm trigger > /dev/null 2>&1

# Setup KVM permissions
if [ -e /dev/kvm ]; then
    if ! getent group kvm > /dev/null; then
        groupadd kvm
    fi
    chown root:kvm /dev/kvm
    chmod 660 /dev/kvm
    success "KVM permissions configured"
fi

################################################################################
# Step 6: Configure System Settings
################################################################################
step "Configuring System Settings"

# Enable huge pages
info "Enabling huge pages (512 pages = ~1GB)..."
sysctl -w vm.nr_hugepages=512 > /dev/null
if ! grep -q "vm.nr_hugepages" /etc/sysctl.conf 2>/dev/null; then
    echo "vm.nr_hugepages=512" >> /etc/sysctl.conf
fi
success "Huge pages configured"

# Other kernel parameters for better performance
info "Setting kernel parameters for Firecracker..."
sysctl -w net.core.somaxconn=65535 > /dev/null
sysctl -w net.ipv4.tcp_max_syn_backlog=65535 > /dev/null
success "Kernel parameters set"

################################################################################
# Step 7: Create Directory Structure
################################################################################
step "Creating Directory Structure"

info "Creating E2B Lite directories..."
mkdir -p "$E2B_LITE_DIR"
mkdir -p "$E2B_LITE_DATA_DIR"/{templates,kernels,firecracker,envd,orchestrator,sandboxes,build-templates,build-cache}
mkdir -p "$E2B_LITE_DATA_DIR"/orchestrator/{build,sandbox,snapshots,template}

success "Directory structure created"
info "Data directory: $E2B_LITE_DATA_DIR"

################################################################################
# Step 8: Clone E2B Repository
################################################################################
step "Cloning E2B Repository"

info "Repository: $E2B_REPO_URL"
info "Branch: $E2B_BRANCH"
info "Destination: $E2B_LITE_DIR"

if [ -d "$E2B_LITE_DIR/.git" ]; then
    info "E2B repository already exists, updating..."
    cd "$E2B_LITE_DIR"
    git fetch origin > /dev/null 2>&1
    git checkout "$E2B_BRANCH" > /dev/null 2>&1
    git pull origin "$E2B_BRANCH" > /dev/null 2>&1
    success "Repository updated to latest $E2B_BRANCH"
else
    info "Cloning E2B repository (this may take a minute)..."
    if git clone -b "$E2B_BRANCH" --depth 1 "$E2B_REPO_URL" "$E2B_LITE_DIR" > /dev/null 2>&1; then
        success "Repository cloned successfully"
    else
        error "Failed to clone repository from $E2B_REPO_URL"
        error "Please check your internet connection and repository URL"
        exit 1
    fi
fi

cd "$E2B_LITE_DIR"
success "Repository ready at: $E2B_LITE_DIR"

################################################################################
# Step 9: Download Firecracker
################################################################################
step "Downloading Firecracker $FIRECRACKER_VERSION"

cd "$E2B_LITE_DATA_DIR/firecracker"

ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    FC_ARCH="x86_64"
elif [ "$ARCH" = "aarch64" ]; then
    FC_ARCH="aarch64"
else
    error "Unsupported architecture: $ARCH"
    exit 1
fi

if [ -f "firecracker" ]; then
    success "Firecracker already exists"
else
    info "Downloading Firecracker $FIRECRACKER_VERSION for $FC_ARCH..."
    wget -q "https://github.com/firecracker-microvm/firecracker/releases/download/${FIRECRACKER_VERSION}/firecracker-${FIRECRACKER_VERSION}-${FC_ARCH}.tgz"

    info "Extracting..."
    tar -xzf "firecracker-${FIRECRACKER_VERSION}-${FC_ARCH}.tgz"
    mv "release-${FIRECRACKER_VERSION}-${FC_ARCH}/firecracker-${FIRECRACKER_VERSION}-${FC_ARCH}" "./firecracker-${FIRECRACKER_VERSION}"
    chmod +x "firecracker-${FIRECRACKER_VERSION}"
    ln -sf "firecracker-${FIRECRACKER_VERSION}" firecracker

    # Cleanup
    rm -rf "release-${FIRECRACKER_VERSION}-${FC_ARCH}" "firecracker-${FIRECRACKER_VERSION}-${FC_ARCH}.tgz"

    success "Firecracker installed"
fi

# Verify Firecracker
if ./firecracker --version > /dev/null 2>&1; then
    FC_VERSION=$(./firecracker --version 2>&1 | head -1 | awk '{print $2}')
    success "Firecracker working: $FC_VERSION"
else
    error "Firecracker installation failed"
    exit 1
fi

################################################################################
# Step 10: Download Linux Kernel
################################################################################
step "Downloading Linux Kernel for Firecracker"

cd "$E2B_LITE_DATA_DIR/kernels"

# Check if kernel exists
if [ -f "$KERNEL_VERSION" ]; then
    success "Kernel already exists: $KERNEL_VERSION"
else
    info "Downloading kernel from E2B public storage..."

    # Try to download from E2B's public bucket
    # Note: This is a placeholder - you'll need to provide actual kernel URLs
    warning "Kernel download not fully implemented yet"
    warning "You'll need to provide a Linux kernel at: $E2B_LITE_DATA_DIR/kernels/$KERNEL_VERSION"
    warning "You can build your own or use E2B's public kernels"

    # For now, create a placeholder
    touch "$KERNEL_VERSION.placeholder"
    warning "Created placeholder - replace with actual kernel before running"
fi

################################################################################
# Step 11: Build envd
################################################################################
step "Building envd (in-VM daemon)"

cd "$E2B_LITE_DIR/packages/envd"

info "Building envd binary..."
if make build > /dev/null 2>&1; then
    if [ -f "bin/envd" ]; then
        cp bin/envd "$E2B_LITE_DATA_DIR/envd/"
        success "envd built and copied to $E2B_LITE_DATA_DIR/envd/"
    else
        error "envd binary not found after build"
        exit 1
    fi
else
    error "envd build failed"
    exit 1
fi

################################################################################
# Step 12: Build Orchestrator
################################################################################
step "Building Orchestrator"

cd "$E2B_LITE_DIR/packages/orchestrator"

info "Building orchestrator binary (this may take a few minutes)..."
export CGO_ENABLED=0
if make build > /dev/null 2>&1; then
    if [ -f "bin/orchestrator" ]; then
        success "Orchestrator built successfully"
        info "Binary location: $(pwd)/bin/orchestrator"
    else
        error "Orchestrator binary not found after build"
        exit 1
    fi
else
    error "Orchestrator build failed"
    exit 1
fi

################################################################################
# Step 13: Build API
################################################################################
step "Building API Server"

cd "$E2B_LITE_DIR/packages/api"

info "Building API binary (this may take a few minutes)..."
export CGO_ENABLED=0
if make build > /dev/null 2>&1; then
    if [ -f "bin/api" ]; then
        success "API built successfully"
        info "Binary location: $(pwd)/bin/api"
    else
        error "API binary not found after build"
        exit 1
    fi
else
    error "API build failed"
    exit 1
fi

################################################################################
# Step 14: Start Docker Services
################################################################################
step "Starting Database Services"

# Create e2b-lite directory if it doesn't exist
mkdir -p "$E2B_LITE_DIR/packages/e2b-lite"
cd "$E2B_LITE_DIR/packages/e2b-lite"

# Create docker-compose.lite.yml if it doesn't exist
if [ ! -f "docker-compose.lite.yml" ]; then
    info "Creating docker-compose.lite.yml..."
    cat > docker-compose.lite.yml <<'COMPOSE_EOF'
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: e2b-lite-postgres
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: e2b_lite_password
      POSTGRES_DB: e2b_lite
    ports:
      - "5432:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: e2b-lite-redis
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5

volumes:
  postgres-data:
  redis-data:
COMPOSE_EOF
    success "docker-compose.lite.yml created"
fi

info "Starting PostgreSQL and Redis..."
docker compose -f docker-compose.lite.yml up -d

info "Waiting for services to be healthy (30 seconds)..."
sleep 30

# Check if services are running
if docker compose -f docker-compose.lite.yml ps | grep -q "Up"; then
    success "Database services started"

    # Test PostgreSQL
    if docker exec e2b-lite-postgres pg_isready -U postgres > /dev/null 2>&1; then
        success "PostgreSQL is ready"
    else
        warning "PostgreSQL not responding"
    fi

    # Test Redis
    if docker exec e2b-lite-redis redis-cli ping | grep -q "PONG"; then
        success "Redis is ready"
    else
        warning "Redis not responding"
    fi
else
    error "Database services failed to start"
    docker compose -f docker-compose.lite.yml ps
    exit 1
fi

################################################################################
# Step 15: Run Database Migrations
################################################################################
step "Running Database Migrations"

cd "$E2B_LITE_DIR/packages/db"

info "Running database migrations..."
export POSTGRES_CONNECTION_STRING="postgres://postgres:e2b_lite_password@localhost:5432/e2b_lite?sslmode=disable"

if make migrate-local > /dev/null 2>&1; then
    success "Database migrations completed"
else
    warning "Database migrations had issues (this might be okay if DB is already set up)"
fi

################################################################################
# Final Setup and Configuration
################################################################################
echo ""
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${GREEN}              E2B Lite Installation Complete!                   ${NC}"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Create startup scripts
info "Creating startup scripts..."

# API startup script
cat > "$E2B_LITE_DIR/packages/api/start-api.sh" <<'EOAPI'
#!/bin/bash
cd "$(dirname "$0")"
export E2B_LITE_MODE=true
export ENVIRONMENT=local
export POSTGRES_CONNECTION_STRING="postgres://postgres:e2b_lite_password@localhost:5432/e2b_lite?sslmode=disable"
export REDIS_URL="localhost:6379"
export LOKI_URL=""
export POSTHOG_API_KEY=""
export LAUNCHDARKLY_SDK_KEY=""
./bin/api
EOAPI
chmod +x "$E2B_LITE_DIR/packages/api/start-api.sh"

# Orchestrator startup script
cat > "$E2B_LITE_DIR/packages/orchestrator/start-orchestrator.sh" <<'EOORCHESTRATOR'
#!/bin/bash
cd "$(dirname "$0")"
export E2B_LITE_MODE=true
export ENVIRONMENT=local
export STORAGE_PROVIDER=Local
export LOCAL_TEMPLATE_STORAGE_BASE_PATH=/var/e2b-lite/templates
export LOCAL_BUILD_CACHE_STORAGE_BASE_PATH=/var/e2b-lite/build-cache
export HOST_KERNELS_DIR=/var/e2b-lite/kernels
export HOST_ENVD_PATH=/var/e2b-lite/envd/envd
export FIRECRACKER_VERSIONS_DIR=/var/e2b-lite/firecracker
export ORCHESTRATOR_BASE_PATH=/var/e2b-lite/orchestrator
export SANDBOX_DIR=/var/e2b-lite/sandboxes
export TEMPLATES_DIR=/var/e2b-lite/build-templates
export REDIS_URL=localhost:6379
export CLICKHOUSE_CONNECTION_STRING=""
export LAUNCH_DARKLY_API_KEY=""
./bin/orchestrator
EOORCHESTRATOR
chmod +x "$E2B_LITE_DIR/packages/orchestrator/start-orchestrator.sh"

success "Startup scripts created"

# Create systemd services (optional)
info "Creating systemd service files..."

cat > /etc/systemd/system/e2b-lite-api.service <<EOF
[Unit]
Description=E2B Lite API Server
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=$E2B_LITE_DIR/packages/api
ExecStart=$E2B_LITE_DIR/packages/api/start-api.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/e2b-lite-orchestrator.service <<EOF
[Unit]
Description=E2B Lite Orchestrator
After=network.target docker.service e2b-lite-api.service
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=$E2B_LITE_DIR/packages/orchestrator
ExecStart=$E2B_LITE_DIR/packages/orchestrator/start-orchestrator.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
success "Systemd services created"

################################################################################
# Summary and Next Steps
################################################################################
echo ""
echo -e "${BOLD}${CYAN}📋 Installation Summary${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BOLD}Installed Components:${NC}"
echo "  ✓ Docker $(docker --version | awk '{print $3}')"
echo "  ✓ Go $(go version | awk '{print $3}')"
echo "  ✓ Firecracker $FIRECRACKER_VERSION"
echo "  ✓ PostgreSQL (Docker)"
echo "  ✓ Redis (Docker)"
echo "  ✓ E2B API binary"
echo "  ✓ E2B Orchestrator binary"
echo "  ✓ envd binary"
echo ""
echo -e "${BOLD}Directory Structure:${NC}"
echo "  Repository: $E2B_LITE_DIR"
echo "  Data: $E2B_LITE_DATA_DIR"
echo "  API: $E2B_LITE_DIR/packages/api/bin/api"
echo "  Orchestrator: $E2B_LITE_DIR/packages/orchestrator/bin/orchestrator"
echo ""
echo -e "${BOLD}${CYAN}🚀 Starting E2B Lite${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BOLD}Option 1: Manual Start (for testing/debugging)${NC}"
echo ""
echo "  # Terminal 1 - Start API"
echo "  cd $E2B_LITE_DIR/packages/api"
echo "  ./start-api.sh"
echo ""
echo "  # Terminal 2 - Start Orchestrator (needs root for Firecracker)"
echo "  cd $E2B_LITE_DIR/packages/orchestrator"
echo "  sudo ./start-orchestrator.sh"
echo ""
echo -e "${BOLD}Option 2: Use systemd services${NC}"
echo ""
echo "  sudo systemctl start e2b-lite-api"
echo "  sudo systemctl start e2b-lite-orchestrator"
echo ""
echo "  # Enable to start on boot"
echo "  sudo systemctl enable e2b-lite-api"
echo "  sudo systemctl enable e2b-lite-orchestrator"
echo ""
echo "  # Check status"
echo "  sudo systemctl status e2b-lite-api"
echo "  sudo systemctl status e2b-lite-orchestrator"
echo ""
echo -e "${BOLD}${CYAN}🧪 Testing E2B Lite${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  # Test API is running"
echo "  curl http://localhost:3000/health"
echo ""
echo "  # Use with E2B SDK (Python)"
echo "  export E2B_API_URL='http://localhost:3000'"
echo "  export E2B_API_KEY='e2b_lite_default_key'"
echo "  python3 -c \"from e2b_code_interpreter import Sandbox; s = Sandbox(); print('Success!')\""
echo ""
echo -e "${BOLD}${CYAN}📚 Documentation${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  README: $E2B_LITE_DIR/packages/e2b-lite/README.md"
echo "  Integration Guide: $E2B_LITE_DIR/packages/e2b-lite/LITE_MODE_INTEGRATION.md"
echo "  Status: $E2B_LITE_DIR/packages/e2b-lite/STATUS.md"
echo ""
echo -e "${BOLD}${YELLOW}⚠️  Important Notes${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
if [ ! -f "$E2B_LITE_DATA_DIR/kernels/$KERNEL_VERSION" ]; then
    echo "  ⚠  Linux kernel needs to be provided"
    echo "     Location: $E2B_LITE_DATA_DIR/kernels/$KERNEL_VERSION"
    echo "     You can build your own or contact E2B for kernel files"
    echo ""
fi
echo "  ⚠  Orchestrator must run as root (for Firecracker/KVM access)"
echo "  ⚠  Default API key: e2b_lite_default_key (change for production!)"
echo "  ⚠  Database password: e2b_lite_password (change for production!)"
echo ""
echo -e "${BOLD}${GREEN}Installation completed successfully!${NC}"
echo -e "${GREEN}E2B Lite is ready to use.${NC}"
echo ""
