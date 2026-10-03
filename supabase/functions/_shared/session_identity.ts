export type AppRole = "worker" | "engineer" | "admin";

export function sessionIdentity(
  username: string,
  issuedAt: number,
  user:
    | { role: string; status: string; password_changed_at: string | null }
    | null,
  nowSeconds = Date.now() / 1000,
): { username: string; role: AppRole } | null {
  if (
    !username || !Number.isFinite(issuedAt) || issuedAt <= 0 ||
    issuedAt > nowSeconds
  ) return null;
  if (!user || user.status !== "Active") return null;
  if (!["worker", "engineer", "admin"].includes(user.role)) return null;
  if (user.password_changed_at) {
    const changedAt = Date.parse(user.password_changed_at);
    if (!Number.isFinite(changedAt) || issuedAt * 1000 < changedAt) return null;
  }
  return { username, role: user.role as AppRole };
}

