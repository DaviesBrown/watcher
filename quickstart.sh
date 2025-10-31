#!/bin/bash
# Quick Start Guide for Blue/Green Deployment

echo "=========================================="
echo "Blue/Green Deployment - Quick Start"
echo "=========================================="
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running. Please start Docker first."
    exit 1
fi

echo "✓ Docker is running"
echo ""

# Start services
echo "Starting services..."
docker compose up -d --build

echo ""
echo "Waiting for services to be healthy..."
sleep 10

# Check service status
echo ""
echo "Service Status:"
docker compose ps

echo ""
echo "=========================================="
echo "Available Endpoints:"
echo "=========================================="
echo "Public (via Nginx):  http://localhost:8080"
echo "Blue (direct):       http://localhost:8081"
echo "Green (direct):      http://localhost:8082"
echo ""

echo "=========================================="
echo "Quick Tests:"
echo "=========================================="
echo ""

echo "1. Check version (should show Blue):"
echo "   curl -I http://localhost:8080/version | grep X-App-Pool"
echo ""

echo "2. Trigger failover:"
echo "   curl -X POST http://localhost:8081/chaos/start?mode=error"
echo ""

echo "3. Check version again (should show Green):"
echo "   curl -I http://localhost:8080/version | grep X-App-Pool"
echo ""

echo "4. Stop chaos:"
echo "   curl -X POST http://localhost:8081/chaos/stop"
echo ""

echo "=========================================="
echo "Run automated test:"
echo "=========================================="
echo "   ./simple-test.sh"
echo ""

echo "=========================================="
echo "View logs:"
echo "=========================================="
echo "   docker compose logs -f"
echo ""

echo "✓ Deployment is ready!"
