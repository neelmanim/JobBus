import { createContext, useContext, useState, useEffect } from 'react';
import { supabase, isDemoMode } from '../lib/supabase';
import { api } from '../lib/api';

const AuthContext = createContext(null);

// Demo profile for when Supabase isn't configured
const DEMO_PROFILE = {
  display_name: 'Demo User',
  email: 'demo@jobbus.dev',
  mode: 'beginner',
  is_admin: true,
  is_active: true,
};

export function AuthProvider({ children }) {
  const [session, setSession] = useState(null);
  const [profile, setProfile] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (isDemoMode) {
      // In demo mode, auto-authenticate
      setSession({ user: { email: 'demo@jobbus.dev' } });
      setProfile(DEMO_PROFILE);
      setLoading(false);
      return;
    }

    supabase.auth.getSession().then(({ data: { session: s } }) => {
      setSession(s);
      if (s?.access_token) {
        api.setToken(s.access_token);
        loadProfile();
      } else {
        setLoading(false);
      }
    }).catch(() => {
      setLoading(false);
    });

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, s) => {
      setSession(s);
      if (s?.access_token) {
        api.setToken(s.access_token);
        loadProfile();
      } else {
        api.setToken(null);
        setProfile(null);
        setLoading(false);
      }
    });

    return () => subscription.unsubscribe();
  }, []);

  async function loadProfile() {
    try {
      const p = await api.getProfile();
      setProfile(p);
    } catch (e) {
      // Profile might not exist yet (new user)
      if (e.status === 404) setProfile(null);
      else console.error('Profile load error:', e);
    } finally {
      setLoading(false);
    }
  }

  async function signInWithGoogle() {
    if (isDemoMode) {
      setSession({ user: { email: 'demo@jobbus.dev' } });
      setProfile(DEMO_PROFILE);
      return;
    }
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: window.location.origin },
    });
    if (error) throw error;
  }

  async function signOut() {
    if (!isDemoMode) {
      await supabase.auth.signOut();
    }
    setProfile(null);
    setSession(null);
  }

  const value = {
    session,
    user: session?.user || null,
    profile,
    loading,
    isAdmin: profile?.is_admin || false,
    isOnboarded: !!profile,
    isDemoMode,
    signInWithGoogle,
    signOut,
    refreshProfile: isDemoMode ? () => Promise.resolve() : loadProfile,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be inside AuthProvider');
  return ctx;
}
