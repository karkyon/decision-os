/**
 * UserManagement - ユーザー管理画面（Admin専用）
 * - ユーザー一覧表示
 * - ロール変更
 * - 権限マトリクス表示
 */
import React, { useEffect, useState } from "react";
import { usePermission } from "../hooks/usePermission";
import { RoleBadge } from "../components/RoleBadge";
import { api } from "../api/client";

interface User {
  id: string;
  email: string;
  role: string;
  created_at?: string;
}

const ROLES = ["admin", "pm", "dev", "viewer"] as const;

const PERMISSION_MATRIX = [
  { action: "Input登録",    admin: true, pm: true,  dev: true,  viewer: false },
  { action: "分類変更",     admin: true, pm: true,  dev: false, viewer: false },
  { action: "Action変更",   admin: true, pm: true,  dev: false, viewer: false },
  { action: "Issue作成",    admin: true, pm: true,  dev: true,  viewer: false },
  { action: "Issue削除",    admin: true, pm: false, dev: false, viewer: false },
  { action: "コメント投稿", admin: true, pm: true,  dev: true,  viewer: false },
  { action: "ラベル管理",   admin: true, pm: true,  dev: false, viewer: false },
  { action: "辞書編集",     admin: true, pm: false, dev: false, viewer: false },
  { action: "ロール変更",   admin: true, pm: false, dev: false, viewer: false },
  { action: "閲覧",         admin: true, pm: true,  dev: true,  viewer: true  },
];

export const UserManagement: React.FC = () => {
  const { isAdmin } = usePermission();
  const [users, setUsers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);
  const [updating, setUpdating] = useState<string | null>(null);
  const [msg, setMsg] = useState<{ type: "ok" | "err"; text: string } | null>(null);

  useEffect(() => {
    if (!isAdmin) return;
    fetchUsers();
  }, [isAdmin]);

  const fetchUsers = async () => {
    try {
      const res = await api.get("/users");
      setUsers(res.data);
    } catch {
      setMsg({ type: "err", text: "ユーザー一覧の取得に失敗しました" });
    } finally {
      setLoading(false);
    }
  };

  const handleRoleChange = async (userId: string, newRole: string) => {
    setUpdating(userId);
    setMsg(null);
    try {
      await api.patch(`/users/${userId}/role`, { role: newRole });
      setUsers(prev => prev.map(u => u.id === userId ? { ...u, role: newRole } : u));
      setMsg({ type: "ok", text: "ロールを変更しました" });
    } catch (e: any) {
      setMsg({ type: "err", text: e.response?.data?.detail ?? "変更に失敗しました" });
    } finally {
      setUpdating(null);
    }
  };

  // Admin 以外は非表示
  if (!isAdmin) {
    return (
      <div className="p-8 text-center">
        <div className="text-4xl mb-3">🔒</div>
        <h2 className="text-lg font-semibold text-gray-700">アクセス権限がありません</h2>
        <p className="text-gray-500 mt-1">この画面は Admin のみ表示できます。</p>
      </div>
    );
  }

  return (
    <div className="max-w-5xl mx-auto p-6 space-y-8">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">👥 ユーザー管理</h1>
          <p className="text-sm text-gray-500 mt-1">Admin専用 — ロールの確認・変更</p>
        </div>
      </div>

      {/* メッセージ */}
      {msg && (
        <div className={`rounded-lg px-4 py-3 text-sm font-medium ${
          msg.type === "ok"
            ? "bg-green-50 text-green-700 border border-green-200"
            : "bg-red-50 text-red-700 border border-red-200"
        }`}>
          {msg.type === "ok" ? "✅ " : "❌ "}{msg.text}
        </div>
      )}

      {/* ユーザー一覧 */}
      <div className="bg-white border border-gray-200 rounded-xl overflow-hidden shadow-sm">
        <div className="px-6 py-4 border-b border-gray-100 bg-gray-50">
          <h2 className="font-semibold text-gray-700">ユーザー一覧</h2>
        </div>
        {loading ? (
          <div className="p-8 text-center text-gray-400">読み込み中...</div>
        ) : users.length === 0 ? (
          <div className="p-8 text-center text-gray-400">ユーザーが見つかりません</div>
        ) : (
          <table className="w-full">
            <thead>
              <tr className="text-xs text-gray-500 border-b border-gray-100 bg-gray-50">
                <th className="px-6 py-3 text-left font-medium">メールアドレス</th>
                <th className="px-6 py-3 text-left font-medium">現在のロール</th>
                <th className="px-6 py-3 text-left font-medium">ロール変更</th>
                <th className="px-6 py-3 text-left font-medium">登録日</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-50">
              {users.map(user => (
                <tr key={user.id} className="hover:bg-gray-50 transition-colors">
                  <td className="px-6 py-4 text-sm text-gray-900">{user.email}</td>
                  <td className="px-6 py-4">
                    <RoleBadge role={user.role} />
                  </td>
                  <td className="px-6 py-4">
                    <div className="flex gap-1.5">
                      {ROLES.map(r => (
                        <button
                          key={r}
                          disabled={user.role === r || updating === user.id}
                          onClick={() => handleRoleChange(user.id, r)}
                          className={`text-xs px-2.5 py-1 rounded-full border font-medium transition-colors ${
                            user.role === r
                              ? "bg-gray-100 text-gray-400 border-gray-200 cursor-default"
                              : "bg-white hover:bg-blue-50 text-gray-600 hover:text-blue-700 border-gray-300 hover:border-blue-300 cursor-pointer"
                          } disabled:opacity-50`}
                        >
                          {r}
                        </button>
                      ))}
                    </div>
                  </td>
                  <td className="px-6 py-4 text-sm text-gray-400">
                    {user.created_at
                      ? new Date(user.created_at).toLocaleDateString("ja-JP")
                      : "—"}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* 権限マトリクス */}
      <div className="bg-white border border-gray-200 rounded-xl overflow-hidden shadow-sm">
        <div className="px-6 py-4 border-b border-gray-100 bg-gray-50">
          <h2 className="font-semibold text-gray-700">権限マトリクス</h2>
          <p className="text-xs text-gray-500 mt-0.5">各ロールが実行できる操作の一覧</p>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="text-xs border-b border-gray-100 bg-gray-50">
                <th className="px-6 py-3 text-left text-gray-500 font-medium">操作</th>
                {ROLES.map(r => (
                  <th key={r} className="px-4 py-3 text-center">
                    <RoleBadge role={r} size="sm" />
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-50">
              {PERMISSION_MATRIX.map(row => (
                <tr key={row.action} className="hover:bg-gray-50">
                  <td className="px-6 py-3 text-sm text-gray-700">{row.action}</td>
                  {ROLES.map(r => (
                    <td key={r} className="px-4 py-3 text-center text-base">
                      {row[r] ? "✅" : "—"}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};

export default UserManagement;
