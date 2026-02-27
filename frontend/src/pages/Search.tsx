import { useState, useEffect, useCallback, useRef } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import Layout from "../components/Layout";
import { searchApi } from "../api/client";

type HitType = "issue" | "input" | "item" | "conversation";

interface SearchHit {
  id: string;
  type: HitType;
  title: string;
  body: string;
  url: string;
  meta: Record<string, any>;
  created_at: string;
}

interface SearchResponse {
  query: string;
  total: number;
  hits: SearchHit[];
  duration_ms: number;
}

const TYPE_CONFIG: Record<HitType, { icon: string; label: string; color: string }> = {
  issue:        { icon: "📋", label: "課題",     color: "#3b82f6" },
  input:        { icon: "📥", label: "原文",     color: "#8b5cf6" },
  item:         { icon: "🧩", label: "ITEM",     color: "#f59e0b" },
  conversation: { icon: "💬", label: "コメント", color: "#22c55e" },
};

const TYPE_FILTERS: { key: string; label: string }[] = [
  { key: "",             label: "すべて" },
  { key: "issue",        label: "📋 課題" },
  { key: "input",        label: "📥 原文" },
  { key: "item",         label: "🧩 ITEM" },
  { key: "conversation", label: "💬 コメント" },
];

// キーワードをハイライト表示するコンポーネント
function Highlight({ text, query }: { text: string; query: string }) {
  if (!query.trim()) return <>{text}</>;
  const keywords = query.trim().split(/\s+/).filter(Boolean);
  const pattern = new RegExp(`(${keywords.map(k => k.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join("|")})`, "gi");
  const parts = text.split(pattern);
  return (
    <>
      {parts.map((part, i) =>
        pattern.test(part)
          ? <mark key={i} style={{ background: "#fef08a", color: "#1e293b", borderRadius: "2px", padding: "0 1px" }}>{part}</mark>
          : <span key={i}>{part}</span>
      )}
    </>
  );
}

export default function Search() {
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const initialQ = searchParams.get("q") || "";
  const initialType = searchParams.get("type") || "";

  const [query, setQuery] = useState(initialQ);
  const [typeFilter, setTypeFilter] = useState(initialType);
  const [result, setResult] = useState<SearchResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);

  const doSearch = useCallback(async (q: string, t: string) => {
    if (!q.trim()) { setResult(null); return; }
    setLoading(true); setError("");
    try {
      const params: any = { q: q.trim(), limit: 50 };
      if (t) params.type = t;
      const res = await searchApi.search(params);
      setResult(res.data);
      setSearchParams({ q: q.trim(), ...(t ? { type: t } : {}) });
    } catch (e: any) {
      setError(e.response?.data?.detail || "検索に失敗しました");
    } finally { setLoading(false); }
  }, [setSearchParams]);

  // URLパラメータからの初期検索
  useEffect(() => {
    if (initialQ) doSearch(initialQ, initialType);
    inputRef.current?.focus();
  }, []); // eslint-disable-line

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    doSearch(query, typeFilter);
  };

  const handleTypeChange = (t: string) => {
    setTypeFilter(t);
    if (query.trim()) doSearch(query, t);
  };

  // タイプ別にグループ化するかどうか（"すべて"の場合のみグループ表示）
  const grouped = !typeFilter && result && result.hits.length > 0;

  const groupedHits: Record<string, SearchHit[]> = {};
  if (grouped) {
    for (const hit of result!.hits) {
      if (!groupedHits[hit.type]) groupedHits[hit.type] = [];
      groupedHits[hit.type].push(hit);
    }
  }

  return (
    <Layout>
      {/* 検索バー */}
      <div style={{ marginBottom: "24px" }}>
        <h1 style={{ margin: "0 0 16px", fontSize: "20px" }}>🔍 横断検索</h1>
        <form onSubmit={handleSubmit} style={{ display: "flex", gap: "8px" }}>
          <input
            ref={inputRef}
            value={query}
            onChange={e => setQuery(e.target.value)}
            placeholder="課題・原文・ITEM・コメントを横断検索… (スペースで AND 検索)"
            style={{
              flex: 1, padding: "12px 16px", borderRadius: "10px",
              background: "#1e293b", border: "1px solid #334155",
              color: "#e2e8f0", fontSize: "15px", outline: "none",
            }}
            onFocus={e => (e.target.style.borderColor = "#3b82f6")}
            onBlur={e => (e.target.style.borderColor = "#334155")}
          />
          <button
            type="submit"
            disabled={loading || !query.trim()}
            style={{
              padding: "12px 28px", borderRadius: "10px", border: "none",
              background: loading || !query.trim() ? "#334155" : "#3b82f6",
              color: "#fff", cursor: loading || !query.trim() ? "not-allowed" : "pointer",
              fontSize: "15px", fontWeight: "600", flexShrink: 0,
            }}
          >
            {loading ? "🔄" : "検索"}
          </button>
        </form>

        {/* タイプフィルター */}
        <div style={{ display: "flex", gap: "6px", marginTop: "12px", flexWrap: "wrap" }}>
          {TYPE_FILTERS.map(f => (
            <button
              key={f.key}
              onClick={() => handleTypeChange(f.key)}
              style={{
                padding: "5px 14px", borderRadius: "20px", border: "none",
                cursor: "pointer", fontSize: "13px",
                background: typeFilter === f.key ? "#3b82f6" : "#1e293b",
                color: typeFilter === f.key ? "#fff" : "#94a3b8",
                fontWeight: typeFilter === f.key ? "600" : "400",
              }}
            >
              {f.label}
            </button>
          ))}
        </div>
      </div>

      {/* エラー */}
      {error && (
        <div style={{
          background: "#fef2f2", border: "1px solid #fca5a5", borderRadius: "8px",
          padding: "10px 16px", marginBottom: "16px", color: "#dc2626", fontSize: "13px",
        }}>⚠️ {error}</div>
      )}

      {/* ローディング */}
      {loading && (
        <div style={{ textAlign: "center", padding: "60px", color: "#64748b" }}>
          <div style={{ fontSize: "32px", marginBottom: "12px" }}>🔄</div>
          検索中...
        </div>
      )}

      {/* 初期状態 */}
      {!loading && !result && !error && (
        <div style={{ textAlign: "center", padding: "80px", color: "#475569" }}>
          <div style={{ fontSize: "48px", marginBottom: "16px" }}>🔍</div>
          <p style={{ margin: 0, fontSize: "16px" }}>キーワードを入力して検索</p>
          <p style={{ margin: "8px 0 0", fontSize: "13px", color: "#334155" }}>
            課題・原文（RAW_INPUT）・分解ITEM・コメントを一括検索できます
          </p>
        </div>
      )}

      {/* 検索結果 */}
      {!loading && result && (
        <>
          {/* サマリー */}
          <div style={{
            display: "flex", justifyContent: "space-between", alignItems: "center",
            marginBottom: "16px", padding: "10px 16px",
            background: "#1e293b", borderRadius: "8px",
          }}>
            <span style={{ color: "#e2e8f0", fontSize: "14px" }}>
              <strong style={{ color: "#3b82f6" }}>{result.total}</strong> 件ヒット
              {result.total > 0 && (
                <span style={{ color: "#64748b", marginLeft: "8px" }}>
                  — {TYPE_FILTERS.slice(1).map(f => {
                    const count = result.hits.filter(h => h.type === f.key).length;
                    return count > 0 ? `${f.label} ${count}件` : null;
                  }).filter(Boolean).join("  ")}
                </span>
              )}
            </span>
            <span style={{ color: "#475569", fontSize: "12px" }}>{result.duration_ms}ms</span>
          </div>

          {/* 結果なし */}
          {result.total === 0 && (
            <div style={{ textAlign: "center", padding: "60px", color: "#64748b" }}>
              <div style={{ fontSize: "40px", marginBottom: "12px" }}>😶</div>
              <p style={{ margin: 0 }}>「{result.query}」に一致する結果がありませんでした</p>
              <p style={{ margin: "8px 0 0", fontSize: "13px", color: "#334155" }}>
                別のキーワードや、スペース区切りの AND 検索をお試しください
              </p>
            </div>
          )}

          {/* グループ表示（すべて） */}
          {grouped && Object.entries(groupedHits).map(([type, hits]) => (
            <div key={type} style={{ marginBottom: "28px" }}>
              <div style={{
                display: "flex", alignItems: "center", gap: "8px",
                marginBottom: "10px", paddingBottom: "6px",
                borderBottom: `2px solid ${TYPE_CONFIG[type as HitType].color}33`,
              }}>
                <span style={{ fontSize: "16px" }}>{TYPE_CONFIG[type as HitType].icon}</span>
                <span style={{
                  fontSize: "14px", fontWeight: "700",
                  color: TYPE_CONFIG[type as HitType].color,
                }}>
                  {TYPE_CONFIG[type as HitType].label}
                </span>
                <span style={{ fontSize: "12px", color: "#64748b" }}>({hits.length}件)</span>
              </div>
              <HitList hits={hits} query={result.query} navigate={navigate} />
            </div>
          ))}

          {/* フラット表示（type絞り込み時） */}
          {!grouped && result.total > 0 && (
            <HitList hits={result.hits} query={result.query} navigate={navigate} />
          )}
        </>
      )}
    </Layout>
  );
}

function HitList({ hits, query, navigate }: {
  hits: SearchHit[];
  query: string;
  navigate: (url: string) => void;
}) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "8px" }}>
      {hits.map(hit => {
        const cfg = TYPE_CONFIG[hit.type];
        return (
          <div
            key={`${hit.type}-${hit.id}`}
            onClick={() => navigate(hit.url)}
            style={{
              background: "#1e293b", borderRadius: "10px",
              padding: "14px 18px", cursor: "pointer",
              border: "1px solid #334155",
              transition: "border-color 0.15s, background 0.15s",
            }}
            onMouseEnter={e => {
              (e.currentTarget as HTMLDivElement).style.borderColor = cfg.color;
              (e.currentTarget as HTMLDivElement).style.background = "#243044";
            }}
            onMouseLeave={e => {
              (e.currentTarget as HTMLDivElement).style.borderColor = "#334155";
              (e.currentTarget as HTMLDivElement).style.background = "#1e293b";
            }}
          >
            <div style={{ display: "flex", alignItems: "flex-start", gap: "10px" }}>
              {/* タイプバッジ */}
              <span style={{
                padding: "2px 8px", borderRadius: "4px", fontSize: "11px",
                fontWeight: "600", flexShrink: 0, marginTop: "2px",
                background: cfg.color + "22", color: cfg.color,
                border: `1px solid ${cfg.color}44`,
              }}>
                {cfg.icon} {cfg.label}
              </span>

              <div style={{ flex: 1, minWidth: 0 }}>
                {/* タイトル */}
                <p style={{
                  margin: "0 0 4px", fontSize: "14px", fontWeight: "600",
                  color: "#e2e8f0", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis",
                }}>
                  <Highlight text={hit.title} query={query} />
                </p>

                {/* 本文スニペット */}
                {hit.body && (
                  <p style={{
                    margin: "0 0 6px", fontSize: "13px", color: "#94a3b8", lineHeight: 1.5,
                  }}>
                    <Highlight text={hit.body} query={query} />
                  </p>
                )}

                {/* メタ情報 */}
                <div style={{ display: "flex", gap: "8px", flexWrap: "wrap" }}>
                  {hit.type === "issue" && (
                    <>
                      <MetaBadge>{hit.meta.status}</MetaBadge>
                      <MetaBadge>{hit.meta.priority}</MetaBadge>
                      {hit.meta.labels && <MetaBadge>{hit.meta.labels}</MetaBadge>}
                    </>
                  )}
                  {hit.type === "item" && (
                    <>
                      <MetaBadge>{hit.meta.intent_code}</MetaBadge>
                      <MetaBadge>{hit.meta.domain_code}</MetaBadge>
                      {hit.meta.confidence && (
                        <MetaBadge>{Math.round(hit.meta.confidence * 100)}%</MetaBadge>
                      )}
                    </>
                  )}
                  {hit.type === "input" && <MetaBadge>{hit.meta.source_type}</MetaBadge>}
                  <span style={{ fontSize: "11px", color: "#475569", marginLeft: "auto" }}>
                    {new Date(hit.created_at).toLocaleDateString("ja-JP")}
                  </span>
                </div>
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

function MetaBadge({ children }: { children: React.ReactNode }) {
  return (
    <span style={{
      padding: "1px 7px", borderRadius: "4px", fontSize: "11px",
      background: "#0f172a", color: "#64748b", border: "1px solid #1e293b",
    }}>
      {children}
    </span>
  );
}
