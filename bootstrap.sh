#!/bin/bash
# =============================================================================
# AirPrint PDF Stack - Bootstrap Installer
# =============================================================================
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/mwilco03/airprint-pdf-stack/main/bootstrap.sh | bash
#
# Or with custom install directory:
#   curl -fsSL https://raw.githubusercontent.com/mwilco03/airprint-pdf-stack/main/bootstrap.sh | bash -s -- /opt/airprint
#
# =============================================================================

set -e

# =============================================================================
# Constants
# =============================================================================
readonly REPO_URL="https://github.com/mwilco03/airprint-pdf-stack.git"
readonly REPO_BRANCH="main"
readonly DEFAULT_INSTALL_DIR="${HOME}/airprint-pdf-stack"
readonly INSTALL_DIR="${1:-$DEFAULT_INSTALL_DIR}"
readonly MIN_DOCKER_VERSION="20.0.0"

# =============================================================================
# Colors
# =============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# =============================================================================
# Logging
# =============================================================================
log_header() {
    echo -e "\n${PURPLE}${BOLD}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}${BOLD}  $1${NC}"
    echo -e "${PURPLE}${BOLD}══════════════════════════════════════════════════════════════${NC}\n"
}

log_step() {
    echo -e "${BLUE}[*]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[+]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[-]${NC} $1" >&2
}

log_info() {
    echo -e "${CYAN}[i]${NC} $1"
}

# =============================================================================
# Utility Functions
# =============================================================================
command_exists() {
    command -v "$1" &> /dev/null
}

version_gte() {
    # Returns 0 if $1 >= $2
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

get_local_ip() {
    local ip=""
    if command_exists hostname; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    if [[ -z "$ip" ]] && command_exists ip; then
        ip=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
    fi
    if [[ -z "$ip" ]]; then
        ip="localhost"
    fi
    echo "$ip"
}

cleanup_on_error() {
    log_error "Installation failed. Cleaning up..."
    if [[ -d "$INSTALL_DIR" ]] && [[ "$CLEANUP_ON_FAIL" == "true" ]]; then
        rm -rf "$INSTALL_DIR"
    fi
    exit 1
}

# =============================================================================
# Prerequisite Checks
# =============================================================================
check_os() {
    log_step "Checking operating system..."

    local os_type
    os_type=$(uname -s)

    case "$os_type" in
        Linux)
            log_success "Linux detected"
            ;;
        Darwin)
            log_success "macOS detected"
            log_warning "Note: Host networking may work differently on macOS"
            ;;
        *)
            log_error "Unsupported operating system: $os_type"
            log_info "This stack requires Linux or macOS"
            exit 1
            ;;
    esac
}

check_docker() {
    log_step "Checking for Docker..."

    if ! command_exists docker; then
        log_error "Docker is not installed"
        log_info ""
        log_info "Install Docker using one of these methods:"
        log_info ""
        log_info "  Ubuntu/Debian:"
        log_info "    curl -fsSL https://get.docker.com | sh"
        log_info "    sudo usermod -aG docker \$USER"
        log_info ""
        log_info "  macOS:"
        log_info "    brew install --cask docker"
        log_info ""
        log_info "  Or visit: https://docs.docker.com/get-docker/"
        log_info ""
        exit 1
    fi

    # Check Docker version
    local docker_version
    docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "0.0.0")

    if version_gte "$docker_version" "$MIN_DOCKER_VERSION"; then
        log_success "Docker $docker_version is installed"
    else
        log_warning "Docker $docker_version may be outdated (recommended: $MIN_DOCKER_VERSION+)"
    fi

    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        log_info ""
        log_info "Start Docker with:"
        log_info "  sudo systemctl start docker    # Linux with systemd"
        log_info "  open -a Docker                 # macOS"
        log_info ""
        exit 1
    fi

    log_success "Docker daemon is running"
}

check_docker_compose() {
    log_step "Checking for Docker Compose..."

    # Check for docker-compose (v1) or docker compose (v2)
    if command_exists docker-compose; then
        DOCKER_COMPOSE="docker-compose"
        local version
        version=$(docker-compose version --short 2>/dev/null || echo "unknown")
        log_success "docker-compose $version is installed"
    elif docker compose version &> /dev/null; then
        DOCKER_COMPOSE="docker compose"
        local version
        version=$(docker compose version --short 2>/dev/null || echo "unknown")
        log_success "docker compose $version is installed"
    else
        log_error "Docker Compose is not installed"
        log_info ""
        log_info "Install Docker Compose:"
        log_info "  sudo apt-get install docker-compose-plugin  # Ubuntu/Debian"
        log_info "  brew install docker-compose                 # macOS"
        log_info ""
        exit 1
    fi
}

check_git() {
    log_step "Checking for Git..."

    if command_exists git; then
        log_success "Git is installed"
        USE_GIT=true
    else
        log_warning "Git not found, will use curl/wget to download"
        USE_GIT=false

        if ! command_exists curl && ! command_exists wget; then
            log_error "Neither git, curl, nor wget is available"
            log_info "Please install git or curl to continue"
            exit 1
        fi
    fi
}

check_ports() {
    log_step "Checking if required ports are available..."

    local ports=(631 8080 8081 5353)
    local blocked_ports=()

    for port in "${ports[@]}"; do
        if command_exists ss; then
            if ss -tuln 2>/dev/null | grep -q ":${port} "; then
                blocked_ports+=("$port")
            fi
        elif command_exists netstat; then
            if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
                blocked_ports+=("$port")
            fi
        fi
    done

    if [[ ${#blocked_ports[@]} -gt 0 ]]; then
        log_warning "The following ports may be in use: ${blocked_ports[*]}"
        log_info "You can change ports in .env after installation"
    else
        log_success "Required ports appear to be available"
    fi
}

check_privileges() {
    log_step "Checking user privileges..."

    # Check if user can run docker without sudo
    if docker ps &> /dev/null; then
        log_success "User can run Docker commands"
    else
        log_warning "May need to run with sudo or add user to docker group"
        log_info "Run: sudo usermod -aG docker \$USER && newgrp docker"
    fi
}

# =============================================================================
# Installation Functions
# =============================================================================
download_repository() {
    log_header "Downloading AirPrint PDF Stack"

    # Check if directory already exists
    if [[ -d "$INSTALL_DIR" ]]; then
        log_warning "Directory already exists: $INSTALL_DIR"
        read -p "Remove and reinstall? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_step "Removing existing installation..."
            rm -rf "$INSTALL_DIR"
        else
            log_info "Using existing installation"
            return 0
        fi
    fi

    CLEANUP_ON_FAIL=true

    if [[ "$USE_GIT" == "true" ]]; then
        log_step "Cloning repository..."
        git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR"
    else
        log_step "Downloading archive..."
        local archive_url="https://github.com/mwilco03/airprint-pdf-stack/archive/refs/heads/${REPO_BRANCH}.tar.gz"
        local tmp_dir
        tmp_dir=$(mktemp -d)

        if command_exists curl; then
            curl -fsSL "$archive_url" | tar -xz -C "$tmp_dir"
        else
            wget -qO- "$archive_url" | tar -xz -C "$tmp_dir"
        fi

        mv "$tmp_dir/airprint-pdf-stack-${REPO_BRANCH}" "$INSTALL_DIR"
        rm -rf "$tmp_dir"
    fi

    log_success "Downloaded to: $INSTALL_DIR"
}

setup_environment() {
    log_header "Configuring Environment"

    cd "$INSTALL_DIR"

    # Create .env from example if it doesn't exist
    if [[ ! -f ".env" ]] && [[ -f ".env.example" ]]; then
        log_step "Creating .env configuration..."
        cp .env.example .env
        log_success ".env file created"
    fi

    # Create required directories
    log_step "Creating directories..."
    mkdir -p pdfs filebrowser/database
    chmod 1777 pdfs
    log_success "Directories created"

    # Make scripts executable
    log_step "Setting script permissions..."
    chmod +x start.sh 2>/dev/null || true
    chmod +x airprint/entrypoint.sh 2>/dev/null || true
    log_success "Permissions set"
}

build_and_start() {
    log_header "Building and Starting Services"

    cd "$INSTALL_DIR"

    # Build images
    log_step "Building Docker images (this may take a few minutes)..."
    $DOCKER_COMPOSE build --no-cache
    log_success "Images built successfully"

    # Start services
    log_step "Starting services..."
    $DOCKER_COMPOSE up -d
    log_success "Services started"

    # Wait for services to be ready
    log_step "Waiting for services to be ready..."
    local max_wait=60
    local waited=0

    while [[ $waited -lt $max_wait ]]; do
        if $DOCKER_COMPOSE ps 2>/dev/null | grep -q "Up"; then
            break
        fi
        sleep 2
        ((waited+=2))
        echo -n "."
    done
    echo

    # Give services a moment to fully initialize
    sleep 5

    log_success "Services are running"
}

verify_installation() {
    log_header "Verifying Installation"

    cd "$INSTALL_DIR"

    local all_healthy=true
    local services=("airprint" "pdf-gallery" "filebrowser")

    for service in "${services[@]}"; do
        local status
        status=$($DOCKER_COMPOSE ps "$service" 2>/dev/null | tail -n 1)

        if echo "$status" | grep -q "Up"; then
            log_success "$service is running"
        else
            log_warning "$service may not be running correctly"
            all_healthy=false
        fi
    done

    # Test CUPS connectivity
    log_step "Testing CUPS connectivity..."
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:631" 2>/dev/null | grep -q "200\|302"; then
        log_success "CUPS web interface is accessible"
    else
        log_warning "CUPS web interface not yet responding (may still be starting)"
    fi

    # Test Gallery connectivity
    log_step "Testing PDF Gallery connectivity..."
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8081" 2>/dev/null | grep -q "200"; then
        log_success "PDF Gallery is accessible"
    else
        log_warning "PDF Gallery not yet responding (may still be starting)"
    fi

    return 0
}

show_completion() {
    local ip
    ip=$(get_local_ip)

    log_header "Installation Complete!"

    echo -e "${GREEN}${BOLD}Your AirPrint PDF Stack is now running!${NC}"
    echo ""
    echo -e "${BOLD}Access URLs:${NC}"
    echo ""
    echo -e "  ${CYAN}PDF Gallery${NC} (Browse/Download PDFs):"
    echo -e "    http://localhost:8081"
    echo -e "    http://${ip}:8081"
    echo ""
    echo -e "  ${CYAN}FileBrowser${NC} (Advanced File Management):"
    echo -e "    http://localhost:8080"
    echo -e "    http://${ip}:8080"
    echo ""
    echo -e "  ${CYAN}CUPS Admin${NC} (Printer Administration):"
    echo -e "    http://localhost:631"
    echo -e "    http://${ip}:631"
    echo ""
    echo -e "${BOLD}Printer Name:${NC} ${GREEN}Virtual-PDF${NC}"
    echo ""
    echo -e "${BOLD}To print from iPhone/iPad:${NC}"
    echo "  1. Connect to the same WiFi network as this server"
    echo "  2. Open any app and tap Share > Print"
    echo "  3. Select 'Virtual-PDF' printer"
    echo "  4. View your PDFs at http://${ip}:8081"
    echo ""
    echo -e "${BOLD}Installation Directory:${NC} ${INSTALL_DIR}"
    echo ""
    echo -e "${BOLD}Quick Commands:${NC}"
    echo "  cd ${INSTALL_DIR}"
    echo "  make help      # Show all commands"
    echo "  make logs      # View service logs"
    echo "  make status    # Check service status"
    echo "  make down      # Stop services"
    echo "  make up        # Start services"
    echo ""

    # Add to PATH hint
    if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
        echo -e "${YELLOW}Tip:${NC} Add to your shell profile for quick access:"
        echo "  echo 'alias airprint=\"cd ${INSTALL_DIR} && make\"' >> ~/.bashrc"
        echo ""
    fi
}

# =============================================================================
# Main
# =============================================================================
main() {
    echo ""
    echo -e "${PURPLE}${BOLD}"
    echo "    _    _      ____       _       _   "
    echo "   / \  (_)_ __|  _ \ _ __(_)_ __ | |_ "
    echo "  / _ \ | | '__| |_) | '__| | '_ \| __|"
    echo " / ___ \| | |  |  __/| |  | | | | | |_ "
    echo "/_/   \_\_|_|  |_|   |_|  |_|_| |_|\__|"
    echo "                                       "
    echo "       PDF Stack Installer             "
    echo -e "${NC}"

    log_info "Installation directory: $INSTALL_DIR"
    echo ""

    # Set up error handling
    trap cleanup_on_error ERR

    # Run prerequisite checks
    log_header "Checking Prerequisites"
    check_os
    check_docker
    check_docker_compose
    check_git
    check_ports
    check_privileges

    # Run installation
    download_repository
    setup_environment
    build_and_start
    verify_installation

    # Show completion message
    show_completion

    CLEANUP_ON_FAIL=false
}

# Run main
main "$@"
