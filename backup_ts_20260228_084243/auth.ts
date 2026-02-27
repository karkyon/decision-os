export const authStore = {
  getToken: () => localStorage.getItem("token"),
  setToken: (token: string) => localStorage.setItem("token", token),
  getUser: () => {
    const u = localStorage.getItem("user");
    return u ? JSON.parse(u) : null;
  },
  setUser: (user: any) => localStorage.setItem("user", JSON.stringify(user)),
  clear: () => {
    localStorage.removeItem("token");
    localStorage.removeItem("user");
  },
  isLoggedIn: () => !!localStorage.getItem("token"),
};
