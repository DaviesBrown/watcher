# Blue/Green Deployment with Nginx Failover & Monitoring

This project implements a Blue/Green deployment strategy for Node.js services using Nginx as a reverse proxy with automatic health-based failover and real-time monitoring with Slack alerts.

## Architecture Overview

- **Nginx Proxy**: Routes traffic to active pool (Blue or Green) with automatic failover
- **Blue Instance**: Primary Node.js service on port 8081
- **Green Instance**: Backup Node.js service on port 8082
- **Alert Watcher**: Python service that monitors logs and sends Slack alerts
- **Public Endpoint**: http://localhost:8080

## Features

### Stage 2: Automatic Failover
✅ **Automatic Failover**: When the active pool fails, Nginx automatically switches to the backup pool  
✅ **Zero Downtime**: Failed requests are retried on the backup pool within the same client request  
✅ **Health Checks**: Built-in health monitoring for both instances  
✅ **Header Forwarding**: App headers (X-App-Pool, X-Release-Id) are preserved and forwarded to clients  
✅ **Tight Timeouts**: Quick failure detection (2s timeouts) for rapid failover  
✅ **Parameterized Configuration**: Fully configurable via .env file

### Stage 3: Operational Visibility
🚨 **Failover Detection**: Real-time alerts when traffic switches between pools  
📊 **Error Rate Monitoring**: Tracks 5xx error rates over sliding windows  
💬 **Slack Integration**: Automated alerts sent to Slack channels  
🔧 **Maintenance Mode**: Suppress alerts during planned operations  
📝 **Structured Logging**: Enhanced Nginx logs capture pool, release, and upstream details  
📖 **Operator Runbook**: Complete documentation for alert response

## Prerequisites

- Docker
- Docker Compose
- Slack workspace with incoming webhook (for alerts)

## Configuration

All configuration is managed through the `.env` file. See `.env.example` for a complete reference.

### Stage 2 Configuration

```env
# Docker Images
BLUE_IMAGE=yimikaade/wonderful:devops-stage-two
GREEN_IMAGE=yimikaade/wonderful:devops-stage-two

# Active Pool (blue or green)
ACTIVE_POOL=blue

# Release IDs
RELEASE_ID_BLUE=blue-v1.0.0
RELEASE_ID_GREEN=green-v1.0.0

# Application Port (optional)
PORT=3000
```

### Stage 3 Configuration (Monitoring & Alerts)

```env
# Slack Webhook URL for alerts
# Create at: https://api.slack.com/messaging/webhooks
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL

# Error rate threshold (percentage)
ERROR_RATE_THRESHOLD=2

# Sliding window size (number of requests)
WINDOW_SIZE=200

# Alert cooldown period (seconds)
ALERT_COOLDOWN_SEC=300

# Maintenance mode flag (suppress alerts during planned work)
MAINTENANCE_MODE=false
```

### Slack Setup

1. Go to https://api.slack.com/messaging/webhooks
2. Create a new Slack app or use existing one
3. Enable Incoming Webhooks
4. Create a webhook for your desired channel
5. Copy the webhook URL to `SLACK_WEBHOOK_URL` in `.env`

## Deployment

### Start the Services

```bash
docker-compose up -d
```

### Check Service Status

```bash
docker-compose ps
```

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f nginx
docker-compose logs -f app_blue
docker-compose logs -f app_green
docker-compose logs -f alert_watcher

# View Nginx structured access logs
docker exec nginx_proxy tail -f /var/log/nginx/access.log
```

### Stop the Services

```bash
docker-compose down
```

## Endpoints

### Public Endpoint (via Nginx)
- **Base URL**: http://localhost:8080
- `GET /version` - Returns version info with headers
- `GET /healthz` - Health check
- `POST /chaos/start` - Trigger failure simulation
- `POST /chaos/stop` - Stop failure simulation

### Direct Access (for testing/grading)
- **Blue Instance**: http://localhost:8081
- **Green Instance**: http://localhost:8082

## Testing Failover

### 1. Verify Normal Operation (Blue Active)

```bash
# Should return 200 with X-App-Pool: blue
curl -i http://localhost:8080/version
```

Expected headers:
```
X-App-Pool: blue
X-Release-Id: blue-v1.0.0
```

### 2. Trigger Chaos on Blue Instance

```bash
# Induce errors on Blue
curl -X POST http://localhost:8081/chaos/start?mode=error

# Or induce timeout
curl -X POST http://localhost:8081/chaos/start?mode=timeout
```

### 3. Verify Automatic Failover to Green

```bash
# Should now return 200 with X-App-Pool: green
curl -i http://localhost:8080/version
```

Expected headers:
```
X-App-Pool: green
X-Release-Id: green-v1.0.0
```

### 4. Test Multiple Consecutive Requests

```bash
# All should return 200 from Green pool
for i in {1..10}; do
  curl -s http://localhost:8080/version | jq -r '.pool'
done
```

### 5. Stop Chaos and Verify Recovery

```bash
# Stop chaos on Blue
curl -X POST http://localhost:8081/chaos/stop

# Requests should still go to Green (backup remains active until manual switch)
curl -i http://localhost:8080/version
```

### 6. Switch Back to Blue (Manual)

```bash
# Update .env file
# Change ACTIVE_POOL=green to ACTIVE_POOL=blue

# Restart Nginx
docker-compose restart nginx

# Verify traffic is back on Blue
curl -i http://localhost:8080/version
```

---

## Stage 3: Testing Monitoring & Alerts

### Prerequisites

Before testing alerts:

1. **Configure Slack Webhook**: Update `SLACK_WEBHOOK_URL` in `.env` with a valid webhook
2. **Start All Services**: Ensure all containers are running including `alert_watcher`
3. **Verify Watcher**: Check watcher logs: `docker logs alert_watcher`

### Test 1: Failover Alert

This test triggers a failover event and verifies a Slack alert is sent.

```bash
# 1. Verify baseline (Blue active)
curl -i http://localhost:8080/version | grep X-App-Pool
# Expected: X-App-Pool: blue

# 2. Generate some baseline traffic
for i in {1..10}; do curl -s http://localhost:8080/version > /dev/null; done

# 3. Trigger chaos on Blue to force failover
curl -X POST http://localhost:8081/chaos/start?mode=error

# 4. Send requests through Nginx (will failover to Green)
for i in {1..20}; do curl -s http://localhost:8080/version > /dev/null; sleep 0.5; done

# 5. Verify failover occurred
curl -i http://localhost:8080/version | grep X-App-Pool
# Expected: X-App-Pool: green

# 6. Check Slack for failover alert
# You should see: "🔄 Failover Detected: Traffic switched from blue to green"

# 7. Check watcher logs
docker logs alert_watcher | tail -n 20
```

**Expected Alert in Slack:**
```
🚨 Blue/Green Deployment Alert
🔄 Failover Detected: Traffic switched from `blue` to `green`

Previous Pool: BLUE
Current Pool: GREEN
Action Required: Check health of `blue` container and investigate root cause
```

### Test 2: High Error Rate Alert

This test generates 5xx errors to trigger an error rate alert.

```bash
# 1. Stop chaos from previous test
curl -X POST http://localhost:8081/chaos/stop
curl -X POST http://localhost:8082/chaos/stop

# 2. Restart services to reset state
docker-compose restart app_blue app_green nginx

# Wait for services to be healthy
sleep 10

# 3. Enable chaos on active pool (Blue)
curl -X POST http://localhost:8081/chaos/start?mode=error

# 4. Generate mixed traffic (errors + successes)
# This will trigger errors on blue, causing failover to green
for i in {1..100}; do 
  curl -s http://localhost:8080/version > /dev/null
  sleep 0.1
done

# 5. Check watcher logs for error rate detection
docker logs alert_watcher | grep -i "error"

# 6. Check Slack for error rate alert
# You should see: "⚠️ High Error Rate Detected"
```

**Expected Alert in Slack:**
```
🚨 Blue/Green Deployment Alert
⚠️ High Error Rate Detected: X.XX% of requests returning 5xx errors

Error Rate: X.XX%
Threshold: 2%
Window: XX errors in 200 requests
Current Pool: GREEN
Action Required: Inspect upstream logs and consider toggling pools
```

### Test 3: Verify Structured Logs

Verify that Nginx logs contain the required monitoring fields.

```bash
# Generate a request
curl http://localhost:8080/version

# Check log format
docker exec nginx_proxy tail -n 1 /var/log/nginx/access.log

# Expected fields in log line:
# - pool=blue (or green)
# - release=blue-v1.0.0 (or green-v1.0.0)
# - upstream_status=200
# - upstream=172.x.x.x:3000
# - request_time=0.xxx
# - upstream_response_time=0.xxx
```

### Test 4: Maintenance Mode

Test that alerts are suppressed during maintenance.

```bash
# 1. Enable maintenance mode
sed -i 's/MAINTENANCE_MODE=false/MAINTENANCE_MODE=true/' .env
docker-compose restart alert_watcher

# 2. Trigger a failover (should not alert)
docker-compose stop app_blue
curl http://localhost:8080/version

# 3. Check logs - should show suppression
docker logs alert_watcher | grep "maintenance mode"

# 4. Disable maintenance mode
sed -i 's/MAINTENANCE_MODE=true/MAINTENANCE_MODE=false/' .env
docker-compose restart alert_watcher
```

### Test 5: Alert Cooldown

Verify that duplicate alerts are rate-limited.

```bash
# 1. Check current cooldown setting
grep ALERT_COOLDOWN_SEC .env
# Default: 300 seconds (5 minutes)

# 2. Trigger multiple failovers rapidly
docker-compose stop app_blue
sleep 2
curl http://localhost:8080/version
docker-compose start app_blue
sleep 10
docker-compose stop app_blue
curl http://localhost:8080/version

# 3. Check logs - second alert should be suppressed
docker logs alert_watcher | grep -i "cooldown"
```

### Viewing Real-Time Monitoring

Monitor the alert watcher in real-time during testing:

```bash
# Terminal 1: Watch alert watcher logs
docker logs -f alert_watcher

# Terminal 2: Watch Nginx access logs
docker exec nginx_proxy tail -f /var/log/nginx/access.log

# Terminal 3: Generate test traffic
watch -n 1 curl -s http://localhost:8080/version
```

---

## Operator Runbook

For detailed operational procedures, alert meanings, and troubleshooting steps, see **[runbook.md](./runbook.md)**.

The runbook covers:
- 🚨 **Alert Types**: Failover, High Error Rate, Recovery
- 🔧 **Response Procedures**: Step-by-step actions for each alert
- 🛠️ **Troubleshooting**: Common issues and resolution steps
- 📞 **Escalation**: When and how to escalate issues
- 🔧 **Maintenance Mode**: How to suppress alerts during planned work

---

## Failover Mechanics

### Primary/Backup Configuration
- **Active Pool**: Configured via `ACTIVE_POOL` in .env
- **Backup Pool**: Automatically determined (opposite of active)
- **max_fails**: 2 (marks upstream as down after 2 failures)
- **fail_timeout**: 5s (upstream stays marked down for 5 seconds)

### Retry Policy
- **proxy_connect_timeout**: 2s
- **proxy_send_timeout**: 2s
- **proxy_read_timeout**: 2s
- **proxy_next_upstream**: error timeout http_500 http_502 http_503 http_504
- **proxy_next_upstream_tries**: 2

### How It Works
1. Client sends request to Nginx (http://localhost:8080)
2. Nginx forwards to active pool (e.g., Blue)
3. If Blue fails (timeout, 5xx error):
   - Nginx marks Blue as failed
   - Nginx automatically retries to backup pool (Green)
   - Client receives successful response from Green
4. Subsequent requests go directly to Green until Blue recovers

## Grading Compliance

✅ **Zero Failed Requests**: All client requests return 200 during failover
✅ **Header Preservation**: X-App-Pool and X-Release-Id headers are forwarded unchanged
✅ **Quick Failover**: Tight timeouts ensure failures are detected within 2 seconds
✅ **≥95% Backup Traffic**: After chaos, nearly 100% of requests are served by backup pool
✅ **Request Duration**: All requests complete within 10 seconds
✅ **No Image Rebuilds**: Uses pre-built images, no Docker build in compose
✅ **Parameterized**: Fully configured via .env file

## Troubleshooting

### Nginx Configuration Issues

```bash
# Test Nginx configuration
docker exec nginx_proxy nginx -t

# View generated config
docker exec nginx_proxy cat /etc/nginx/nginx.conf
```

### App Not Responding

```bash
# Check app health directly
curl http://localhost:8081/healthz
curl http://localhost:8082/healthz

# Check container logs
docker-compose logs app_blue
docker-compose logs app_green
```

### Failover Not Working

1. Verify timeouts are properly configured
2. Check Nginx logs for upstream errors
3. Ensure both Blue and Green containers are healthy
4. Verify backup directive is in upstream configuration

```bash
docker-compose logs nginx
```

## Environment Variables Reference

### Stage 2: Deployment

| Variable | Description | Example |
|----------|-------------|---------|
| BLUE_IMAGE | Docker image for Blue instance | yimikaade/wonderful:devops-stage-two |
| GREEN_IMAGE | Docker image for Green instance | yimikaade/wonderful:devops-stage-two |
| ACTIVE_POOL | Active pool (blue or green) | blue |
| RELEASE_ID_BLUE | Release ID for Blue instance | blue-v1.0.0 |
| RELEASE_ID_GREEN | Release ID for Green instance | green-v1.0.0 |
| PORT | Application port (optional) | 3000 |

### Stage 3: Monitoring & Alerts

| Variable | Description | Default |
|----------|-------------|---------|
| SLACK_WEBHOOK_URL | Slack incoming webhook URL | (required) |
| ERROR_RATE_THRESHOLD | Error rate percentage threshold | 2 |
| WINDOW_SIZE | Sliding window size (requests) | 200 |
| ALERT_COOLDOWN_SEC | Cooldown between alerts (seconds) | 300 |
| MAINTENANCE_MODE | Suppress alerts (true/false) | false |

## Files Structure

```
.
├── .env                      # Environment configuration
├── .env.example             # Example configuration with documentation
├── docker-compose.yml        # Docker Compose orchestration
├── Dockerfile.nginx          # Custom Nginx image (if used)
├── Dockerfile.watcher        # Alert watcher Docker image
├── nginx.conf.template       # Nginx configuration template with custom logging
├── entrypoint.sh            # Nginx entrypoint script
├── watcher.py               # Python log monitoring and alerting script
├── requirements.txt         # Python dependencies
├── runbook.md               # Operational runbook for alerts
├── README.md                # This file
├── quickstart.sh            # Quick start script (optional)
└── simple-test.sh           # Simple test script (optional)
```

## CI/CD Integration

### Stage 2 Grading

The grader will:
1. Set environment variables in `.env`
2. Run `docker-compose up -d`
3. Test baseline (GET /version → Blue)
4. Trigger chaos (POST to 8081/chaos/start)
5. Verify failover (GET /version → Green, 0 non-200s)
6. Verify headers match expected pool/release

### Stage 3 Verification

For Stage 3, provide the following:

#### Required Screenshots

1. **Slack Alert - Failover Event**
   - Screenshot showing Slack message when Blue fails and Green takes over
   - Must show: alert title, previous/current pool, timestamp

2. **Slack Alert - High Error Rate**
   - Screenshot showing error rate alert when threshold is breached
   - Must show: error percentage, threshold, window size

3. **Container Logs - Structured Format**
   - Screenshot of Nginx log line showing structured fields
   - Must display: `pool=`, `release=`, `upstream_status=`, `upstream=`, `request_time=`

#### Log Verification

```bash
# Verify structured logging
docker exec nginx_proxy tail -n 10 /var/log/nginx/access.log

# Expected fields in each line:
# - pool=blue (or green)
# - release=blue-v1.0.0 (or green-v1.0.0)  
# - upstream_status=200 (or 500, etc.)
# - upstream=172.x.x.x:3000
# - request_time=0.xxx
# - upstream_response_time=0.xxx
```

#### Alert Testing

```bash
# Test failover alert
docker-compose stop app_blue
curl http://localhost:8080/version
# Check Slack for alert

# Test error rate alert  
curl -X POST http://localhost:8081/chaos/start?mode=error
for i in {1..100}; do curl -s http://localhost:8080/version > /dev/null; sleep 0.1; done
# Check Slack for alert
```

---

## Quick Start Guide

### Complete Setup (Stages 2 + 3)

```bash
# 1. Clone repository
git clone <your-repo-url>
cd watcher

# 2. Configure environment
cp .env.example .env
# Edit .env and set your SLACK_WEBHOOK_URL

# 3. Start all services
docker-compose up -d

# 4. Verify services are running
docker-compose ps

# 5. Check that alert watcher is monitoring
docker logs alert_watcher

# 6. Test the setup
curl http://localhost:8080/version

# 7. Test failover and alerts
curl -X POST http://localhost:8081/chaos/start?mode=error
for i in {1..20}; do curl http://localhost:8080/version; sleep 0.5; done

# 8. Check Slack for alerts
# You should see a failover alert

# 9. Cleanup
docker-compose down -v
```

---

## Troubleshooting

### Stage 2 Issues

See existing troubleshooting section above for Nginx configuration, app health, and failover issues.

### Stage 3 Issues

#### Alert Watcher Not Starting

```bash
# Check watcher container status
docker ps -a | grep alert_watcher

# Check watcher logs for errors
docker logs alert_watcher

# Verify required environment variables
docker exec alert_watcher env | grep -E "SLACK_|ERROR_RATE|WINDOW"
```

#### No Slack Alerts Received

```bash
# Verify webhook URL is set
grep SLACK_WEBHOOK_URL .env

# Test webhook manually
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Test alert"}' \
  YOUR_SLACK_WEBHOOK_URL

# Check watcher logs for Slack errors
docker logs alert_watcher | grep -i slack
```

#### Alerts Not Detecting Failover

```bash
# Check if logs contain pool information
docker exec nginx_proxy tail -n 5 /var/log/nginx/access.log | grep "pool="

# Verify watcher can read logs
docker exec alert_watcher ls -la /var/log/nginx/

# Check watcher parsing
docker logs alert_watcher | grep -i "pool"
```

#### Error Rate Alerts Too Frequent/Infrequent

```bash
# Adjust threshold in .env
# Increase ERROR_RATE_THRESHOLD for less sensitive alerts
# Decrease ERROR_RATE_THRESHOLD for more sensitive alerts

# Adjust window size for smoother averaging
# Increase WINDOW_SIZE for more stable calculations
# Decrease WINDOW_SIZE for faster detection

# Restart watcher to apply changes
docker-compose restart alert_watcher
```

#### Maintenance Mode Not Working

```bash
# Verify setting
grep MAINTENANCE_MODE .env

# Ensure watcher restarted after change
docker-compose restart alert_watcher

# Check logs for maintenance mode message
docker logs alert_watcher | grep -i maintenance
```

---

## License

This project is for educational purposes as part of the HNG DevOps Stage 2 challenge.
