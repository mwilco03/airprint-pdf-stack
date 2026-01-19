#!/bin/bash
# AirPrint PDF Stack - Automated Setup Script
# This script checks prerequisites, creates directories, and starts all services

set -e

# =============================================================================
# Constants
# =============================================================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_NAME="AirPrint PDF Stack"
readonly REQUIRED_COMMANDS=("docker" "docker-compose")
readonly PDF_DIR="${SCRIPT_DIR}/pdfs"
readonly ENV_FILE="${SCRIPT_DIR}/.env"
readonly ENV_EXAMPLE="${SCRIPT_DIR}/.env.example"

# Service ports (defaults, can be overridden in .env)
readonly DEFAULT_CUPS_PORT=631
readonly DEFAULT_FILEBROWSER_PORT=8080
readonly DEFAULT_GALLERY_PORT=8081

# =============================================================================
# Color Constants
# =============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# =============================================================================
# Logging Functions
# =============================================================================
print_header() {
    echo -e "\n${PURPLE}${BOLD}=========================================${NC}"
    echo -e "${PURPLE}${BOLD}  $1${NC}"
    echo -e "${PURPLE}${BOLD}=========================================${NC}\n"
}

print_step() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[-]${NC} $1" >&2
}

print_info() {
    echo -e "${CYAN}[i]${NC} $1"
}

# =============================================================================
# Utility Functions
# =============================================================================
command_exists() {
    command -v "$1" &> /dev/null
}

get_local_ip() {
    # Try multiple methods to get local IP
    local ip=""

    # Method 1: hostname -I
    if command_exists hostname; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi

    # Method 2: ip route
    if [[ -z "$ip" ]] && command_exists ip; then
        ip=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
    fi

    # Method 3: ifconfig
    if [[ -z "$ip" ]] && command_exists ifconfig; then
        ip=$(ifconfig 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n1)
    fi

    # Fallback
    if [[ -z "$ip" ]]; then
        ip="localhost"
    fi

    echo "$ip"
}

load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$ENV_FILE"
    fi
}

# =============================================================================
# Check Functions
# =============================================================================
check_prerequisites() {
    print_header "Checking Prerequisites"

    local missing_commands=()

    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        print_step "Checking for $cmd..."
        if command_exists "$cmd"; then
            print_success "$cmd is installed"
        else
            print_error "$cmd is not installed"
            missing_commands+=("$cmd")
        fi
    done

    # Check for docker-compose vs docker compose
    if ! command_exists docker-compose; then
        if docker compose version &> /dev/null; then
            print_info "Using 'docker compose' instead of 'docker-compose'"
            DOCKER_COMPOSE="docker compose"
        else
            missing_commands+=("docker-compose")
        fi
    else
        DOCKER_COMPOSE="docker-compose"
    fi

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        print_error "Missing required commands: ${missing_commands[*]}"
        print_info "Please install Docker and Docker Compose to continue."
        exit 1
    fi

    # Check if Docker daemon is running
    print_step "Checking Docker daemon..."
    if docker info &> /dev/null; then
        print_success "Docker daemon is running"
    else
        print_error "Docker daemon is not running"
        print_info "Please start Docker and try again."
        exit 1
    fi
}

# =============================================================================
# Setup Functions
# =============================================================================
setup_directories() {
    print_header "Setting Up Directories"

    print_step "Creating PDF storage directory..."
    mkdir -p "$PDF_DIR"
    chmod 1777 "$PDF_DIR"
    print_success "PDF directory created: $PDF_DIR"

    print_step "Creating FileBrowser database directory..."
    mkdir -p "${SCRIPT_DIR}/filebrowser/database"
    print_success "FileBrowser database directory created"
}

setup_environment() {
    print_header "Setting Up Environment"

    if [[ ! -f "$ENV_FILE" ]]; then
        print_step "Creating .env file from template..."
        if [[ -f "$ENV_EXAMPLE" ]]; then
            cp "$ENV_EXAMPLE" "$ENV_FILE"
            print_success ".env file created"
        else
            print_warning ".env.example not found, using defaults"
        fi
    else
        print_info ".env file already exists, keeping current configuration"
    fi

    # Load environment variables
    load_env
}

build_images() {
    print_header "Building Docker Images"

    print_step "Building AirPrint service image..."
    cd "$SCRIPT_DIR"
    $DOCKER_COMPOSE build --no-cache airprint
    print_success "AirPrint image built successfully"
}

start_services() {
    print_header "Starting Services"

    print_step "Starting all services..."
    cd "$SCRIPT_DIR"
    $DOCKER_COMPOSE up -d

    print_success "Services started"

    # Wait for services to be healthy
    print_step "Waiting for services to be ready..."
    sleep 5

    # Check service health
    local services=("airprint" "pdf-gallery" "filebrowser")
    for service in "${services[@]}"; do
        if $DOCKER_COMPOSE ps "$service" 2>/dev/null | grep -q "Up"; then
            print_success "$service is running"
        else
            print_warning "$service may still be starting..."
        fi
    done
}

# =============================================================================
# Status Functions
# =============================================================================
show_status() {
    print_header "Service Status"

    cd "$SCRIPT_DIR"
    $DOCKER_COMPOSE ps

    # Get configuration values
    load_env
    local cups_port="${CUPS_PORT:-$DEFAULT_CUPS_PORT}"
    local filebrowser_port="${FILEBROWSER_PORT:-$DEFAULT_FILEBROWSER_PORT}"
    local gallery_port="${GALLERY_PORT:-$DEFAULT_GALLERY_PORT}"
    local printer_name="${PRINTER_NAME:-Virtual-PDF}"
    local local_ip=$(get_local_ip)

    print_header "Access URLs"

    echo -e "${BOLD}PDF Gallery (View/Download PDFs):${NC}"
    echo -e "  ${CYAN}http://localhost:${gallery_port}${NC}"
    echo -e "  ${CYAN}http://${local_ip}:${gallery_port}${NC}"
    echo ""

    echo -e "${BOLD}FileBrowser (Advanced File Management):${NC}"
    echo -e "  ${CYAN}http://localhost:${filebrowser_port}${NC}"
    echo -e "  ${CYAN}http://${local_ip}:${filebrowser_port}${NC}"
    echo ""

    echo -e "${BOLD}CUPS Web Interface (Printer Admin):${NC}"
    echo -e "  ${CYAN}http://localhost:${cups_port}${NC}"
    echo -e "  ${CYAN}http://${local_ip}:${cups_port}${NC}"
    echo ""

    print_header "AirPrint Information"

    echo -e "${BOLD}Printer Name:${NC} ${GREEN}${printer_name}${NC}"
    echo -e "${BOLD}Network:${NC} Your iPhone/iPad should auto-discover the printer"
    echo ""
    echo -e "${YELLOW}Note:${NC} Make sure your mobile device is on the same network."
    echo -e "      The printer will appear as '${printer_name}' in the print dialog."
    echo ""

    print_header "Quick Commands"

    echo -e "  ${BOLD}View logs:${NC}        make logs"
    echo -e "  ${BOLD}Stop services:${NC}    make down"
    echo -e "  ${BOLD}Restart:${NC}          make restart"
    echo -e "  ${BOLD}List PDFs:${NC}        make pdfs"
    echo -e "  ${BOLD}Backup PDFs:${NC}      make backup"
    echo ""
}

# =============================================================================
# Main
# =============================================================================
main() {
    print_header "${PROJECT_NAME} Setup"

    echo -e "This script will set up your AirPrint PDF virtual printer."
    echo -e "It will create necessary directories, build Docker images,"
    echo -e "and start all services.\n"

    # Run setup steps
    check_prerequisites
    setup_directories
    setup_environment
    build_images
    start_services
    show_status

    print_header "Setup Complete!"
    echo -e "${GREEN}${BOLD}Your AirPrint PDF Stack is now running!${NC}"
    echo -e "\nPrint from your iPhone/iPad and PDFs will appear in the gallery."
    echo ""
}

# Run main function
main "$@"
