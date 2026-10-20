import { useState } from 'react'

// =============================================================================
// IPTV Proxmox Stack - Документация проекта
// =============================================================================
// Веб-интерфейс для просмотра документации и структуры проекта
// =============================================================================

type FileNode = {
  name: string
  type: 'file' | 'folder'
  children?: FileNode[]
  description?: string
  icon?: string
}

const projectStructure: FileNode[] = [
  {
    name: 'README.md',
    type: 'file',
    icon: '📄',
    description: 'Подробная документация проекта с инструкциями по установке'
  },
  {
    name: 'docker-compose.yml',
    type: 'file',
    icon: '🐳',
    description: 'Docker Compose: threadfin, epg-grabber, nginx'
  },
  {
    name: '.env.example',
    type: 'file',
    icon: '⚙️',
    description: 'Пример переменных окружения (TZ, EPG_URL, EPG_INTERVAL)'
  },
  {
    name: 'install.sh',
    type: 'file',
    icon: '🚀',
    description: 'Скрипт установки на хост Proxmox (создаёт LXC, Docker, cron)'
  },
  {
    name: 'config',
    type: 'folder',
    children: [
      {
        name: 'nginx',
        type: 'folder',
        children: [
          {
            name: 'default.conf',
            type: 'file',
            icon: '🌐',
            description: 'Nginx: playlist.m3u, playlist-all.m3u, xmltv.xml, healthz'
          }
        ]
      }
    ]
  },
  {
    name: 'scripts',
    type: 'folder',
    children: [
      {
        name: 'check_playlist.py',
        type: 'file',
        icon: '🐍',
        description: 'Python: проверка каналов через ThreadPoolExecutor'
      },
      {
        name: 'check-playlist.sh',
        type: 'file',
        icon: '📜',
        description: 'Bash обёртка для cron (вызов Python скрипта)'
      },
      {
        name: 'epg-sync.sh',
        type: 'file',
        icon: '📡',
        description: 'Синхронизация EPG (XMLTV) с поддержкой gzip'
      }
    ]
  },
  {
    name: 'data',
    type: 'folder',
    children: [
      { name: 'source/', type: 'folder', children: [{ name: '.gitkeep', type: 'file', icon: '📁', description: 'Исходные плейлисты' }] },
      { name: 'checked/', type: 'folder', children: [{ name: '.gitkeep', type: 'file', icon: '✅', description: 'Проверенные плейлисты' }] },
      { name: 'epg/', type: 'folder', children: [{ name: '.gitkeep', type: 'file', icon: '📺', description: 'EPG данные (XMLTV)' }] },
      { name: 'threadfin/', type: 'folder', children: [{ name: '.gitkeep', type: 'file', icon: '🔧', description: 'Конфигурация Threadfin' }] }
    ]
  }
]

function FileTree({ nodes, depth = 0 }: { nodes: FileNode[], depth?: number }) {
  return (
    <div className={depth > 0 ? 'ml-4 border-l border-gray-700 pl-3' : ''}>
      {nodes.map((node, i) => (
        <div key={i} className="mb-1">
          <div className="flex items-center gap-2 py-1 px-2 rounded hover:bg-gray-800/50 transition-colors">
            <span className="text-sm">{node.icon || (node.type === 'folder' ? '📁' : '📄')}</span>
            <span className={`font-mono text-sm ${node.type === 'folder' ? 'text-blue-400 font-semibold' : 'text-gray-200'}`}>
              {node.name}
            </span>
            {node.description && (
              <span className="text-xs text-gray-500 ml-2 hidden sm:inline">— {node.description}</span>
            )}
          </div>
          {node.children && <FileTree nodes={node.children} depth={depth + 1} />}
        </div>
      ))}
    </div>
  )
}

function ArchitectureDiagram() {
  return (
    <div className="bg-gray-900 rounded-xl p-6 border border-gray-700 overflow-x-auto">
      <pre className="text-xs sm:text-sm text-green-400 font-mono whitespace-pre">
{`┌─────────────────────────────────────────────────────────┐
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
└─────────────────────────────────────────────────────────┘`}
      </pre>
    </div>
  )
}

function QuickStart() {
  const steps = [
    {
      title: '1. Клонировать репозиторий',
      command: 'cd /root\ngit clone https://github.com/your-repo/iptv-proxmox-stack.git\ncd iptv-proxmox-stack',
    },
    {
      title: '2. Запустить установку',
      command: 'chmod +x install.sh\n./install.sh 210',
    },
    {
      title: '3. Настроить .env',
      command: 'pct exec 210 -- nano /opt/iptv/.env',
    },
    {
      title: '4. Настроить Threadfin',
      command: 'ssh -L 34400:localhost:34400 root@<container-ip>\n# Открыть: http://localhost:34400/web',
    },
  ]

  return (
    <div className="space-y-4">
      {steps.map((step, i) => (
        <div key={i} className="bg-gray-900 rounded-lg border border-gray-700 overflow-hidden">
          <div className="px-4 py-2 bg-gray-800 border-b border-gray-700">
            <span className="text-sm font-semibold text-blue-400">{step.title}</span>
          </div>
          <pre className="px-4 py-3 text-sm text-green-300 font-mono overflow-x-auto">
            {step.command}
          </pre>
        </div>
      ))}
    </div>
  )
}

function EndpointsTable() {
  const endpoints = [
    { path: '/playlist.m3u', desc: 'Проверенный плейлист (только рабочие каналы)', type: 'M3U' },
    { path: '/playlist-all.m3u', desc: 'Сырой плейлист от Threadfin (все каналы)', type: 'M3U' },
    { path: '/xmltv.xml', desc: 'EPG данные (XMLTV формат)', type: 'XML' },
    { path: '/report.json', desc: 'JSON отчёт о проверке каналов', type: 'JSON' },
    { path: '/healthz', desc: 'Health check endpoint', type: 'Text' },
  ]

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-gray-700">
            <th className="text-left py-2 px-3 text-gray-400 font-medium">Путь</th>
            <th className="text-left py-2 px-3 text-gray-400 font-medium">Описание</th>
            <th className="text-left py-2 px-3 text-gray-400 font-medium hidden sm:table-cell">Тип</th>
          </tr>
        </thead>
        <tbody>
          {endpoints.map((ep, i) => (
            <tr key={i} className="border-b border-gray-800 hover:bg-gray-800/50">
              <td className="py-2 px-3 font-mono text-yellow-400">{ep.path}</td>
              <td className="py-2 px-3 text-gray-300">{ep.desc}</td>
              <td className="py-2 px-3 hidden sm:table-cell">
                <span className="px-2 py-0.5 rounded bg-gray-700 text-xs text-gray-300">{ep.type}</span>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function EnvTable() {
  const vars = [
    { name: 'TZ', desc: 'Часовой пояс', default: 'Europe/Moscow' },
    { name: 'EPG_URL', desc: 'URL XMLTV EPG (поддерживает .gz)', default: '(обязательно)' },
    { name: 'EPG_INTERVAL', desc: 'Интервал обновления EPG (сек)', default: '60' },
    { name: 'THREADFIN_PORT', desc: 'Порт Threadfin', default: '34400' },
    { name: 'NGINX_PORT', desc: 'Порт Nginx', default: '8080' },
    { name: 'CHECK_TIMEOUT', desc: 'Таймаут проверки канала (сек)', default: '5' },
    { name: 'CHECK_WORKERS', desc: 'Потоки для проверки', default: '20' },
  ]

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-gray-700">
            <th className="text-left py-2 px-3 text-gray-400 font-medium">Переменная</th>
            <th className="text-left py-2 px-3 text-gray-400 font-medium">Описание</th>
            <th className="text-left py-2 px-3 text-gray-400 font-medium">По умолчанию</th>
          </tr>
        </thead>
        <tbody>
          {vars.map((v, i) => (
            <tr key={i} className="border-b border-gray-800 hover:bg-gray-800/50">
              <td className="py-2 px-3 font-mono text-purple-400">{v.name}</td>
              <td className="py-2 px-3 text-gray-300">{v.desc}</td>
              <td className="py-2 px-3 font-mono text-green-400 text-xs">{v.default}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

export default function App() {
  const [activeTab, setActiveTab] = useState<'overview' | 'structure' | 'quickstart' | 'api'>('overview')

  const tabs = [
    { id: 'overview' as const, label: 'Обзор', icon: '🏠' },
    { id: 'structure' as const, label: 'Структура', icon: '📂' },
    { id: 'quickstart' as const, label: 'Быстрый старт', icon: '🚀' },
    { id: 'api' as const, label: 'Endpoints', icon: '🔗' },
  ]

  return (
    <div className="min-h-screen bg-gray-950 text-gray-100">
      {/* Header */}
      <header className="bg-gradient-to-r from-gray-900 via-gray-800 to-gray-900 border-b border-gray-700">
        <div className="max-w-6xl mx-auto px-4 py-6">
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center text-2xl shadow-lg">
              📺
            </div>
            <div>
              <h1 className="text-2xl font-bold bg-gradient-to-r from-blue-400 to-purple-400 bg-clip-text text-transparent">
                IPTV Proxmox Stack
              </h1>
              <p className="text-sm text-gray-400">
                Docker + Threadfin + Nginx + EPG на Proxmox LXC
              </p>
            </div>
          </div>
        </div>
      </header>

      {/* Navigation */}
      <nav className="bg-gray-900/50 border-b border-gray-800 sticky top-0 z-10 backdrop-blur-sm">
        <div className="max-w-6xl mx-auto px-4">
          <div className="flex gap-1 overflow-x-auto py-2">
            {tabs.map(tab => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-all whitespace-nowrap ${
                  activeTab === tab.id
                    ? 'bg-blue-600/20 text-blue-400 border border-blue-500/30'
                    : 'text-gray-400 hover:text-gray-200 hover:bg-gray-800'
                }`}
              >
                <span>{tab.icon}</span>
                {tab.label}
              </button>
            ))}
          </div>
        </div>
      </nav>

      {/* Content */}
      <main className="max-w-6xl mx-auto px-4 py-8">
        {activeTab === 'overview' && (
          <div className="space-y-8">
            {/* Description */}
            <section>
              <h2 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
                <span>📋</span> Описание проекта
              </h2>
              <div className="bg-gray-900 rounded-xl border border-gray-700 p-6 space-y-3 text-gray-300">
                <p>
                  Полный стек для IPTV на базе Proxmox LXC контейнера с Docker.
                  Включает Threadfin для управления плейлистами, автоматическую проверку каналов,
                  синхронизацию EPG и Nginx для раздачи проверенных плейлистов.
                </p>
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mt-4">
                  <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
                    <div className="text-2xl mb-2">🐳</div>
                    <h3 className="font-semibold text-white">Docker</h3>
                    <p className="text-xs text-gray-400 mt-1">3 сервиса: Threadfin, EPG Grabber, Nginx</p>
                  </div>
                  <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
                    <div className="text-2xl mb-2">🔍</div>
                    <h3 className="font-semibold text-white">Проверка каналов</h3>
                    <p className="text-xs text-gray-400 mt-1">Python + ThreadPoolExecutor, каждые 15 мин</p>
                  </div>
                  <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
                    <div className="text-2xl mb-2">📡</div>
                    <h3 className="font-semibold text-white">EPG Sync</h3>
                    <p className="text-xs text-gray-400 mt-1">XMLTV с поддержкой gzip, обновление каждую минуту</p>
                  </div>
                </div>
              </div>
            </section>

            {/* Architecture */}
            <section>
              <h2 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
                <span>🏗️</span> Архитектура
              </h2>
              <ArchitectureDiagram />
            </section>

            {/* Environment Variables */}
            <section>
              <h2 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
                <span>⚙️</span> Переменные окружения
              </h2>
              <div className="bg-gray-900 rounded-xl border border-gray-700 overflow-hidden">
                <EnvTable />
              </div>
            </section>
          </div>
        )}

        {activeTab === 'structure' && (
          <div className="space-y-6">
            <section>
              <h2 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
                <span>📂</span> Структура проекта
              </h2>
              <div className="bg-gray-900 rounded-xl border border-gray-700 p-6">
                <FileTree nodes={projectStructure} />
              </div>
            </section>

            <section>
              <h2 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
                <span>📝</span> Описание файлов
              </h2>
              <div className="space-y-3">
                {[
                  { file: 'install.sh', desc: 'Скрипт для запуска НА ХОСТЕ PROXMOX. Создаёт unprivileged LXC контейнер Debian 12 с features nesting=1,keyctl=1. Устанавливает Docker, клонирует репозиторий, настраивает cron и запускает docker compose.' },
                  { file: 'docker-compose.yml', desc: 'Определяет 3 сервиса: threadfin (IPTV прокси), epg-grabber (alpine + скрипты), nginx (раздача плейлистов). Использует bridge сеть и shared volumes.' },
                  { file: 'config/nginx/default.conf', desc: 'Nginx конфиг для раздачи playlist.m3u (проверенный), playlist-all.m3u (сырой через прокси на threadfin:34400), xmltv.xml и healthz endpoint.' },
                  { file: 'scripts/check_playlist.py', desc: 'Python скрипт с ThreadPoolExecutor для параллельной проверки каналов. HTTP HEAD/GET с таймаутом. Сохраняет рабочие каналы и генерирует JSON отчёт.' },
                  { file: 'scripts/epg-sync.sh', desc: 'Alpine-совместимый скрипт для скачивания XMLTV EPG. Поддерживает gzip (.gz). Работает в бесконечном цикле с настраиваемым интервалом.' },
                ].map((item, i) => (
                  <div key={i} className="bg-gray-900 rounded-lg border border-gray-700 p-4">
                    <code className="text-yellow-400 font-mono text-sm">{item.file}</code>
                    <p className="text-gray-400 text-sm mt-1">{item.desc}</p>
                  </div>
                ))}
              </div>
            </section>
          </div>
        )}

        {activeTab === 'quickstart' && (
          <div className="space-y-6">
            <section>
              <h2 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
                <span>🚀</span> Быстрый старт
              </h2>
              <QuickStart />
            </section>

            <section>
              <h2 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
                <span>⚠️</span> Важные замечания
              </h2>
              <div className="bg-yellow-900/20 border border-yellow-700/50 rounded-xl p-4 space-y-2">
                <p className="text-yellow-300 text-sm">
                  <strong>install.sh</strong> запускается на хосте Proxmox, а не внутри LXC контейнера!
                </p>
                <p className="text-yellow-300 text-sm">
                  После установки отредактируйте <code className="bg-gray-800 px-1 rounded">.env</code> — укажите <code className="bg-gray-800 px-1 rounded">EPG_URL</code>.
                </p>
                <p className="text-yellow-300 text-sm">
                  Threadfin UI доступен через SSH туннель: <code className="bg-gray-800 px-1 rounded">ssh -L 34400:localhost:34400 root@&lt;ip&gt;</code>
                </p>
              </div>
            </section>

            <section>
              <h2 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
                <span>🔧</span> Troubleshooting
              </h2>
              <div className="space-y-3">
                {[
                  { q: 'Контейнер не запускается', a: 'pct status 210 && pct enter 210 && docker compose ps' },
                  { q: 'Каналы не проверяются', a: 'docker compose exec epg-grabber python3 /scripts/check_playlist.py' },
                  { q: 'EPG не обновляется', a: 'docker compose logs epg-grabber && проверьте EPG_URL в .env' },
                ].map((item, i) => (
                  <div key={i} className="bg-gray-900 rounded-lg border border-gray-700 p-4">
                    <p className="text-red-400 text-sm font-semibold">❓ {item.q}</p>
                    <pre className="text-green-300 text-xs font-mono mt-2 bg-gray-800 p-2 rounded">{item.a}</pre>
                  </div>
                ))}
              </div>
            </section>
          </div>
        )}

        {activeTab === 'api' && (
          <div className="space-y-6">
            <section>
              <h2 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
                <span>🔗</span> Nginx Endpoints (порт 8080)
              </h2>
              <div className="bg-gray-900 rounded-xl border border-gray-700 overflow-hidden">
                <EndpointsTable />
              </div>
            </section>

            <section>
              <h2 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
                <span>📊</span> Пример report.json
              </h2>
              <div className="bg-gray-900 rounded-xl border border-gray-700 p-4">
                <pre className="text-sm text-green-300 font-mono overflow-x-auto">
{`{
  "timestamp": "2024-01-15T10:30:00+00:00",
  "source": "http://threadfin:34400/playlist.m3u8",
  "stats": {
    "total_channels": 150,
    "alive_channels": 132,
    "dead_channels": 18,
    "alive_percent": 88.0,
    "check_duration_seconds": 45.2,
    "timeout_seconds": 5,
    "workers": 20
  },
  "dead_channels": [...],
  "alive_channels": [...]
}`}
                </pre>
              </div>
            </section>

            <section>
              <h2 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
                <span>🔐</span> Доступ к Threadfin
              </h2>
              <div className="bg-gray-900 rounded-xl border border-gray-700 p-4">
                <p className="text-gray-300 text-sm mb-3">
                  Threadfin UI доступен только через SSH туннель для безопасности:
                </p>
                <pre className="text-sm text-green-300 font-mono bg-gray-800 p-3 rounded">
{`# Создать SSH туннель
ssh -L 34400:localhost:34400 root@<container-ip>

# Затем открыть в браузере:
http://localhost:34400/web`}
                </pre>
              </div>
            </section>
          </div>
        )}
      </main>

      {/* Footer */}
      <footer className="border-t border-gray-800 bg-gray-900/50 mt-12">
        <div className="max-w-6xl mx-auto px-4 py-4 text-center text-sm text-gray-500">
          IPTV Proxmox Stack • Docker + Threadfin + Nginx + EPG
        </div>
      </footer>
    </div>
  )
}
