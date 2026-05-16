import { useState, useEffect } from 'react';
import { useAuth } from '../../contexts/AuthContext';
import { supabase } from '../../lib/supabase';
import { Zap, ArrowRight, Sparkles, Target, BarChart3, Loader } from 'lucide-react';
import './Login.css';

/**
 * Login flow — industry-standard invite-only pattern:
 *
 *  Returning user:  "Continue with Google" → OAuth → profile exists → dashboard
 *  New user:        "Continue with Google" → OAuth → no profile → invite code prompt → register → dashboard
 *
 * The invite code NEVER blocks returning users. It's only shown once, post-OAuth,
 * to users who don't yet have a profile. This matches how Linear, Figma (beta),
 * and Loom handled invite-only access.
 */
export default function Login() {
  const { signInWithGoogle, session, profile, loading: authLoading } = useAuth();

  // 'sso'     — default: just show "Continue with Google"
  // 'invite'  — post-OAuth, user has no profile yet → ask for code
  // 'registering' — submitting the invite + registering
  const [step, setStep] = useState('sso');
  const [inviteCode, setInviteCode] = useState('');
  const [error, setError] = useState('');
  const [signingIn, setSigningIn] = useState(false);
  const [registering, setRegistering] = useState(false);

  // AuthContext fires loadOrCreateProfile after OAuth. If profile is null
  // AND we have a session (meaning SSO completed but no profile exists),
  // it means this is a brand-new user → prompt for invite code.
  useEffect(() => {
    if (!authLoading && session && !profile) {
      // OAuth completed but no profile yet — new user needs invite code
      setStep('invite');
      setSigningIn(false);
    }
  }, [authLoading, session, profile]);

  async function handleGoogleLogin() {
    setSigningIn(true);
    setError('');
    try {
      await signInWithGoogle();
      // Page redirects to Google — user returns via OAuth callback
      // AuthContext then fires and either finds profile (returning user → dashboard)
      // or sets profile=null (new user → useEffect above sets step='invite')
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
      // Step 1: validate the invite code against Supabase directly
      const { data, error: sbError } = await supabase
        .from('invites')
        .select('id, code, used, expires_at, reusable')
        .eq('code', code)
        .single();

      if (sbError || !data) {
        setError('Invalid invite code. Ask the admin for a valid code.');
        return;
      }
      if (data.used && !data.reusable) {
        setError('This invite code has already been used.');
        return;
      }
      if (data.expires_at && new Date(data.expires_at) < new Date()) {
        setError('This invite code has expired.');
        return;
      }

      // Step 2: save and register via backend
      localStorage.setItem('jobbus_invite_code', code);

      // Trigger AuthContext to re-run loadOrCreateProfile with saved code
      // The AuthContext already has the session — it just needs the saved code
      window.location.reload();

    } catch (err) {
      setError(err.message || 'Registration failed. Please try again.');
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
                    Continue with your Google account. New here? You'll be asked for an invite code after signing in.
                  </p>
                </>
              )}

              {step === 'invite' && (
                <>
                  <h2>You're almost in</h2>
                  <p className="text-secondary">
                    You're signed in with Google but JobBus is invite-only.
                    Enter your invite code to complete registration.
                  </p>
                </>
              )}
            </div>

            {error && (
              <div className="login-error">
                <span>✕</span> {error}
              </div>
            )}

            {/* Step: SSO — shown to everyone by default */}
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
                  Already have an account? We'll sign you straight in.
                </p>
              </div>
            )}

            {/* Step: Invite — shown only to new users post-OAuth */}
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
                  {registering ? <span className="spinner" /> : <>Complete Registration <ArrowRight size={16} /></>}
                </button>

                <button
                  type="button"
                  className="btn btn-ghost btn-sm w-full"
                  style={{ marginTop: 8 }}
                  onClick={async () => {
                    await supabase.auth.signOut();
                    setStep('sso');
                    setError('');
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
