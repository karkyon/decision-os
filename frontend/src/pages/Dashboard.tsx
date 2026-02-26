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
