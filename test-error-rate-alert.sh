#!/bin/bash

# Test Script for Stage 3: Error Rate Alert Verification
# This script generates high error rates and verifies alert is sent

set -e

echo "================================================"
echo "Stage 3 Test: Error Rate Alert"
echo "================================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

# Step 1: Reset environment
echo "🔄 Step 1: Resetting environment..."

# Stop any existing chaos
curl -s -X POST http://localhost:8081/chaos/stop > /dev/null 2>&1 || true
curl -s -X POST http://localhost:8082/chaos/stop > /dev/null 2>&1 || true

# Restart services to ensure clean state
echo "Restarting services..."
docker compose restart app_blue app_green nginx > /dev/null 2>&1

echo "Waiting for services to be healthy (10 seconds)..."
sleep 10

echo -e "${GREEN}✅ Environment reset${NC}"
echo ""

# Step 2: Verify current active pool
echo "📊 Step 2: Detecting active pool..."
ACTIVE_POOL=$(curl -s -I http://localhost:8080/version | grep -i "X-App-Pool" | awk '{print $2}' | tr -d '\r')

if [ -z "$ACTIVE_POOL" ]; then
    echo -e "${RED}❌ Could not detect active pool${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Active pool: $ACTIVE_POOL${NC}"

# Determine port for chaos
if [ "$ACTIVE_POOL" == "blue" ]; then
    CHAOS_PORT=8081
else
    CHAOS_PORT=8082
fi
echo ""

# Step 3: Enable chaos to generate errors
echo "💥 Step 3: Enabling error mode on active pool (port $CHAOS_PORT)..."
CHAOS_RESPONSE=$(curl -s -X POST "http://localhost:${CHAOS_PORT}/chaos/start?mode=error")
echo "Chaos response: $CHAOS_RESPONSE"
echo -e "${GREEN}✅ Error mode activated${NC}"
echo ""

# Step 4: Generate traffic to accumulate errors
echo "📈 Step 4: Generating traffic to trigger error rate alert..."
echo "Sending 150 requests (this will take ~15 seconds)..."

ERROR_COUNT=0
SUCCESS_COUNT=0

for i in {1..150}; do
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/version)
    
    if [ "$HTTP_STATUS" == "200" ]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        echo -n "."
    else
        ERROR_COUNT=$((ERROR_COUNT + 1))
        echo -n "x"
    fi
    
    # Small delay between requests
    sleep 0.1
done

echo ""
echo ""
echo "Traffic generation complete:"
echo "  - Successful requests (200): $SUCCESS_COUNT"
echo "  - Failed requests (5xx): $ERROR_COUNT"

if [ $ERROR_COUNT -gt 0 ]; then
    ERROR_RATE=$(awk "BEGIN {printf \"%.2f\", ($ERROR_COUNT / 150) * 100}")
    echo "  - Error rate: $ERROR_RATE%"
else
    echo "  - Error rate: 0%"
fi

echo ""

# Step 5: Check if error rate threshold was breached
THRESHOLD=$(grep ERROR_RATE_THRESHOLD .env | cut -d'=' -f2)
echo "Configured threshold: ${THRESHOLD}%"

if [ $ERROR_COUNT -gt 0 ]; then
    echo -e "${GREEN}✅ Errors were generated${NC}"
else
    echo -e "${YELLOW}⚠️  No errors detected - chaos may not be working properly${NC}"
fi
echo ""

# Step 6: Check for alert in watcher logs
echo "🚨 Step 6: Checking alert watcher logs for error rate alert..."
sleep 5  # Give watcher time to process and potentially send alert

ALERT_LOG=$(docker logs alert_watcher 2>&1 | tail -n 100)

if echo "$ALERT_LOG" | grep -qi "error"; then
    echo -e "${GREEN}✅ ERROR MONITORING DETECTED in watcher logs${NC}"
    echo ""
    echo "Recent watcher activity:"
    echo "$ALERT_LOG" | grep -i "error" | tail -n 10
else
    echo -e "${YELLOW}⚠️  No error-related logs found (may still be processing)${NC}"
fi

echo ""

# Check specifically for error rate alerts
if echo "$ALERT_LOG" | grep -qi "error rate"; then
    echo -e "${GREEN}✅ ERROR RATE ALERT detected in logs${NC}"
    echo ""
    echo "Alert details:"
    echo "$ALERT_LOG" | grep -A 5 -i "error rate" | head -n 10
else
    echo -e "${YELLOW}⚠️  Note: Alert may not fire if error rate is below threshold${NC}"
    echo "   or if alert is in cooldown period from previous test"
fi

echo ""

# Step 7: View structured logs
echo "📝 Step 7: Checking Nginx structured logs..."
echo ""
echo "Sample log entries (last 5):"
docker exec nginx_proxy tail -n 5 /var/log/nginx/access.log
echo ""

# Step 8: Instructions for Slack verification
echo "================================================"
echo "📱 MANUAL VERIFICATION REQUIRED"
echo "================================================"
echo ""
echo "1. Check your Slack channel for an error rate alert"
echo "2. The alert should contain:"
echo "   - Title: '🚨 Blue/Green Deployment Alert'"
echo "   - Message: 'High Error Rate Detected'"
echo "   - Error Rate: X.XX%"
echo "   - Threshold: ${THRESHOLD}%"
echo "   - Window: XX errors in YYY requests"
echo ""
echo "3. Take a screenshot of the Slack alert for submission"
echo ""
echo "Note: If no alert was sent, possible reasons:"
echo "  - Error rate was below threshold (${THRESHOLD}%)"
echo "  - Alert is in cooldown period (check ALERT_COOLDOWN_SEC in .env)"
echo "  - Not enough requests in window (check WINDOW_SIZE in .env)"
echo ""

# Cleanup
echo "================================================"
echo "🧹 CLEANUP"
echo "================================================"
echo ""
echo "Stopping chaos mode..."
curl -s -X POST "http://localhost:${CHAOS_PORT}/chaos/stop" > /dev/null
echo -e "${GREEN}✅ Chaos stopped${NC}"
echo ""

echo "To fully reset:"
echo "  docker compose restart"
echo ""

echo "================================================"
echo "✅ TEST COMPLETED"
echo "================================================"
