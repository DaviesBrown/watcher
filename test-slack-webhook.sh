#!/bin/bash

# Quick test to verify Slack webhook is working

set -e

echo "🧪 Testing Slack Webhook Connection"
echo "===================================="
echo ""

# Get webhook URL from .env
WEBHOOK_URL=$(grep SLACK_WEBHOOK_URL .env | cut -d'=' -f2)

if [ -z "$WEBHOOK_URL" ]; then
    echo "❌ SLACK_WEBHOOK_URL not found in .env"
    exit 1
fi

if [ "$WEBHOOK_URL" == "https://hooks.slack.com/services/YOUR/WEBHOOK/URL" ]; then
    echo "❌ SLACK_WEBHOOK_URL is not configured"
    echo "   Please update .env with your actual webhook URL"
    exit 1
fi

echo "📡 Webhook URL: ${WEBHOOK_URL:0:40}..."
echo ""
echo "Sending test message to Slack..."
echo ""

RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  -H 'Content-type: application/json' \
  --data '{"text":"🧪 Test Alert from Blue/Green Monitoring System\n\nThis is a test message to verify Slack integration is working correctly.\n\nTimestamp: '"$(date)"'"}' \
  "$WEBHOOK_URL")

echo "HTTP Response Code: $RESPONSE"
echo ""

if [ "$RESPONSE" == "200" ]; then
    echo "✅ SUCCESS! Slack webhook is working correctly"
    echo ""
    echo "Check your Slack channel for the test message."
    echo "If you see it, your alerts are configured correctly!"
else
    echo "❌ FAILED! HTTP $RESPONSE"
    echo ""
    echo "Possible issues:"
    echo "  - Webhook URL is incorrect"
    echo "  - Webhook has been revoked"
    echo "  - Network connectivity issue"
    echo ""
    echo "To fix:"
    echo "  1. Go to https://api.slack.com/messaging/webhooks"
    echo "  2. Create a new webhook or verify existing one"
    echo "  3. Update SLACK_WEBHOOK_URL in .env"
fi

echo ""
