# AirPrint PDF Stack - Makefile
# Common commands for managing the stack

# =============================================================================
# Configuration
# =============================================================================
SHELL := /bin/bash
.DEFAULT_GOAL := help

# Docker Compose command (supports both v1 and v2)
DOCKER_COMPOSE := $(shell command -v docker-compose 2>/dev/null || echo "docker compose")

# Project directories
PROJECT_DIR := $(shell pwd)
PDF_DIR := $(PROJECT_DIR)/pdfs
BACKUP_DIR := $(PROJECT_DIR)/backups

# Timestamp for backups
TIMESTAMP := $(shell date +%Y%m%d_%H%M%S)

# Service names
SERVICES := airprint pdf-gallery filebrowser

# =============================================================================
# Help
# =============================================================================
.PHONY: help
help: ## Show this help message
	@echo ""
	@echo "AirPrint PDF Stack - Management Commands"
	@echo "========================================="
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*##"; printf ""} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""

# =============================================================================
# Docker Compose Commands
# =============================================================================
.PHONY: build
build: ## Build all Docker images
	@echo "Building Docker images..."
	$(DOCKER_COMPOSE) build

.PHONY: build-no-cache
build-no-cache: ## Build images without cache
	@echo "Building Docker images (no cache)..."
	$(DOCKER_COMPOSE) build --no-cache

.PHONY: up
up: ## Start all services
	@echo "Starting services..."
	$(DOCKER_COMPOSE) up -d
	@echo ""
	@echo "Services started. Access URLs:"
	@echo "  PDF Gallery:  http://localhost:8081"
	@echo "  FileBrowser:  http://localhost:8080"
	@echo "  CUPS Admin:   http://localhost:631"

.PHONY: down
down: ## Stop all services
	@echo "Stopping services..."
	$(DOCKER_COMPOSE) down

.PHONY: restart
restart: ## Restart all services
	@echo "Restarting services..."
	$(DOCKER_COMPOSE) restart

.PHONY: start
start: up ## Alias for 'up'

.PHONY: stop
stop: down ## Alias for 'down'

# =============================================================================
# Logging and Status
# =============================================================================
.PHONY: logs
logs: ## Show logs from all services (follow mode)
	$(DOCKER_COMPOSE) logs -f

.PHONY: logs-airprint
logs-airprint: ## Show AirPrint service logs
	$(DOCKER_COMPOSE) logs -f airprint

.PHONY: logs-gallery
logs-gallery: ## Show PDF Gallery logs
	$(DOCKER_COMPOSE) logs -f pdf-gallery

.PHONY: logs-filebrowser
logs-filebrowser: ## Show FileBrowser logs
	$(DOCKER_COMPOSE) logs -f filebrowser

.PHONY: status
status: ## Show status of all services
	@echo ""
	@echo "Service Status"
	@echo "=============="
	$(DOCKER_COMPOSE) ps
	@echo ""
	@echo "PDF Storage: $(PDF_DIR)"
	@echo "PDF Count: $$(find $(PDF_DIR) -name '*.pdf' 2>/dev/null | wc -l) files"
	@echo "Total Size: $$(du -sh $(PDF_DIR) 2>/dev/null | cut -f1)"
	@echo ""

.PHONY: ps
ps: status ## Alias for 'status'

# =============================================================================
# PDF Management
# =============================================================================
.PHONY: pdfs
pdfs: ## List all PDF files
	@echo ""
	@echo "PDF Files in $(PDF_DIR)"
	@echo "========================"
	@if [ -d "$(PDF_DIR)" ]; then \
		find $(PDF_DIR) -name '*.pdf' -printf '%T+ %s %p\n' 2>/dev/null | sort -r | \
		while read timestamp size path; do \
			name=$$(basename "$$path"); \
			size_h=$$(numfmt --to=iec-i --suffix=B $$size 2>/dev/null || echo "$$size B"); \
			echo "  $$name ($$size_h)"; \
		done; \
		echo ""; \
		echo "Total: $$(find $(PDF_DIR) -name '*.pdf' 2>/dev/null | wc -l) files"; \
	else \
		echo "  No PDF directory found"; \
	fi
	@echo ""

.PHONY: pdfs-count
pdfs-count: ## Show PDF count and total size
	@echo "PDF Count: $$(find $(PDF_DIR) -name '*.pdf' 2>/dev/null | wc -l)"
	@echo "Total Size: $$(du -sh $(PDF_DIR) 2>/dev/null | cut -f1)"

# =============================================================================
# Backup and Cleanup
# =============================================================================
.PHONY: backup
backup: ## Create a backup of all PDFs
	@echo "Creating backup..."
	@mkdir -p $(BACKUP_DIR)
	@if [ -d "$(PDF_DIR)" ] && [ "$$(find $(PDF_DIR) -name '*.pdf' 2>/dev/null | wc -l)" -gt 0 ]; then \
		tar -czvf $(BACKUP_DIR)/pdfs_$(TIMESTAMP).tar.gz -C $(PDF_DIR) .; \
		echo "Backup created: $(BACKUP_DIR)/pdfs_$(TIMESTAMP).tar.gz"; \
	else \
		echo "No PDFs to backup"; \
	fi

.PHONY: clean
clean: ## Remove all PDFs (with confirmation)
	@echo ""
	@echo "WARNING: This will delete all PDF files!"
	@read -p "Are you sure? (yes/no): " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		find $(PDF_DIR) -name '*.pdf' -delete 2>/dev/null; \
		echo "All PDFs deleted"; \
	else \
		echo "Cancelled"; \
	fi

.PHONY: clean-volumes
clean-volumes: down ## Stop services and remove all volumes
	@echo ""
	@echo "WARNING: This will remove all Docker volumes including configuration!"
	@read -p "Are you sure? (yes/no): " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		$(DOCKER_COMPOSE) down -v; \
		echo "Volumes removed"; \
	else \
		echo "Cancelled"; \
	fi

.PHONY: clean-all
clean-all: clean-volumes ## Remove everything (volumes, images, PDFs)
	@echo "Removing Docker images..."
	$(DOCKER_COMPOSE) down --rmi all 2>/dev/null || true
	@echo "Cleanup complete"

# =============================================================================
# Development Commands
# =============================================================================
.PHONY: shell-airprint
shell-airprint: ## Open shell in AirPrint container
	$(DOCKER_COMPOSE) exec airprint /bin/bash

.PHONY: shell-gallery
shell-gallery: ## Open shell in Gallery container
	$(DOCKER_COMPOSE) exec pdf-gallery /bin/sh

.PHONY: shell-filebrowser
shell-filebrowser: ## Open shell in FileBrowser container
	$(DOCKER_COMPOSE) exec filebrowser /bin/sh

.PHONY: printer-status
printer-status: ## Show CUPS printer status
	$(DOCKER_COMPOSE) exec airprint lpstat -p -d

.PHONY: cups-error-log
cups-error-log: ## Show CUPS error log
	$(DOCKER_COMPOSE) exec airprint tail -f /var/log/cups/error_log

# =============================================================================
# Setup Commands
# =============================================================================
.PHONY: init
init: ## Initialize the project (create directories, .env)
	@echo "Initializing project..."
	@mkdir -p $(PDF_DIR)
	@chmod 1777 $(PDF_DIR)
	@mkdir -p filebrowser/database
	@if [ ! -f .env ]; then \
		cp .env.example .env 2>/dev/null || echo "No .env.example found"; \
		echo ".env file created"; \
	fi
	@echo "Initialization complete"

.PHONY: setup
setup: init build up status ## Full setup: init, build, and start

# =============================================================================
# Test Commands
# =============================================================================
.PHONY: test-print
test-print: ## Print a test page
	@echo "Printing test page..."
	$(DOCKER_COMPOSE) exec airprint lp -d Virtual-PDF /usr/share/cups/data/testprint
	@echo "Test page sent to printer"

.PHONY: health
health: ## Check health of all services
	@echo "Checking service health..."
	@for service in $(SERVICES); do \
		status=$$($(DOCKER_COMPOSE) ps $$service --format "{{.Status}}" 2>/dev/null); \
		if echo "$$status" | grep -q "Up"; then \
			echo "  $$service: OK"; \
		else \
			echo "  $$service: FAILED ($$status)"; \
		fi; \
	done
