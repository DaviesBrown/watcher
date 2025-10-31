#!/bin/bash

# Test Script for Stage 3: Failover Alert Verification
# This script triggers a failover event and verifies the alert is sent

set -e

echo "================================================"
echo "Stage 3 Test: Failover Alert"
echo "================================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check prerequisites
echo "🔍 Checking prerequisites..."

if ! docker compose ps | grep -q "nginx_proxy.*running"; then
    echo -e "${RED}❌ Nginx proxy is not running. Start services first: docker compose up -d${NC}"
    exit 1
fi

if ! docker compose ps | grep -q "alert_watcher.*running"; then
    echo -e "${RED}❌ Alert watcher is not running. Start services first: docker compose up -d${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All required services are running${NC}"
echo ""

# Step 1: Verify baseline
echo "📊 Step 1: Verifying baseline (Blue should be active)..."
BASELINE_POOL=$(curl -s -I http://localhost:8080/version | grep -i "X-App-Pool" | awk '{print $2}' | tr -d '\r')

if [ -z "$BASELINE_POOL" ]; then
    echo -e "${RED}❌ Could not detect active pool from headers${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Baseline pool: $BASELINE_POOL${NC}"
echo ""

# Step 2: Generate baseline traffic
echo "📈 Step 2: Generating baseline traffic (10 requests)..."
for i in {1..10}; do
    curl -s http://localhost:8080/version > /dev/null
    echo -n "."
done
echo ""
echo -e "${GREEN}✅ Baseline traffic generated${NC}"
echo ""

# Step 3: Trigger chaos on active pool
echo "💥 Step 3: Triggering chaos on active pool ($BASELINE_POOL)..."

if [ "$BASELINE_POOL" == "blue" ]; then
    CHAOS_PORT=8081
    EXPECTED_FAILOVER_POOL="green"
else
    CHAOS_PORT=8082
    EXPECTED_FAILOVER_POOL="blue"
fi

CHAOS_RESPONSE=$(curl -s -X POST "http://localhost:${CHAOS_PORT}/chaos/start?mode=error")
echo "Chaos response: $CHAOS_RESPONSE"
echo -e "${GREEN}✅ Chaos activated on port $CHAOS_PORT${NC}"
echo ""

# Step 4: Generate traffic to trigger failover
echo "🔄 Step 4: Generating traffic to trigger failover (20 requests)..."
sleep 2  # Give chaos a moment to activate

for i in {1..20}; do
    curl -s http://localhost:8080/version > /dev/null
    echo -n "."
    sleep 0.5
done
echo ""
echo -e "${GREEN}✅ Failover traffic generated${NC}"
echo ""

# Step 5: Verify failover occurred
echo "✅ Step 5: Verifying failover..."
sleep 2  # Wait for failover to stabilize

FAILOVER_POOL=$(curl -s -I http://localhost:8080/version | grep -i "X-App-Pool" | awk '{print $2}' | tr -d '\r')

if [ "$FAILOVER_POOL" == "$EXPECTED_FAILOVER_POOL" ]; then
    echo -e "${GREEN}✅ FAILOVER SUCCESSFUL: Traffic switched from $BASELINE_POOL to $FAILOVER_POOL${NC}"
else
    echo -e "${RED}❌ FAILOVER FAILED: Expected $EXPECTED_FAILOVER_POOL but got $FAILOVER_POOL${NC}"
    exit 1
fi
echo ""

# Step 6: Check for alert in watcher logs
echo "🚨 Step 6: Checking alert watcher logs..."
sleep 3  # Give watcher time to process and send alert

ALERT_LOG=$(docker logs alert_watcher 2>&1 | tail -n 50)

if echo "$ALERT_LOG" | grep -q "Failover"; then
    echo -e "${GREEN}✅ ALERT DETECTED in watcher logs${NC}"
    echo ""
    echo "Alert details:"
    echo "$ALERT_LOG" | grep -A 5 "Failover" | head -n 10
else
    echo -e "${YELLOW}⚠️  No failover alert found in logs yet (may still be processing)${NC}"
fi
echo ""

# Step 7: Instructions for Slack verification
echo "================================================"
echo "📱 MANUAL VERIFICATION REQUIRED"
echo "================================================"
echo ""
echo "1. Check your Slack channel for a failover alert"
echo "2. The alert should contain:"
echo "   - Title: '🚨 Blue/Green Deployment Alert'"
echo "   - Message: 'Failover Detected'"
echo "   - Previous Pool: $BASELINE_POOL"
echo "   - Current Pool: $FAILOVER_POOL"
echo ""
echo "3. Take a screenshot of the Slack alert for submission"
echo ""

# Cleanup instructions
echo "================================================"
echo "🧹 CLEANUP (Optional)"
echo "================================================"
echo ""
echo "To reset the environment:"
echo "  1. Stop chaos: curl -X POST http://localhost:${CHAOS_PORT}/chaos/stop"
echo "  2. Restart services: docker compose restart"
echo ""

# Stop chaos automatically
echo "Stopping chaos automatically..."
curl -s -X POST "http://localhost:${CHAOS_PORT}/chaos/stop" > /dev/null
echo -e "${GREEN}✅ Chaos stopped${NC}"
echo ""

echo "================================================"
echo "✅ TEST COMPLETED"
echo "================================================"
