#!/usr/bin/env bash
# =============================================================================
# decision-os  /  Step 4: フロントエンドセットアップ
# 実行方法: bash 04_frontend_setup.sh
# 前提: 03_backend_setup.sh が完了済み
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

# ---------- プロジェクトルートへ移動 ----------
PROJECT_DIR="$HOME/projects/decision-os"
[[ -d "$PROJECT_DIR" ]] || error "プロジェクトが見つかりません: $PROJECT_DIR"
cd "$PROJECT_DIR/frontend"

# nvm 有効化
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
nvm use 20 2>/dev/null || true

command -v node &>/dev/null || error "Node.js が見つかりません"
success "Node.js: $(node --version) / npm: $(npm --version)"

# ---------- 1. package.json の生成 ----------
section "1. package.json の生成"

cat > package.json << 'EOF'
{
  "name": "decision-os-frontend",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev":     "vite",
    "build":   "tsc -b && vite build",
    "preview": "vite preview",
    "test":    "vitest run",
    "test:ui": "vitest --ui",
    "lint":    "eslint . --ext ts,tsx --report-unused-disable-directives --max-warnings 0",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "react":                   "^18.3.1",
    "react-dom":               "^18.3.1",
    "react-router-dom":        "^6.26.0",
    "@tanstack/react-query":   "^5.56.0",
    "axios":                   "^1.7.7",
    "zustand":                 "^4.5.5"
  },
  "devDependencies": {
    "@vitejs/plugin-react":         "^4.3.1",
    "vite":                         "^5.4.3",
    "typescript":                   "^5.5.3",
    "@types/react":                 "^18.3.5",
    "@types/react-dom":             "^18.3.0",
    "vitest":                       "^2.1.0",
    "@vitest/ui":                   "^2.1.0",
    "@testing-library/react":       "^16.0.0",
    "@testing-library/jest-dom":    "^6.5.0",
    "jsdom":                        "^25.0.0",
    "eslint":                       "^9.9.1",
    "@typescript-eslint/eslint-plugin": "^8.3.0",
    "@typescript-eslint/parser":    "^8.3.0",
    "eslint-plugin-react-hooks":    "^5.1.0",
    "eslint-plugin-react-refresh":  "^0.4.11"
  }
}
EOF

success "package.json を生成しました"

# ---------- 2. TypeScript 設定 ----------
section "2. TypeScript 設定の生成"

cat > tsconfig.json << 'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "isolatedModules": true,
    "moduleDetection": "force",
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "baseUrl": ".",
    "paths": {
      "@/*": ["src/*"]
    }
  },
  "include": ["src"]
}
EOF

success "tsconfig.json を生成しました"

# ---------- 3. vite.config.ts の生成 ----------
section "3. vite.config.ts の生成（APIプロキシ設定）"

cat > vite.config.ts << 'EOF'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    port: 3000,
    host: '0.0.0.0',   // サーバーからアクセスできるようにバインド
    proxy: {
      // バックエンドAPIへのプロキシ
      '/api': {
        target: 'http://localhost:8000',
        changeOrigin: true,
      },
      // WebSocketへのプロキシ
      '/ws': {
        target: 'ws://localhost:8000',
        ws: true,
      },
    },
  },
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
  },
})
EOF

success "vite.config.ts を生成しました"

# ---------- 4. 基本ソースファイルの生成 ----------
section "4. 基本ソースファイルの生成"

# index.html
cat > index.html << 'EOF'
<!doctype html>
<html lang="ja">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>decision-os</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
EOF

# src/main.tsx
cat > src/main.tsx << 'EOF'
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { BrowserRouter } from 'react-router-dom'
import App from './App'

const queryClient = new QueryClient()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <App />
      </BrowserRouter>
    </QueryClientProvider>
  </StrictMode>,
)
EOF

# src/App.tsx
cat > src/App.tsx << 'EOF'
import { Routes, Route } from 'react-router-dom'
import Dashboard from '@/pages/Dashboard'

export default function App() {
  return (
    <Routes>
      <Route path="/" element={<Dashboard />} />
    </Routes>
  )
}
EOF

# src/pages/Dashboard.tsx
mkdir -p src/pages
cat > src/pages/Dashboard.tsx << 'EOF'
import { useQuery } from '@tanstack/react-query'
import axios from 'axios'

async function fetchHealth() {
  const res = await axios.get('/api/v1/ping')
  return res.data
}

export default function Dashboard() {
  const { data, isLoading, isError } = useQuery({
    queryKey: ['health'],
    queryFn: fetchHealth,
  })

  return (
    <div style={{ padding: '2rem', fontFamily: 'sans-serif' }}>
      <h1>decision-os</h1>
      <p>開発判断OS - 意思決定管理システム</p>
      <hr />
      <h2>API接続確認</h2>
      {isLoading && <p>接続中...</p>}
      {isError  && <p style={{ color: 'red' }}>❌ バックエンドに接続できません（make be で起動してください）</p>}
      {data     && <p style={{ color: 'green' }}>✅ バックエンド接続OK: {JSON.stringify(data)}</p>}
    </div>
  )
}
EOF

# src/api/client.ts
cat > src/api/client.ts << 'EOF'
import axios from 'axios'

const apiClient = axios.create({
  baseURL: '/api/v1',
  headers: {
    'Content-Type': 'application/json',
  },
})

// リクエストインターセプター（JWTトークンを自動付与）
apiClient.interceptors.request.use((config) => {
  const token = localStorage.getItem('access_token')
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})

export default apiClient
EOF

# src/types/index.ts
cat > src/types/index.ts << 'EOF'
export interface Input {
  id: string
  source_type: 'email' | 'voice' | 'meeting' | 'bug' | 'other'
  raw_text: string
  author_id?: string
  created_at: string
}

export interface Item {
  id: string
  input_id: string
  text: string
  intent_code: string
  domain_code: string
  confidence: number
  position: number
}

export interface Action {
  id: string
  item_id: string
  type: 'CREATE_ISSUE' | 'ANSWER' | 'STORE' | 'REJECT' | 'HOLD' | 'LINK_EXISTING'
  status: string
  reason?: string
}

export interface Issue {
  id: string
  title: string
  status: 'open' | 'doing' | 'done'
  priority: number
  created_at: string
}
EOF

# テストセットアップ
mkdir -p src/test
cat > src/test/setup.ts << 'EOF'
import '@testing-library/jest-dom'
EOF

cat > src/test/App.test.tsx << 'EOF'
import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import App from '../App'

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: false } },
})

describe('App', () => {
  it('renders without crashing', () => {
    render(
      <QueryClientProvider client={queryClient}>
        <MemoryRouter>
          <App />
        </MemoryRouter>
      </QueryClientProvider>
    )
    expect(screen.getByText('decision-os')).toBeInTheDocument()
  })
})
EOF

success "ソースファイルを生成しました"

# ---------- 5. npm install ----------
section "5. 依存パッケージのインストール"

npm install
success "npm install 完了"

# ---------- 6. ビルド確認 ----------
section "6. TypeScript / ビルド確認"

npm run typecheck && success "型チェック OK"
npm run build     && success "ビルド OK"

# ---------- 完了メッセージ ----------
cd "$PROJECT_DIR"
section "Step 4 完了"
echo -e "${GREEN}"
echo "  ✔ package.json"
echo "  ✔ tsconfig.json"
echo "  ✔ vite.config.ts（プロキシ設定済み）"
echo "  ✔ src/main.tsx, App.tsx, pages/Dashboard.tsx"
echo "  ✔ src/api/client.ts"
echo "  ✔ src/types/index.ts"
echo "  ✔ テストファイル"
echo "  ✔ ビルド確認 OK"
echo -e "${RESET}"
echo -e "${YELLOW}【次のアクション】${RESET}"
echo -e "  bash ${BOLD}05_launch.sh${RESET}"
