#!/bin/bash
# =============================================================================
# check-playlist.sh - Bash обёртка для запуска check_playlist.py
# =============================================================================
# Вызывает Python-скрипт проверки каналов с правильными переменными окружения.
# Предназначен для запуска из cron.
#
# Использование:
#   ./check-playlist.sh
#   # или через cron:
#   */15 * * * * /opt/iptv/scripts/check-playlist.sh >> /var/log/iptv-check.log 2>&1
#
# Переменные окружения:
#   THREADFIN_URL  - URL Threadfin (по умолчанию: http://threadfin:34400)
#   CHECK_TIMEOUT  - Таймаут проверки (по умолчанию: 5)
#   CHECK_WORKERS  - Количество потоков (по умолчанию: 20)
#   OUTPUT_DIR     - Директория результатов (по умолчанию: /data/checked)
# =============================================================================

set -euo pipefail

# =============================================================================
# Конфигурация
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PYTHON_SCRIPT="${SCRIPT_DIR}/check_playlist.py"
LOG_FILE="${PROJECT_DIR}/data/checked/check.log"

# Переменные окружения (можно переопределить из .env)
export THREADFIN_URL="${THREADFIN_URL:-http://threadfin:34400}"
export CHECK_TIMEOUT="${CHECK_TIMEOUT:-5}"
export CHECK_WORKERS="${CHECK_WORKERS:-20}"
export OUTPUT_DIR="${OUTPUT_DIR:-/data/checked}"

# =============================================================================
# Функции
# =============================================================================

# Логирование с временной меткой
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Проверка зависимостей
check_dependencies() {
    # Проверяем наличие Python 3
    if ! command -v python3 &>/dev/null; then
        log "ОШИБКА: Python3 не найден. Установите: apt install python3"
        exit 1
    fi
    
    # Проверяем наличие скрипта
    if [[ ! -f "$PYTHON_SCRIPT" ]]; then
        log "ОШИБКА: Скрипт не найден: $PYTHON_SCRIPT"
        exit 1
    fi
    
    # Проверяем наличие модуля requests
    if ! python3 -c "import requests" 2>/dev/null; then
        log "Установка модуля requests..."
        pip3 install requests --quiet 2>/dev/null || {
            log "ОШИБКА: Не удалось установить модуль requests"
            exit 1
        }
    fi
}

# Проверка доступности Threadfin
check_threadfin() {
    log "Проверка доступности Threadfin: ${THREADFIN_URL}"
    
    local max_retries=5
    local retry_interval=10
    
    for i in $(seq 1 $max_retries); do
        if curl -sf --max-time 10 "${THREADFIN_URL}/playlist.m3u8" > /dev/null 2>&1; then
            log "Threadfin доступен"
            return 0
        fi
        
        log "Попытка ${i}/${max_retries}: Threadfin недоступен, ждём ${retry_interval}с..."
        sleep "$retry_interval"
    done
    
    log "ОШИБКА: Threadfin недоступен после ${max_retries} попыток"
    return 1
}

# Создание выходной директории
ensure_output_dir() {
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        log "Создание директории: $OUTPUT_DIR"
        mkdir -p "$OUTPUT_DIR"
    fi
}

# =============================================================================
# Основной процесс
# =============================================================================
main() {
    log "=== Запуск проверки плейлиста ==="
    log "Скрипт: $PYTHON_SCRIPT"
    log "Threadfin: $THREADFIN_URL"
    log "Выход: $OUTPUT_DIR"
    
    # Проверки
    check_dependencies
    ensure_output_dir
    
    # Проверяем Threadfin (если запущены на хосте, а не в Docker)
    if [[ "${SKIP_THREADFIN_CHECK:-}" != "1" ]]; then
        check_threadfin || {
            log "Пропускаем проверку - Threadfin недоступен"
            exit 1
        }
    fi
    
    # Запуск Python-скрипта
    log "Запуск проверки каналов..."
    python3 "$PYTHON_SCRIPT"
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        log "=== Проверка завершена успешно ==="
    else
        log "=== Проверка завершена с ошибкой (код: $exit_code) ==="
    fi
    
    exit $exit_code
}

# Запуск
main "$@"
