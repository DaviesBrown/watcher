#!/bin/bash

echo "==================================="
echo "Blue/Green Failover Test"
echo "==================================="
echo ""

# Test baseline
echo "1. Testing baseline (Blue active)..."
for i in {1..3}; do
    curl -s -I http://localhost:8080/version | grep "X-App-Pool"
done
echo ""

# Trigger chaos
echo "2. Triggering chaos on Blue..."
curl -s -X POST "http://localhost:8081/chaos/start?mode=error"
echo ""
sleep 1

# Test failover
echo ""
echo "3. Testing failover (should be Green)..."
for i in {1..5}; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/version)
    POOL=$(curl -s -I http://localhost:8080/version | grep "X-App-Pool" | cut -d' ' -f2)
    echo "Request $i: HTTP $STATUS | Pool: $POOL"
    sleep 0.5
done
echo ""

# Stop chaos
echo "4. Stopping chaos..."
curl -s -X POST "http://localhost:8081/chaos/stop"
echo ""
echo ""

echo "Test completed!"
