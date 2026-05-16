import { createContext, useContext, useState, useEffect, useRef } from 'react';
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

  // Prevents redundant api.getProfile() calls on every TOKEN_REFRESHED event.
  // Supabase fires this event ~every hour; no need to re-fetch profile each time.
  const profileLoadedRef = useRef(false);

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
        // Optimization: skip re-fetch on silent token refreshes — profile hasn't changed.
        // Still re-fetch on explicit SIGNED_IN (fresh OAuth) and USER_UPDATED events.
        if (event === 'TOKEN_REFRESHED' && profileLoadedRef.current) return;
        loadOrCreateProfile(s);
      } else {
        api.setToken(null);
        setProfile(null);
        profileLoadedRef.current = false;
        setLoading(false);
      }
    });

    return () => subscription.unsubscribe();
  }, []);

  /**
   * Core profile loader. Called after every SSO event.
   *
   * Flow:
   *  - 200: Profile exists → set it, mark as loaded (returning user)
   *  - 404: No profile → check localStorage for invite code → register
   *    - On registration success: set profile, clear localStorage
   *    - On registration failure: clear localStorage to prevent loop (Bug 1 fix)
   *  - 401: Invalid/expired token → sign out cleanly so user re-SSOs (Bug 3 fix)
   *  - other: log error, leave profile null
   */
  async function loadOrCreateProfile(currentSession) {
    try {
      const p = await api.getProfile();
      setProfile(p);
      profileLoadedRef.current = true;
    } catch (e) {
      if (e.status === 404) {
        // New user — attempt registration with saved invite code (if any)
        const savedInvite = localStorage.getItem('jobbus_invite_code');
        if (savedInvite) {
          try {
            const newProfile = await api.register(savedInvite);
            setProfile(newProfile);
            profileLoadedRef.current = true;
            localStorage.removeItem('jobbus_invite_code'); // Clean up after successful registration
          } catch (regErr) {
            console.error('Auto-registration failed:', regErr);
            // Bug 1 fix: clear localStorage so the next page load doesn't loop infinitely
            // with a bad code (e.g. backend error, revoked code, etc.)
            localStorage.removeItem('jobbus_invite_code');
            setProfile(null);
          }
        } else {
          // No invite code saved — Login page will prompt user for one
          setProfile(null);
        }
      } else if (e.status === 401) {
        // Bug 3 fix: Token is invalid or expired. Sign out cleanly so the user
        // gets a fresh SSO prompt instead of being stuck seeing the invite screen.
        console.warn('Auth token expired or invalid — signing out for re-authentication.');
        await supabase.auth.signOut();
        // onAuthStateChange fires with null session → state is cleared automatically above
      } else {
        console.error('Profile load error:', e);
        setProfile(null);
      }
    } finally {
      setLoading(false);
    }
  }

  /**
   * Manual profile refresh — used by Settings, Onboarding, etc. to sync
   * profile changes (e.g. after completing onboarding).
   */
  async function loadProfile() {
    try {
      const p = await api.getProfile();
      setProfile(p);
      profileLoadedRef.current = true;
    } catch (e) {
      if (e.status === 404) setProfile(null);
      else console.error('Profile load error:', e);
    } finally {
      setLoading(false);
    }
  }

  /**
   * Bug 2 fix: Register a new user directly without a page reload.
   *
   * The Login page calls this after validating the invite code client-side.
   * On success, AuthContext profile is set → route guard redirects to /onboarding.
   * On failure, throws so the Login component can display the error inline.
   */
  async function registerNewUser(inviteCode) {
    const newProfile = await api.register(inviteCode);
    setProfile(newProfile);
    profileLoadedRef.current = true;
    localStorage.removeItem('jobbus_invite_code');
    return newProfile;
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
      api.setToken(null);
      setProfile(null);
      setSession(null);
      profileLoadedRef.current = false;
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
    registerNewUser,   // exposed for Login page (Bug 2 fix)
    refreshProfile: isDemoMode ? () => Promise.resolve() : loadProfile,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be inside AuthProvider');
  return ctx;
}
