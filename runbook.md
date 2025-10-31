# 📖 Operations Runbook: Blue/Green Deployment Monitoring

This runbook provides guidance for operators responding to alerts from the Nginx Log Watcher.

---

## 🚨 Alert Types

### 1. Failover Detected

**Alert Message:**
```
🔄 Failover Detected: Traffic switched from `blue` to `green`
```

**What it means:**
- The primary pool (e.g., `blue`) has become unhealthy or unresponsive
- Nginx has automatically failed over to the backup pool (e.g., `green`)
- User requests are now being served by the backup pool
- This indicates the primary container is experiencing issues

**Immediate Actions:**

1. **Check Container Health**
   ```bash
   docker ps
   docker logs app_blue  # or app_green, depending on failed pool
   ```

2. **Inspect Health Check Status**
   ```bash
   docker inspect app_blue | grep -A 10 Health
   ```

3. **Review Nginx Logs**
   ```bash
   docker logs nginx_proxy
   ```

4. **Check Upstream Errors**
   ```bash
   docker exec nginx_proxy tail -n 50 /var/log/nginx/error.log
   ```

**Root Cause Investigation:**

- **Application Crash**: Check if the container exited unexpectedly
  ```bash
  docker ps -a | grep app_blue
  ```

- **Health Check Failures**: Review the `/healthz` endpoint
  ```bash
  curl http://localhost:8081/healthz
  ```

- **Resource Exhaustion**: Check CPU/memory usage
  ```bash
  docker stats app_blue --no-stream
  ```

- **Network Issues**: Verify connectivity between containers
  ```bash
  docker exec nginx_proxy ping -c 3 app_blue
  ```

**Recovery Steps:**

1. **Restart Failed Container**
   ```bash
   docker compose restart app_blue
   ```

2. **Verify Health After Restart**
   ```bash
   # Wait 10-15 seconds for health checks
   docker inspect app_blue | grep -A 5 Health
   ```

3. **Test Endpoint Directly**
   ```bash
   curl http://localhost:8081/version
   ```

4. **Monitor for Recovery Alert**
   - Once primary pool is healthy, traffic will return automatically
   - Watch for "✅ Recovery Detected" alert in Slack

**When to Escalate:**
- Container fails to restart after 3 attempts
- Health checks continue to fail after restart
- Both pools are unhealthy (total outage)
- Pattern of repeated failovers (flapping)

---

### 2. High Error Rate Alert

**Alert Message:**
```
⚠️ High Error Rate Detected: 5.23% of requests returning 5xx errors
```

**What it means:**
- The currently active pool is returning 5xx errors above the configured threshold
- This could indicate application bugs, database issues, or resource problems
- Users are experiencing degraded service

**Immediate Actions:**

1. **Identify Current Active Pool**
   ```bash
   # Check which pool is serving traffic
   curl -I http://localhost:8080/version | grep X-App-Pool
   ```

2. **Check Application Logs**
   ```bash
   # If blue is active:
   docker logs app_blue --tail 100
   
   # If green is active:
   docker logs app_green --tail 100
   ```

3. **Analyze Error Distribution**
   ```bash
   # Check Nginx access logs for error patterns
   docker exec nginx_proxy grep "upstream_status=5" /var/log/nginx/access.log | tail -n 20
   ```

4. **Check Resource Utilization**
   ```bash
   docker stats --no-stream
   ```

**Root Cause Investigation:**

- **Application Errors**: Look for exceptions in container logs
  ```bash
  docker logs app_blue 2>&1 | grep -i error
  ```

- **Database Connection Issues**: Check for DB connection errors
- **Memory Leaks**: Monitor container memory over time
  ```bash
  docker stats app_blue
  ```

- **External Dependencies**: Verify upstream services are reachable
- **Configuration Issues**: Review environment variables
  ```bash
  docker inspect app_blue | grep -A 20 Env
  ```

**Mitigation Options:**

**Option A: Toggle to Backup Pool** (if backup is healthy)
```bash
# Update .env to switch active pool
sed -i 's/ACTIVE_POOL=blue/ACTIVE_POOL=green/' .env

# Recreate Nginx with new config
docker compose up -d nginx

# Verify traffic switched
curl -I http://localhost:8080/version | grep X-App-Pool
```

**Option B: Restart Active Container**
```bash
docker compose restart app_blue
```

**Option C: Scale Down and Back Up** (clears state)
```bash
docker compose stop app_blue
docker compose up -d app_blue
```

**Recovery Verification:**

1. **Monitor Error Rate**
   ```bash
   # Watch watcher logs
   docker logs -f alert_watcher
   ```

2. **Test Endpoints**
   ```bash
   # Make several test requests
   for i in {1..20}; do curl -s http://localhost:8080/version; done
   ```

3. **Check Alert Resolution**
   - Error rate should drop below threshold within 1-2 minutes
   - No new error rate alerts should fire

**When to Escalate:**
- Error rate remains above threshold after pool toggle
- Both pools exhibit high error rates
- Errors correlate with recent deployments
- Pattern indicates systemic issue (database, external API)

---

### 3. Recovery Detected

**Alert Message:**
```
✅ Recovery Detected: Primary pool `blue` is serving traffic again
```

**What it means:**
- The previously failed primary pool has recovered
- Traffic has automatically switched back to the primary pool
- System has returned to normal operations

**Actions:**

1. **Confirm Stable Operations**
   ```bash
   # Monitor for 5-10 minutes
   docker logs -f alert_watcher
   ```

2. **Review Incident Timeline**
   ```bash
   # Check nginx logs for failover/recovery pattern
   docker exec nginx_proxy grep "pool=" /var/log/nginx/access.log | tail -n 50
   ```

3. **Document Incident**
   - Record downtime duration
   - Note root cause if identified
   - Update incident log/ticketing system

4. **Post-Incident Review**
   - Was alert accurate and timely?
   - Were runbook steps effective?
   - Any improvements needed?

**No immediate action required** - system has self-healed.

---

## 🔧 Maintenance Mode

Use maintenance mode to suppress alerts during planned operations.

**Enable Maintenance Mode:**
```bash
# Update .env
sed -i 's/MAINTENANCE_MODE=false/MAINTENANCE_MODE=true/' .env

# Restart watcher to pick up new config
docker compose restart alert_watcher
```

**Disable Maintenance Mode:**
```bash
# Update .env
sed -i 's/MAINTENANCE_MODE=true/MAINTENANCE_MODE=false/' .env

# Restart watcher
docker compose restart alert_watcher
```

**When to Use:**
- Planned pool toggles for deployments
- Testing failover scenarios
- Maintenance windows
- Load testing that may trigger false positives

**Important:** Always disable maintenance mode after planned work is complete!

---

## 🛠️ Troubleshooting Commands

### View Real-Time Logs

```bash
# Watcher logs
docker logs -f alert_watcher

# Nginx access logs (structured)
docker exec nginx_proxy tail -f /var/log/nginx/access.log

# Nginx error logs
docker exec nginx_proxy tail -f /var/log/nginx/error.log

# Application logs
docker logs -f app_blue
docker logs -f app_green
```

### Test Slack Integration

```bash
# Check if webhook is configured
docker exec alert_watcher env | grep SLACK_WEBHOOK_URL

# Force a test alert (manually trigger failover)
docker compose stop app_blue
sleep 5
curl http://localhost:8080/version
docker compose start app_blue
```

### Verify Log Format

```bash
# Check that logs contain required fields
docker exec nginx_proxy tail -n 1 /var/log/nginx/access.log | grep -o "pool=\S*"
docker exec nginx_proxy tail -n 1 /var/log/nginx/access.log | grep -o "release=\S*"
docker exec nginx_proxy tail -n 1 /var/log/nginx/access.log | grep -o "upstream_status=\S*"
```

### Check Watcher Health

```bash
# Verify watcher container is running
docker ps | grep alert_watcher

# Check for errors in watcher
docker logs alert_watcher | grep -i error

# Verify watcher can read logs
docker exec alert_watcher ls -la /var/log/nginx/access.log
```

### Reset Alert State

```bash
# Restart watcher to clear cooldown timers
docker compose restart alert_watcher
```

---

## 📊 Monitoring Best Practices

1. **Regular Health Checks**
   - Run `docker ps` daily to verify all containers are up
   - Review logs weekly for patterns

2. **Alert Tuning**
   - Adjust `ERROR_RATE_THRESHOLD` if too sensitive/insensitive
   - Increase `WINDOW_SIZE` for more stable error rate calculations
   - Adjust `ALERT_COOLDOWN_SEC` to balance notification frequency

3. **Capacity Planning**
   - Monitor resource usage trends
   - Plan scaling before reaching limits

4. **Documentation**
   - Keep this runbook updated with lessons learned
   - Document recurring issues and permanent fixes

---

## 🆘 Emergency Contacts

| Role | Contact | When to Escalate |
|------|---------|------------------|
| On-Call Engineer | [Your Contact] | Immediate issues, both pools down |
| DevOps Lead | [Your Contact] | Infrastructure problems, repeated alerts |
| Application Team | [Your Contact] | Application errors, bug fixes needed |
| Platform Team | [Your Contact] | Docker/networking issues |

---

## 📚 Additional Resources

- [Nginx Upstream Documentation](http://nginx.org/en/docs/http/ngx_http_upstream_module.html)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Slack Incoming Webhooks](https://api.slack.com/messaging/webhooks)
- Project README: `README.md`
- Configuration Examples: `.env.example`

---

**Last Updated:** October 31, 2025  
**Version:** 1.0.0  
**Maintained By:** DevOps Team
