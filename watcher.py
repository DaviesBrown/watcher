#!/usr/bin/env python3
"""
Nginx Log Watcher for Blue/Green Deployment Monitoring
Monitors Nginx access logs in real-time and sends Slack alerts for:
  - Failover events (pool transitions)
  - High upstream error rates (5xx responses)
"""

import os
import sys
import time
import json
import re
from collections import deque
from datetime import datetime
from typing import Optional, Dict, Any
import requests


class LogWatcher:
    """Monitors Nginx logs and sends alerts to Slack"""

    def __init__(self):
        # Configuration from environment variables
        self.slack_webhook_url = os.getenv('SLACK_WEBHOOK_URL')
        self.error_rate_threshold = float(
            os.getenv('ERROR_RATE_THRESHOLD', '2'))
        self.window_size = int(os.getenv('WINDOW_SIZE', '200'))
        self.alert_cooldown_sec = int(os.getenv('ALERT_COOLDOWN_SEC', '300'))
        self.maintenance_mode = os.getenv(
            'MAINTENANCE_MODE', 'false').lower() == 'true'
        self.initial_active_pool = os.getenv('ACTIVE_POOL', 'blue')

        # State tracking
        self.last_seen_pool: Optional[str] = None
        self.request_window = deque(maxlen=self.window_size)
        self.last_alert_times: Dict[str, float] = {}

        # Log file path
        self.log_file_path = '/var/log/nginx/access.log'

        # Validate configuration
        if not self.slack_webhook_url or self.slack_webhook_url == 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL':
            print("⚠️  WARNING: SLACK_WEBHOOK_URL is not configured properly.")
            print("   Alerts will be logged to console only.")
            self.slack_webhook_url = None

        print("🔍 Log Watcher initialized with configuration:")
        print(f"   - Error Rate Threshold: {self.error_rate_threshold}%")
        print(f"   - Window Size: {self.window_size} requests")
        print(f"   - Alert Cooldown: {self.alert_cooldown_sec}s")
        print(f"   - Maintenance Mode: {self.maintenance_mode}")
        print(f"   - Initial Active Pool: {self.initial_active_pool}")
        print(
            f"   - Slack Alerts: {'Enabled' if self.slack_webhook_url else 'Disabled (console only)'}")

    def parse_log_line(self, line: str) -> Optional[Dict[str, Any]]:
        """Parse a single Nginx log line and extract relevant fields"""
        try:
            # Extract pool (handles pool=value or pool=-)
            pool_match = re.search(r'pool=(\S+)', line)
            pool = pool_match.group(
                1) if pool_match and pool_match.group(1) != '-' else None

            # Extract release ID
            release_match = re.search(r'release=(\S+)', line)
            release = release_match.group(
                1) if release_match and release_match.group(1) != '-' else None

            # Extract upstream status (may be comma-separated for retries)
            upstream_status_match = re.search(r'upstream_status=(\S+)', line)
            upstream_status_raw = upstream_status_match.group(
                1) if upstream_status_match else None

            # Handle comma-separated upstream statuses (failover/retry scenarios)
            upstream_statuses = []
            if upstream_status_raw and upstream_status_raw != '-':
                upstream_statuses = upstream_status_raw.split(',')

            # Extract final response status
            status_match = re.search(r'"[^"]*" (\d{3})', line)
            final_status = int(status_match.group(1)) if status_match else None

            # Extract upstream address
            upstream_match = re.search(r'upstream=(\S+)', line)
            upstream = upstream_match.group(1) if upstream_match else None

            # Extract request time
            request_time_match = re.search(r'request_time=([\d.]+)', line)
            request_time = float(request_time_match.group(
                1)) if request_time_match else None

            # Extract upstream response time
            upstream_time_match = re.search(
                r'upstream_response_time=([\d.,\s]+)', line)
            upstream_response_time = upstream_time_match.group(
                1) if upstream_time_match else None

            return {
                'pool': pool,
                'release': release,
                'upstream_statuses': upstream_statuses,
                'final_status': final_status,
                'upstream': upstream,
                'request_time': request_time,
                'upstream_response_time': upstream_response_time,
                'raw_line': line.strip()
            }
        except Exception as e:
            print(f"⚠️  Failed to parse log line: {e}")
            return None

    def check_failover(self, pool: str) -> bool:
        """Detect if a failover event occurred"""
        if self.last_seen_pool is None:
            # First request - set baseline
            self.last_seen_pool = pool
            print(f"📊 Baseline pool established: {pool}")
            return False

        if pool != self.last_seen_pool:
            # Failover detected!
            old_pool = self.last_seen_pool
            self.last_seen_pool = pool

            if not self.maintenance_mode:
                self.send_failover_alert(old_pool, pool)
            else:
                print(
                    f"🔇 Failover detected ({old_pool} → {pool}) but suppressed (maintenance mode)")

            return True

        return False

    def check_error_rate(self, parsed: Dict[str, Any]):
        """Monitor error rate in sliding window"""
        # Determine if this request had upstream errors
        has_5xx_error = False

        # Check upstream statuses for 5xx errors
        for status in parsed['upstream_statuses']:
            try:
                status_code = int(status)
                if 500 <= status_code < 600:
                    has_5xx_error = True
                    break
            except (ValueError, TypeError):
                continue

        # Also check final status
        if parsed['final_status'] and 500 <= parsed['final_status'] < 600:
            has_5xx_error = True

        # Add to sliding window
        self.request_window.append(has_5xx_error)

        # Calculate error rate if window is full enough (at least 10% full)
        min_requests = max(10, self.window_size // 10)
        if len(self.request_window) >= min_requests:
            error_count = sum(self.request_window)
            total_count = len(self.request_window)
            error_rate = (error_count / total_count) * 100

            if error_rate > self.error_rate_threshold:
                if not self.maintenance_mode and self.can_send_alert('error_rate'):
                    self.send_error_rate_alert(
                        error_rate, error_count, total_count)

    def can_send_alert(self, alert_type: str) -> bool:
        """Check if we can send an alert (respects cooldown)"""
        current_time = time.time()
        last_alert_time = self.last_alert_times.get(alert_type, 0)

        if current_time - last_alert_time >= self.alert_cooldown_sec:
            self.last_alert_times[alert_type] = current_time
            return True

        return False

    def send_slack_alert(self, message: str, color: str = "danger", fields: list = None):
        """Send an alert to Slack"""
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

        # Console output
        print(f"\n🚨 ALERT at {timestamp}")
        print(f"   {message}")
        if fields:
            for field in fields:
                print(f"   - {field['title']}: {field['value']}")
        print()

        # Send to Slack if configured
        if not self.slack_webhook_url:
            return

        payload = {
            "attachments": [
                {
                    "color": color,
                    "title": "🚨 Blue/Green Deployment Alert",
                    "text": message,
                    "fields": fields or [],
                    "footer": "Nginx Log Watcher",
                    "ts": int(time.time())
                }
            ]
        }

        try:
            response = requests.post(
                self.slack_webhook_url,
                json=payload,
                timeout=10
            )
            if response.status_code == 200:
                print(f"✅ Alert sent to Slack successfully")
            else:
                print(
                    f"⚠️  Slack API returned status {response.status_code}: {response.text}")
        except Exception as e:
            print(f"❌ Failed to send Slack alert: {e}")

    def send_failover_alert(self, old_pool: str, new_pool: str):
        """Send alert for failover event"""
        message = f"🔄 **Failover Detected**: Traffic switched from `{old_pool}` to `{new_pool}`"

        fields = [
            {
                "title": "Previous Pool",
                "value": old_pool.upper(),
                "short": True
            },
            {
                "title": "Current Pool",
                "value": new_pool.upper(),
                "short": True
            },
            {
                "title": "Action Required",
                "value": f"Check health of `{old_pool}` container and investigate root cause",
                "short": False
            }
        ]

        self.send_slack_alert(message, color="warning", fields=fields)
        self.last_alert_times['failover'] = time.time()

    def send_error_rate_alert(self, error_rate: float, error_count: int, total_count: int):
        """Send alert for high error rate"""
        message = f"⚠️ **High Error Rate Detected**: {error_rate:.2f}% of requests returning 5xx errors"

        fields = [
            {
                "title": "Error Rate",
                "value": f"{error_rate:.2f}%",
                "short": True
            },
            {
                "title": "Threshold",
                "value": f"{self.error_rate_threshold}%",
                "short": True
            },
            {
                "title": "Window",
                "value": f"{error_count} errors in {total_count} requests",
                "short": False
            },
            {
                "title": "Current Pool",
                "value": self.last_seen_pool.upper() if self.last_seen_pool else "Unknown",
                "short": True
            },
            {
                "title": "Action Required",
                "value": "Inspect upstream logs and consider toggling pools",
                "short": False
            }
        ]

        self.send_slack_alert(message, color="danger", fields=fields)

    def send_recovery_alert(self):
        """Send alert when primary pool recovers"""
        if self.last_seen_pool == self.initial_active_pool:
            message = f"✅ **Recovery Detected**: Primary pool `{self.initial_active_pool}` is serving traffic again"

            fields = [
                {
                    "title": "Current Pool",
                    "value": self.last_seen_pool.upper(),
                    "short": True
                },
                {
                    "title": "Status",
                    "value": "Normal Operations Resumed",
                    "short": True
                }
            ]

            if self.can_send_alert('recovery'):
                self.send_slack_alert(message, color="good", fields=fields)

    def tail_log_file(self):
        """Tail the Nginx access log file and process new lines"""
        print(f"📂 Monitoring log file: {self.log_file_path}")

        # Wait for log file to exist
        while not os.path.exists(self.log_file_path):
            print(f"⏳ Waiting for log file to be created...")
            time.sleep(2)

        print("✅ Log file found. Starting to monitor...")
        
        # Start from end of existing logs
        try:
            with open(self.log_file_path, 'r') as f:
                # Move to end to get initial position
                f.read()
        except Exception as e:
            print(f"⚠️  Note: {e}")
        
        # Use subprocess to tail the file (more reliable in Docker volumes)
        import subprocess
        
        try:
            # Use tail -F which handles file rotation and follows by name
            proc = subprocess.Popen(
                ['tail', '-F', '-n', '0', self.log_file_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                universal_newlines=True,
                bufsize=1
            )
            
            print("📡 Monitoring started. Waiting for new log entries...")
            
            for line in iter(proc.stdout.readline, ''):
                if not line:
                    time.sleep(0.1)
                    continue
                
                # Process the log line
                parsed = self.parse_log_line(line)
                
                if parsed and parsed['pool']:
                    # Check for failover
                    self.check_failover(parsed['pool'])
                    
                    # Check error rate
                    self.check_error_rate(parsed)
                    
        except KeyboardInterrupt:
            if proc:
                proc.terminate()
            raise
        except Exception as e:
            print(f"❌ Error in tail process: {e}")
            if proc:
                proc.terminate()
            raise

    def run(self):
        """Main entry point"""
        print("=" * 60)
        print("🚀 Nginx Log Watcher Starting...")
        print("=" * 60)

        try:
            self.tail_log_file()
        except KeyboardInterrupt:
            print("\n⏹️  Shutting down gracefully...")
            sys.exit(0)
        except Exception as e:
            print(f"\n❌ Fatal error: {e}")
            import traceback
            traceback.print_exc()
            sys.exit(1)


if __name__ == '__main__':
    watcher = LogWatcher()
    watcher.run()
