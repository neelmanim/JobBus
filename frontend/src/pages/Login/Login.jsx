import { useState, useEffect } from 'react';
import { useAuth } from '../../contexts/AuthContext';
import { supabase } from '../../lib/supabase';
import { Zap, ArrowRight, Sparkles, Target, BarChart3, Loader } from 'lucide-react';
import './Login.css';

/**
 * Login flow — industry-standard invite-only pattern:
 *
 *  Returning user:  "Continue with Google" → OAuth → profile found → dashboard (no code ever shown)
 *  New user:        "Continue with Google" → OAuth → no profile → invite code prompt → register → onboarding
 *
 * The invite code is a REGISTRATION gate, not a login gate.
 * It is shown exactly once, only to brand-new users, post-OAuth.
 */
export default function Login() {
  const {
    signInWithGoogle,
    registerNewUser,
    session,
    profile,
    loading: authLoading,
  } = useAuth();

  // 'sso'    — default: show "Continue with Google" to everyone
  // 'invite' — post-OAuth for new users only: show invite code entry
  const [step, setStep] = useState('sso');
  const [inviteCode, setInviteCode] = useState('');
  const [error, setError] = useState('');
  const [signingIn, setSigningIn] = useState(false);
  const [registering, setRegistering] = useState(false);

  // After OAuth completes, AuthContext fires. If the user has no profile yet
  // (brand-new account, 404 from backend), show the invite code step.
  // Returning users will have profile set → route guard redirects them away from /login.
  useEffect(() => {
    if (!authLoading && session && !profile) {
      setStep('invite');
      setSigningIn(false);
    }
  }, [authLoading, session, profile]);

  async function handleGoogleLogin() {
    setSigningIn(true);
    setError('');
    try {
      await signInWithGoogle();
      // Page redirects to Google → user returns via OAuth callback.
      // AuthContext fires, sets session. If profile exists → route guard takes them to dashboard.
      // If no profile → useEffect above sets step='invite'.
    } catch (err) {
      setSigningIn(false);
      setError(err.message);
    }
  }

  async function handleRegisterWithInvite(e) {
    e.preventDefault();
    const code = inviteCode.trim().toUpperCase();
    if (!code) return;

    setRegistering(true);
    setError('');

    try {
      // Step 1: validate the invite code against Supabase.
      // Bug 4 fix: also fetch the `email` field and check email restrictions
      // (email-restricted codes can only be used by the matching Google account).
      const { data, error: sbError } = await supabase
        .from('invites')
        .select('id, code, used, expires_at, reusable, email')
        .eq('code', code)
        .maybeSingle(); // maybeSingle() returns null instead of throwing on 0 rows

      if (sbError) {
        setError('Could not verify invite code. Please try again.');
        return;
      }
      if (!data) {
        setError('Invalid invite code. Ask your inviter for a valid code.');
        return;
      }
      if (data.used && !data.reusable) {
        setError('This invite code has already been used.');
        return;
      }
      if (data.expires_at && new Date(data.expires_at) < new Date()) {
        setError('This invite code has expired. Ask your inviter for a new one.');
        return;
      }

      // Bug 4 fix: enforce email restriction if the code was created for a specific address.
      // At this point the user is already signed in via Google, so session.user.email is known.
      if (data.email) {
        const userEmail = session?.user?.email || '';
        if (data.email.toLowerCase() !== userEmail.toLowerCase()) {
          setError(`This invite code is restricted to ${data.email}. Please sign in with that Google account.`);
          return;
        }
      }

      // Step 2: register directly via backend — no page reload needed (Bug 2 fix).
      // registerNewUser() calls api.register(), sets profile in context, and clears localStorage.
      // On success, AuthContext profile is populated → route guard redirects to /onboarding.
      // On failure, throws → caught below, error shown inline.
      await registerNewUser(code);

    } catch (err) {
      // registerNewUser threw — code was valid on Supabase but backend rejected it.
      // (e.g. race condition where another user used a single-use code at the same moment)
      setError(err.message || 'Registration failed. Please try again or contact support.');
    } finally {
      setRegistering(false);
    }
  }

  return (
    <div className="login-page">
      {/* Background */}
      <div className="login-bg">
        <div className="bg-orb bg-orb-1" />
        <div className="bg-orb bg-orb-2" />
        <div className="bg-grid" />
      </div>

      <div className="login-container">
        {/* Left — Branding */}
        <div className="login-hero">
          <div className="hero-badge">
            <Sparkles size={14} />
            <span>Intelligent Career Outreach</span>
          </div>
          <h1>Find the right<br /><span className="gradient-text">opportunities</span></h1>
          <p>
            JobBus helps you discover high-signal opportunities, approach the right people
            with context-driven outreach, and track your path to interviews.
          </p>

          <div className="hero-features">
            <div className="feature-item">
              <div className="feature-icon"><Target size={18} /></div>
              <div>
                <strong>Opportunity Scoring</strong>
                <span>6-signal weighted scoring engine</span>
              </div>
            </div>
            <div className="feature-item">
              <div className="feature-icon"><Sparkles size={18} /></div>
              <div>
                <strong>Angle-First Outreach</strong>
                <span>Context-driven, never generic</span>
              </div>
            </div>
            <div className="feature-item">
              <div className="feature-icon"><BarChart3 size={18} /></div>
              <div>
                <strong>Outcome Tracking</strong>
                <span>Replies → Interviews pipeline</span>
              </div>
            </div>
          </div>
        </div>

        {/* Right — Form */}
        <div className="login-form-area">
          <div className="login-card">
            <div className="login-card-header">
              <div className="logo-mark">
                <Zap size={22} />
              </div>

              {step === 'sso' && (
                <>
                  <h2>Sign In</h2>
                  <p className="text-secondary">
                    Continue with your Google account.
                    New here? You'll be asked for an invite code after signing in.
                  </p>
                </>
              )}

              {step === 'invite' && (
                <>
                  <h2>You're almost in</h2>
                  <p className="text-secondary">
                    You've signed in with Google. JobBus is invite-only —
                    enter your invite code to complete registration.
                  </p>
                </>
              )}
            </div>

            {error && (
              <div className="login-error">
                <span>✕</span> {error}
              </div>
            )}

            {/* Default step: Google SSO — shown to everyone */}
            {step === 'sso' && (
              <div className="login-form">
                <button
                  className="btn btn-primary btn-lg w-full google-btn"
                  onClick={handleGoogleLogin}
                  disabled={signingIn || authLoading}
                >
                  {signingIn ? (
                    <><Loader size={18} className="spin" /> Redirecting to Google…</>
                  ) : (
                    <>
                      <svg width="18" height="18" viewBox="0 0 18 18">
                        <path d="M17.64 9.2c0-.637-.057-1.251-.164-1.84H9v3.481h4.844a4.14 4.14 0 01-1.796 2.716v2.259h2.908c1.702-1.567 2.684-3.875 2.684-6.615z" fill="#4285F4"/>
                        <path d="M9 18c2.43 0 4.467-.806 5.956-2.18l-2.908-2.259c-.806.54-1.837.86-3.048.86-2.344 0-4.328-1.584-5.036-3.711H.957v2.332A8.997 8.997 0 009 18z" fill="#34A853"/>
                        <path d="M3.964 10.71A5.41 5.41 0 013.682 9c0-.593.102-1.17.282-1.71V4.958H.957A8.996 8.996 0 000 9c0 1.452.348 2.827.957 4.042l3.007-2.332z" fill="#FBBC05"/>
                        <path d="M9 3.58c1.321 0 2.508.454 3.44 1.345l2.582-2.58C13.463.891 11.426 0 9 0A8.997 8.997 0 00.957 4.958L3.964 7.29C4.672 5.163 6.656 3.58 9 3.58z" fill="#EA4335"/>
                      </svg>
                      Continue with Google
                    </>
                  )}
                </button>

                <p className="text-center text-sm text-tertiary" style={{ marginTop: 16 }}>
                  Already a member? We'll sign you straight in — no code needed.
                </p>
              </div>
            )}

            {/* Invite step: only shown to new users after OAuth */}
            {step === 'invite' && (
              <form onSubmit={handleRegisterWithInvite} className="login-form">
                <div className="input-group">
                  <label className="input-label">Invite Code</label>
                  <input
                    type="text"
                    className="input"
                    placeholder="e.g. BETA001"
                    value={inviteCode}
                    onChange={(e) => setInviteCode(e.target.value.toUpperCase())}
                    autoFocus
                    spellCheck={false}
                  />
                  <span className="text-sm text-tertiary">
                    Don't have one? Ask the person who referred you.
                  </span>
                </div>

                <button
                  type="submit"
                  className="btn btn-primary btn-lg w-full"
                  disabled={registering || !inviteCode.trim()}
                >
                  {registering
                    ? <><span className="spinner" /> Registering…</>
                    : <>Complete Registration <ArrowRight size={16} /></>
                  }
                </button>

                {/* Allow switching accounts without getting stuck */}
                <button
                  type="button"
                  className="btn btn-ghost btn-sm w-full"
                  style={{ marginTop: 8 }}
                  onClick={async () => {
                    await supabase.auth.signOut();
                    setStep('sso');
                    setError('');
                    setInviteCode('');
                  }}
                >
                  ← Use a different Google account
                </button>
              </form>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
