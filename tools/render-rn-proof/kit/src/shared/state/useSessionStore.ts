import { create } from 'zustand';
type UserId = string;
type SessionState = { userId: UserId | null; signIn: (id: UserId) => void; signOut: () => void };
export const useSessionStore = create<SessionState>()((set) => ({
  userId: null,
  signIn: (userId) => {
    set({ userId });
  },
  signOut: () => {
    set({ userId: null });
  },
}));
