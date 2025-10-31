#!/bin/bash

# Verification Script: Check Nginx Structured Logs
# This script verifies that Nginx logs contain all required fields

set -e

echo "================================================"
echo "Stage 3 Verification: Structured Logs"
echo "================================================"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if nginx is running
if ! docker compose ps | grep -q "nginx_proxy.*running"; then
    echo -e "${RED}❌ Nginx proxy is not running${NC}"
    exit 1
fi

echo "🔍 Checking Nginx log format..."
echo ""

# Generate a test request
echo "Generating test request..."
curl -s http://localhost:8080/version > /dev/null

sleep 1

# Get the last log line
echo "Retrieving last log entry..."
LOG_LINE=$(docker exec nginx_proxy tail -n 1 /var/log/nginx/access.log)

echo ""
echo "Full log line:"
echo "----------------------------------------"
echo "$LOG_LINE"
echo "----------------------------------------"
echo ""

# Check for required fields
echo "Validating required fields:"
echo ""

ERRORS=0

# Check pool field
if echo "$LOG_LINE" | grep -q "pool="; then
    POOL_VALUE=$(echo "$LOG_LINE" | grep -o "pool=[^ ]*" | cut -d'=' -f2)
    echo -e "${GREEN}✅ pool field found: $POOL_VALUE${NC}"
else
    echo -e "${RED}❌ pool field missing${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check release field
if echo "$LOG_LINE" | grep -q "release="; then
    RELEASE_VALUE=$(echo "$LOG_LINE" | grep -o "release=[^ ]*" | cut -d'=' -f2)
    echo -e "${GREEN}✅ release field found: $RELEASE_VALUE${NC}"
else
    echo -e "${RED}❌ release field missing${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check upstream_status field
if echo "$LOG_LINE" | grep -q "upstream_status="; then
    UPSTREAM_STATUS=$(echo "$LOG_LINE" | grep -o "upstream_status=[^ ]*" | cut -d'=' -f2)
    echo -e "${GREEN}✅ upstream_status field found: $UPSTREAM_STATUS${NC}"
else
    echo -e "${RED}❌ upstream_status field missing${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check upstream field
if echo "$LOG_LINE" | grep -q "upstream="; then
    UPSTREAM_VALUE=$(echo "$LOG_LINE" | grep -o "upstream=[^ ]*" | cut -d'=' -f2)
    echo -e "${GREEN}✅ upstream field found: $UPSTREAM_VALUE${NC}"
else
    echo -e "${RED}❌ upstream field missing${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check request_time field
if echo "$LOG_LINE" | grep -q "request_time="; then
    REQUEST_TIME=$(echo "$LOG_LINE" | grep -o "request_time=[^ ]*" | cut -d'=' -f2)
    echo -e "${GREEN}✅ request_time field found: $REQUEST_TIME${NC}"
else
    echo -e "${RED}❌ request_time field missing${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check upstream_response_time field
if echo "$LOG_LINE" | grep -q "upstream_response_time="; then
    UPSTREAM_RESPONSE_TIME=$(echo "$LOG_LINE" | grep -o "upstream_response_time=[^ ]*" | cut -d'=' -f2)
    echo -e "${GREEN}✅ upstream_response_time field found: $UPSTREAM_RESPONSE_TIME${NC}"
else
    echo -e "${RED}❌ upstream_response_time field missing${NC}"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# Summary
if [ $ERRORS -eq 0 ]; then
    echo "================================================"
    echo -e "${GREEN}✅ ALL REQUIRED FIELDS PRESENT${NC}"
    echo "================================================"
    echo ""
    echo "Log format is correctly configured for Stage 3!"
    echo ""
    echo "📸 SCREENSHOT THIS OUTPUT for submission"
    exit 0
else
    echo "================================================"
    echo -e "${RED}❌ VALIDATION FAILED${NC}"
    echo "================================================"
    echo ""
    echo "Missing $ERRORS required field(s)"
    echo "Check nginx.conf.template for log_format configuration"
    exit 1
fi
