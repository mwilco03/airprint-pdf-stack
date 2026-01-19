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
readonly PORT_INCREMENT=1000
readonly MAX_PORT_ATTEMPTS=10

# Default ports
readonly DEFAULT_CUPS_PORT=631
readonly DEFAULT_FILEBROWSER_PORT=8080
readonly DEFAULT_GALLERY_PORT=8081

# Assigned ports (will be set during port checking)
CUPS_PORT=""
FILEBROWSER_PORT=""
GALLERY_PORT=""
PORTS_CHANGED=false

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

is_port_in_use() {
    local port=$1

    if command_exists ss; then
        ss -tuln 2>/dev/null | grep -q ":${port} " && return 0
    elif command_exists netstat; then
        netstat -tuln 2>/dev/null | grep -q ":${port} " && return 0
    elif command_exists lsof; then
        lsof -i ":${port}" &>/dev/null && return 0
    fi

    return 1
}

find_available_port() {
    local default_port=$1
    local service_name=$2
    local port=$default_port
    local attempts=0

    while [[ $attempts -lt $MAX_PORT_ATTEMPTS ]]; do
        if ! is_port_in_use "$port"; then
            echo "$port"
            return 0
        fi

        # Increment by PORT_INCREMENT (1000)
        port=$((port + PORT_INCREMENT))
        ((attempts++))
    done

    # Failed to find available port
    echo ""
    return 1
}

check_ports() {
    log_step "Checking and assigning available ports..."

    local port_changes=()

    # Check CUPS port (631)
    CUPS_PORT=$(find_available_port $DEFAULT_CUPS_PORT "CUPS")
    if [[ -z "$CUPS_PORT" ]]; then
        log_error "Could not find available port for CUPS (tried $DEFAULT_CUPS_PORT - $((DEFAULT_CUPS_PORT + PORT_INCREMENT * MAX_PORT_ATTEMPTS)))"
        exit 1
    fi
    if [[ "$CUPS_PORT" -ne "$DEFAULT_CUPS_PORT" ]]; then
        port_changes+=("CUPS: $DEFAULT_CUPS_PORT -> $CUPS_PORT")
        PORTS_CHANGED=true
    fi

    # Check FileBrowser port (8080)
    FILEBROWSER_PORT=$(find_available_port $DEFAULT_FILEBROWSER_PORT "FileBrowser")
    if [[ -z "$FILEBROWSER_PORT" ]]; then
        log_error "Could not find available port for FileBrowser (tried $DEFAULT_FILEBROWSER_PORT - $((DEFAULT_FILEBROWSER_PORT + PORT_INCREMENT * MAX_PORT_ATTEMPTS)))"
        exit 1
    fi
    if [[ "$FILEBROWSER_PORT" -ne "$DEFAULT_FILEBROWSER_PORT" ]]; then
        port_changes+=("FileBrowser: $DEFAULT_FILEBROWSER_PORT -> $FILEBROWSER_PORT")
        PORTS_CHANGED=true
    fi

    # Check Gallery port (8081)
    GALLERY_PORT=$(find_available_port $DEFAULT_GALLERY_PORT "PDF Gallery")
    if [[ -z "$GALLERY_PORT" ]]; then
        log_error "Could not find available port for PDF Gallery (tried $DEFAULT_GALLERY_PORT - $((DEFAULT_GALLERY_PORT + PORT_INCREMENT * MAX_PORT_ATTEMPTS)))"
        exit 1
    fi
    if [[ "$GALLERY_PORT" -ne "$DEFAULT_GALLERY_PORT" ]]; then
        port_changes+=("PDF Gallery: $DEFAULT_GALLERY_PORT -> $GALLERY_PORT")
        PORTS_CHANGED=true
    fi

    # Report results
    if [[ "$PORTS_CHANGED" == "true" ]]; then
        log_warning "Some default ports are in use. Auto-assigned alternative ports:"
        for change in "${port_changes[@]}"; do
            log_info "  $change"
        done
        echo ""
    else
        log_success "All default ports are available"
    fi

    log_info "Port assignments: CUPS=$CUPS_PORT, FileBrowser=$FILEBROWSER_PORT, Gallery=$GALLERY_PORT"
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

    # Update ports in .env if any were changed
    if [[ "$PORTS_CHANGED" == "true" ]] && [[ -f ".env" ]]; then
        log_step "Updating .env with assigned ports..."

        # Update or add port configurations
        update_env_var "GALLERY_PORT" "$GALLERY_PORT"
        update_env_var "FILEBROWSER_PORT" "$FILEBROWSER_PORT"
        # Note: CUPS port is handled via host networking, but we track it for reference
        update_env_var "CUPS_PORT" "$CUPS_PORT"

        log_success "Port configuration updated in .env"
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

update_env_var() {
    local var_name=$1
    local var_value=$2
    local env_file=".env"

    if grep -q "^${var_name}=" "$env_file" 2>/dev/null; then
        # Update existing variable
        sed -i.bak "s/^${var_name}=.*/${var_name}=${var_value}/" "$env_file"
        rm -f "${env_file}.bak"
    else
        # Add new variable
        echo "${var_name}=${var_value}" >> "$env_file"
    fi
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
    log_step "Testing CUPS connectivity on port $CUPS_PORT..."
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${CUPS_PORT}" 2>/dev/null | grep -q "200\|302"; then
        log_success "CUPS web interface is accessible"
    else
        log_warning "CUPS web interface not yet responding (may still be starting)"
    fi

    # Test Gallery connectivity
    log_step "Testing PDF Gallery connectivity on port $GALLERY_PORT..."
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${GALLERY_PORT}" 2>/dev/null | grep -q "200"; then
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

    # Show port change notice if ports were modified
    if [[ "$PORTS_CHANGED" == "true" ]]; then
        echo -e "${YELLOW}${BOLD}Note: Some ports were already in use. Alternative ports have been assigned.${NC}"
        echo ""
    fi

    echo -e "${BOLD}Access URLs:${NC}"
    echo ""
    echo -e "  ${CYAN}PDF Gallery${NC} (Browse/Download PDFs):"
    echo -e "    http://localhost:${GALLERY_PORT}"
    echo -e "    http://${ip}:${GALLERY_PORT}"
    echo ""
    echo -e "  ${CYAN}FileBrowser${NC} (Advanced File Management):"
    echo -e "    http://localhost:${FILEBROWSER_PORT}"
    echo -e "    http://${ip}:${FILEBROWSER_PORT}"
    echo ""
    echo -e "  ${CYAN}CUPS Admin${NC} (Printer Administration):"
    echo -e "    http://localhost:${CUPS_PORT}"
    echo -e "    http://${ip}:${CUPS_PORT}"
    echo ""
    echo -e "${BOLD}Printer Name:${NC} ${GREEN}Virtual-PDF${NC}"
    echo ""
    echo -e "${BOLD}To print from iPhone/iPad:${NC}"
    echo "  1. Connect to the same WiFi network as this server"
    echo "  2. Open any app and tap Share > Print"
    echo "  3. Select 'Virtual-PDF' printer"
    echo "  4. View your PDFs at http://${ip}:${GALLERY_PORT}"
    echo ""
    echo -e "${BOLD}Installation Directory:${NC} ${INSTALL_DIR}"
    echo ""

    # Show port summary if changed
    if [[ "$PORTS_CHANGED" == "true" ]]; then
        echo -e "${BOLD}Port Configuration:${NC}"
        echo "  CUPS:        ${CUPS_PORT} (default: ${DEFAULT_CUPS_PORT})"
        echo "  FileBrowser: ${FILEBROWSER_PORT} (default: ${DEFAULT_FILEBROWSER_PORT})"
        echo "  PDF Gallery: ${GALLERY_PORT} (default: ${DEFAULT_GALLERY_PORT})"
        echo ""
    fi

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
