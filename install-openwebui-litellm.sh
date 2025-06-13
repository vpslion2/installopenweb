#!/bin/bash

# =============================================================================
# Open WebUI + LiteLLM Automated Installation Script
# =============================================================================
# This script automatically installs and configures:
# - Docker and Docker Compose
# - Open WebUI (ChatGPT-like interface)
# - LiteLLM (Unified AI gateway)
# - PostgreSQL database
# - LiteLLM Dashboard with authentication
# - All required configurations
# =============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration variables
INSTALL_DIR="$HOME/openwebui-litellm"
LITELLM_MASTER_KEY="sk-$(openssl rand -hex 16)"
LITELLM_SALT_KEY="sk-salt-$(openssl rand -hex 24)"
DB_PASSWORD="$(openssl rand -base64 16)"
WEBUI_SECRET="$(openssl rand -hex 16)"
UI_USERNAME="admin"
UI_PASSWORD="admin123"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${PURPLE}================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}================================${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to wait for service to be ready
wait_for_service() {
    local url=$1
    local service_name=$2
    local max_attempts=30
    local attempt=1
    
    print_status "Waiting for $service_name to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s "$url" >/dev/null 2>&1; then
            print_success "$service_name is ready!"
            return 0
        fi
        
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    print_error "$service_name failed to start within expected time"
    return 1
}

# Function to install Docker
install_docker() {
    print_header "Installing Docker"
    
    if command_exists docker; then
        print_success "Docker is already installed"
        return 0
    fi
    
    print_status "Updating package manager..."
    sudo apt update -qq
    
    print_status "Installing dependencies..."
    sudo apt install -y curl wget gnupg lsb-release ca-certificates
    
    print_status "Adding Docker GPG key..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    print_status "Adding Docker repository..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    print_status "Installing Docker..."
    sudo apt update -qq
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    print_status "Configuring Docker permissions..."
    sudo usermod -aG docker $USER
    sudo systemctl start docker
    sudo systemctl enable docker
    
    print_success "Docker installed successfully!"
}

# Function to create project directory
create_project_directory() {
    print_header "Creating Project Directory"
    
    if [ -d "$INSTALL_DIR" ]; then
        print_warning "Directory $INSTALL_DIR already exists. Backing up..."
        mv "$INSTALL_DIR" "${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    print_success "Project directory created: $INSTALL_DIR"
}

# Function to create LiteLLM configuration
create_litellm_config() {
    print_header "Creating LiteLLM Configuration"
    
    cat > litellm-config.yaml << 'EOF'
model_list:
  # OpenAI Models
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: os.environ/OPENAI_API_KEY
  
  - model_name: gpt-4o-mini
    litellm_params:
      model: openai/gpt-4o-mini
      api_key: os.environ/OPENAI_API_KEY
  
  - model_name: gpt-3.5-turbo
    litellm_params:
      model: openai/gpt-3.5-turbo
      api_key: os.environ/OPENAI_API_KEY

  # Anthropic Models
  - model_name: claude-3-5-sonnet
    litellm_params:
      model: anthropic/claude-3-5-sonnet-20241022
      api_key: os.environ/ANTHROPIC_API_KEY
  
  - model_name: claude-3-5-haiku
    litellm_params:
      model: anthropic/claude-3-5-haiku-20241022
      api_key: os.environ/ANTHROPIC_API_KEY

  # Google Models
  - model_name: gemini-pro
    litellm_params:
      model: gemini/gemini-pro
      api_key: os.environ/GOOGLE_API_KEY

  # Cohere Models
  - model_name: command-r-plus
    litellm_params:
      model: cohere/command-r-plus
      api_key: os.environ/COHERE_API_KEY

  # Test/Echo Model
  - model_name: echo
    litellm_params:
      model: openai/gpt-3.5-turbo
      api_key: test

# Router settings
router_settings:
  routing_strategy: least-busy
  model_group_alias:
    gpt-4: gpt-4o
    gpt-3.5: gpt-3.5-turbo

# General settings
general_settings:
  completion_model: gpt-4o-mini
  disable_spend_logs: false
  disable_master_key_return: false
  master_key: ${LITELLM_MASTER_KEY}
  
# Logging
litellm_settings:
  success_callback: ["langfuse"]
  failure_callback: ["langfuse"]
  set_verbose: true
  json_logs: true
EOF

    print_success "LiteLLM configuration created"
}

# Function to create environment file
create_environment_file() {
    print_header "Creating Environment Configuration"
    
    cat > .env << EOF
# =============================================================================
# Open WebUI + LiteLLM Environment Configuration
# Generated on: $(date)
# =============================================================================

# LiteLLM Configuration
LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
LITELLM_SALT_KEY=${LITELLM_SALT_KEY}
LITELLM_LOG=INFO
LITELLM_PORT=4000
LITELLM_HOST=0.0.0.0
STORE_MODEL_IN_DB=True

# Database Configuration
DATABASE_URL=postgresql://litellm:${DB_PASSWORD}@localhost:5432/litellm
POSTGRES_DB=litellm
POSTGRES_USER=litellm
POSTGRES_PASSWORD=${DB_PASSWORD}

# LiteLLM Dashboard Authentication
UI_USERNAME=${UI_USERNAME}
UI_PASSWORD=${UI_PASSWORD}

# Open WebUI Configuration
OPENAI_API_BASE_URL=http://localhost:4000/v1
OPENAI_API_KEY=${LITELLM_MASTER_KEY}
WEBUI_SECRET_KEY=${WEBUI_SECRET}
DEFAULT_MODELS=gpt-4o-mini,echo
ENABLE_SIGNUP=true

# API Keys for External Providers
# Uncomment and set these with your actual API keys
# OPENAI_API_KEY=your_openai_api_key_here
# ANTHROPIC_API_KEY=your_anthropic_api_key_here
# GOOGLE_API_KEY=your_google_api_key_here
# COHERE_API_KEY=your_cohere_api_key_here

# Security Settings (Change these for production!)
# CORS_ALLOW_ORIGIN=*
# LITELLM_PROXY_BUDGET_NAME=default
EOF

    print_success "Environment configuration created"
}

# Function to create Docker Compose file
create_docker_compose() {
    print_header "Creating Docker Compose Configuration"
    
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  # PostgreSQL Database for LiteLLM
  postgres:
    image: postgres:15
    container_name: litellm-postgres
    environment:
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - postgres-data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    restart: unless-stopped
    network_mode: host
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5

  # LiteLLM Proxy Server
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm-proxy
    network_mode: host
    volumes:
      - ./litellm-config.yaml:/app/config.yaml
      - litellm-data:/app/data
    environment:
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
      - LITELLM_SALT_KEY=${LITELLM_SALT_KEY}
      - DATABASE_URL=${DATABASE_URL}
      - LITELLM_LOG=${LITELLM_LOG}
      - LITELLM_PORT=${LITELLM_PORT}
      - LITELLM_HOST=${LITELLM_HOST}
      - STORE_MODEL_IN_DB=${STORE_MODEL_IN_DB}
      - UI_USERNAME=${UI_USERNAME}
      - UI_PASSWORD=${UI_PASSWORD}
    command: ["--config", "/app/config.yaml", "--port", "4000", "--host", "0.0.0.0"]
    depends_on:
      postgres:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Open WebUI
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    network_mode: host
    volumes:
      - open-webui-data:/app/backend/data
    environment:
      - OPENAI_API_BASE_URL=${OPENAI_API_BASE_URL}
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY}
      - DEFAULT_MODELS=${DEFAULT_MODELS}
      - ENABLE_SIGNUP=${ENABLE_SIGNUP}
    depends_on:
      litellm:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  open-webui-data:
    driver: local
  litellm-data:
    driver: local
  postgres-data:
    driver: local

networks:
  default:
    name: openwebui-litellm-network
EOF

    print_success "Docker Compose configuration created"
}

# Function to create management scripts
create_management_scripts() {
    print_header "Creating Management Scripts"
    
    # Start script
    cat > start.sh << 'EOF'
#!/bin/bash
echo "🚀 Starting Open WebUI + LiteLLM services..."
docker compose up -d
echo "✅ Services started!"
echo ""
echo "Access URLs:"
echo "- Open WebUI: http://localhost:8080"
echo "- LiteLLM API: http://localhost:4000"
echo "- LiteLLM Dashboard: http://localhost:4000/ui"
EOF
    chmod +x start.sh
    
    # Stop script
    cat > stop.sh << 'EOF'
#!/bin/bash
echo "🛑 Stopping Open WebUI + LiteLLM services..."
docker compose down
echo "✅ Services stopped!"
EOF
    chmod +x stop.sh
    
    # Status script
    cat > status.sh << 'EOF'
#!/bin/bash
echo "📊 Service Status:"
echo "=================="
docker compose ps
echo ""
echo "🔍 Health Checks:"
echo "=================="
echo -n "LiteLLM API: "
if curl -s http://localhost:4000/health >/dev/null 2>&1; then
    echo "✅ Online"
else
    echo "❌ Offline"
fi

echo -n "Open WebUI: "
if curl -s http://localhost:8080 >/dev/null 2>&1; then
    echo "✅ Online"
else
    echo "❌ Offline"
fi

echo -n "PostgreSQL: "
if docker compose exec -T postgres pg_isready -U litellm >/dev/null 2>&1; then
    echo "✅ Online"
else
    echo "❌ Offline"
fi
EOF
    chmod +x status.sh
    
    # Logs script
    cat > logs.sh << 'EOF'
#!/bin/bash
if [ "$1" = "follow" ] || [ "$1" = "-f" ]; then
    echo "📋 Following logs (Ctrl+C to exit)..."
    docker compose logs -f
else
    echo "📋 Recent logs:"
    docker compose logs --tail=50
    echo ""
    echo "💡 Use './logs.sh follow' to follow logs in real-time"
fi
EOF
    chmod +x logs.sh
    
    # Restart script
    cat > restart.sh << 'EOF'
#!/bin/bash
echo "🔄 Restarting Open WebUI + LiteLLM services..."
docker compose restart
echo "✅ Services restarted!"
EOF
    chmod +x restart.sh
    
    # Update script
    cat > update.sh << 'EOF'
#!/bin/bash
echo "⬆️ Updating Open WebUI + LiteLLM to latest versions..."
docker compose pull
docker compose up -d
echo "✅ Services updated!"
EOF
    chmod +x update.sh
    
    # Backup script
    cat > backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="./backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "💾 Creating backup..."
echo "Backing up Open WebUI data..."
docker run --rm -v openwebui-litellm_open-webui-data:/data -v "$(pwd)/$BACKUP_DIR":/backup alpine tar czf /backup/openwebui-data.tar.gz -C /data .

echo "Backing up LiteLLM data..."
docker run --rm -v openwebui-litellm_litellm-data:/data -v "$(pwd)/$BACKUP_DIR":/backup alpine tar czf /backup/litellm-data.tar.gz -C /data .

echo "Backing up PostgreSQL data..."
docker compose exec -T postgres pg_dump -U litellm litellm > "$BACKUP_DIR/postgres-dump.sql"

echo "Backing up configuration files..."
cp .env docker-compose.yml litellm-config.yaml "$BACKUP_DIR/"

echo "✅ Backup completed: $BACKUP_DIR"
EOF
    chmod +x backup.sh
    
    print_success "Management scripts created"
}

# Function to create README
create_readme() {
    print_header "Creating Documentation"
    
    cat > README.md << EOF
# Open WebUI + LiteLLM Installation

This directory contains a complete Open WebUI + LiteLLM setup with PostgreSQL database.

## 🚀 Quick Start

\`\`\`bash
# Start all services
./start.sh

# Check status
./status.sh

# View logs
./logs.sh

# Stop services
./stop.sh
\`\`\`

## 🔗 Access URLs

- **Open WebUI**: http://localhost:8080
- **LiteLLM API**: http://localhost:4000
- **LiteLLM Dashboard**: http://localhost:4000/ui

## 🔑 Default Credentials

### LiteLLM Dashboard
- **Username**: ${UI_USERNAME}
- **Password**: ${UI_PASSWORD}

### API Access
- **Master Key**: \`${LITELLM_MASTER_KEY}\`

## 📁 Management Scripts

- \`start.sh\` - Start all services
- \`stop.sh\` - Stop all services  
- \`restart.sh\` - Restart all services
- \`status.sh\` - Check service status
- \`logs.sh\` - View service logs
- \`update.sh\` - Update to latest versions
- \`backup.sh\` - Create data backup

## 🔧 Configuration

### Adding API Keys
Edit the \`.env\` file and uncomment/set your API keys:

\`\`\`bash
OPENAI_API_KEY=your_openai_key_here
ANTHROPIC_API_KEY=your_anthropic_key_here
GOOGLE_API_KEY=your_google_key_here
COHERE_API_KEY=your_cohere_key_here
\`\`\`

Then restart services: \`./restart.sh\`

### Available Models
- gpt-4o
- gpt-4o-mini (default)
- gpt-3.5-turbo
- claude-3-5-sonnet
- claude-3-5-haiku
- gemini-pro
- command-r-plus

## 🗄️ Database Access

\`\`\`bash
# Connect to PostgreSQL
docker compose exec postgres psql -U litellm -d litellm
\`\`\`

## 🔒 Security Notes

**For Production Use:**
1. Change default passwords in \`.env\`
2. Set up proper firewall rules
3. Use HTTPS with reverse proxy
4. Restrict database access
5. Regular backups

## 📊 Monitoring

\`\`\`bash
# Resource usage
docker stats

# Disk usage  
docker system df

# Service health
./status.sh
\`\`\`

## 🆘 Troubleshooting

\`\`\`bash
# View logs
./logs.sh follow

# Restart services
./restart.sh

# Check Docker status
sudo systemctl status docker

# Reset everything (WARNING: deletes data)
docker compose down -v
./start.sh
\`\`\`

## 📞 Support

- Check logs first: \`./logs.sh\`
- Verify service status: \`./status.sh\`
- Review configuration: \`.env\` and \`docker-compose.yml\`

Generated on: $(date)
EOF

    print_success "Documentation created"
}

# Function to start services
start_services() {
    print_header "Starting Services"
    
    print_status "Pulling Docker images..."
    sudo docker compose pull
    
    print_status "Starting services..."
    sudo docker compose up -d
    
    print_status "Waiting for PostgreSQL to be ready..."
    sleep 10
    
    print_status "Waiting for LiteLLM to be ready..."
    wait_for_service "http://localhost:4000/health" "LiteLLM"
    
    print_status "Waiting for Open WebUI to be ready..."
    wait_for_service "http://localhost:8080" "Open WebUI"
    
    print_success "All services are running!"
}

# Function to display final information
display_final_info() {
    print_header "Installation Complete!"
    
    echo -e "${GREEN}🎉 Open WebUI + LiteLLM has been successfully installed!${NC}"
    echo ""
    echo -e "${CYAN}📍 Installation Directory:${NC} $INSTALL_DIR"
    echo ""
    echo -e "${CYAN}🔗 Access URLs:${NC}"
    echo -e "   • Open WebUI:        ${YELLOW}http://localhost:8080${NC}"
    echo -e "   • LiteLLM API:       ${YELLOW}http://localhost:4000${NC}"
    echo -e "   • LiteLLM Dashboard: ${YELLOW}http://localhost:4000/ui${NC}"
    echo ""
    echo -e "${CYAN}🔑 LiteLLM Dashboard Credentials:${NC}"
    echo -e "   • Username: ${YELLOW}${UI_USERNAME}${NC}"
    echo -e "   • Password: ${YELLOW}${UI_PASSWORD}${NC}"
    echo ""
    echo -e "${CYAN}🔧 Management Commands:${NC}"
    echo -e "   • Start services:  ${YELLOW}./start.sh${NC}"
    echo -e "   • Stop services:   ${YELLOW}./stop.sh${NC}"
    echo -e "   • Check status:    ${YELLOW}./status.sh${NC}"
    echo -e "   • View logs:       ${YELLOW}./logs.sh${NC}"
    echo -e "   • Restart:         ${YELLOW}./restart.sh${NC}"
    echo ""
    echo -e "${CYAN}📝 Next Steps:${NC}"
    echo -e "   1. Visit the Open WebUI at ${YELLOW}http://localhost:8080${NC}"
    echo -e "   2. Create your admin account (first user becomes admin)"
    echo -e "   3. Access LiteLLM dashboard at ${YELLOW}http://localhost:4000/ui${NC}"
    echo -e "   4. Add your API keys in the ${YELLOW}.env${NC} file"
    echo -e "   5. Run ${YELLOW}./restart.sh${NC} after adding API keys"
    echo ""
    echo -e "${GREEN}✨ Enjoy your unified AI gateway!${NC}"
}

# Main installation function
main() {
    clear
    print_header "Open WebUI + LiteLLM Automated Installer"
    echo -e "${CYAN}This script will install and configure:${NC}"
    echo -e "  • Docker and Docker Compose"
    echo -e "  • Open WebUI (ChatGPT-like interface)"
    echo -e "  • LiteLLM (Unified AI gateway)"
    echo -e "  • PostgreSQL database"
    echo -e "  • LiteLLM Dashboard with authentication"
    echo ""
    
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Installation cancelled."
        exit 0
    fi
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root. Please run as a regular user with sudo privileges."
        exit 1
    fi
    
    # Check for sudo privileges
    if ! sudo -n true 2>/dev/null; then
        print_error "This script requires sudo privileges. Please ensure you can run sudo commands."
        exit 1
    fi
    
    # Start installation
    install_docker
    create_project_directory
    create_litellm_config
    create_environment_file
    create_docker_compose
    create_management_scripts
    create_readme
    start_services
    display_final_info
    
    # Save credentials to file
    cat > credentials.txt << EOF
Open WebUI + LiteLLM Installation Credentials
============================================
Generated on: $(date)

Access URLs:
- Open WebUI: http://localhost:8080
- LiteLLM API: http://localhost:4000  
- LiteLLM Dashboard: http://localhost:4000/ui

LiteLLM Dashboard:
- Username: ${UI_USERNAME}
- Password: ${UI_PASSWORD}

API Access:
- Master Key: ${LITELLM_MASTER_KEY}

Database:
- Host: localhost:5432
- Database: litellm
- Username: litellm
- Password: ${DB_PASSWORD}

IMPORTANT: Keep this file secure and delete it after noting the credentials!
EOF
    
    print_success "Credentials saved to: $INSTALL_DIR/credentials.txt"
    print_warning "Please save your credentials and delete the credentials.txt file for security!"
}

# Run main function
main "$@"

