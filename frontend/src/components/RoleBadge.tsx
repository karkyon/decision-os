/**
 * RoleBadge - ロール表示バッジ
 */
import React from "react";

type Role = "admin" | "pm" | "dev" | "viewer";

const ROLE_CONFIG: Record<Role, { label: string; color: string; icon: string }> = {
  admin: { label: "Admin", color: "bg-red-100 text-red-700 border-red-200", icon: "🔴" },
  pm:    { label: "PM",    color: "bg-purple-100 text-purple-700 border-purple-200", icon: "🟣" },
  dev:   { label: "Dev",   color: "bg-blue-100 text-blue-700 border-blue-200", icon: "🔵" },
  viewer:{ label: "Viewer",color: "bg-gray-100 text-gray-600 border-gray-200", icon: "⚪" },
};

interface Props {
  role: string;
  showIcon?: boolean;
  size?: "sm" | "md";
}

export const RoleBadge: React.FC<Props> = ({ role, showIcon = true, size = "sm" }) => {
  const config = ROLE_CONFIG[role as Role] ?? ROLE_CONFIG.viewer;
  const sizeClass = size === "sm" ? "text-xs px-1.5 py-0.5" : "text-sm px-2 py-1";

  return (
    <span className={`inline-flex items-center gap-0.5 rounded border font-medium ${config.color} ${sizeClass}`}>
      {showIcon && <span>{config.icon}</span>}
      {config.label}
    </span>
  );
};
