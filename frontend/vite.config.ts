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
    port: 3008,
    host: '0.0.0.0',   // サーバーからアクセスできるようにバインド
    proxy: {
      // バックエンドAPIへのプロキシ
      '/api': {
        target: 'http://localhost:8089',
        changeOrigin: true,
      },
      // WebSocketへのプロキシ
      '/ws': {
        target: 'ws://localhost:8089',
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
