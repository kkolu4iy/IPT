#!/bin/bash
# =============================================================================
# install.sh - Установка IPTV Proxmox Stack на хост Proxmox
# =============================================================================
# Этот скрипт запускается НА ХОСТЕ PROXMOX (не внутри LXC контейнера)!
# Он создаёт unprivileged LXC контейнер, устанавливает Docker,
# клонирует репозиторий и запускает docker compose.
#
# Использование:
#   chmod +x install.sh
#   ./install.sh [CTID]
#
# Аргументы:
#   CTID - ID контейнера (по умолчанию: 210)
#
# Пример:
#   ./install.sh 210
# =============================================================================

set -euo pipefail

# =============================================================================
# Конфигурация
# =============================================================================
CTID="${1:-210}"
HOSTNAME="iptv-stack"
PASSWORD="iptv-proxmox-$(openssl rand -hex 4)"
STORAGE="local-lvm"
TEMPLATE="local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst"
BRIDGE="vmbr0"

# Сетевые настройки контейнера
CT_IP="dhcp"  # или статический: "192.168.1.210/24"
CT_GW="192.168.1.1"  # шлюз (только для статического IP)

# Репозиторий (замените на ваш URL)
REPO_URL="${REPO_URL:-https://github.com/your-repo/iptv-proxmox-stack.git}"
INSTALL_DIR="/opt/iptv"

# Ресурсы контейнера
CT_CORES=2
CT_MEMORY=2048
CT_SWAP=512
CT_DISK=8

# =============================================================================
# Функции
# =============================================================================

# Цветной вывод
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

header() {
    echo ""
    echo -e "${BLUE}=============================================${NC}"
    echo -e "${BLUE} $*${NC}"
    echo -e "${BLUE}=============================================${NC}"
    echo ""
}

# Проверка что мы на хосте Proxmox
check_proxmox() {
    if ! command -v pveversion &>/dev/null; then
        error "Этот скрипт должен запускаться на хосте Proxmox!"
        error "pveversion не найден."
        exit 1
    fi
    
    log "Proxmox версия: $(pveversion)"
}

# Проверка что контейнер не существует
check_ct_exists() {
    if pct status "$CTID" &>/dev/null; then
        error "Контейнер CTID=$CTID уже существует!"
        error "Остановите и удалите его: pct stop $CTID && pct destroy $CTID"
        exit 1
    fi
}

# Проверка наличия шаблона
check_template() {
    if ! pveam list local | grep -q "debian-12"; then
        log "Шаблон Debian 12 не найден, скачиваем..."
        pveam update
        pveam download local debian-12-standard_12.2-1_amd64.tar.zst || {
            # Пробуем другую версию шаблона
            local template
            template=$(pveam available | grep "debian-12" | head -1 | awk '{print $2}')
            if [[ -n "$template" ]]; then
                pveam download local "$template"
                TEMPLATE="local:vztmpl/${template##*/}"
            else
                error "Не удалось найти шаблон Debian 12"
                exit 1
            fi
        }
    fi
    log "Шаблон готов"
}

# Создание LXC контейнера
create_container() {
    header "Создание LXC контейнера (CTID: $CTID)"
    
    log "Создание unprivileged контейнера..."
    
    pct create "$CTID" "$TEMPLATE" \
        --hostname "$HOSTNAME" \
        --password "$PASSWORD" \
        --storage "$STORAGE" \
        --rootfs "${STORAGE}:${CT_DISK}" \
        --cores "$CT_CORES" \
        --memory "$CT_MEMORY" \
        --swap "$CT_SWAP" \
        --net0 "name=eth0,bridge=${BRIDGE},ip=${CT_IP}" \
        --unprivileged 1 \
        --features "nesting=1,keyctl=1" \
        --onboot 1 \
        --start 0
    
    log "Контейнер создан"
}

# Настройка контейнера
configure_container() {
    header "Настройка контейнера"
    
    # Включаем контейнер
    log "Запуск контейнера..."
    pct start "$CTID"
    sleep 5
    
    # Обновляем систему внутри контейнера
    log "Обновление системы..."
    pct exec "$CTID" -- bash -c "apt-get update && apt-get upgrade -y"
    
    # Устанавливаем необходимые пакеты
    log "Установка пакетов..."
    pct exec "$CTID" -- bash -c "apt-get install -y \
        curl \
        wget \
        git \
        ca-certificates \
        gnupg \
        lsb-release \
        python3 \
        python3-pip \
        cron \
        nano"
}

# Установка Docker
install_docker() {
    header "Установка Docker"
    
    log "Добавление репозитория Docker..."
    pct exec "$CTID" -- bash -c "
        install -m 0755 -d /etc/apt/keyrings &&
        curl -fsSL https://download.docker.com/linux/debian/gpg | \
            gpg --dearmor -o /etc/apt/keyrings/docker.gpg &&
        chmod a+r /etc/apt/keyrings/docker.gpg &&
        echo 'deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
            https://download.docker.com/linux/debian \$(lsb_release -cs) stable' | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null
    "
    
    log "Установка Docker..."
    pct exec "$CTID" -- bash -c "
        apt-get update &&
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    "
    
    # Включаем Docker
    pct exec "$CTID" -- bash -c "systemctl enable docker && systemctl start docker"
    
    log "Docker установлен: $(pct exec "$CTID" -- docker --version)"
}

# Клонирование репозитория
clone_repository() {
    header "Клонирование репозитория"
    
    log "Клонирование в ${INSTALL_DIR}..."
    pct exec "$CTID" -- bash -c "
        git clone '${REPO_URL}' '${INSTALL_DIR}' || {
            echo 'Клонирование из git не удалось, копируем локально...'
            exit 1
        }
    " || {
        # Если git clone не удался, копируем из текущего каталога
        warn "Git clone не удался, копируем локальные файлы..."
        
        # Создаём директорию
        pct exec "$CTID" -- mkdir -p "$INSTALL_DIR"
        
        # Копируем файлы через pct push
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        
        pct push "$CTID" "$script_dir/docker-compose.yml" "${INSTALL_DIR}/docker-compose.yml"
        pct push "$CTID" "$script_dir/.env.example" "${INSTALL_DIR}/.env.example"
        pct push "$CTID" "$script_dir/README.md" "${INSTALL_DIR}/README.md"
        
        # Копируем директории
        pct exec "$CTID" -- mkdir -p "${INSTALL_DIR}/config/nginx"
        pct exec "$CTID" -- mkdir -p "${INSTALL_DIR}/scripts"
        pct exec "$CTID" -- mkdir -p "${INSTALL_DIR}/data/source"
        pct exec "$CTID" -- mkdir -p "${INSTALL_DIR}/data/checked"
        pct exec "$CTID" -- mkdir -p "${INSTALL_DIR}/data/epg"
        pct exec "$CTID" -- mkdir -p "${INSTALL_DIR}/data/threadfin"
        
        pct push "$CTID" "$script_dir/config/nginx/default.conf" "${INSTALL_DIR}/config/nginx/default.conf"
        pct push "$CTID" "$script_dir/scripts/check_playlist.py" "${INSTALL_DIR}/scripts/check_playlist.py"
        pct push "$CTID" "$script_dir/scripts/check-playlist.sh" "${INSTALL_DIR}/scripts/check-playlist.sh"
        pct push "$CTID" "$script_dir/scripts/epg-sync.sh" "${INSTALL_DIR}/scripts/epg-sync.sh"
        
        log "Файлы скопированы локально"
    }
    
    # Устанавливаем права
    log "Настройка прав доступа..."
    pct exec "$CTID" -- bash -c "
        chmod +x ${INSTALL_DIR}/scripts/*.sh &&
        chmod +x ${INSTALL_DIR}/scripts/*.py &&
        chown -R root:root ${INSTALL_DIR}
    "
}

# Настройка .env
setup_env() {
    header "Настройка переменных окружения"
    
    # Создаём .env из примера если его нет
    pct exec "$CTID" -- bash -c "
        if [[ ! -f ${INSTALL_DIR}/.env ]]; then
            cp ${INSTALL_DIR}/.env.example ${INSTALL_DIR}/.env
            echo '.env создан из .env.example'
        fi
    "
    
    warn "ВАЖНО: Отредактируйте ${INSTALL_DIR}/.env внутри контейнера!"
    warn "  pct exec $CTID -- nano ${INSTALL_DIR}/.env"
    warn "  Укажите EPG_URL и другие параметры"
}

# Настройка cron
setup_cron() {
    header "Настройка cron для проверки каналов"
    
    log "Настройка cron job (каждые 15 минут)..."
    pct exec "$CTID" -- bash -c "
        # Создаём cron job
        cat > /etc/cron.d/iptv-check << 'CRON_EOF'
# IPTV Channel Checker - проверка каналов каждые 15 минут
# Запускается внутри Docker контейнера через docker compose exec
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

*/15 * * * * root cd /opt/iptv && docker compose exec -T epg-grabber python3 /scripts/check_playlist.py >> /var/log/iptv-check.log 2>&1
CRON_EOF
        
        # Устанавливаем правильные права
        chmod 0644 /etc/cron.d/iptv-check
        
        # Создаём лог-файл
        touch /var/log/iptv-check.log
        
        # Перезапускаем cron
        service cron restart || systemctl restart cron || true
    "
    
    log "Cron настроен"
}

# Запуск Docker Compose
start_services() {
    header "Запуск сервисов"
    
    log "Запуск docker compose..."
    pct exec "$CTID" -- bash -c "
        cd ${INSTALL_DIR} &&
        docker compose up -d
    "
    
    # Ждём запуска
    log "Ожидание запуска сервисов..."
    sleep 10
    
    # Проверяем статус
    log "Статус контейнеров:"
    pct exec "$CTID" -- bash -c "cd ${INSTALL_DIR} && docker compose ps"
}

# Вывод информации
print_info() {
    header "Установка завершена!"
    
    local ct_ip
    ct_ip=$(pct exec "$CTID" -- hostname -I 2>/dev/null | awk '{print $1}' || echo "не определён")
    
    echo ""
    echo -e "${GREEN}Контейнер:${NC} CTID=$CTID ($HOSTNAME)"
    echo -e "${GREEN}IP адрес:${NC} $ct_ip"
    echo -e "${GREEN}Пароль root:${NC} $PASSWORD"
    echo ""
    echo -e "${YELLOW}Доступ:${NC}"
    echo "  SSH:          ssh root@${ct_ip}"
    echo "  Nginx:        http://${ct_ip}:8080"
    echo "  Плейлист:     http://${ct_ip}:8080/playlist.m3u"
    echo "  EPG:          http://${ct_ip}:8080/xmltv.xml"
    echo "  Threadfin:    ssh -L 34400:localhost:34400 root@${ct_ip}"
    echo "                затем: http://localhost:34400/web"
    echo ""
    echo -e "${YELLOW}Полезные команды:${NC}"
    echo "  pct enter $CTID                    # Войти в контейнер"
    echo "  pct exec $CTID -- docker compose ps  # Статус сервисов"
    echo "  pct exec $CTID -- docker compose logs # Логи"
    echo "  pct exec $CTID -- nano /opt/iptv/.env # Редактировать .env"
    echo ""
    echo -e "${RED}ВАЖНО:${NC} Не забудьте настроить .env внутри контейнера!"
    echo "  pct exec $CTID -- nano /opt/iptv/.env"
    echo ""
    
    # Сохраняем информацию в файл
    cat > "/root/iptv-info-${CTID}.txt" << EOF
IPTV Proxmox Stack - Информация о контейнере
=============================================
Дата установки: $(date)
CTID: $CTID
Hostname: $HOSTNAME
IP: $ct_ip
Root пароль: $PASSWORD

Доступ:
  SSH: ssh root@${ct_ip}
  Nginx: http://${ct_ip}:8080
  Плейлист: http://${ct_ip}:8080/playlist.m3u
  EPG: http://${ct_ip}:8080/xmltv.xml
  Threadfin: ssh -L 34400:localhost:34400 root@${ct_ip} -> http://localhost:34400/web
EOF
    
    log "Информация сохранена в /root/iptv-info-${CTID}.txt"
}

# =============================================================================
# Основной процесс
# =============================================================================
main() {
    header "IPTV Proxmox Stack - Установка"
    log "CTID: $CTID"
    log "Хост: $(hostname)"
    echo ""
    
    # Проверки
    check_proxmox
    check_ct_exists
    check_template
    
    # Установка
    create_container
    configure_container
    install_docker
    clone_repository
    setup_env
    setup_cron
    start_services
    print_info
}

# Обработка ошибок
trap 'error "Скрипт завершён с ошибкой на строке $LINENO"' ERR

# Запуск
main "$@"
