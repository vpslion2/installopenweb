#!/bin/bash

# =============================================================================
# Universal Open WebUI + LiteLLM Installation Script
# =============================================================================
# Works with any user (root or regular user with/without sudo)
# Automatically detects permissions and adapts accordingly
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Global variables
CURRENT_USER=$(whoami)
IS_ROOT=false
HAS_SUDO=false
INSTALL_DIR=""
SUDO_CMD=""

# Check user permissions
check_permissions() {
    echo -e "${BLUE}[INFO]${NC} Checking user permissions..."
    
    if [ "$EUID" -eq 0 ]; then
        IS_ROOT=true
        INSTALL_DIR="/root/openwebui-litellm"
        SUDO_CMD=""
        echo -e "${GREEN}[SUCCESS]${NC} Running as root user"
    else
        # Check if user has sudo privileges
        if sudo -n true 2>/dev/null; then
            HAS_SUDO=true
            SUDO_CMD="sudo"
            echo -e "${GREEN}[SUCCESS]${NC} Running as regular user with sudo privileges"
        else
            # Try to get sudo access
            echo -e "${YELLOW}[WARNING]${NC} Checking sudo access..."
            if sudo -v 2>/dev/null; then
                HAS_SUDO=true
                SUDO_CMD="sudo"
                echo -e "${GREEN}[SUCCESS]${NC} Sudo access granted"
            else
                echo -e "${RED}[ERROR]${NC} No sudo access available"
                echo -e "${YELLOW}[INFO]${NC} Will attempt installation with current user permissions"
                SUDO_CMD=""
            fi
        fi
        INSTALL_DIR="$HOME/openwebui-litellm"
    fi
    
    echo -e "${CYAN}[INFO]${NC} Installation directory: $INSTALL_DIR"
}

# Function to run commands with appropriate privileges
run_cmd() {
    if [ "$IS_ROOT" = true ] || [ "$HAS_SUDO" = false ]; then
        "$@"
    else
        $SUDO_CMD "$@"
    fi
}

# Print functions
print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() {
    echo -e "${PURPLE}================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}================================${NC}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install Docker
install_docker() {
    print_header "Installing Docker"
    
    if command_exists docker; then
        print_success "Docker is already installed"
        # Add current user to docker group if not root
        if [ "$IS_ROOT" = false ]; then
            run_cmd usermod -aG docker $CURRENT_USER || true
        fi
        return 0
    fi
    
    print_status "Installing Docker..."
    
    # Update package manager
    run_cmd apt update -qq || {
        print_warning "Could not update package manager, continuing..."
    }
    
    # Install dependencies
    run_cmd apt install -y curl wget ca-certificates gnupg lsb-release || {
        print_error "Failed to install dependencies"
        exit 1
    }
    
    # Install Docker using convenience script
    print_status "Downloading and installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    run_cmd sh get-docker.sh
    
    # Start and enable Docker
    run_cmd systemctl start docker || true
    run_cmd systemctl enable docker || true
    
    # Add user to docker group
    if [ "$IS_ROOT" = false ]; then
        run_cmd usermod -aG docker $CURRENT_USER || true
        print_warning "You may need to log out and back in for Docker permissions to take effect"
    fi
    
    # Clean up
    rm -f get-docker.sh
    
    print_success "Docker installed successfully!"
}

# Create project directory
create_project_directory() {
    print_header "Creating Project Directory"
    
    if [ -d "$INSTALL_DIR" ]; then
        print_warning "Directory exists, backing up..."
        mv "$INSTALL_DIR" "${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)" || true
    fi
    
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    print_success "Project directory created: $INSTALL_DIR"
}

# Generate secure random values
generate_secrets() {
    print_status "Generating secure credentials..."
    
    # Try different methods to generate random values
    if command_exists openssl; then
        LITELLM_MASTER_KEY="sk-$(openssl rand -hex 16)"
        LITELLM_SALT_KEY="sk-salt-$(openssl rand -hex 24)"
        DB_PASSWORD="$(openssl rand -base64 16 | tr -d '=+/')"
        WEBUI_SECRET="$(openssl rand -hex 16)"
    elif [ -f /dev/urandom ]; then
        LITELLM_MASTER_KEY="sk-$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)"
        LITELLM_SALT_KEY="sk-salt-$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 48 | head -n 1)"
        DB_PASSWORD="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"
        WEBUI_SECRET="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)"
    else
        # Fallback to timestamp-based generation
        TIMESTAMP=$(date +%s)
        LITELLM_MASTER_KEY="sk-${TIMESTAMP}$(echo $RANDOM | md5sum | head -c 16)"
        LITELLM_SALT_KEY="sk-salt-${TIMESTAMP}$(echo $RANDOM | md5sum | head -c 24)"
        DB_PASSWORD="db${TIMESTAMP}$(echo $RANDOM | md5sum | head -c 12)"
        WEBUI_SECRET="web${TIMESTAMP}$(echo $RANDOM | md5sum | head -c 16)"
    fi
    
    UI_USERNAME="admin"
    UI_PASSWORD="admin123"
    
    print_success "Credentials generated successfully"
}

# Create configuration files
create_configurations() {
    print_header "Creating Configuration Files"
    
    # LiteLLM configuration
    cat > litellm-config.yaml << 'EOF'
model_list:
  - model_name: gpt-4o-mini
    litellm_params:
      model: openai/gpt-4o-mini
      api_key: os.environ/OPENAI_API_KEY
  
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: os.environ/OPENAI_API_KEY
  
  - model_name: claude-3-5-sonnet
    litellm_params:
      model: anthropic/claude-3-5-sonnet-20241022
      api_key: os.environ/ANTHROPIC_API_KEY
  
  - model_name: claude-3-5-haiku
    litellm_params:
      model: anthropic/claude-3-5-haiku-20241022
      api_key: os.environ/ANTHROPIC_API_KEY
  
  - model_name: gemini-pro
    litellm_params:
      model: gemini/gemini-pro
      api_key: os.environ/GOOGLE_API_KEY
  
  - model_name: echo
    litellm_params:
      model: openai/gpt-3.5-turbo
      api_key: test

general_settings:
  completion_model: gpt-4o-mini
  master_key: ${LITELLM_MASTER_KEY}
EOF

    # Environment file
    cat > .env << EOF
# Open WebUI + LiteLLM Configuration
LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
LITELLM_SALT_KEY=${LITELLM_SALT_KEY}
DATABASE_URL=postgresql://litellm:${DB_PASSWORD}@localhost:5432/litellm
POSTGRES_DB=litellm
POSTGRES_USER=litellm
POSTGRES_PASSWORD=${DB_PASSWORD}
UI_USERNAME=${UI_USERNAME}
UI_PASSWORD=${UI_PASSWORD}
WEBUI_SECRET_KEY=${WEBUI_SECRET}
STORE_MODEL_IN_DB=True

# Add your API keys here:
# OPENAI_API_KEY=your_openai_key_here
# ANTHROPIC_API_KEY=your_anthropic_key_here
# GOOGLE_API_KEY=your_google_key_here
EOF

    # Docker Compose file
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:15
    container_name: litellm-postgres
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5

  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm-proxy
    ports:
      - "4000:4000"
    volumes:
      - ./litellm-config.yaml:/app/config.yaml:ro
    environment:
      LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
      LITELLM_SALT_KEY: ${LITELLM_SALT_KEY}
      DATABASE_URL: ${DATABASE_URL}
      UI_USERNAME: ${UI_USERNAME}
      UI_PASSWORD: ${UI_PASSWORD}
      STORE_MODEL_IN_DB: ${STORE_MODEL_IN_DB}
    command: ["--config", "/app/config.yaml", "--port", "4000", "--host", "0.0.0.0"]
    depends_on:
      postgres:
        condition: service_healthy
    restart: unless-stopped

  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    ports:
      - "8080:8080"
    volumes:
      - open_webui_data:/app/backend/data
    environment:
      OPENAI_API_BASE_URL: http://litellm:4000/v1
      OPENAI_API_KEY: ${LITELLM_MASTER_KEY}
      WEBUI_SECRET_KEY: ${WEBUI_SECRET_KEY}
    depends_on:
      - litellm
    restart: unless-stopped

volumes:
  postgres_data:
  open_webui_data:
EOF

    print_success "Configuration files created"
}

# Create management scripts
create_management_scripts() {
    print_header "Creating Management Scripts"
    
    # Start script
    cat > start.sh << 'EOF'
#!/bin/bash
echo "🚀 Starting Open WebUI + LiteLLM..."
docker compose up -d
echo "✅ Services started!"
echo ""
echo "🌐 Access URLs:"
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}' || echo "localhost")
echo "  - Open WebUI: http://${SERVER_IP}:8080"
echo "  - LiteLLM Dashboard: http://${SERVER_IP}:4000/ui"
echo "  - LiteLLM API: http://${SERVER_IP}:4000"
EOF
    chmod +x start.sh
    
    # Stop script
    cat > stop.sh << 'EOF'
#!/bin/bash
echo "🛑 Stopping services..."
docker compose down
echo "✅ Services stopped!"
EOF
    chmod +x stop.sh
    
    # Status script
    cat > status.sh << 'EOF'
#!/bin/bash
echo "📊 Service Status:"
docker compose ps
echo ""
echo "🔍 Health Checks:"
curl -s http://localhost:8080 >/dev/null && echo "✅ Open WebUI: Online" || echo "❌ Open WebUI: Offline"
curl -s http://localhost:4000 >/dev/null && echo "✅ LiteLLM: Online" || echo "❌ LiteLLM: Offline"
EOF
    chmod +x status.sh
    
    # Restart script
    cat > restart.sh << 'EOF'
#!/bin/bash
echo "🔄 Restarting services..."
docker compose restart
echo "✅ Services restarted!"
EOF
    chmod +x restart.sh
    
    # Logs script
    cat > logs.sh << 'EOF'
#!/bin/bash
if [ "$1" = "follow" ] || [ "$1" = "-f" ]; then
    echo "📋 Following logs (Ctrl+C to exit)..."
    docker compose logs -f
else
    echo "📋 Recent logs:"
    docker compose logs --tail=50
fi
EOF
    chmod +x logs.sh
    
    print_success "Management scripts created"
}

# Start services
start_services() {
    print_header "Starting Services"
    
    print_status "Pulling Docker images..."
    docker compose pull || {
        print_warning "Failed to pull some images, continuing..."
    }
    
    print_status "Starting services..."
    docker compose up -d
    
    print_status "Waiting for services to start..."
    sleep 20
    
    # Wait for services to be ready
    local attempts=0
    local max_attempts=30
    
    while [ $attempts -lt $max_attempts ]; do
        if curl -s http://localhost:8080 >/dev/null 2>&1 && curl -s http://localhost:4000 >/dev/null 2>&1; then
            print_success "All services are running!"
            return 0
        fi
        echo -n "."
        sleep 2
        attempts=$((attempts + 1))
    done
    
    print_warning "Services may still be starting up. Check status with: ./status.sh"
}

# Display final information
display_final_info() {
    print_header "Installation Complete!"
    
    # Get server IP
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}' || echo "your-server-ip")
    
    echo -e "${GREEN}🎉 Open WebUI + LiteLLM installed successfully!${NC}"
    echo ""
    echo -e "${CYAN}📍 Installation Directory:${NC} $INSTALL_DIR"
    echo ""
    echo -e "${CYAN}🌐 Access URLs:${NC}"
    echo -e "  • Open WebUI:        ${YELLOW}http://${SERVER_IP}:8080${NC}"
    echo -e "  • LiteLLM Dashboard: ${YELLOW}http://${SERVER_IP}:4000/ui${NC}"
    echo -e "  • LiteLLM API:       ${YELLOW}http://${SERVER_IP}:4000${NC}"
    echo ""
    echo -e "${CYAN}🔑 LiteLLM Dashboard Credentials:${NC}"
    echo -e "  • Username: ${YELLOW}${UI_USERNAME}${NC}"
    echo -e "  • Password: ${YELLOW}${UI_PASSWORD}${NC}"
    echo ""
    echo -e "${CYAN}🔧 Management Commands:${NC}"
    echo -e "  • Start:  ${YELLOW}./start.sh${NC}"
    echo -e "  • Stop:   ${YELLOW}./stop.sh${NC}"
    echo -e "  • Status: ${YELLOW}./status.sh${NC}"
    echo -e "  • Logs:   ${YELLOW}./logs.sh${NC}"
    echo ""
    echo -e "${CYAN}📝 Next Steps:${NC}"
    echo -e "  1. Visit Open WebUI and create your admin account"
    echo -e "  2. Add API keys to the .env file"
    echo -e "  3. Run ./restart.sh after adding API keys"
    echo ""
    
    # Save credentials
    cat > credentials.txt << EOF
Open WebUI + LiteLLM Installation
================================
Server: ${SERVER_IP}
Installed: $(date)

Access URLs:
- Open WebUI: http://${SERVER_IP}:8080
- LiteLLM Dashboard: http://${SERVER_IP}:4000/ui
- LiteLLM API: http://${SERVER_IP}:4000

Credentials:
- Username: ${UI_USERNAME}
- Password: ${UI_PASSWORD}
- API Key: ${LITELLM_MASTER_KEY}

Management:
cd $INSTALL_DIR
./start.sh / ./stop.sh / ./status.sh / ./logs.sh
EOF
    
    echo -e "${GREEN}✨ Installation completed! Credentials saved to credentials.txt${NC}"
}

# Main function
main() {
    clear
    print_header "Universal Open WebUI + LiteLLM Installer"
    echo -e "${CYAN}This installer works with any user configuration${NC}"
    echo ""
    
    read -p "Continue with installation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Installation cancelled"
        exit 0
    fi
    
    check_permissions
    install_docker
    create_project_directory
    generate_secrets
    create_configurations
    create_management_scripts
    start_services
    display_final_info
    
    print_success "Installation completed successfully!"
}

# Run main function
main "$@"

