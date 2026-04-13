#!/usr/bin/env bash
#
# scripts/install-server.sh — non-Docker server installer for Ubuntu 24.04 LTS.
#
# Installs nginx + mariadb-server + php-fpm, creates a database and user for
# Zegel, writes an nginx site config, and runs the Laravel install wizard in
# headless mode. Safe to re-run: every step is idempotent.
#
# Usage: sudo scripts/install-server.sh [DOMAIN] [DB_PASSWORD]
set -euo pipefail

DOMAIN="${1:-zegel.local}"
DB_NAME="zegel"
DB_USER="zegel"
DB_PASS="${2:-$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)}"
APP_DIR="/var/www/zegel"

if [[ $EUID -ne 0 ]]; then
  echo "[x] This script must be run as root (use sudo)." >&2
  exit 1
fi

echo "[*] Installing packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y install nginx mariadb-server mariadb-client \
  php8.4-cli php8.4-fpm php8.4-mysql php8.4-sqlite3 php8.4-mbstring php8.4-xml php8.4-zip php8.4-curl php8.4-gd php8.4-intl php8.4-bcmath \
  git unzip curl composer

echo "[*] Starting services..."
systemctl enable --now mariadb
systemctl enable --now php8.4-fpm
systemctl enable --now nginx

echo "[*] Provisioning database..."
mariadb -uroot <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

if [[ ! -d "${APP_DIR}" ]]; then
  echo "[*] Cloning Zegel into ${APP_DIR}..."
  mkdir -p "$(dirname "${APP_DIR}")"
  git clone https://github.com/jw-1980/zegel.git "${APP_DIR}"
fi

cd "${APP_DIR}/website"
echo "[*] Installing Composer dependencies..."
sudo -u www-data composer install --no-interaction --no-dev --prefer-dist

if [[ ! -f .env ]]; then
  cp .env.example .env
  php artisan key:generate --force
fi

php -r "
  \$env = file_get_contents('.env');
  \$env = preg_replace('/^DB_CONNECTION=.*/m', 'DB_CONNECTION=mysql', \$env);
  \$env = preg_replace('/^#?\\s*DB_HOST=.*/m', 'DB_HOST=127.0.0.1', \$env);
  \$env = preg_replace('/^#?\\s*DB_PORT=.*/m', 'DB_PORT=3306', \$env);
  \$env = preg_replace('/^#?\\s*DB_DATABASE=.*/m', 'DB_DATABASE=${DB_NAME}', \$env);
  \$env = preg_replace('/^#?\\s*DB_USERNAME=.*/m', 'DB_USERNAME=${DB_USER}', \$env);
  \$env = preg_replace('/^#?\\s*DB_PASSWORD=.*/m', 'DB_PASSWORD=${DB_PASS}', \$env);
  \$env = preg_replace('/^APP_URL=.*/m', 'APP_URL=https://${DOMAIN}', \$env);
  \$env = preg_replace('/^APP_ENV=.*/m', 'APP_ENV=production', \$env);
  \$env = preg_replace('/^APP_DEBUG=.*/m', 'APP_DEBUG=false', \$env);
  file_put_contents('.env', \$env);
"

chown -R www-data:www-data "${APP_DIR}"
find "${APP_DIR}" -type d -exec chmod 755 {} \;
find "${APP_DIR}" -type f -exec chmod 644 {} \;

sudo -u www-data php artisan migrate --force
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
sudo -u www-data php artisan view:cache

echo "[*] Writing nginx site config..."
cat >/etc/nginx/sites-available/zegel <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    root ${APP_DIR}/website/public;
    index index.php;

    charset utf-8;
    client_max_body_size 50M;

    add_header X-Frame-Options "DENY";
    add_header X-Content-Type-Options "nosniff";
    add_header Referrer-Policy "strict-origin-when-cross-origin";

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_pass unix:/run/php/php8.4-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known) {
        deny all;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/zegel /etc/nginx/sites-enabled/zegel
nginx -t
systemctl reload nginx

echo
echo "=========================================================="
echo " Zegel is installed at https://${DOMAIN}"
echo " Database name:    ${DB_NAME}"
echo " Database user:    ${DB_USER}"
echo " Database password: ${DB_PASS}"
echo " App directory:    ${APP_DIR}"
echo "=========================================================="
echo " Next steps:"
echo "  1. Point your DNS A record to this server."
echo "  2. Run: sudo certbot --nginx -d ${DOMAIN}"
echo "  3. Visit https://${DOMAIN}/install to finish the wizard."
echo "=========================================================="
