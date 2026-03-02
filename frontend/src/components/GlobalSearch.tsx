/**
 * GlobalSearch.tsx — W-003 テナント横断検索 UI
 *
 * ヘッダーの検索バーとして使用。
 * キーワード入力 → /api/v1/search?q=xxx → 結果をドロップダウン表示
 */
import { useState, useEffect, useRef, useCallback } from "react";
import { useNavigate } from "react-router-dom";

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

const TYPE_COLORS: Record<string, string> = {
  input:    "bg-blue-100 text-blue-700",
  item:     "bg-purple-100 text-purple-700",
  issue:    "bg-orange-100 text-orange-700",
  decision: "bg-green-100 text-green-700",
};

function useDebounce<T>(value: T, delay: number): T {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const t = setTimeout(() => setDebounced(value), delay);
    return () => clearTimeout(t);
  }, [value, delay]);
  return debounced;
}

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
    <div className="relative w-full max-w-md" style={{ zIndex: 50 }}>
      {/* 検索バー */}
      <div className="relative">
        <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 pointer-events-none">
          🔍
        </span>
        <input
          ref={inputRef}
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onFocus={() => results.length > 0 && setOpen(true)}
          onKeyDown={handleKeyDown}
          placeholder="テナント横断検索..."
          className="w-full pl-9 pr-4 py-2 text-sm rounded-lg border border-gray-300 dark:border-gray-600
                     bg-white dark:bg-gray-800 text-gray-900 dark:text-white
                     focus:outline-none focus:ring-2 focus:ring-blue-500"
          style={{ minWidth: "240px" }}
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
          className="absolute top-full left-0 mt-1 w-full bg-white dark:bg-gray-800
                     border border-gray-200 dark:border-gray-700 rounded-xl shadow-2xl
                     overflow-hidden"
          style={{ minWidth: "360px", maxHeight: "480px", overflowY: "auto" }}
        >
          {/* ヘッダー */}
          <div className="px-4 py-2 text-xs text-gray-500 dark:text-gray-400 border-b border-gray-100 dark:border-gray-700 bg-gray-50 dark:bg-gray-900">
            「{query}」の検索結果: {total} 件
          </div>

          {/* 結果リスト */}
          {results.map((r, i) => (
            <button
              key={`${r.type}-${r.id}`}
              onClick={() => navigateTo(r)}
              onMouseEnter={() => setSelected(i)}
              className={`w-full text-left px-4 py-3 border-b border-gray-100 dark:border-gray-700
                          last:border-0 transition-colors
                          ${i === selected ? "bg-blue-50 dark:bg-blue-900/30" : "hover:bg-gray-50 dark:hover:bg-gray-700"}`}
            >
              <div className="flex items-start gap-3">
                {/* タイプバッジ */}
                <span className={`flex-shrink-0 mt-0.5 text-xs font-medium px-1.5 py-0.5 rounded
                                  ${TYPE_COLORS[r.type] || "bg-gray-100 text-gray-600"}`}>
                  {TYPE_LABELS[r.type] || r.type}
                </span>
                <div className="flex-1 min-w-0">
                  {/* タイトル */}
                  <p className="text-sm font-medium text-gray-900 dark:text-white truncate">
                    {r.title || "(タイトルなし)"}
                  </p>
                  {/* スニペット */}
                  {r.snippet && r.snippet !== r.title && (
                    <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5 line-clamp-2">
                      {r.snippet}
                    </p>
                  )}
                  {/* プロジェクト名 */}
                  {r.project_name && (
                    <p className="text-xs text-blue-500 mt-1">
                      📁 {r.project_name}
                    </p>
                  )}
                </div>
              </div>
            </button>
          ))}

          {/* もっと見る */}
          {total > results.length && (
            <div className="px-4 py-2 text-xs text-center text-gray-400">
              他 {total - results.length} 件
            </div>
          )}
        </div>
      )}

      {/* 結果なし */}
      {open && !loading && results.length === 0 && debouncedQuery && (
        <div
          ref={dropRef}
          className="absolute top-full left-0 mt-1 w-full bg-white dark:bg-gray-800
                     border border-gray-200 dark:border-gray-700 rounded-xl shadow-xl
                     px-4 py-6 text-center text-sm text-gray-400"
        >
          「{debouncedQuery}」に一致する結果が見つかりません
        </div>
      )}
    </div>
  );
}
