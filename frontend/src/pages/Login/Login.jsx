import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../../contexts/AuthContext';
import { supabase } from '../../lib/supabase';
import { Zap, ArrowRight, Sparkles, Target, BarChart3, Loader } from 'lucide-react';
import './Login.css';

export default function Login() {
  const { signInWithGoogle } = useAuth();
  const navigate = useNavigate();
  const [inviteCode, setInviteCode] = useState('');
  const [step, setStep] = useState('invite'); // invite | login
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [signingIn, setSigningIn] = useState(false);

  // If user already validated an invite code, skip to login step
  useEffect(() => {
    const savedCode = localStorage.getItem('jobbus_invite_code');
    if (savedCode) {
      setInviteCode(savedCode);
      setStep('login');
    }
  }, []);

  async function handleValidateInvite(e) {
    e.preventDefault();
    if (!inviteCode.trim()) return;
    setLoading(true);
    setError('');
    try {
      // Validate directly against Supabase — no backend needed
      const { data, error: sbError } = await supabase
        .from('invites')
        .select('id, code, used, expires_at')
        .eq('code', inviteCode.trim())
        .single();

      if (sbError || !data) {
        setError('Invalid invite code');
      } else if (data.used) {
        setError('This invite code has already been used');
      } else if (data.expires_at && new Date(data.expires_at) < new Date()) {
        setError('This invite code has expired');
      } else {
        localStorage.setItem('jobbus_invite_code', inviteCode.trim());
        setStep('login');
      }
    } catch (err) {
      setError(err.message || 'Could not validate invite code');
    } finally {
      setLoading(false);
    }
  }

  async function handleGoogleLogin() {
    setSigningIn(true);
    setError('');
    try {
      await signInWithGoogle();
      // Note: The page will redirect to Google OAuth — user will come back automatically
    } catch (err) {
      setSigningIn(false);
      setError(err.message);
    }
  }

  return (
    <div className="login-page">
      {/* Background effect */}
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
              <h2>{step === 'invite' ? 'Enter Invite Code' : 'Sign In'}</h2>
              <p className="text-secondary">
                {step === 'invite'
                  ? 'JobBus is invite-only. Enter your code to continue.'
                  : 'You\'ll be redirected to Google to sign in securely.'
                }
              </p>
            </div>

            {error && (
              <div className="login-error">
                <span>✕</span> {error}
              </div>
            )}

            {step === 'invite' ? (
              <form onSubmit={handleValidateInvite} className="login-form">
                <div className="input-group">
                  <label className="input-label">Invite Code</label>
                  <input
                    type="text"
                    className="input"
                    placeholder="Enter your invite code"
                    value={inviteCode}
                    onChange={(e) => setInviteCode(e.target.value.toUpperCase())}
                    autoFocus
                    spellCheck={false}
                  />
                </div>
                <button
                  type="submit"
                  className="btn btn-primary btn-lg w-full"
                  disabled={loading || !inviteCode.trim()}
                >
                  {loading ? <span className="spinner" /> : <>Validate <ArrowRight size={16} /></>}
                </button>
              </form>
            ) : (
              <div className="login-form">
                <div className="invite-success">
                  <span className="badge badge-success">✓ Invite Validated</span>
                  <span className="text-sm text-secondary">Code: {inviteCode}</span>
                </div>
                <button
                  className="btn btn-primary btn-lg w-full google-btn"
                  onClick={handleGoogleLogin}
                  disabled={signingIn}
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
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
