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
      setSession({ user: { email: 'demo@jobbus.dev' } });
      setProfile(DEMO_PROFILE);
      setLoading(false);
      return;
    }

    supabase.auth.getSession().then(({ data: { session: s } }) => {
      setSession(s);
      if (s?.access_token) {
        api.setToken(s.access_token);
        loadOrCreateProfile(s);
      } else {
        setLoading(false);
      }
    }).catch(() => {
      setLoading(false);
    });

    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, s) => {
      setSession(s);
      if (s?.access_token) {
        api.setToken(s.access_token);
        // On SIGNED_IN event (fresh login), try to load or create profile
        loadOrCreateProfile(s);
      } else {
        api.setToken(null);
        setProfile(null);
        setLoading(false);
      }
    });

    return () => subscription.unsubscribe();
  }, []);

  async function loadOrCreateProfile(currentSession) {
    try {
      const p = await api.getProfile();
      setProfile(p);
    } catch (e) {
      if (e.status === 404) {
        // New user — auto-register with saved invite code
        const savedInvite = localStorage.getItem('jobbus_invite_code');
        if (savedInvite) {
          try {
            const newProfile = await api.register(savedInvite);
            setProfile(newProfile);
            // Don't clear invite code — keep for reference
          } catch (regErr) {
            console.error('Auto-registration failed:', regErr);
            setProfile(null);
          }
        } else {
          setProfile(null);
        }
      } else {
        console.error('Profile load error:', e);
      }
    } finally {
      setLoading(false);
    }
  }

  async function loadProfile() {
    try {
      const p = await api.getProfile();
      setProfile(p);
    } catch (e) {
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
    try {
      if (!isDemoMode) {
        await supabase.auth.signOut();
      }
    } catch (err) {
      console.error('Sign out error:', err);
    } finally {
      // Always clear state, even if Supabase call fails
      api.setToken(null);
      setProfile(null);
      setSession(null);
      localStorage.removeItem('jobbus_invite_code');
    }
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
