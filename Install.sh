#!/bin/bash

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
    echo "Script này cần được chạy với quyền root!" 
    exit 1
fi

# Kiểm tra xem domain đã trỏ về VPS chưa
check_domain() {
    local domain=$1
    local server_ip=$(curl -s https://api.ipify.org)
    local domain_ip=$(dig +short $domain)

    if [ "$domain_ip" = "$server_ip" ]; then
        return 0  # Domain đã trỏ đúng
    else
        return 1  # Domain chưa trỏ đúng
    fi
}

# Nhận domain từ người dùng
read -p "Nhập domain hoặc subdomain của bạn (đã trỏ về VPS): " DOMAIN

# Kiểm tra domain
if check_domain $DOMAIN; then
    echo "Domain $DOMAIN đã trỏ đúng về VPS. Tiếp tục cài đặt..."
else
    echo "Domain $DOMAIN chưa trỏ đúng về VPS. Vui lòng kiểm tra DNS!"
    exit 1
fi

# Thư mục chính để lưu trữ các dịch vụ
BASE_DIR="/opt/services"
N8N_DIR="$BASE_DIR/n8n"
WIREGUARD_DIR="$BASE_DIR/wireguard"
NGINX_DIR="$BASE_DIR/nginx"

# Cài đặt Docker và Docker Compose
echo "Cài đặt Docker và Docker Compose..."
apt update && apt upgrade -y
apt install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt update
apt install -y docker-ce docker-compose

# Tạo các thư mục cho dịch vụ
echo "Tạo thư mục cho các dịch vụ..."
mkdir -p $N8N_DIR $WIREGUARD_DIR $NGINX_DIR
chown -R $USER:$USER $BASE_DIR

# Cấu hình N8n
echo "Cấu hình dịch vụ n8n..."
cat << EOF > $N8N_DIR/docker-compose.yml
version: "3.8"
services:
  n8n:
    image: n8nio/n8n
    container_name: n8n
    restart: unless-stopped
    environment:
      - N8N_HOST=${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${DOMAIN}
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
    volumes:
      - ./data:/home/node/.n8n
    expose:
      - 5678
EOF

# Cấu hình WireGuard
echo "Cấu hình dịch vụ WireGuard..."
cat << EOF > $WIREGUARD_DIR/docker-compose.yml
version: "3.8"
services:
  wireguard:
    image: linuxserver/wireguard
    container_name: wireguard
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Ho_Chi_Minh
      - SERVERURL=${DOMAIN}
      - SERVERPORT=51820
      - PEERS=5
    ports:
      - "51820:51820/udp"
    volumes:
      - ./config:/config
    restart: unless-stopped
EOF

# Cấu hình Nginx
echo "Cấu hình dịch vụ Nginx..."
cat << EOF > $NGINX_DIR/docker-compose.yml
version: "3.8"
services:
  nginx:
    image: nginx:latest
    container_name: nginx
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./certs:/etc/ssl/certs
      - ./logs:/var/log/nginx
    restart: unless-stopped
EOF

cat << EOF > $NGINX_DIR/nginx.conf
events {}

http {
    server {
        listen 80;
        server_name ${DOMAIN};

        location / {
            proxy_pass http://n8n:5678;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        location /wireguard {
            proxy_pass http://wireguard:51820;
            proxy_set_header Host \$host;
        }
    }
}
EOF

# Khởi động các dịch vụ
echo "Khởi động tất cả dịch vụ..."
cd $N8N_DIR && docker-compose up -d
cd $WIREGUARD_DIR && docker-compose up -d
cd $NGINX_DIR && docker-compose up -d

# Thêm alias để cập nhật nhanh các dịch vụ
echo "Thêm alias để cập nhật nhanh các dịch vụ..."
cat << EOF >> ~/.bashrc
# Alias để cập nhật nhanh các dịch vụ
alias update-n8n='cd $N8N_DIR && docker-compose down && docker-compose pull && docker-compose up -d'
alias update-wireguard='cd $WIREGUARD_DIR && docker-compose down && docker-compose pull && docker-compose up -d'
alias update-nginx='cd $NGINX_DIR && docker-compose down && docker-compose pull && docker-compose up -d'
alias update-all='update-n8n && update-wireguard && update-nginx'
EOF

# Nạp lại ~/.bashrc
source ~/.bashrc

# Thông báo hoàn tất
echo "Các alias sau đã được tạo:"
echo " - update-n8n: Cập nhật dịch vụ n8n"
echo " - update-wireguard: Cập nhật dịch vụ WireGuard"
echo " - update-nginx: Cập nhật dịch vụ Nginx"
echo " - update-all: Cập nhật tất cả dịch vụ"

# Hoàn tất
echo "Cài đặt hoàn tất!"
echo "Dịch vụ n8n: https://${DOMAIN}"
echo "WireGuard có thể cấu hình qua file tại ${WIREGUARD_DIR}/config"
