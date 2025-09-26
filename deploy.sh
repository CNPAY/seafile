#!/bin/bash

# =============================================================================
# Seafile 13 群晖一键部署脚本
# 适用于群晖 NAS + FRP 内网穿透 + Docker 环境
# 作者: Assistant
# 版本: 1.0
# =============================================================================

set -e  # 遇到错误立即退出

# 颜色输出函数
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }

# 脚本标题
echo -e "${BLUE}"
echo "=================================================="
echo "       Seafile 13 群晖一键部署脚本"
echo "         群晖 + FRP + Docker 环境"
echo "=================================================="
echo -e "${NC}"

# 检查运行环境
print_info "检查运行环境..."

# 检查是否为root用户或有sudo权限
if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
    print_warning "建议使用root用户或sudo权限运行此脚本"
    read -p "是否继续? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 检查Docker是否安装
if ! command -v docker &> /dev/null; then
    print_error "未检测到Docker，请先安装Docker"
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    print_error "未检测到docker-compose，请先安装docker-compose"
    exit 1
fi

print_success "环境检查通过"

# 设置项目根目录
PROJECT_ROOT="/volume1/docker/seafile"

print_info "项目将部署到: $PROJECT_ROOT"

# 询问用户确认
read -p "确认继续部署? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "部署已取消"
    exit 0
fi

# 创建项目目录结构
print_info "创建项目目录结构..."

# 创建主项目目录
mkdir -p "${PROJECT_ROOT}"

# 创建数据目录
mkdir -p "${PROJECT_ROOT}/seafile-data"     # Seafile 主数据目录
mkdir -p "${PROJECT_ROOT}/mysql-data"       # MySQL 数据库文件
mkdir -p "${PROJECT_ROOT}/redis-data"       # Redis 数据持久化
mkdir -p "${PROJECT_ROOT}/logs"             # 日志目录
mkdir -p "${PROJECT_ROOT}/config"           # 配置文件目录
mkdir -p "${PROJECT_ROOT}/backups"          # 备份目录

print_success "目录结构创建完成"

# 设置目录权限
print_info "设置目录权限..."
if [[ $EUID -eq 0 ]]; then
    chown -R 1000:1000 "${PROJECT_ROOT}/seafile-data" 2>/dev/null || true
    chown -R 999:999 "${PROJECT_ROOT}/mysql-data" 2>/dev/null || true
    chown -R 999:999 "${PROJECT_ROOT}/redis-data" 2>/dev/null || true
    print_success "权限设置完成"
else
    print_warning "非root用户，跳过权限设置"
fi

# 生成随机密码函数
generate_password() {
    openssl rand -base64 12 | tr -d "=+/" | cut -c1-12
}

# 生成JWT密钥
print_info "生成安全密钥..."
JWT_KEY=$(openssl rand -hex 32)
MYSQL_ROOT_PASSWORD=$(generate_password)
SEAFILE_DB_PASSWORD=$(generate_password)
REDIS_PASSWORD=$(generate_password)
ADMIN_PASSWORD=$(generate_password)

print_success "密钥生成完成"

# 获取用户输入
print_info "配置基础信息..."

# 域名配置
read -p "请输入您的域名 (默认: yunpan.org): " DOMAIN
DOMAIN=${DOMAIN:-yunpan.org}

# 管理员邮箱
read -p "请输入管理员邮箱 (默认: admin@${DOMAIN}): " ADMIN_EMAIL
ADMIN_EMAIL=${ADMIN_EMAIL:-admin@${DOMAIN}}

# 端口配置
read -p "请输入服务端口 (默认: 8000): " PORT
PORT=${PORT:-8000}

# 协议选择
read -p "使用HTTPS协议? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    PROTOCOL="http"
else
    PROTOCOL="https"
fi

# 创建 .env 文件
print_info "创建环境配置文件..."
cat > "${PROJECT_ROOT}/.env" << EOF
# =============================================================================
# Seafile 13 环境配置文件
# 群晖 + FRP 内网穿透配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# =============================================================================

# === 基础配置 ===
SEAFILE_SERVER_HOSTNAME=${DOMAIN}
SEAFILE_SERVER_PROTOCOL=${PROTOCOL}
SEAFILE_PORT=${PORT}
TIME_ZONE=Asia/Shanghai

# === 管理员账户 ===
INIT_SEAFILE_ADMIN_EMAIL=${ADMIN_EMAIL}
INIT_SEAFILE_ADMIN_PASSWORD=${ADMIN_PASSWORD}

# === 数据库配置 ===
SEAFILE_DB_IMAGE=mariadb:10.11
INIT_SEAFILE_MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
SEAFILE_MYSQL_DB_USER=seafile
SEAFILE_MYSQL_DB_PASSWORD=${SEAFILE_DB_PASSWORD}
SEAFILE_MYSQL_DB_HOST=db
SEAFILE_MYSQL_DB_PORT=3306
SEAFILE_MYSQL_DB_CCNET_DB_NAME=ccnet_db
SEAFILE_MYSQL_DB_SEAFILE_DB_NAME=seafile_db
SEAFILE_MYSQL_DB_SEAHUB_DB_NAME=seahub_db

# === Redis 配置 ===
SEAFILE_REDIS_IMAGE=redis:7-alpine
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_HOST=redis
REDIS_PORT=6379

# === 存储路径（统一在seafile目录下）===
SEAFILE_VOLUME=${PROJECT_ROOT}/seafile-data
SEAFILE_MYSQL_VOLUME=${PROJECT_ROOT}/mysql-data
SEAFILE_REDIS_VOLUME=${PROJECT_ROOT}/redis-data

# === Seafile 镜像 ===
SEAFILE_IMAGE=seafileltd/seafile-mc:13.0-latest

# === JWT 密钥（已自动生成 - 请勿修改）===
JWT_PRIVATE_KEY=${JWT_KEY}

# === 功能配置 ===
ENABLE_SEADOC=true
SEAFILE_LOG_TO_STDOUT=true
CACHE_PROVIDER=redis
ENABLE_NOTIFICATION_SERVER=false
ENABLE_SEAFILE_AI=false
SITE_ROOT=/
NON_ROOT=false
MD_FILE_COUNT_LIMIT=100000

# === 内存缓存（可选）===
MEMCACHED_HOST=memcached
MEMCACHED_PORT=11211
EOF

print_success "环境配置文件创建完成"

# 创建 docker-compose.yml 文件
print_info "创建Docker编排文件..."
cat > "${PROJECT_ROOT}/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  db:
    image: ${SEAFILE_DB_IMAGE:-mariadb:10.11}
    container_name: seafile-mysql
    restart: unless-stopped
    environment:
      - MYSQL_ROOT_PASSWORD=${INIT_SEAFILE_MYSQL_ROOT_PASSWORD}
      - MYSQL_LOG_CONSOLE=true
      - MARIADB_AUTO_UPGRADE=1
    volumes:
      - "${SEAFILE_MYSQL_VOLUME}:/var/lib/mysql"
    networks:
      - seafile-net
    healthcheck:
      test:
        [
          "CMD",
          "/usr/local/bin/healthcheck.sh",
          "--connect",
          "--mariadbupgrade",
          "--innodb_initialized",
        ]
      interval: 20s
      start_period: 30s
      timeout: 5s
      retries: 10

  redis:
    image: ${SEAFILE_REDIS_IMAGE:-redis:7-alpine}
    container_name: seafile-redis
    restart: unless-stopped
    command:
      - /bin/sh
      - -c
      - redis-server --requirepass "$$REDIS_PASSWORD"
    environment:
      - REDIS_PASSWORD=${REDIS_PASSWORD}
    volumes:
      - "${SEAFILE_REDIS_VOLUME}:/data"
    networks:
      - seafile-net
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 30s
      timeout: 3s
      retries: 3

  seafile:
    image: ${SEAFILE_IMAGE:-seafileltd/seafile-mc:13.0-latest}
    container_name: seafile
    restart: unless-stopped
    ports:
      - "${SEAFILE_PORT:-8000}:80"
    volumes:
      - ${SEAFILE_VOLUME}:/shared
    environment:
      - SEAFILE_MYSQL_DB_HOST=${SEAFILE_MYSQL_DB_HOST:-db}
      - SEAFILE_MYSQL_DB_PORT=${SEAFILE_MYSQL_DB_PORT:-3306}
      - SEAFILE_MYSQL_DB_USER=${SEAFILE_MYSQL_DB_USER:-seafile}
      - SEAFILE_MYSQL_DB_PASSWORD=${SEAFILE_MYSQL_DB_PASSWORD}
      - INIT_SEAFILE_MYSQL_ROOT_PASSWORD=${INIT_SEAFILE_MYSQL_ROOT_PASSWORD}
      - SEAFILE_MYSQL_DB_CCNET_DB_NAME=${SEAFILE_MYSQL_DB_CCNET_DB_NAME:-ccnet_db}
      - SEAFILE_MYSQL_DB_SEAFILE_DB_NAME=${SEAFILE_MYSQL_DB_SEAFILE_DB_NAME:-seafile_db}
      - SEAFILE_MYSQL_DB_SEAHUB_DB_NAME=${SEAFILE_MYSQL_DB_SEAHUB_DB_NAME:-seahub_db}
      - TIME_ZONE=${TIME_ZONE:-Asia/Shanghai}
      - INIT_SEAFILE_ADMIN_EMAIL=${INIT_SEAFILE_ADMIN_EMAIL}
      - INIT_SEAFILE_ADMIN_PASSWORD=${INIT_SEAFILE_ADMIN_PASSWORD}
      - SEAFILE_SERVER_HOSTNAME=${SEAFILE_SERVER_HOSTNAME}
      - SEAFILE_SERVER_PROTOCOL=${SEAFILE_SERVER_PROTOCOL:-https}
      - SITE_ROOT=${SITE_ROOT:-/}
      - NON_ROOT=${NON_ROOT:-false}
      - JWT_PRIVATE_KEY=${JWT_PRIVATE_KEY}
      - SEAFILE_LOG_TO_STDOUT=${SEAFILE_LOG_TO_STDOUT:-true}
      - ENABLE_SEADOC=${ENABLE_SEADOC:-true}
      - SEADOC_SERVER_URL=${SEAFILE_SERVER_PROTOCOL}://${SEAFILE_SERVER_HOSTNAME}/sdoc-server
      - CACHE_PROVIDER=${CACHE_PROVIDER:-redis}
      - REDIS_HOST=${REDIS_HOST:-redis}
      - REDIS_PORT=${REDIS_PORT:-6379}
      - REDIS_PASSWORD=${REDIS_PASSWORD}
      - MEMCACHED_HOST=${MEMCACHED_HOST:-memcached}
      - MEMCACHED_PORT=${MEMCACHED_PORT:-11211}
      - ENABLE_NOTIFICATION_SERVER=${ENABLE_NOTIFICATION_SERVER:-false}
      - INNER_NOTIFICATION_SERVER_URL=${INNER_NOTIFICATION_SERVER_URL:-http://notification-server:8083}
      - NOTIFICATION_SERVER_URL=${NOTIFICATION_SERVER_URL:-${SEAFILE_SERVER_PROTOCOL}://${SEAFILE_SERVER_HOSTNAME}/notification}
      - ENABLE_SEAFILE_AI=${ENABLE_SEAFILE_AI:-false}
      - SEAFILE_AI_SERVER_URL=${SEAFILE_AI_SERVER_URL:-http://seafile-ai:8888}
      - SEAFILE_AI_SECRET_KEY=${JWT_PRIVATE_KEY}
      - MD_FILE_COUNT_LIMIT=${MD_FILE_COUNT_LIMIT:-100000}
      - FORCE_HTTPS_IN_CONF=true
      - SECURE_PROXY_SSL_HEADER=HTTP_X_FORWARDED_PROTO,https
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    networks:
      - seafile-net

networks:
  seafile-net:
    name: seafile-net
    driver: bridge
EOF

print_success "Docker编排文件创建完成"

# 创建管理脚本
print_info "创建管理脚本..."

# 启动脚本
cat > "${PROJECT_ROOT}/start.sh" << 'EOF'
#!/bin/bash
cd /volume1/docker/seafile
echo "🚀 启动 Seafile 服务..."
docker-compose up -d
echo ""
echo "📊 查看服务状态..."
docker-compose ps
echo ""
echo "🌐 服务地址:"
source .env
echo "  内网访问: http://192.168.50.95:${SEAFILE_PORT}"
echo "  外网访问: ${SEAFILE_SERVER_PROTOCOL}://${SEAFILE_SERVER_HOSTNAME}"
echo ""
echo "👤 管理员账户:"
echo "  邮箱: ${INIT_SEAFILE_ADMIN_EMAIL}"
echo "  密码: ${INIT_SEAFILE_ADMIN_PASSWORD}"
echo ""
echo "📝 查看日志请运行: ./logs.sh"
EOF

# 停止脚本
cat > "${PROJECT_ROOT}/stop.sh" << 'EOF'
#!/bin/bash
cd /volume1/docker/seafile
echo "⏹️  停止 Seafile 服务..."
docker-compose down
echo "✅ 服务已停止"
EOF

# 重启脚本
cat > "${PROJECT_ROOT}/restart.sh" << 'EOF'
#!/bin/bash
cd /volume1/docker/seafile
echo "🔄 重启 Seafile 服务..."
docker-compose restart
echo ""
echo "📊 查看服务状态..."
docker-compose ps
EOF

# 更新脚本
cat > "${PROJECT_ROOT}/update.sh" << 'EOF'
#!/bin/bash
cd /volume1/docker/seafile
echo "📥 拉取最新镜像..."
docker-compose pull
echo ""
echo "🔄 重启服务应用更新..."
docker-compose up -d
echo ""
echo "🧹 清理旧镜像..."
docker image prune -f
echo "✅ 更新完成"
EOF

# 备份脚本
cat > "${PROJECT_ROOT}/backup.sh" << 'EOF'
#!/bin/bash
cd /volume1/docker/seafile
source .env

BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="./backups/backup_${BACKUP_DATE}"

echo "📦 创建备份目录..."
mkdir -p "${BACKUP_DIR}"

echo "🗄️  备份数据库..."
if docker-compose exec -T db mysqldump -uroot -p$INIT_SEAFILE_MYSQL_ROOT_PASSWORD --all-databases > "${BACKUP_DIR}/mysql_backup.sql" 2>/dev/null; then
    echo "✅ 数据库备份完成"
else
    echo "❌ 数据库备份失败"
fi

echo "📁 备份 Seafile 数据..."
if tar -czf "${BACKUP_DIR}/seafile_data_backup.tar.gz" -C ./seafile-data . 2>/dev/null; then
    echo "✅ 数据文件备份完成"
else
    echo "❌ 数据文件备份失败"
fi

echo "⚙️  备份配置文件..."
cp .env "${BACKUP_DIR}/" 2>/dev/null
cp docker-compose.yml "${BACKUP_DIR}/" 2>/dev/null

echo ""
echo "✅ 备份完成!"
echo "📂 备份位置: ${BACKUP_DIR}"
echo "📊 备份大小: $(du -sh "${BACKUP_DIR}" | cut -f1)"
EOF

# 日志查看脚本
cat > "${PROJECT_ROOT}/logs.sh" << 'EOF'
#!/bin/bash
cd /volume1/docker/seafile

echo "📋 请选择要查看的日志:"
echo "1) Seafile 主服务"
echo "2) MySQL 数据库" 
echo "3) Redis 缓存"
echo "4) 所有服务"
echo "5) 实时监控所有日志"
echo ""
read -p "请输入选择 (1-5): " choice

case $choice in
    1) 
        echo "📖 查看 Seafile 日志 (按 Ctrl+C 退出)..."
        docker-compose logs -f seafile 
        ;;
    2) 
        echo "📖 查看 MySQL 日志 (按 Ctrl+C 退出)..."
        docker-compose logs -f db 
        ;;
    3) 
        echo "📖 查看 Redis 日志 (按 Ctrl+C 退出)..."
        docker-compose logs -f redis 
        ;;
    4) 
        echo "📖 查看所有服务日志..."
        docker-compose logs --tail=50
        ;;
    5) 
        echo "📖 实时监控所有日志 (按 Ctrl+C 退出)..."
        docker-compose logs -f 
        ;;
    *) 
        echo "❌ 无效选择" 
        ;;
esac
EOF

# 状态检查脚本
cat > "${PROJECT_ROOT}/status.sh" << 'EOF'
#!/bin/bash
cd /volume1/docker/seafile
source .env

echo "🔍 Seafile 服务状态检查"
echo "=========================="
echo ""

echo "📊 Docker 容器状态:"
docker-compose ps
echo ""

echo "💾 磁盘使用情况:"
echo "  Seafile 数据: $(du -sh ./seafile-data 2>/dev/null | cut -f1 || echo '计算中...')"
echo "  MySQL 数据:   $(du -sh ./mysql-data 2>/dev/null | cut -f1 || echo '计算中...')"
echo "  Redis 数据:   $(du -sh ./redis-data 2>/dev/null | cut -f1 || echo '计算中...')"
echo "  总计大小:     $(du -sh . 2>/dev/null | cut -f1 || echo '计算中...')"
echo ""

echo "🌐 访问地址:"
echo "  内网访问: http://192.168.50.95:${SEAFILE_PORT}"
echo "  外网访问: ${SEAFILE_SERVER_PROTOCOL}://${SEAFILE_SERVER_HOSTNAME}"
echo ""

echo "🔑 管理员信息:"
echo "  邮箱: ${INIT_SEAFILE_ADMIN_EMAIL}"
echo "  密码: ${INIT_SEAFILE_ADMIN_PASSWORD}"
echo ""

echo "🔧 服务健康检查:"
if curl -s -o /dev/null -w "%{http_code}" http://localhost:${SEAFILE_PORT} | grep -q "200\|302"; then
    echo "  ✅ Seafile 服务运行正常"
else
    echo "  ❌ Seafile 服务异常，请检查容器状态"
fi
EOF

# 设置脚本执行权限
chmod +x "${PROJECT_ROOT}"/*.sh

print_success "管理脚本创建完成"

# 创建 FRP 配置示例
print_info "创建FRP配置示例..."
cat > "${PROJECT_ROOT}/frpc.ini.example" << EOF
# =============================================================================
# FRP 客户端配置示例
# 请复制到实际的 frpc.ini 文件中并修改相应参数
# =============================================================================

[common]
server_addr = your_frp_server_ip
server_port = 7000
token = your_frp_token
# 心跳配置
heartbeat_interval = 30
heartbeat_timeout = 90

# HTTP 代理配置
[seafile_web]
type = http
local_ip = 192.168.50.95
local_port = ${PORT}
custom_domains = ${DOMAIN}

# 如果FRP服务器支持HTTPS，可以使用以下配置
[seafile_https]
type = https
local_ip = 192.168.50.95  
local_port = ${PORT}
custom_domains = ${DOMAIN}
plugin = https2http
plugin_local_addr = 192.168.50.95:${PORT}

# TCP代理配置（备用方案）
[seafile_tcp]
type = tcp
local_ip = 192.168.50.95
local_port = ${PORT}
remote_port = 8000
EOF

print_success "FRP配置示例创建完成"

# 创建说明文件
print_info "创建项目文档..."
cat > "${PROJECT_ROOT}/README.md" << EOF
# Seafile 13 私有云盘部署

## 📋 项目信息
- **部署时间**: $(date '+%Y-%m-%d %H:%M:%S')
- **项目目录**: ${PROJECT_ROOT}
- **访问域名**: ${DOMAIN}
- **服务端口**: ${PORT}
- **访问协议**: ${PROTOCOL}

## 🏗️ 目录结构
\`\`\`
${PROJECT_ROOT}/
├── docker-compose.yml     # Docker编排文件
├── .env                   # 环境变量配置
├── seafile-data/          # Seafile主数据目录
├── mysql-data/            # MySQL数据库文件
├── redis-data/            # Redis数据持久化
├── logs/                  # 日志目录
├── config/                # 配置文件目录
├── backups/               # 备份目录
├── frpc.ini.example       # FRP配置示例
├── start.sh              # 启动脚本
├── stop.sh               # 停止脚本
├── restart.sh            # 重启脚本
├── update.sh             # 更新脚本
├── backup.sh             # 备份脚本
├── logs.sh               # 日志查看脚本
├── status.sh             # 状态检查脚本
└── README.md             # 说明文件
\`\`\`

## 🚀 快速开始

### 启动服务
\`\`\`bash
cd ${PROJECT_ROOT}
./start.sh
\`\`\`

### 查看状态
\`\`\`bash
./status.sh
\`\`\`

### 查看日志
\`\`\`bash
./logs.sh
\`\`\`

## 🌐 访问地址
- **内网访问**: http://192.168.50.95:${PORT}
- **外网访问**: ${PROTOCOL}://${DOMAIN}

## 🔑 管理员账户
- **用户名**: ${ADMIN_EMAIL}
- **初始密码**: ${ADMIN_PASSWORD}

> ⚠️ 请在首次登录后立即修改管理员密码！

## 🔧 常用命令
- 启动服务: \`./start.sh\`
- 停止服务: \`./stop.sh\`
- 重启服务: \`./restart.sh\`
- 查看状态: \`./status.sh\`
- 查看日志: \`./logs.sh\`
- 更新服务: \`./update.sh\`
- 数据备份: \`./backup.sh\`

## 📡 FRP 配置
请参考 \`frpc.ini.example\` 文件配置FRP客户端。

## 🔒 安全提醒
1. 定期备份数据: \`./backup.sh\`
2. 及时更新镜像: \`./update.sh\`
3. 监控服务状态: \`./status.sh\`
4. 使用强密码保护管理员账户
5. 配置防火墙规则限制访问

## 📞 支持
如有问题，请检查：
1. Docker服务是否正常运行
2. 端口${PORT}是否被占用
3. 域名${DOMAIN}是否正确解析
4. FRP配置是否正确

## 🔄 更新日志
- v1.0: 初始版本部署完成
EOF

print_success "项目文档创建完成"

# 保存密码信息到安全文件
print_info "保存密钥信息..."
cat > "${PROJECT_ROOT}/PASSWORDS.txt" << EOF
=============================================================================
Seafile 13 密钥信息
生成时间: $(date '+%Y-%m-%d %H:%M:%S')
请妥善保管此文件，建议保存到安全位置后删除服务器上的副本
=============================================================================

访问信息:
- 域名: ${DOMAIN}
- 内网地址: http://192.168.50.95:${PORT}
- 外网地址: ${PROTOCOL}://${DOMAIN}

管理员账户:
- 邮箱: ${ADMIN_EMAIL}
- 密码: ${ADMIN_PASSWORD}

数据库信息:
- MySQL Root密码: ${MYSQL_ROOT_PASSWORD}
- Seafile数据库密码: ${SEAFILE_DB_PASSWORD}

缓存信息:
- Redis密码: ${REDIS_PASSWORD}

JWT密钥:
- ${JWT_KEY}

注意事项:
1. 请在首次登录后立即修改管理员密码
2. 妥善保管所有密码信息
3. 定期备份数据和配置文件
4. 建议保存此文件到安全位置后删除服务器副本
EOF

# 设置密码文件权限
chmod 600 "${PROJECT_ROOT}/PASSWORDS.txt" 2>/dev/null || true

print_success "密钥信息已保存到 PASSWORDS.txt"

# 询问是否立即启动服务
echo ""
print_info "部署完成! 🎉"
echo ""
print_warning "重要信息:"
echo "📂 项目目录: ${PROJECT_ROOT}"
echo "🔑 密码文件: ${PROJECT_ROOT}/PASSWORDS.txt"
echo "📖 说明文档: ${PROJECT_ROOT}/README.md"
echo ""

read -p "是否现在启动 Seafile 服务? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    print_info "正在启动服务..."
    cd "${PROJECT_ROOT}"
    
    # 拉取镜像
    print_info "拉取Docker镜像..."
    docker-compose pull
    
    # 启动服务
    print_info "启动容器..."
    docker-compose up -d
    
    # 等待服务启动
    print_info "等待服务启动..."
    sleep 10
    
    # 检查服务状态
    print_info "检查服务状态..."
    docker-compose ps
    
    echo ""
    print_success "🎉 Seafile 部署成功!"
    echo ""
    print_info "访问信息:"
    echo "  🌐 内网访问: http://192.168.50.95:${PORT}"
    echo "  🌍 外网访问: ${PROTOCOL}://${DOMAIN}"
    echo ""
    print_info "管理员账户:"
    echo "  📧 邮箱: ${ADMIN_EMAIL}"
    echo "  🔐 密码: ${ADMIN_PASSWORD}"
    echo ""
    print_warning "后续步骤:"
    echo "  1. 配置 FRP 客户端 (参考 frpc.ini.example)"
    echo "  2. 设置域名解析指向 FRP 服务器"
    echo "  3. 首次登录后修改管理员密码"
    echo "  4. 运行 ./status.sh 检查服务状态"
else
    print_info "您可以稍后手动启动服务:"
    echo "  cd ${PROJECT_ROOT} && ./start.sh"
fi

echo ""
print_success "部署脚本执行完成! ✨"
echo ""
print_info "获取帮助:"
echo "  查看状态: cd ${PROJECT_ROOT} && ./status.sh"
echo "  查看日志: cd ${PROJECT_ROOT} && ./logs.sh" 
echo "  查看文档: cat ${PROJECT_ROOT}/README.md"
echo ""
