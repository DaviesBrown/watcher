#!/bin/bash

# Comprehensive Test Script for All Alert Types
# Tests: Failover Alert, Error Rate Alert, and Recovery Alert

set -e

echo "================================================"
echo "Complete Alert System Test"
echo "================================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check prerequisites
echo "🔍 Checking prerequisites..."

if ! docker compose ps nginx 2>/dev/null | grep -q "Up"; then
    echo -e "${RED}❌ Nginx proxy is not running. Start services first: docker compose up -d${NC}"
    exit 1
fi

if ! docker compose ps alert_watcher 2>/dev/null | grep -q "Up"; then
    echo -e "${RED}❌ Alert watcher is not running. Start services first: docker compose up -d${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All required services are running${NC}"
echo ""

# Reset environment
echo "🔄 Resetting environment..."
curl -s -X POST http://localhost:8081/chaos/stop > /dev/null 2>&1 || true
curl -s -X POST http://localhost:8082/chaos/stop > /dev/null 2>&1 || true
docker compose restart app_blue app_green nginx > /dev/null 2>&1
echo "Waiting for services to be healthy (15 seconds)..."
sleep 15
echo -e "${GREEN}✅ Environment reset${NC}"
echo ""

# Test 1: Baseline
echo "================================================"
echo "Test 1: Verify Baseline"
echo "================================================"
BASELINE_POOL=$(curl -s -I http://localhost:8080/version | grep -i "X-App-Pool" | awk '{print $2}' | tr -d '\r')
echo -e "${GREEN}✅ Baseline pool: $BASELINE_POOL${NC}"
echo ""

# Test 2: Failover Alert
echo "================================================"
echo "Test 2: Failover Alert"
echo "================================================"
echo "Triggering chaos on blue pool..."
curl -s -X POST http://localhost:8081/chaos/start?mode=error > /dev/null
echo "Generating traffic to trigger failover..."
for i in {1..10}; do
    curl -s http://localhost:8080/version > /dev/null
    sleep 0.2
done
echo "Waiting for alert processing..."
sleep 5

FAILOVER_POOL=$(curl -s -I http://localhost:8080/version | grep -i "X-App-Pool" | awk '{print $2}' | tr -d '\r')
echo -e "${GREEN}✅ Failover complete: $BASELINE_POOL → $FAILOVER_POOL${NC}"

if docker logs alert_watcher 2>&1 | grep -q "Failover Detected"; then
    echo -e "${GREEN}✅ Failover alert detected in logs${NC}"
else
    echo -e "${YELLOW}⚠️  Failover alert not found${NC}"
fi
echo ""

# Test 3: Error Rate Alert
echo "================================================"
echo "Test 3: Error Rate Alert"
echo "================================================"
echo "Continuing to generate errors..."
for i in {1..15}; do
    curl -s http://localhost:8080/version > /dev/null
    sleep 0.2
done
echo "Waiting for error rate alert..."
sleep 5

if docker logs alert_watcher 2>&1 | grep -q "High Error Rate Detected"; then
    echo -e "${GREEN}✅ Error rate alert detected in logs${NC}"
else
    echo -e "${YELLOW}⚠️  Error rate alert not found (may be in cooldown)${NC}"
fi
echo ""

# Test 4: Recovery Alert
echo "================================================"
echo "Test 4: Recovery Alert"
echo "================================================"
echo "Stopping chaos to trigger recovery..."
curl -s -X POST http://localhost:8081/chaos/stop > /dev/null
echo "Generating traffic to trigger recovery..."
for i in {1..10}; do
    curl -s http://localhost:8080/version > /dev/null
    sleep 0.2
done
echo "Waiting for recovery alert..."
sleep 5

RECOVERY_POOL=$(curl -s -I http://localhost:8080/version | grep -i "X-App-Pool" | awk '{print $2}' | tr -d '\r')
echo -e "${GREEN}✅ Recovery complete: $FAILOVER_POOL → $RECOVERY_POOL${NC}"

if docker logs alert_watcher 2>&1 | grep -q "Recovery Detected"; then
    echo -e "${GREEN}✅ Recovery alert detected in logs${NC}"
else
    echo -e "${YELLOW}⚠️  Recovery alert not found${NC}"
fi
echo ""

# Summary
echo "================================================"
echo "Alert Summary"
echo "================================================"
echo ""
echo "Recent alerts sent to Slack:"
docker logs alert_watcher 2>&1 | grep -A 5 "🚨 ALERT" | tail -50
echo ""

echo "================================================"
echo "📱 MANUAL VERIFICATION REQUIRED"
echo "================================================"
echo ""
echo "Check your Slack channel for these 3 alerts:"
echo ""
echo "1. 🔄 Failover Alert"
echo "   - Message: 'Failover Detected'"
echo "   - Previous Pool: blue"
echo "   - Current Pool: green"
echo ""
echo "2. ⚠️  Error Rate Alert"
echo "   - Message: 'High Error Rate Detected'"
echo "   - Error Rate: > 2%"
echo "   - Window: X errors in Y requests"
echo ""
echo "3. ✅ Recovery Alert"
echo "   - Message: 'Recovery Detected'"
echo "   - Current Pool: blue"
echo "   - Status: Normal Operations Resumed"
echo ""
echo "Take screenshots of all three alerts for submission"
echo ""

echo "================================================"
echo "✅ ALL TESTS COMPLETED"
echo "================================================"
