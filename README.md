# AirPrint PDF Stack

A complete Docker stack that turns any server into an AirPrint-enabled virtual printer. Print from your iPhone, iPad, or Mac and automatically save documents as PDF files, accessible through beautiful web interfaces.

## Features

- **AirPrint Support**: Seamlessly print from any Apple device without additional apps or configuration
- **Automatic PDF Conversion**: All print jobs are converted to PDF and saved to a shared volume
- **PDF Gallery**: Modern, responsive web interface for browsing and downloading PDFs
- **FileBrowser**: Advanced file management with bulk download support
- **CUPS Admin**: Full CUPS web interface for printer administration
- **Zero Authentication**: Designed for home network use with no login required
- **Auto-Discovery**: Devices automatically discover the printer via mDNS/Bonjour

## Quick Start

### Option 1: Automated Setup

```bash
# Clone or download the repository
git clone <repository-url>
cd airprint-pdf-stack

# Run the setup script
chmod +x start.sh
./start.sh
```

### Option 2: Manual Setup

```bash
# Create required directories
mkdir -p pdfs filebrowser/database
chmod 1777 pdfs

# Copy environment file
cp .env.example .env

# Build and start services
docker-compose up -d
```

## Access URLs

| Service | URL | Description |
|---------|-----|-------------|
| PDF Gallery | http://localhost:8081 | Browse and download PDFs |
| FileBrowser | http://localhost:8080 | Advanced file management |
| CUPS Admin | http://localhost:631 | Printer administration |

Replace `localhost` with your server's IP address for access from other devices.

## Printing from iOS/iPadOS

1. Ensure your device is on the same network as the server
2. Open any app and tap the Share button
3. Select "Print"
4. The "Virtual-PDF" printer should appear automatically
5. Tap "Print" to send the document
6. Your PDF will appear in the gallery within seconds

## Configuration

All configuration is done through environment variables. Copy `.env.example` to `.env` and customize:

```bash
# Printer Settings
PRINTER_NAME=Virtual-PDF
PRINTER_DESCRIPTION=AirPrint Virtual PDF Printer
PRINTER_LOCATION=Home Network

# Port Configuration
GALLERY_PORT=8081
FILEBROWSER_PORT=8080

# Timezone
TZ=America/New_York
```

## Management Commands

Use the included Makefile for common operations:

```bash
# Show all available commands
make help

# Start services
make up

# Stop services
make down

# View logs
make logs

# Check service status
make status

# List all PDFs
make pdfs

# Create backup of PDFs
make backup

# Print a test page
make test-print

# Full cleanup (removes volumes)
make clean-all
```

## Directory Structure

```
airprint-pdf-stack/
├── docker-compose.yml    # Service orchestration
├── .env.example          # Environment template
├── .env                  # Your configuration (create from .env.example)
├── start.sh              # Automated setup script
├── Makefile              # Management commands
├── README.md             # This file
├── pdfs/                 # PDF storage (created automatically)
├── airprint/
│   ├── Dockerfile        # AirPrint service image
│   ├── entrypoint.sh     # Service startup script
│   └── airprint.service  # Avahi service definition
├── nginx/
│   ├── nginx.conf        # Web server configuration
│   └── html/
│       └── index.html    # PDF Gallery UI
└── filebrowser/
    └── config/
        └── settings.json # FileBrowser configuration
```

## Troubleshooting

### Printer not discovered by iOS device

1. **Check network**: Ensure the iOS device and server are on the same network/subnet
2. **Verify mDNS**: The AirPrint service uses host networking for mDNS. Check that port 5353 is not blocked
3. **Restart Avahi**: Try restarting the service with `make restart`
4. **Check logs**: Run `make logs-airprint` to see any errors

```bash
# Verify the printer is registered
make printer-status
```

### PDFs not appearing in gallery

1. **Check permissions**: The PDF directory should have 1777 permissions
2. **Verify CUPS**: Access http://localhost:631 to check the CUPS queue
3. **Check cups-pdf**: Review logs for any conversion errors

```bash
# Fix permissions
chmod 1777 pdfs/

# Check CUPS error log
make cups-error-log
```

### Service won't start

1. **Docker running?**: Ensure Docker daemon is running
2. **Port conflicts**: Check if ports 631, 8080, or 8081 are already in use
3. **Build issues**: Try rebuilding with `make build-no-cache`

```bash
# Check Docker status
docker info

# Check for port conflicts
netstat -tulpn | grep -E '631|8080|8081'

# Rebuild from scratch
make clean-all
make setup
```

### FileBrowser shows empty

1. **Volume mounting**: Ensure the PDF volume is correctly mounted
2. **PDF directory**: Check that PDFs exist in the `pdfs/` directory
3. **Container health**: Verify the container is healthy with `make status`

## Security Notes

This stack is designed for home network use and includes no authentication by default:

- **CUPS**: All admin functions are accessible without login
- **FileBrowser**: Read-only access, no authentication required
- **PDF Gallery**: Public access to all PDFs

**Do not expose these services to the internet without adding proper authentication.**

For production or multi-user environments, consider:

1. Adding a reverse proxy with authentication (e.g., Traefik, Caddy)
2. Enabling CUPS authentication in `cupsd.conf`
3. Enabling FileBrowser authentication in `settings.json`
4. Using a VPN for remote access

## Backup and Restore

### Creating Backups

```bash
# Create a timestamped backup
make backup

# Backups are stored in ./backups/
ls -la backups/
```

### Restoring from Backup

```bash
# Extract backup to PDF directory
tar -xzvf backups/pdfs_TIMESTAMP.tar.gz -C pdfs/
```

### Automated Backups

Add a cron job for automated backups:

```bash
# Edit crontab
crontab -e

# Add daily backup at 2 AM
0 2 * * * cd /path/to/airprint-pdf-stack && make backup
```

## Advanced Configuration

### Changing the Printer Name

Edit `.env` and change:

```bash
PRINTER_NAME=My-PDF-Printer
PRINTER_DESCRIPTION=My Custom PDF Printer
```

Then rebuild and restart:

```bash
make clean-volumes
make setup
```

### Using External Storage

To store PDFs on external storage, update `.env`:

```bash
PDF_HOST_PATH=/mnt/external-drive/pdfs
```

### Custom Network Configuration

If you need specific network settings, modify `docker-compose.yml`:

```yaml
services:
  airprint:
    # Change from host network to bridge if needed
    network_mode: bridge
    ports:
      - "631:631"
```

Note: Bridge networking may affect mDNS discovery.

## Technical Details

### Components

- **CUPS**: Common UNIX Printing System with cups-pdf backend
- **Avahi**: mDNS/DNS-SD daemon for AirPrint discovery
- **Nginx**: Web server for PDF Gallery
- **FileBrowser**: File management interface

### Supported Print Formats

CUPS accepts various formats and converts them to PDF:

- PostScript
- PDF
- Images (JPEG, PNG, GIF, TIFF)
- Plain text
- Various application formats via CUPS filters

### Network Ports

| Port | Protocol | Service |
|------|----------|---------|
| 631 | TCP | CUPS (IPP) |
| 5353 | UDP | mDNS (Avahi) |
| 8080 | TCP | FileBrowser |
| 8081 | TCP | PDF Gallery |

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## License

This project is provided as-is for personal and educational use. Please check individual component licenses (CUPS, Avahi, FileBrowser, Nginx) for their respective terms.
