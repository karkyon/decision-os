/**
 * LabelInput
 * オートコンプリート付きタグ入力コンポーネント
 *
 * 使用例:
 *   <LabelInput value={labels} onChange={setLabels} />
 *   value/onChange は string[] 形式
 */
import { useState, useRef, useEffect, useCallback } from "react";
import { labelApi } from "../api/client";

interface Props {
  value:      string[];
  onChange:   (labels: string[]) => void;
  projectId?: string;
  placeholder?: string;
  maxTags?:   number;
  disabled?:  boolean;
}

const TAG_COLORS = [
  { bg: "#1e3a5f", color: "#93c5fd", border: "#1d4ed8" },
  { bg: "#14532d", color: "#86efac", border: "#15803d" },
  { bg: "#4a1942", color: "#e879f9", border: "#7e22ce" },
  { bg: "#7c2d12", color: "#fdba74", border: "#c2410c" },
  { bg: "#1e293b", color: "#94a3b8", border: "#334155" },
];

function getTagColor(label: string) {
  let hash = 0;
  for (const c of label) hash = (hash * 31 + c.charCodeAt(0)) % TAG_COLORS.length;
  return TAG_COLORS[Math.abs(hash) % TAG_COLORS.length];
}

export default function LabelInput({
  value = [],
  onChange,
  projectId,
  placeholder = "タグを追加...",
  maxTags = 20,
  disabled = false,
}: Props) {
  const [input,       setInput]       = useState("");
  const [suggestions, setSuggestions] = useState<string[]>([]);
  const [showDrop,    setShowDrop]    = useState(false);
  const [activeIdx,   setActiveIdx]   = useState(-1);
  const inputRef = useRef<HTMLInputElement>(null);
  const dropRef  = useRef<HTMLDivElement>(null);

  // オートコンプリート取得
  useEffect(() => {
    if (input.trim().length === 0) { setSuggestions([]); return; }
    const timer = setTimeout(async () => {
      try {
        const res = await labelApi.suggest(input.trim(), projectId);
        const all: string[] = res.data.suggestions || [];
        // 既存タグを除外
        setSuggestions(all.filter(s => !value.includes(s)));
        setShowDrop(true);
      } catch { setSuggestions([]); }
    }, 200);
    return () => clearTimeout(timer);
  }, [input, projectId]);

  const addTag = useCallback((tag: string) => {
    const t = tag.trim();
    if (!t || value.includes(t) || value.length >= maxTags) return;
    onChange([...value, t]);
    setInput("");
    setSuggestions([]);
    setShowDrop(false);
    setActiveIdx(-1);
    inputRef.current?.focus();
  }, [value, onChange, maxTags]);

  const removeTag = useCallback((tag: string) => {
    onChange(value.filter(v => v !== tag));
  }, [value, onChange]);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" || e.key === "," || e.key === " ") {
      e.preventDefault();
      if (activeIdx >= 0 && suggestions[activeIdx]) {
        addTag(suggestions[activeIdx]);
      } else if (input.trim()) {
        addTag(input.trim());
      }
    } else if (e.key === "ArrowDown") {
      e.preventDefault();
      setActiveIdx(i => Math.min(i + 1, suggestions.length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setActiveIdx(i => Math.max(i - 1, -1));
    } else if (e.key === "Escape") {
      setShowDrop(false);
    } else if (e.key === "Backspace" && input === "" && value.length > 0) {
      removeTag(value[value.length - 1]);
    }
  };

  // 外クリックで閉じる
  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (dropRef.current && !dropRef.current.contains(e.target as Node) &&
          inputRef.current && !inputRef.current.contains(e.target as Node)) {
        setShowDrop(false);
      }
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, []);

  return (
    <div style={{ position: "relative" }}>
      {/* タグ + 入力欄 */}
      <div
        onClick={() => !disabled && inputRef.current?.focus()}
        style={{
          display: "flex", flexWrap: "wrap", gap: "6px", alignItems: "center",
          padding: "8px 10px", borderRadius: "8px",
          background: "#0f172a", border: "1px solid #334155",
          minHeight: "40px", cursor: disabled ? "default" : "text",
        }}
      >
        {value.map(tag => {
          const c = getTagColor(tag);
          return (
            <span key={tag} style={{
              display: "inline-flex", alignItems: "center", gap: "4px",
              padding: "2px 8px", borderRadius: "20px",
              background: c.bg, color: c.color,
              border: `1px solid ${c.border}`,
              fontSize: "12px", fontWeight: "500",
            }}>
              {tag}
              {!disabled && (
                <button
                  type="button"
                  onClick={e => { e.stopPropagation(); removeTag(tag); }}
                  style={{
                    background: "none", border: "none", cursor: "pointer",
                    color: c.color, padding: "0", lineHeight: 1, fontSize: "13px",
                    opacity: 0.7,
                  }}
                >×</button>
              )}
            </span>
          );
        })}
        {!disabled && value.length < maxTags && (
          <input
            ref={inputRef}
            value={input}
            onChange={e => { setInput(e.target.value); setShowDrop(true); }}
            onKeyDown={handleKeyDown}
            onFocus={() => input.trim() && setShowDrop(true)}
            placeholder={value.length === 0 ? placeholder : ""}
            style={{
              background: "none", border: "none", outline: "none",
              color: "#e2e8f0", fontSize: "13px",
              flex: "1", minWidth: "80px",
            }}
          />
        )}
      </div>

      {/* ヒント */}
      {!disabled && (
        <div style={{ fontSize: "11px", color: "#475569", marginTop: "4px" }}>
          Enter / カンマ / スペースで追加　Backspaceで最後のタグを削除
        </div>
      )}

      {/* サジェストドロップダウン */}
      {showDrop && suggestions.length > 0 && (
        <div ref={dropRef} style={{
          position: "absolute", top: "calc(100% + 4px)", left: 0, right: 0,
          background: "#0f172a", border: "1px solid #334155",
          borderRadius: "8px", zIndex: 100,
          boxShadow: "0 4px 16px rgba(0,0,0,0.4)",
          maxHeight: "200px", overflowY: "auto",
        }}>
          {suggestions.map((s, i) => {
            const c = getTagColor(s);
            return (
              <div
                key={s}
                onMouseDown={() => addTag(s)}
                style={{
                  padding: "8px 12px", cursor: "pointer",
                  background: i === activeIdx ? "#1e293b" : "transparent",
                  display: "flex", alignItems: "center", gap: "8px",
                  fontSize: "13px", color: "#e2e8f0",
                }}
                onMouseEnter={() => setActiveIdx(i)}
              >
                <span style={{
                  padding: "1px 8px", borderRadius: "20px",
                  background: c.bg, color: c.color, border: `1px solid ${c.border}`,
                  fontSize: "11px",
                }}>{s}</span>
              </div>
            );
          })}
          {/* 新規作成 */}
          {input.trim() && !suggestions.includes(input.trim()) && (
            <div
              onMouseDown={() => addTag(input.trim())}
              style={{
                padding: "8px 12px", cursor: "pointer",
                borderTop: "1px solid #1e293b",
                color: "#64748b", fontSize: "13px",
              }}
            >
              ＋ 「{input.trim()}」を新規作成
            </div>
          )}
        </div>
      )}
    </div>
  );
}
