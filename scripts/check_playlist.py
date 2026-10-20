#!/usr/bin/env python3
# =============================================================================
# check_playlist.py - Проверка доступности IPTV каналов
# =============================================================================
# Читает плейлист с Threadfin, проверяет каждый канал (HTTP HEAD/GET),
# сохраняет только рабочие каналы и генерирует JSON отчёт.
#
# Использование:
#   python3 check_playlist.py
#
# Переменные окружения:
#   THREADFIN_URL  - URL Threadfin (по умолчанию: http://threadfin:34400)
#   CHECK_TIMEOUT  - Таймаут проверки в секундах (по умолчанию: 5)
#   CHECK_WORKERS  - Количество потоков (по умолчанию: 20)
#   OUTPUT_DIR     - Директория для результатов (по умолчанию: /data/checked)
# =============================================================================

import os
import sys
import json
import time
import logging
import requests
from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import List, Dict, Tuple, Optional
from urllib.parse import urlparse

# =============================================================================
# Настройка логирования
# =============================================================================
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

# =============================================================================
# Конфигурация из переменных окружения
# =============================================================================
THREADFIN_URL = os.environ.get('THREADFIN_URL', 'http://threadfin:34400')
PLAYLIST_URL = f"{THREADFIN_URL}/playlist.m3u8"
CHECK_TIMEOUT = int(os.environ.get('CHECK_TIMEOUT', '5'))
CHECK_WORKERS = int(os.environ.get('CHECK_WORKERS', '20'))
OUTPUT_DIR = os.environ.get('OUTPUT_DIR', '/data/checked')
OUTPUT_PLAYLIST = os.path.join(OUTPUT_DIR, 'playlist.m3u')
OUTPUT_REPORT = os.path.join(OUTPUT_DIR, 'report.json')

# User-Agent для HTTP запросов (некоторые серверы блокируют дефолтный)
USER_AGENT = 'IPTV-Checker/1.0'

# HTTP заголовки для проверки
REQUEST_HEADERS = {
    'User-Agent': USER_AGENT,
    'Accept': '*/*',
    'Connection': 'close',
}


# =============================================================================
# Парсинг M3U плейлиста
# =============================================================================
def parse_m3u(content: str) -> List[Dict]:
    """
    Парсит M3U плейлист и возвращает список каналов.
    
    Формат M3U:
        #EXTM3U
        #EXTINF:-1 tvg-id="..." tvg-name="..." group-title="...",Channel Name
        http://stream-url.com/stream
    
    Args:
        content: Содержимое M3U файла
        
    Returns:
        Список словарей с информацией о каналах
    """
    channels = []
    lines = content.strip().split('\n')
    
    # Проверяем заголовок
    if not lines or not lines[0].strip().startswith('#EXTM3U'):
        logger.warning("Плейлист не начинается с #EXTM3U, пробуем обработать как есть")
    
    current_channel = None
    
    for line in lines:
        line = line.strip()
        
        # Пропускаем пустые строки
        if not line:
            continue
        
        # Обработка EXTINF строки (метаданные канала)
        if line.startswith('#EXTINF:'):
            current_channel = {
                'extinf': line,
                'name': '',
                'url': '',
                'tvg_id': '',
                'tvg_name': '',
                'tvg_logo': '',
                'group_title': '',
            }
            
            # Извлекаем имя канала (после последней запятой)
            if ',' in line:
                current_channel['name'] = line.split(',')[-1].strip()
            
            # Извлекаем атрибуты
            import re
            tvg_id_match = re.search(r'tvg-id="([^"]*)"', line)
            if tvg_id_match:
                current_channel['tvg_id'] = tvg_id_match.group(1)
            
            tvg_name_match = re.search(r'tvg-name="([^"]*)"', line)
            if tvg_name_match:
                current_channel['tvg_name'] = tvg_name_match.group(1)
            
            tvg_logo_match = re.search(r'tvg-logo="([^"]*)"', line)
            if tvg_logo_match:
                current_channel['tvg_logo'] = tvg_logo_match.group(1)
            
            group_match = re.search(r'group-title="([^"]*)"', line)
            if group_match:
                current_channel['group_title'] = group_match.group(1)
            
            continue
        
        # Пропускаем другие директивы
        if line.startswith('#'):
            continue
        
        # Это URL потока
        if current_channel is not None:
            current_channel['url'] = line
            channels.append(current_channel)
            current_channel = None
        else:
            # URL без метаданных - создаём минимальный канал
            channels.append({
                'extinf': f'#EXTINF:-1,{urlparse(line).path.split("/")[-1]}',
                'name': urlparse(line).path.split('/')[-1] or 'Unknown',
                'url': line,
                'tvg_id': '',
                'tvg_name': '',
                'tvg_logo': '',
                'group_title': '',
            })
    
    return channels


# =============================================================================
# Проверка доступности канала
# =============================================================================
def check_channel(channel: Dict) -> Tuple[Dict, bool, Optional[str]]:
    """
    Проверяет доступность канала через HTTP HEAD/GET запрос.
    
    Стратегия проверки:
    1. Пробуем HEAD запрос (быстрее, не скачивает тело)
    2. Если HEAD не поддерживается (405), пробуем GET с Range header
    3. Если GET тоже не работает, пробуем обычный GET с маленьким таймаутом
    
    Args:
        channel: Словарь с информацией о канале
        
    Returns:
        Кортеж (channel, is_alive, error_message)
    """
    url = channel['url']
    
    # Пропускаем не-HTTP ссылки (UDP, file, etc.)
    parsed = urlparse(url)
    if parsed.scheme not in ('http', 'https'):
        logger.debug(f"Пропускаем не-HTTP канал: {channel['name']} ({parsed.scheme})")
        return (channel, True, None)  # Считаем рабочим
    
    try:
        # Попытка 1: HEAD запрос
        response = requests.head(
            url,
            headers=REQUEST_HEADERS,
            timeout=CHECK_TIMEOUT,
            allow_redirects=True,
        )
        
        # Успех: статус 2xx или 3xx
        if response.status_code < 400:
            return (channel, True, None)
        
        # Метод не разрешён - пробуем GET
        if response.status_code == 405:
            return _check_with_get(channel)
        
        # Другие ошибки
        return (channel, False, f"HTTP {response.status_code}")
    
    except requests.exceptions.Timeout:
        # Таймаут - пробуем GET
        return _check_with_get(channel)
    
    except requests.exceptions.ConnectionError as e:
        return (channel, False, f"Connection error: {str(e)[:50]}")
    
    except requests.exceptions.RequestException as e:
        return (channel, False, f"Request error: {str(e)[:50]}")
    
    except Exception as e:
        return (channel, False, f"Unexpected error: {str(e)[:50]}")


def _check_with_get(channel: Dict) -> Tuple[Dict, bool, Optional[str]]:
    """
    Проверка канала через GET запрос с Range header.
    Запрашиваем только первые 1024 байта для экономии трафика.
    """
    url = channel['url']
    
    try:
        headers = {**REQUEST_HEADERS, 'Range': 'bytes=0-1023'}
        response = requests.get(
            url,
            headers=headers,
            timeout=CHECK_TIMEOUT,
            stream=True,
            allow_redirects=True,
        )
        
        # Успех: 2xx (полный ответ) или 206 (partial content)
        if response.status_code in (200, 206):
            return (channel, True, None)
        
        # 416 = Range Not Satisfiable, но сервер отвечает - канал жив
        if response.status_code == 416:
            return (channel, True, None)
        
        # 403 = Forbidden, но сервер отвечает - канал может быть жив
        # (некоторые IPTV провайдеры требуют авторизацию)
        if response.status_code == 403:
            return (channel, True, None)
        
        return (channel, False, f"GET HTTP {response.status_code}")
    
    except requests.exceptions.Timeout:
        return (channel, False, "Timeout (GET)")
    
    except requests.exceptions.ConnectionError as e:
        return (channel, False, f"Connection error (GET): {str(e)[:50]}")
    
    except requests.exceptions.RequestException as e:
        return (channel, False, f"Request error (GET): {str(e)[:50]}")
    
    except Exception as e:
        return (channel, False, f"Unexpected error (GET): {str(e)[:50]}")


# =============================================================================
# Генерация M3U из списка каналов
# =============================================================================
def generate_m3u(channels: List[Dict]) -> str:
    """
    Генерирует M3U плейлист из списка каналов.
    
    Args:
        channels: Список рабочих каналов
        
    Returns:
        Строка с содержимым M3U файла
    """
    lines = ['#EXTM3U']
    
    for ch in channels:
        # Восстанавливаем EXTINF строку
        lines.append(ch['extinf'])
        lines.append(ch['url'])
    
    return '\n'.join(lines) + '\n'


# =============================================================================
# Основной процесс
# =============================================================================
def main():
    """Основная функция проверки плейлиста."""
    start_time = time.time()
    logger.info(f"=== Начало проверки плейлиста ===")
    logger.info(f"Источник: {PLAYLIST_URL}")
    logger.info(f"Таймаут: {CHECK_TIMEOUT}с, Потоки: {CHECK_WORKERS}")
    
    # -----------------------------------------------------------------
    # Шаг 1: Загрузка плейлиста
    # -----------------------------------------------------------------
    try:
        logger.info("Загрузка плейлиста...")
        response = requests.get(
            PLAYLIST_URL,
            headers=REQUEST_HEADERS,
            timeout=30,
        )
        response.raise_for_status()
        playlist_content = response.text
        logger.info(f"Плейлист загружен: {len(playlist_content)} байт")
    except requests.exceptions.RequestException as e:
        logger.error(f"Ошибка загрузки плейлиста: {e}")
        sys.exit(1)
    
    # -----------------------------------------------------------------
    # Шаг 2: Парсинг каналов
    # -----------------------------------------------------------------
    channels = parse_m3u(playlist_content)
    total_channels = len(channels)
    logger.info(f"Найдено каналов: {total_channels}")
    
    if total_channels == 0:
        logger.warning("Плейлист пуст! Проверьте настройки Threadfin.")
        sys.exit(0)
    
    # -----------------------------------------------------------------
    # Шаг 3: Проверка каналов (параллельно)
    # -----------------------------------------------------------------
    logger.info(f"Проверка каналов ({CHECK_WORKERS} потоков)...")
    alive_channels = []
    dead_channels = []
    checked = 0
    
    with ThreadPoolExecutor(max_workers=CHECK_WORKERS) as executor:
        # Отправляем все задачи на выполнение
        future_to_channel = {
            executor.submit(check_channel, ch): ch
            for ch in channels
        }
        
        # Собираем результаты по мере выполнения
        for future in as_completed(future_to_channel):
            channel, is_alive, error = future.result()
            checked += 1
            
            if is_alive:
                alive_channels.append(channel)
            else:
                dead_channels.append({
                    'name': channel['name'],
                    'url': channel['url'],
                    'error': error,
                })
            
            # Прогресс каждые 50 каналов
            if checked % 50 == 0 or checked == total_channels:
                progress = (checked / total_channels) * 100
                logger.info(
                    f"Прогресс: {checked}/{total_channels} ({progress:.0f}%) | "
                    f"Рабочих: {len(alive_channels)} | "
                    f"Мёртвых: {len(dead_channels)}"
                )
    
    # -----------------------------------------------------------------
    # Шаг 4: Сохранение результатов
    # -----------------------------------------------------------------
    # Создаём выходную директорию
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    # Сохраняем проверенный плейлист
    m3u_content = generate_m3u(alive_channels)
    with open(OUTPUT_PLAYLIST, 'w', encoding='utf-8') as f:
        f.write(m3u_content)
    logger.info(f"Проверенный плейлист сохранён: {OUTPUT_PLAYLIST} ({len(alive_channels)} каналов)")
    
    # -----------------------------------------------------------------
    # Шаг 5: Генерация JSON отчёта
    # -----------------------------------------------------------------
    elapsed = time.time() - start_time
    report = {
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'source': PLAYLIST_URL,
        'stats': {
            'total_channels': total_channels,
            'alive_channels': len(alive_channels),
            'dead_channels': len(dead_channels),
            'alive_percent': round((len(alive_channels) / total_channels) * 100, 1) if total_channels > 0 else 0,
            'check_duration_seconds': round(elapsed, 1),
            'timeout_seconds': CHECK_TIMEOUT,
            'workers': CHECK_WORKERS,
        },
        'dead_channels': dead_channels,
        'alive_channels': [
            {
                'name': ch['name'],
                'group': ch['group_title'],
                'url': ch['url'],
            }
            for ch in alive_channels
        ],
    }
    
    with open(OUTPUT_REPORT, 'w', encoding='utf-8') as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
    logger.info(f"Отчёт сохранён: {OUTPUT_REPORT}")
    
    # -----------------------------------------------------------------
    # Итоги
    # -----------------------------------------------------------------
    logger.info(f"=== Проверка завершена за {elapsed:.1f}с ===")
    logger.info(
        f"Результат: {len(alive_channels)}/{total_channels} каналов работают "
        f"({report['stats']['alive_percent']}%)"
    )
    
    if dead_channels:
        logger.info(f"Мёртвые каналы ({len(dead_channels)}):")
        for dc in dead_channels[:10]:  # Показываем первые 10
            logger.info(f"  - {dc['name']}: {dc['error']}")
        if len(dead_channels) > 10:
            logger.info(f"  ... и ещё {len(dead_channels) - 10}")


# =============================================================================
# Точка входа
# =============================================================================
if __name__ == '__main__':
    main()
