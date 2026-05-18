#!/usr/bin/env bash
# setup-https.sh — Installs nginx + Let's Encrypt TLS for the Kong API Gateway.
#
# Target: AWS EC2 Ubuntu 22.04 LTS
# Domain: cloud-computing-uni.duckdns.org → Kong on 127.0.0.1:8000
#
# Idempotent: safe to re-run. Certbot skips renewal if cert is already valid.
#
# Usage (run as root or with sudo):
#   sudo bash setup-https.sh

set -euo pipefail

DOMAIN="cloud-computing-uni.duckdns.org"
EMAIL="carlo.invernizzi@studenti.unimi.it"
KONG_UPSTREAM="http://127.0.0.1:8000"
NGINX_CONF="/etc/nginx/sites-available/cloud-computing"

# ---------------------------------------------------------------------------
# 0. Root check
# ---------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "Re-running with sudo..."
  exec sudo bash "$0" "$@"
fi

echo "==> [1/7] Installing nginx + certbot..."
apt-get update -qq
apt-get install -y -qq nginx certbot python3-certbot-nginx

# ---------------------------------------------------------------------------
# 1. Firewall — open ports 80 and 443 if ufw is active
# ---------------------------------------------------------------------------
echo "==> [2/7] Configuring firewall..."
if ufw status | grep -q "Status: active"; then
  ufw allow 80/tcp
  ufw allow 443/tcp
  echo "    ufw: opened 80 and 443"
else
  echo "    ufw inactive — skipping (check AWS Security Group instead)"
fi

# ---------------------------------------------------------------------------
# 2. nginx virtual host
# ---------------------------------------------------------------------------
echo "==> [3/7] Writing nginx config..."
cat > "$NGINX_CONF" <<'NGINX'
server {
    listen 80;
    server_name cloud-computing-uni.duckdns.org;

    # Let certbot manage the ACME challenge and the HTTPS redirect.
    # certbot --nginx will replace this block on first run.

    client_max_body_size 10M;

    location / {
        proxy_pass          http://127.0.0.1:8000;
        proxy_http_version  1.1;
        proxy_set_header    Host              $host;
        proxy_set_header    X-Real-IP         $remote_addr;
        proxy_set_header    X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header    X-Forwarded-Proto $scheme;
        proxy_set_header    Connection        "";
        proxy_read_timeout  60s;
        proxy_send_timeout  60s;
    }
}
NGINX

# Enable site, remove default if still linked
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/cloud-computing
if [[ -L /etc/nginx/sites-enabled/default ]]; then
  rm /etc/nginx/sites-enabled/default
  echo "    Removed sites-enabled/default"
fi

# ---------------------------------------------------------------------------
# 3. Test and reload nginx
# ---------------------------------------------------------------------------
echo "==> [4/7] Testing nginx config..."
nginx -t

echo "==> [5/7] Reloading nginx..."
systemctl enable nginx --quiet
systemctl reload nginx

# ---------------------------------------------------------------------------
# 4. Obtain / renew Let's Encrypt certificate
# ---------------------------------------------------------------------------
echo "==> [6/7] Running certbot..."
certbot --nginx \
  -d "$DOMAIN" \
  --non-interactive \
  --agree-tos \
  --email "$EMAIL" \
  --redirect \
  --keep-until-expiring

# certbot --redirect rewrites the nginx config to add the 443 block and a
# 301 redirect from port 80. Reload to apply those changes.
echo "==> [7/7] Reloading nginx with TLS config..."
systemctl reload nginx

# ---------------------------------------------------------------------------
# 5. Ensure auto-renewal cron/timer is active
# ---------------------------------------------------------------------------
if systemctl list-timers | grep -q certbot; then
  echo "    certbot systemd timer already active"
elif crontab -l 2>/dev/null | grep -q certbot; then
  echo "    certbot cron already present"
else
  (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet && systemctl reload nginx") | crontab -
  echo "    Added certbot renewal cron (daily at 03:00)"
fi

echo ""
echo "✅ HTTPS attivo su https://${DOMAIN}"
echo "   Kong proxy: ${KONG_UPSTREAM}"
echo "   Cert:       $(certbot certificates 2>/dev/null | grep 'Expiry Date' | head -1 | xargs)"
