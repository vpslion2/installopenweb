#!/bin/bash

# =============================================================================
# LiteLLM External Access Fix Script
# =============================================================================
# Fixes external access to LiteLLM on remote server
# =============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "🌐 LiteLLM External Access Fix"
echo "=============================="

# Get server IP
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}')
print_status "Server IP detected: $SERVER_IP"

echo ""
print_status "Step 1: Checking if LiteLLM is running internally..."
if curl -s http://localhost:4000 >/dev/null 2>&1; then
    print_success "✅ LiteLLM is running on localhost:4000"
else
    print_error "❌ LiteLLM is not running internally"
    print_status "Starting LiteLLM..."
    docker compose up -d litellm
    sleep 15
    
    if curl -s http://localhost:4000 >/dev/null 2>&1; then
        print_success "✅ LiteLLM started successfully"
    else
        print_error "❌ Failed to start LiteLLM"
        echo "Check logs: docker compose logs litellm"
        exit 1
    fi
fi

echo ""
print_status "Step 2: Checking Docker port binding..."
docker compose ps | grep litellm
docker port litellm-proxy 2>/dev/null || echo "Container port info not available"

echo ""
print_status "Step 3: Checking firewall settings..."
ufw status 2>/dev/null || echo "UFW not available"

print_status "Opening port 4000 in firewall..."
ufw allow 4000 2>/dev/null || echo "Could not modify firewall (may not have permissions)"

echo ""
print_status "Step 4: Checking if port 4000 is listening externally..."
netstat -tlnp | grep :4000 || echo "Port 4000 not found in netstat"

echo ""
print_status "Step 5: Testing external access..."
print_status "Testing from server to external IP..."

# Test external access
if curl -s --connect-timeout 5 http://${SERVER_IP}:4000 >/dev/null 2>&1; then
    print_success "✅ LiteLLM is accessible externally!"
else
    print_error "❌ LiteLLM is not accessible externally"
    
    print_status "Checking Docker Compose configuration..."
    grep -A 10 -B 5 "litellm:" docker-compose.yml
    
    print_status "This might be a Docker networking issue. Let's fix it..."
    
    # Check if using host networking or port mapping
    if grep -q "network_mode.*host" docker-compose.yml; then
        print_status "Using host networking - checking if service binds to 0.0.0.0..."
        docker compose logs litellm | grep -i "listening\|bind\|host" | tail -5
    else
        print_status "Using port mapping - checking port configuration..."
        grep -A 5 -B 5 "ports:" docker-compose.yml
    fi
fi

echo ""
print_status "Step 6: Checking container health..."
docker inspect litellm-proxy --format='{{.State.Health.Status}}' 2>/dev/null || echo "Health check not configured"

echo ""
print_status "Step 7: Testing LiteLLM endpoints..."
echo "Testing health endpoint..."
curl -s http://localhost:4000/health | head -3 2>/dev/null || echo "Health endpoint not responding"

echo ""
echo "Testing models endpoint..."
curl -s http://localhost:4000/v1/models | head -3 2>/dev/null || echo "Models endpoint not responding"

echo ""
print_status "Step 8: Final status check..."
echo "🔍 Container Status:"
docker compose ps

echo ""
echo "🌐 Access URLs (try these from your browser):"
echo "- LiteLLM API: http://${SERVER_IP}:4000"
echo "- LiteLLM Dashboard: http://${SERVER_IP}:4000/ui"
echo "- Open WebUI: http://${SERVER_IP}:8080"

echo ""
echo "🔧 If still not working, try:"
echo "1. Check cloud provider firewall/security groups"
echo "2. Restart with host networking: docker compose down && sed -i '/litellm:/a\\    network_mode: host' docker-compose.yml && docker compose up -d"
echo "3. Check logs: docker compose logs litellm -f"

echo ""
print_status "Testing final external access..."
if timeout 10 curl -s http://${SERVER_IP}:4000/health >/dev/null 2>&1; then
    print_success "🎉 SUCCESS! LiteLLM is accessible at http://${SERVER_IP}:4000"
    print_success "🎉 Dashboard available at http://${SERVER_IP}:4000/ui"
else
    print_error "❌ External access still not working"
    echo ""
    echo "💡 This is likely a cloud provider firewall issue."
    echo "   Check your cloud provider's security groups/firewall rules."
    echo "   Make sure port 4000 is open for inbound traffic."
fi

