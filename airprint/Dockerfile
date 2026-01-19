# AirPrint PDF Service - Dockerfile
# Based on Debian slim with CUPS, cups-pdf, and Avahi for AirPrint support

FROM debian:bookworm-slim

# Build arguments
ARG DEBIAN_FRONTEND=noninteractive

# Labels
LABEL maintainer="AirPrint PDF Stack"
LABEL description="AirPrint-enabled virtual PDF printer using CUPS and Avahi"
LABEL version="1.0"

# Environment variables (defaults)
ENV PRINTER_NAME="Virtual-PDF" \
    PRINTER_DESCRIPTION="AirPrint Virtual PDF Printer" \
    PRINTER_LOCATION="Home Network" \
    PDF_OUTPUT_DIR="/pdfs" \
    TZ="UTC"

# Install required packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    # CUPS and PDF backend
    cups \
    cups-pdf \
    cups-filters \
    # Avahi for mDNS/AirPrint discovery
    avahi-daemon \
    avahi-utils \
    libnss-mdns \
    # Utilities
    procps \
    iproute2 \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Configure CUPS for network access and no authentication
RUN sed -i 's/Listen localhost:631/Listen *:631/' /etc/cups/cupsd.conf && \
    sed -i 's/<Location \/>/<Location \/>\n  Allow all\n  AuthType None/' /etc/cups/cupsd.conf && \
    sed -i 's/<Location \/admin>/<Location \/admin>\n  Allow all\n  AuthType None/' /etc/cups/cupsd.conf && \
    sed -i 's/<Location \/admin\/conf>/<Location \/admin\/conf>\n  Allow all\n  AuthType None/' /etc/cups/cupsd.conf && \
    sed -i 's/<Location \/admin\/log>/<Location \/admin\/log>\n  Allow all\n  AuthType None/' /etc/cups/cupsd.conf && \
    # Enable browsing and DNS-SD
    echo "Browsing On" >> /etc/cups/cupsd.conf && \
    echo "BrowseLocalProtocols dnssd" >> /etc/cups/cupsd.conf && \
    echo "DefaultAuthType None" >> /etc/cups/cupsd.conf && \
    echo "WebInterface Yes" >> /etc/cups/cupsd.conf && \
    echo "ServerAlias *" >> /etc/cups/cupsd.conf

# Configure cups-pdf output directory
RUN mkdir -p /etc/cups/cups-pdf.conf.d && \
    echo "Out /pdfs" > /etc/cups/cups-pdf.conf.d/output.conf && \
    echo "AnonDirName /pdfs" >> /etc/cups/cups-pdf.conf.d/output.conf && \
    echo "UserUMask 0000" >> /etc/cups/cups-pdf.conf.d/output.conf && \
    echo "AnonUMask 0000" >> /etc/cups/cups-pdf.conf.d/output.conf

# Configure Avahi
RUN sed -i 's/#enable-dbus=yes/enable-dbus=no/' /etc/avahi/avahi-daemon.conf && \
    sed -i 's/rlimit-nproc=3/#rlimit-nproc=3/' /etc/avahi/avahi-daemon.conf

# Create PDF output directory with proper permissions
RUN mkdir -p /pdfs && chmod 1777 /pdfs

# Create run directories
RUN mkdir -p /run/cups /run/avahi-daemon /var/spool/cups-pdf && \
    chmod 755 /run/cups /run/avahi-daemon && \
    chmod 1777 /var/spool/cups-pdf

# Copy Avahi service definition for AirPrint
COPY airprint.service /etc/avahi/services/airprint.service

# Copy and set up entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose CUPS port (mDNS uses host network)
EXPOSE 631

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD lpstat -r || exit 1

# Run entrypoint
ENTRYPOINT ["/entrypoint.sh"]
