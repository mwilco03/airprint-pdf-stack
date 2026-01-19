#!/bin/bash
# AirPrint PDF Service - Entrypoint Script
# Starts Avahi daemon, CUPS, and configures the virtual PDF printer

set -e

# =============================================================================
# Constants
# =============================================================================
readonly LOG_PREFIX="[AirPrint]"
readonly CUPS_PID_FILE="/run/cups/cupsd.pid"
readonly AVAHI_PID_FILE="/run/avahi-daemon/pid"
readonly PRINTER_DRIVER="cups-pdf://"
readonly MAX_RETRIES=30
readonly RETRY_DELAY=1

# =============================================================================
# Logging Functions
# =============================================================================
log_info() {
    echo "${LOG_PREFIX} INFO: $*"
}

log_error() {
    echo "${LOG_PREFIX} ERROR: $*" >&2
}

log_success() {
    echo "${LOG_PREFIX} SUCCESS: $*"
}

# =============================================================================
# Service Functions
# =============================================================================
start_avahi() {
    log_info "Starting Avahi daemon for mDNS/AirPrint discovery..."

    # Create run directory if needed
    mkdir -p /run/avahi-daemon

    # Start Avahi daemon
    avahi-daemon --daemonize --no-drop-root 2>/dev/null || true

    # Wait for Avahi to start
    local retries=0
    while [[ ! -f "${AVAHI_PID_FILE}" ]] && [[ ${retries} -lt 10 ]]; do
        sleep 1
        ((retries++))
    done

    if [[ -f "${AVAHI_PID_FILE}" ]]; then
        log_success "Avahi daemon started (PID: $(cat ${AVAHI_PID_FILE}))"
    else
        log_info "Avahi daemon may be running without PID file (host network mode)"
    fi
}

start_cups() {
    log_info "Starting CUPS daemon..."

    # Ensure run directory exists
    mkdir -p /run/cups

    # Start CUPS in foreground mode (we'll background it ourselves)
    /usr/sbin/cupsd -f &

    # Wait for CUPS to be ready
    local retries=0
    while ! lpstat -r &>/dev/null && [[ ${retries} -lt ${MAX_RETRIES} ]]; do
        sleep ${RETRY_DELAY}
        ((retries++))
    done

    if lpstat -r &>/dev/null; then
        log_success "CUPS daemon started and ready"
    else
        log_error "CUPS failed to start within ${MAX_RETRIES} seconds"
        exit 1
    fi
}

configure_cups_pdf() {
    log_info "Configuring cups-pdf output directory..."

    # Update cups-pdf configuration for output directory
    local cups_pdf_conf="/etc/cups/cups-pdf.conf"

    if [[ -f "${cups_pdf_conf}" ]]; then
        # Set output directory
        sed -i "s|^Out .*|Out ${PDF_OUTPUT_DIR}|g" "${cups_pdf_conf}" 2>/dev/null || true
        sed -i "s|^#Out .*|Out ${PDF_OUTPUT_DIR}|g" "${cups_pdf_conf}" 2>/dev/null || true

        # Set anonymous output directory
        sed -i "s|^AnonDirName .*|AnonDirName ${PDF_OUTPUT_DIR}|g" "${cups_pdf_conf}" 2>/dev/null || true
        sed -i "s|^#AnonDirName .*|AnonDirName ${PDF_OUTPUT_DIR}|g" "${cups_pdf_conf}" 2>/dev/null || true
    fi

    # Ensure output directory exists with proper permissions
    mkdir -p "${PDF_OUTPUT_DIR}"
    chmod 1777 "${PDF_OUTPUT_DIR}"

    log_success "cups-pdf configured to output to: ${PDF_OUTPUT_DIR}"
}

setup_printer() {
    log_info "Setting up virtual PDF printer: ${PRINTER_NAME}"

    # Check if printer already exists
    if lpstat -p "${PRINTER_NAME}" &>/dev/null; then
        log_info "Printer ${PRINTER_NAME} already exists, updating configuration..."
        lpadmin -x "${PRINTER_NAME}" 2>/dev/null || true
    fi

    # Create the PDF printer
    lpadmin -p "${PRINTER_NAME}" \
        -v "${PRINTER_DRIVER}" \
        -E \
        -D "${PRINTER_DESCRIPTION}" \
        -L "${PRINTER_LOCATION}" \
        -m "CUPS-PDF_opt.ppd" \
        -o printer-is-shared=true \
        -o auth-info-required=none

    # Enable the printer
    cupsenable "${PRINTER_NAME}"

    # Accept jobs
    cupsaccept "${PRINTER_NAME}"

    # Set as default printer
    lpadmin -d "${PRINTER_NAME}"

    # Verify printer is ready
    if lpstat -p "${PRINTER_NAME}" | grep -q "enabled"; then
        log_success "Printer ${PRINTER_NAME} created and enabled"
    else
        log_error "Failed to enable printer ${PRINTER_NAME}"
        exit 1
    fi
}

update_avahi_service() {
    log_info "Updating Avahi service definition..."

    # Update the AirPrint service file with current printer name
    local service_file="/etc/avahi/services/airprint.service"

    if [[ -f "${service_file}" ]]; then
        sed -i "s|%PRINTER_NAME%|${PRINTER_NAME}|g" "${service_file}"
        sed -i "s|%PRINTER_DESCRIPTION%|${PRINTER_DESCRIPTION}|g" "${service_file}"
        sed -i "s|%PRINTER_LOCATION%|${PRINTER_LOCATION}|g" "${service_file}"
    fi

    log_success "Avahi service updated"
}

show_status() {
    log_info "========================================="
    log_info "AirPrint PDF Service Status"
    log_info "========================================="
    log_info "Printer Name: ${PRINTER_NAME}"
    log_info "Description: ${PRINTER_DESCRIPTION}"
    log_info "Location: ${PRINTER_LOCATION}"
    log_info "PDF Output: ${PDF_OUTPUT_DIR}"
    log_info "CUPS Web UI: http://localhost:631"
    log_info "========================================="

    # Show printer status
    log_info "Printer Status:"
    lpstat -p "${PRINTER_NAME}" 2>/dev/null || log_error "Could not get printer status"

    log_info "========================================="
    log_success "AirPrint service is ready!"
    log_info "Your iPhone/iPad should now discover: ${PRINTER_NAME}"
    log_info "========================================="
}

monitor_logs() {
    log_info "Monitoring CUPS and service logs..."

    # Tail CUPS logs in background
    tail -F /var/log/cups/access_log /var/log/cups/error_log 2>/dev/null &

    # Wait for any process to exit
    wait
}

cleanup() {
    log_info "Shutting down services..."

    # Stop CUPS
    if [[ -f "${CUPS_PID_FILE}" ]]; then
        kill "$(cat ${CUPS_PID_FILE})" 2>/dev/null || true
    fi

    # Stop Avahi
    if [[ -f "${AVAHI_PID_FILE}" ]]; then
        kill "$(cat ${AVAHI_PID_FILE})" 2>/dev/null || true
    fi

    log_info "Cleanup complete"
    exit 0
}

# =============================================================================
# Main Execution
# =============================================================================
main() {
    # Set up signal handlers
    trap cleanup SIGTERM SIGINT SIGQUIT

    log_info "========================================="
    log_info "Starting AirPrint PDF Service"
    log_info "========================================="

    # Start services in order
    start_avahi
    start_cups
    configure_cups_pdf
    update_avahi_service
    setup_printer
    show_status

    # Keep container running and monitor logs
    monitor_logs
}

# Run main function
main "$@"
