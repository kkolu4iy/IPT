#!/bin/bash
# =============================================================================
# epg-sync.sh - Синхронизация EPG (XMLTV) для Alpine Linux
# =============================================================================
# Скачивает XMLTV EPG по ссылке из переменной EPG_URL и сохраняет
# в /data/epg/epg.xml. Поддерживает gzip архивы (.gz).
# Работает в бесконечном цикле с интервалом из EPG_INTERVAL.
#
# Использование:
#   EPG_URL=https://example.com/epg.xml.gz ./epg-sync.sh
#
# Переменные окружения:
#   EPG_URL       - URL для загрузки EPG (обязательно)
#   EPG_INTERVAL  - Интервал загрузки в секундах (по умолчанию: 60)
#   EPG_OUTPUT    - Путь для сохранения (по умолчанию: /data/epg/epg.xml)
# =============================================================================

set -euo pipefail

# =============================================================================
# Конфигурация
# =============================================================================
EPG_URL="${EPG_URL:-}"
EPG_INTERVAL="${EPG_INTERVAL:-60}"
EPG_OUTPUT="${EPG_OUTPUT:-/data/epg/epg.xml}"
EPG_TEMP="${EPG_OUTPUT}.tmp"
EPG_DIR="$(dirname "$EPG_OUTPUT")"

# =============================================================================
# Функции
# =============================================================================

# Логирование с временной меткой
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Проверка конфигурации
check_config() {
    if [[ -z "$EPG_URL" ]]; then
        log "ОШИБКА: Переменная EPG_URL не установлена!"
        log "Установите: export EPG_URL=https://example.com/epg.xml.gz"
        exit 1
    fi
    
    log "Конфигурация:"
    log "  URL: $EPG_URL"
    log "  Интервал: ${EPG_INTERVAL}с"
    log "  Выход: $EPG_OUTPUT"
}

# Создание директории
ensure_dir() {
    if [[ ! -d "$EPG_DIR" ]]; then
        log "Создание директории: $EPG_DIR"
        mkdir -p "$EPG_DIR"
    fi
}

# Определение типа файла по URL
is_gzip_url() {
    local url="$1"
    # Проверяем расширение .gz в URL
    if echo "$url" | grep -qiE '\.gz(\?|$)'; then
        return 0
    fi
    return 1
}

# Загрузка EPG
download_epg() {
    log "Загрузка EPG: $EPG_URL"
    
    # Скачиваем во временный файл
    if ! wget -q --timeout=30 --tries=3 -O "$EPG_TEMP" "$EPG_URL" 2>/dev/null; then
        if ! curl -sf --max-time 30 --retry 3 -o "$EPG_TEMP" "$EPG_URL" 2>/dev/null; then
            log "ОШИБКА: Не удалось загрузить EPG"
            rm -f "$EPG_TEMP"
            return 1
        fi
    fi
    
    # Проверяем что файл не пустой
    if [[ ! -s "$EPG_TEMP" ]]; then
        log "ОШИБКА: Загруженный файл пустой"
        rm -f "$EPG_TEMP"
        return 1
    fi
    
    local file_size
    file_size=$(stat -c%s "$EPG_TEMP" 2>/dev/null || stat -f%z "$EPG_TEMP" 2>/dev/null || echo "0")
    log "Загружено: ${file_size} байт"
    
    # Обработка gzip
    if is_gzip_url "$EPG_URL"; then
        log "Распаковка gzip..."
        if ! gunzip -c "$EPG_TEMP" > "${EPG_TEMP}.xml" 2>/dev/null; then
            # Может быть не gzip, пробуем как обычный XML
            log "Файл не является gzip, используем как есть"
            mv "$EPG_TEMP" "$EPG_OUTPUT"
        else
            mv "${EPG_TEMP}.xml" "$EPG_OUTPUT"
            rm -f "$EPG_TEMP"
        fi
    else
        # Проверяем magic bytes для gzip
        local magic
        magic=$(head -c 2 "$EPG_TEMP" | xxd -p 2>/dev/null || echo "")
        if [[ "$magic" == "1f8b" ]]; then
            log "Обнаружен gzip (по magic bytes), распаковка..."
            if gunzip -c "$EPG_TEMP" > "${EPG_TEMP}.xml" 2>/dev/null; then
                mv "${EPG_TEMP}.xml" "$EPG_OUTPUT"
                rm -f "$EPG_TEMP"
            else
                log "ОШИБКА: Не удалось распаковать gzip"
                rm -f "$EPG_TEMP" "${EPG_TEMP}.xml"
                return 1
            fi
        else
            # Обычный XML файл
            mv "$EPG_TEMP" "$EPG_OUTPUT"
        fi
    fi
    
    # Проверяем валидность XML
    if [[ -f "$EPG_OUTPUT" ]]; then
        local output_size
        output_size=$(stat -c%s "$EPG_OUTPUT" 2>/dev/null || stat -f%z "$EPG_OUTPUT" 2>/dev/null || echo "0")
        
        # Проверяем что файл содержит XML
        if head -c 100 "$EPG_OUTPUT" | grep -q '<?xml\|<tv'; then
            log "EPG обновлён успешно: ${output_size} байт"
            return 0
        else
            log "ПРЕДУПРЕЖДЕНИЕ: Файл может не быть валидным XML"
            # Всё равно сохраняем - возможно это другой формат
            return 0
        fi
    fi
    
    return 1
}

# Обработка сигналов для graceful shutdown
cleanup() {
    log "Получен сигнал завершения, выход..."
    rm -f "$EPG_TEMP" "${EPG_TEMP}.xml"
    exit 0
}

# =============================================================================
# Основной процесс
# =============================================================================
main() {
    # Обработка сигналов
    trap cleanup SIGTERM SIGINT SIGHUP
    
    log "=== EPG Sync запущен ==="
    
    # Проверки
    check_config
    ensure_dir
    
    # Бесконечный цикл синхронизации
    while true; do
        download_epg || log "Предупреждение: ошибка загрузки, повторим через ${EPG_INTERVAL}с"
        
        # Ждём следующий интервал
        log "Следующая загрузка через ${EPG_INTERVAL}с..."
        sleep "$EPG_INTERVAL"
    done
}

# Запуск
main "$@"
