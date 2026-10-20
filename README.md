# IPTV Proxmox Stack

Полноценный стек для IPTV на базе Proxmox LXC контейнера с Docker. Включает Threadfin для управления плейлистами, автоматическую проверку каналов, синхронизацию EPG и Nginx для раздачи проверенных плейлистов.

## Архитектура

```
┌─────────────────────────────────────────────────────────┐
│  Proxmox Host                                           │
│  ┌───────────────────────────────────────────────────┐  │
│  │  LXC Container (CTID: 210)                        │  │
│  │  ┌─────────────────────────────────────────────┐  │  │
│  │  │  Docker Compose                             │  │  │
│  │  │  ┌──────────┐ ┌──────────┐ ┌────────────┐  │  │  │
│  │  │  │ Threadfin│ │EPG Grab. │ │   Nginx    │  │  │  │
│  │  │  │ :34400   │ │ (alpine) │ │   :8080    │  │  │  │
│  │  │  └──────────┘ └──────────┘ └────────────┘  │  │  │
│  │  │       │              │             │        │  │  │
│  │  │       ▼              ▼             ▼        │  │  │
│  │  │  ┌──────────────────────────────────────┐   │  │  │
│  │  │  │  Shared Volumes                      │   │  │  │
│  │  │  │  /data/source/   - исходный плейлист │   │  │  │
│  │  │  │  /data/checked/  - проверенный M3U   │   │  │  │
│  │  │  │  /data/epg/      - XMLTV EPG         │   │  │  │
│  │  │  │  /data/threadfin/ - конфиг Threadfin │   │  │  │
│  │  │  └──────────────────────────────────────┘   │  │  │
│  │  └─────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Быстрый старт

### 1. Клонировать репозиторий на хост Proxmox

```bash
cd /root
git clone https://github.com/your-repo/iptv-proxmox-stack.git
cd iptv-proxmox-stack
```

### 2. Запустить установку

```bash
chmod +x install.sh
./install.sh 210  # или любой другой CTID
```

Скрипт автоматически:
- Создаст unprivileged LXC контейнер Debian 12
- Установит Docker
- Скопирует проект в /opt/iptv
- Настроит cron для проверки каналов
- Запустит docker compose

### 3. Настроить переменные окружения

```bash
# Внутри контейнера (или через SSH)
ssh root@<container-ip>
cd /opt/iptv
cp .env.example .env
nano .env
```

Укажите:
- `EPG_URL` — ссылка на XMLTV EPG (поддерживает .gz)
- `EPG_INTERVAL` — интервал обновления EPG в секундах (по умолчанию 60)
- `TZ` — часовой пояс

### 4. Настроить Threadfin

Откройте веб-интерфейс Threadfin:
- Через SSH туннель: `ssh -L 34400:localhost:34400 root@<container-ip>`
- Откройте: `http://localhost:34400/web`

Добавьте ваш IPTV плейлист в Threadfin.

### 5. Доступ к файлам

| Файл | URL | Описание |
|------|-----|----------|
| Проверенный плейлист | `http://<host>:8080/playlist.m3u` | Только рабочие каналы |
| Сырой плейлист | `http://<host>:8080/playlist-all.m3u` | Все каналы из Threadfin |
| EPG | `http://<host>:8080/xmltv.xml` | XMLTV EPG |
| Health check | `http://<host>:8080/healthz` | Проверка работоспособности |
| Threadfin UI | `http://localhost:34400/web` (через SSH туннель) | Управление Threadfin |

## Структура проекта

```
iptv-proxmox-stack/
├── README.md                    # Документация
├── docker-compose.yml           # Docker сервисы
├── .env.example                 # Пример переменных окружения
├── install.sh                   # Скрипт установки на Proxmox
├── config/
│   └── nginx/
│       └── default.conf         # Конфигурация Nginx
├── scripts/
│   ├── check_playlist.py        # Python: проверка каналов
│   ├── check-playlist.sh        # Bash: обёртка для cron
│   └── epg-sync.sh              # Shell: синхронизация EPG
└── data/
    ├── source/                  # Исходные плейлисты
    ├── checked/                 # Проверенные плейлисты
    ├── epg/                     # EPG данные
    └── threadfin/               # Конфигурация Threadfin
```

## Переменные окружения

| Переменная | Описание | По умолчанию |
|-----------|----------|-------------|
| `TZ` | Часовой пояс | `Europe/Moscow` |
| `EPG_URL` | URL XMLTV EPG | (обязательно) |
| `EPG_INTERVAL` | Интервал обновления EPG (сек) | `60` |
| `THREADFIN_PORT` | Порт Threadfin | `34400` |

## Проверка каналов

Скрипт `check_playlist.py` выполняет:
- Параллельную проверку всех каналов через `ThreadPoolExecutor`
- HTTP HEAD/GET запросы с таймаутом 5 секунд
- Сохранение только рабочих каналов в `/data/checked/playlist.m3u`
- Генерацию JSON отчёта в `/data/checked/report.json`

Запускается по cron каждые 15 минут.

## Обновление EPG

Скрипт `epg-sync.sh`:
- Скачивает XMLTV по `EPG_URL`
- Поддерживает gzip архивы (.gz)
- Сохраняет в `/data/epg/epg.xml`
- Запускается каждую минуту (или заданный интервал)

## Troubleshooting

### Контейнер не запускается
```bash
# Проверить статус
pct status 210
# Войти в контейнер
pct enter 210
# Проверить Docker
docker compose ps
docker compose logs
```

### Каналы не проверяются
```bash
# Проверить вручную
cd /opt/iptv
docker compose exec epg-grabber python /scripts/check_playlist.py
```

### EPG не обновляется
```bash
# Проверить переменные
docker compose exec epg-grabber env | grep EPG
# Проверить логи
docker compose logs epg-grabber
```

## Лицензия

MIT
