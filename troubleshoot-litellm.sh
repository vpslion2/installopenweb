#!/bin/bash

# =============================================================================
# LiteLLM Troubleshooting and Fix Script
# =============================================================================
# This script diagnoses and fixes LiteLLM connectivity issues
# =============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "🔍 LiteLLM Troubleshooting Script"
echo "================================="

# Check if we're in the right directory
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ docker-compose.yml not found. Please run this from your installation directory."
    echo "Try: cd ~/openwebui-litellm && ./troubleshoot-litellm.sh"
    exit 1
fi

print_status "Checking Docker containers..."
docker compose ps

echo ""
print_status "Checking LiteLLM container logs..."
docker compose logs litellm --tail=20

echo ""
print_status "Checking if LiteLLM port is accessible..."
if curl -s http://localhost:4000 >/dev/null 2>&1; then
    print_success "LiteLLM is accessible on localhost:4000"
else
    print_error "LiteLLM is not accessible on localhost:4000"
fi

echo ""
print_status "Checking if LiteLLM container is running..."
if docker ps | grep -q litellm-proxy; then
    print_success "LiteLLM container is running"
else
    print_error "LiteLLM container is not running"
    print_status "Attempting to start LiteLLM..."
    docker compose up -d litellm
    sleep 10
fi

echo ""
print_status "Checking port usage..."
netstat -tlnp | grep :4000 || echo "Port 4000 is not in use"

echo ""
print_status "Checking firewall status..."
ufw status 2>/dev/null || echo "UFW not installed or not active"

echo ""
print_status "Testing LiteLLM health endpoint..."
curl -v http://localhost:4000/health 2>&1 | head -10

echo ""
print_status "Checking LiteLLM configuration..."
if [ -f "litellm-config.yaml" ]; then
    echo "✅ LiteLLM config file exists"
    head -10 litellm-config.yaml
else
    echo "❌ LiteLLM config file missing"
fi

echo ""
print_status "Checking environment variables..."
if [ -f ".env" ]; then
    echo "✅ Environment file exists"
    grep -E "(LITELLM|DATABASE)" .env | head -5
else
    echo "❌ Environment file missing"
fi

echo ""
echo "🔧 Quick Fixes:"
echo "==============="
echo "1. Restart LiteLLM: docker compose restart litellm"
echo "2. Check logs: docker compose logs litellm -f"
echo "3. Rebuild: docker compose down && docker compose up -d"
echo "4. Check firewall: ufw allow 4000"
echo ""
echo "🌐 Access URLs:"
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}' || echo "your-server-ip")
echo "- LiteLLM API: http://${SERVER_IP}:4000"
echo "- LiteLLM Dashboard: http://${SERVER_IP}:4000/ui"
echo "- Open WebUI: http://${SERVER_IP}:8080"

