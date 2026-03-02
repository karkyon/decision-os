/**
 * SearchPage.tsx — テナント横断検索ページ (/search)
 * URLクエリ ?q=keyword で直接アクセス可能
 */
import { useState, useEffect } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";

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

const TYPE_LABELS: Record<string, string> = {
  input:    "要望",
  item:     "ITEM",
  issue:    "課題",
  decision: "決定ログ",
};
const TYPE_COLORS: Record<string, string> = {
  input:    "border-l-blue-500 bg-blue-50 dark:bg-blue-900/20",
  item:     "border-l-purple-500 bg-purple-50 dark:bg-purple-900/20",
  issue:    "border-l-orange-500 bg-orange-50 dark:bg-orange-900/20",
  decision: "border-l-green-500 bg-green-50 dark:bg-green-900/20",
};
const TYPE_BADGE: Record<string, string> = {
  input:    "bg-blue-100 text-blue-700",
  item:     "bg-purple-100 text-purple-700",
  issue:    "bg-orange-100 text-orange-700",
  decision: "bg-green-100 text-green-700",
};

export default function SearchPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const [query, setQuery]     = useState(searchParams.get("q") || "");
  const [input, setInput]     = useState(searchParams.get("q") || "");
  const [filter, setFilter]   = useState(searchParams.get("type") || "");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [total, setTotal]     = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError]     = useState("");
  const navigate = useNavigate();

  const doSearch = (q: string, t: string) => {
    if (!q.trim()) return;
    const token = localStorage.getItem("access_token");
    if (!token) return;
    setLoading(true); setError("");
    const params = new URLSearchParams({ q, limit: "50" });
    if (t) params.set("type", t);
    fetch(`/api/v1/search?${params}`, {
      headers: { Authorization: `Bearer ${token}` },
    })
      .then((r) => r.json())
      .then((data) => { setResults(data.results || []); setTotal(data.total || 0); })
      .catch(() => setError("検索に失敗しました"))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    if (query) doSearch(query, filter);
  }, [query, filter]);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setQuery(input);
    setSearchParams({ q: input, ...(filter ? { type: filter } : {}) });
  };

  const navigateTo = (r: SearchResult) => {
    switch (r.type) {
      case "input":    navigate(`/inputs/${r.id}`); break;
      case "issue":    navigate(`/issues/${r.id}`); break;
      default:         navigate(`/inputs`); break;
    }
  };

  return (
    <div className="max-w-4xl mx-auto px-4 py-8">
      {/* 検索フォーム */}
      <form onSubmit={handleSubmit} className="flex gap-3 mb-6">
        <input
          type="text"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="キーワードを入力..."
          className="flex-1 px-4 py-3 text-base rounded-xl border border-gray-300 dark:border-gray-600
                     bg-white dark:bg-gray-800 text-gray-900 dark:text-white
                     focus:outline-none focus:ring-2 focus:ring-blue-500"
        />
        <button
          type="submit"
          className="px-6 py-3 bg-blue-600 text-white rounded-xl font-medium hover:bg-blue-700 transition-colors"
        >
          検索
        </button>
      </form>

      {/* タイプフィルタ */}
      <div className="flex gap-2 mb-6 flex-wrap">
        {[["", "すべて"], ["input","要望"], ["item","ITEM"], ["issue","課題"], ["decision","決定"]].map(([val, label]) => (
          <button
            key={val}
            onClick={() => { setFilter(val); if (query) doSearch(query, val); }}
            className={`px-4 py-1.5 rounded-full text-sm font-medium border transition-colors
              ${filter === val
                ? "bg-blue-600 text-white border-blue-600"
                : "bg-white dark:bg-gray-800 text-gray-600 dark:text-gray-300 border-gray-300 dark:border-gray-600 hover:border-blue-400"
              }`}
          >
            {label}
          </button>
        ))}
      </div>

      {/* 結果サマリ */}
      {query && !loading && (
        <p className="text-sm text-gray-500 mb-4">
          「<span className="font-medium text-gray-700 dark:text-gray-200">{query}</span>」
          の検索結果: <span className="font-semibold">{total}</span> 件
        </p>
      )}

      {/* ローディング */}
      {loading && (
        <div className="text-center py-12 text-gray-400">検索中...</div>
      )}

      {/* エラー */}
      {error && <div className="text-red-500 text-sm mb-4">{error}</div>}

      {/* 結果なし */}
      {!loading && !error && query && results.length === 0 && (
        <div className="text-center py-12 text-gray-400">
          「{query}」に一致する結果が見つかりませんでした
        </div>
      )}

      {/* 結果リスト */}
      <div className="space-y-3">
        {results.map((r) => (
          <button
            key={`${r.type}-${r.id}`}
            onClick={() => navigateTo(r)}
            className={`w-full text-left p-4 rounded-xl border-l-4 shadow-sm
                        hover:shadow-md transition-shadow cursor-pointer
                        ${TYPE_COLORS[r.type] || ""}`}
          >
            <div className="flex items-start gap-3">
              <span className={`flex-shrink-0 mt-0.5 text-xs font-medium px-2 py-0.5 rounded
                                ${TYPE_BADGE[r.type] || ""}`}>
                {TYPE_LABELS[r.type] || r.type}
              </span>
              <div className="flex-1 min-w-0">
                <p className="font-medium text-gray-900 dark:text-white">
                  {r.title || "(タイトルなし)"}
                </p>
                {r.snippet && (
                  <p className="text-sm text-gray-600 dark:text-gray-300 mt-1 line-clamp-2">
                    {r.snippet}
                  </p>
                )}
                <div className="flex items-center gap-3 mt-2 text-xs text-gray-400">
                  {r.project_name && <span>📁 {r.project_name}</span>}
                  {r.created_at   && <span>{r.created_at.slice(0, 10)}</span>}
                </div>
              </div>
            </div>
          </button>
        ))}
      </div>
    </div>
  );
}
