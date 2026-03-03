/**
 * GlobalSearch.tsx — W-003 テナント横断検索 UI
 *
 * ヘッダーの検索バーとして使用。
 * キーワード入力 → /api/v1/search?q=xxx → 結果をドロップダウン表示
 */
import { useState, useEffect, useRef } from "react";
import { useNavigate } from "react-router-dom";

function useDebounce<T>(value: T, delay: number): T {
  const [debounced, setDebounced] = useState<T>(value)
  useEffect(() => {
    const t = setTimeout(() => setDebounced(value), delay)
    return () => clearTimeout(t)
  }, [value, delay])
  return debounced
}

interface SearchResult {
  type: "input" | "item" | "issue" | "decision";
  id: string;
  project_id: string | null;
  project_name: string;
  title: string;
  snippet: string;
  score: number;
  created_at: string | null;
}

interface SearchResponse {
  total: number;
  keyword: string;
  results: SearchResult[];
}

const TYPE_LABELS: Record<string, string> = {
  input:    "要望",
  item:     "ITEM",
  issue:    "課題",
  decision: "決定",
};


export default function GlobalSearch() {
  const [query, setQuery]       = useState("");
  const [results, setResults]   = useState<SearchResult[]>([]);
  const [total, setTotal]       = useState(0);
  const [loading, setLoading]   = useState(false);
  const [open, setOpen]         = useState(false);
  const [selected, setSelected] = useState(-1);
  const inputRef = useRef<HTMLInputElement>(null);
  const dropRef  = useRef<HTMLDivElement>(null);
  const navigate = useNavigate();

  const debouncedQuery = useDebounce(query, 300);

  // 検索実行
  useEffect(() => {
    if (!debouncedQuery.trim()) {
      setResults([]); setTotal(0); setOpen(false); return;
    }
    const token = localStorage.getItem("access_token");
    if (!token) return;

    setLoading(true);
    fetch(`/api/v1/search?q=${encodeURIComponent(debouncedQuery)}&limit=10`, {
      headers: { Authorization: `Bearer ${token}` },
    })
      .then((r) => r.json())
      .then((data: SearchResponse) => {
        setResults(data.results || []);
        setTotal(data.total || 0);
        setOpen(true);
        setSelected(-1);
      })
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [debouncedQuery]);

  // 外クリックで閉じる
  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (
        dropRef.current && !dropRef.current.contains(e.target as Node) &&
        inputRef.current && !inputRef.current.contains(e.target as Node)
      ) {
        setOpen(false);
      }
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, []);

  // キーボードナビゲーション
  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (!open) return;
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setSelected((s) => Math.min(s + 1, results.length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setSelected((s) => Math.max(s - 1, -1));
    } else if (e.key === "Enter" && selected >= 0) {
      e.preventDefault();
      navigateTo(results[selected]);
    } else if (e.key === "Escape") {
      setOpen(false);
    }
  };

  const navigateTo = (result: SearchResult) => {
    setOpen(false);
    setQuery("");
    switch (result.type) {
      case "input":    navigate(`/inputs/${result.id}`); break;
      case "item":     navigate(`/inputs`); break;
      case "issue":    navigate(`/issues/${result.id}`); break;
      case "decision": navigate(`/decisions`); break;
    }
  };

  return (
    <div style={{ position:"relative", width:"100%", maxWidth:"480px", zIndex:50 }}>
      {/* 検索バー */}
      <div style={{ position:"relative" }}>
        <span style={{
          position: "absolute", left: "10px", top: "50%", transform: "translateY(-50%)",
          color: "var(--text-muted)", pointerEvents: "none", fontSize: "14px", lineHeight: 1,
        }}>🔍</span>
        <input
          ref={inputRef}
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="テナント横断検索..."
          style={{
            width: "100%", minWidth: "240px",
            paddingLeft: "36px", paddingRight: "16px",
            paddingTop: "7px", paddingBottom: "7px",
            fontSize: "13px", borderRadius: "8px",
            border: "1px solid var(--border)",
            background: "var(--bg-input)",
            color: "var(--text-primary)",
            outline: "none",
          }}
          onFocus={e => { e.currentTarget.style.borderColor = "var(--accent)"; e.currentTarget.style.boxShadow = "0 0 0 3px var(--accent-light)"; if (results.length > 0) setOpen(true); }}
          onBlur={e => { e.currentTarget.style.borderColor = "var(--border)"; e.currentTarget.style.boxShadow = "none"; }}
        />
        {loading && (
          <span className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 text-xs">
            ...
          </span>
        )}
      </div>

      {/* ドロップダウン */}
      {open && results.length > 0 && (
        <div
          ref={dropRef}
          style={{
            position: "absolute", top: "100%", left: 0, marginTop: "4px",
            width: "100%", minWidth: "360px", maxHeight: "480px", overflowY: "auto",
            background: "var(--bg-surface)", border: "1px solid var(--border)",
            borderRadius: "12px", boxShadow: "var(--shadow-lg)", zIndex: 9999,
          }}
        >
          {/* ヘッダー */}
          <div style={{ padding: "8px 16px", fontSize: "12px", color: "var(--text-muted)", borderBottom: "1px solid var(--border)", background: "var(--bg-muted)" }}>
            「{query}」の検索結果: {total} 件
          </div>

          {/* 結果リスト */}
          {results.map((r, i) => (
            <button
              key={`${r.type}-${r.id}`}
              onClick={() => navigateTo(r)}
              onMouseEnter={() => setSelected(i)}
              style={{
                width: "100%", textAlign: "left", padding: "10px 16px",
                borderBottom: "1px solid var(--border)", background: i === selected ? "var(--accent-light)" : "transparent",
                border: "none", cursor: "pointer", transition: "background 0.1s",
              }}
              onMouseLeave={e => (e.currentTarget as HTMLButtonElement).style.background = i === selected ? "var(--accent-light)" : "transparent"}
            >
              <div className="flex items-start gap-3">
                {/* タイプバッジ */}
                <span style={{
                  flexShrink: 0, fontSize: "11px", fontWeight: 600,
                  padding: "2px 6px", borderRadius: "4px",
                  background: r.type === "input" ? "rgba(59,130,246,0.12)" : r.type === "item" ? "rgba(139,92,246,0.12)" : r.type === "issue" ? "rgba(249,115,22,0.12)" : "rgba(34,197,94,0.12)",
                  color: r.type === "input" ? "#3b82f6" : r.type === "item" ? "#8b5cf6" : r.type === "issue" ? "#f97316" : "#22c55e",
                }}>
                  {TYPE_LABELS[r.type] || r.type}
                </span>
                <div className="flex-1 min-w-0">
                  {/* タイトル */}
                  <p style={{ fontSize:"13px", fontWeight:600, color:"var(--text-primary)", overflow:"hidden", textOverflow:"ellipsis", whiteSpace:"nowrap", margin:0 }}>
                    {r.title || "(タイトルなし)"}
                  </p>
                  {/* スニペット */}
                  {r.snippet && r.snippet !== r.title && (
                    <p style={{ fontSize:"12px", color:"var(--text-muted)", marginTop:"3px", overflow:"hidden", display:"-webkit-box", WebkitLineClamp:2, WebkitBoxOrient:"vertical" as any, margin:"3px 0 0" }}>
                      {r.snippet}
                    </p>
                  )}
                  {/* プロジェクト名 */}
                  {r.project_name && (
                    <p style={{ fontSize:"11px", color:"var(--accent)", marginTop:"4px", margin:"4px 0 0" }}>
                      📁 {r.project_name}
                    </p>
                  )}
                </div>
              </div>
            </button>
          ))}

          {/* もっと見る */}
          {total > results.length && (
            <div style={{ padding:"8px 16px", fontSize:"12px", textAlign:"center", color:"var(--text-muted)" }}>
              他 {total - results.length} 件
            </div>
          )}
        </div>
      )}

      {/* 結果なし */}
      {open && !loading && results.length === 0 && debouncedQuery && (
        <div
          ref={dropRef}
          style={{
            position:"absolute", top:"100%", left:0, marginTop:"4px",
            width:"100%", minWidth:"300px",
            background:"var(--bg-surface)", border:"1px solid var(--border)",
            borderRadius:"12px", boxShadow:"var(--shadow-lg)", zIndex:9999,
            padding:"24px 16px", textAlign:"center", fontSize:"13px", color:"var(--text-muted)",
          }}
        >
          「{debouncedQuery}」に一致する結果が見つかりません
        </div>
      )}
    </div>
  );
}
