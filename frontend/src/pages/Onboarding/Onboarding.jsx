import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../../contexts/AuthContext';
import { api } from '../../lib/api';
import { useToast } from '../../contexts/ToastContext';
import {
  Mail, Key, FileText, CheckCircle, ArrowRight,
  ArrowLeft, Sparkles, Eye, EyeOff, Upload, Zap,
  Globe, Loader
} from 'lucide-react';
import './Onboarding.css';

const STEPS = [
  { id: 'welcome',   label: 'Welcome',   icon: Sparkles },
  { id: 'smtp',      label: 'Email',     icon: Mail      },
  { id: 'providers', label: 'AI & Search', icon: Key     },
  { id: 'resume',    label: 'Resume',    icon: FileText  },
];

export default function Onboarding() {
  const { profile, refreshProfile } = useAuth();
  const navigate = useNavigate();
  const toast = useToast();
  const [step, setStep] = useState(0);
  const [saving, setSaving] = useState(false);

  // SMTP state
  const [smtpEmail, setSmtpEmail]     = useState('');
  const [smtpPassword, setSmtpPassword] = useState('');
  const [showPass, setShowPass]       = useState(false);
  const [smtpSaved, setSmtpSaved]     = useState(false);

  // Provider state
  const [groqKey, setGroqKey]         = useState('');
  const [openaiKey, setOpenaiKey]     = useState('');
  const [geminiKey, setGeminiKey]     = useState('');
  const [hunterKey, setHunterKey]     = useState('');
  const [apolloKey, setApolloKey]     = useState('');
  const [aiProvider, setAiProvider]   = useState('groq');
  const [searchProvider, setSearchProvider] = useState('hunter');
  const [providersSaved, setProvidersSaved] = useState(false);

  // Resume state
  const [resumeText, setResumeText]   = useState('');
  const [resumeFile, setResumeFile]   = useState(null);
  const [uploading, setUploading]     = useState(false);
  const [resumeSaved, setResumeSaved] = useState(false);

  const firstName = profile?.display_name?.split(' ')[0] || 'there';

  /* ── Step handlers ─────────────────────────────────────── */
  async function handleSmtpSave() {
    if (!smtpEmail || !smtpPassword) { toast.error('Enter your Gmail and App Password'); return; }
    setSaving(true);
    try {
      await api.saveSmtpCredentials({ email: smtpEmail, password: smtpPassword });
      setSmtpSaved(true);
      toast.success('Email connected!');
    } catch (err) {
      toast.error(err.message || 'SMTP save failed');
    } finally {
      setSaving(false);
    }
  }

  async function handleProvidersSave() {
    setSaving(true);
    try {
      const saves = [];
      if (groqKey)    saves.push(api.saveProviderKey('groq',       groqKey));
      if (openaiKey)  saves.push(api.saveProviderKey('openai',     openaiKey));
      if (geminiKey)  saves.push(api.saveProviderKey('gemini',     geminiKey));
      if (hunterKey)  saves.push(api.saveProviderKey('hunter',     hunterKey));
      if (apolloKey)  saves.push(api.saveProviderKey('apollo',     apolloKey));
      saves.push(api.setAiProvider(aiProvider));
      saves.push(api.setSearchProvider(searchProvider));
      await Promise.all(saves);
      setProvidersSaved(true);
      toast.success('Providers saved!');
    } catch (err) {
      toast.error(err.message || 'Provider save failed');
    } finally {
      setSaving(false);
    }
  }

  async function handleResumeUpload() {
    if (!resumeText.trim() && !resumeFile) { toast.error('Paste your resume or upload a file'); return; }
    setUploading(true);
    try {
      if (resumeFile) {
        const form = new FormData();
        form.append('file', resumeFile);
        await api.uploadResume(form);
      } else {
        await api.saveResumeText(resumeText);
      }
      setResumeSaved(true);
      toast.success('Resume saved!');
    } catch (err) {
      toast.error(err.message || 'Resume upload failed');
    } finally {
      setUploading(false);
    }
  }

  async function handleFinish() {
    setSaving(true);
    try {
      await api.completeOnboarding();
      await refreshProfile();
      navigate('/');
    } catch {
      navigate('/'); // best-effort
    } finally {
      setSaving(false);
    }
  }

  function next() { setStep(s => Math.min(s + 1, STEPS.length - 1)); }
  function back() { setStep(s => Math.max(s - 1, 0)); }
  const isLast = step === STEPS.length - 1;

  /* ── Render ────────────────────────────────────────────── */
  return (
    <div className="onboarding-root">
      {/* Sidebar progress */}
      <aside className="onboarding-sidebar">
        <div className="onboarding-brand">
          <span className="brand-icon">🚌</span>
          <span className="brand-name">JobBus</span>
        </div>
        <nav className="onboarding-steps-nav">
          {STEPS.map((s, i) => {
            const Icon = s.icon;
            const done  = i < step;
            const active = i === step;
            return (
              <div key={s.id} className={`onboarding-step-nav ${active ? 'active' : ''} ${done ? 'done' : ''}`}>
                <div className="step-nav-icon">
                  {done ? <CheckCircle size={18} /> : <Icon size={18} />}
                </div>
                <span>{s.label}</span>
              </div>
            );
          })}
        </nav>
        <div className="onboarding-tagline">
          <p>Set up once.</p>
          <p>Outreach smarter,</p>
          <p>forever.</p>
        </div>
      </aside>

      {/* Main content */}
      <main className="onboarding-main">
        <div className="onboarding-card">
          {/* Step 0: Welcome */}
          {step === 0 && (
            <div className="onboarding-step-content">
              <div className="welcome-emoji">🎯</div>
              <h1>Welcome to JobBus, {firstName}!</h1>
              <p className="onboarding-desc">
                JobBus is your guided career outreach system. We'll help you find the right people,
                craft hyper-personalised emails, and track every reply — all in one place.
              </p>
              <div className="welcome-features">
                {[
                  { icon: '🔍', text: 'Discover high-signal job opportunities' },
                  { icon: '👤', text: 'Find decision-makers via Hunter, Apollo & RocketReach' },
                  { icon: '✍️', text: 'Generate personalised emails with Groq, OpenAI or Gemini' },
                  { icon: '📊', text: 'Track replies, interviews and outcomes' },
                ].map((f, i) => (
                  <div key={i} className="welcome-feature">
                    <span className="feature-emoji">{f.icon}</span>
                    <span>{f.text}</span>
                  </div>
                ))}
              </div>
              <p className="text-sm text-secondary" style={{ marginTop: 8 }}>
                This setup takes about 3 minutes. You can skip any step and configure it later in Settings.
              </p>
            </div>
          )}

          {/* Step 1: SMTP */}
          {step === 1 && (
            <div className="onboarding-step-content">
              <div className="step-header-icon"><Mail size={28} /></div>
              <h2>Connect your email</h2>
              <p className="onboarding-desc">
                JobBus sends emails through your own Gmail account — keeping your sender reputation pristine.
              </p>
              <div className="input-group">
                <label className="input-label">Gmail Address</label>
                <input className="input" type="email" placeholder="you@gmail.com"
                  value={smtpEmail} onChange={e => setSmtpEmail(e.target.value)} />
              </div>
              <div className="input-group">
                <label className="input-label">
                  Google App Password
                  <a href="https://myaccount.google.com/apppasswords" target="_blank" rel="noopener noreferrer"
                    className="text-xs text-accent" style={{ marginLeft: 8 }}>
                    Get one →
                  </a>
                </label>
                <div className="password-field">
                  <input className="input" type={showPass ? 'text' : 'password'}
                    placeholder="xxxx xxxx xxxx xxxx"
                    value={smtpPassword} onChange={e => setSmtpPassword(e.target.value)} />
                  <button type="button" className="password-toggle"
                    onClick={() => setShowPass(v => !v)}>
                    {showPass ? <EyeOff size={16} /> : <Eye size={16} />}
                  </button>
                </div>
                <span className="text-xs text-secondary">
                  Enable 2FA on your Google account first, then create an App Password.
                </span>
              </div>
              {smtpSaved ? (
                <div className="step-success"><CheckCircle size={18} /> Email connected!</div>
              ) : (
                <button className="btn btn-secondary" onClick={handleSmtpSave} disabled={saving || !smtpEmail || !smtpPassword}>
                  {saving ? <Loader size={15} className="spin-icon" /> : <Mail size={15} />} Save Email
                </button>
              )}
            </div>
          )}

          {/* Step 2: Providers */}
          {step === 2 && (
            <div className="onboarding-step-content">
              <div className="step-header-icon"><Key size={28} /></div>
              <h2>AI & Search Providers</h2>
              <p className="onboarding-desc">
                Add your own API keys for full power. No key? JobBus uses system keys in beginner mode — you can add yours later.
              </p>

              <div className="provider-section-label">AI Provider (for drafting emails)</div>
              <div className="provider-toggle-group">
                {['groq', 'openai', 'gemini'].map(p => (
                  <button key={p} className={`provider-toggle ${aiProvider === p ? 'selected' : ''}`}
                    onClick={() => setAiProvider(p)}>
                    {p === 'groq' ? '⚡ Groq' : p === 'openai' ? '🤖 OpenAI' : '✨ Gemini'}
                  </button>
                ))}
              </div>

              {aiProvider === 'groq' && (
                <div className="input-group">
                  <label className="input-label">Groq API Key <span className="text-secondary text-xs">(groq.com)</span></label>
                  <input className="input" placeholder="gsk_..." value={groqKey} onChange={e => setGroqKey(e.target.value)} />
                </div>
              )}
              {aiProvider === 'openai' && (
                <div className="input-group">
                  <label className="input-label">OpenAI API Key</label>
                  <input className="input" placeholder="sk-..." value={openaiKey} onChange={e => setOpenaiKey(e.target.value)} />
                </div>
              )}
              {aiProvider === 'gemini' && (
                <div className="input-group">
                  <label className="input-label">Gemini API Key</label>
                  <input className="input" placeholder="AIza..." value={geminiKey} onChange={e => setGeminiKey(e.target.value)} />
                </div>
              )}

              <div className="provider-section-label" style={{ marginTop: 16 }}>Contact Search</div>
              <div className="provider-toggle-group">
                {['hunter', 'apollo'].map(p => (
                  <button key={p} className={`provider-toggle ${searchProvider === p ? 'selected' : ''}`}
                    onClick={() => setSearchProvider(p)}>
                    {p === 'hunter' ? '🎯 Hunter.io' : '🚀 Apollo.io'}
                  </button>
                ))}
              </div>
              {searchProvider === 'hunter' && (
                <div className="input-group">
                  <label className="input-label">Hunter API Key <span className="text-secondary text-xs">(hunter.io)</span></label>
                  <input className="input" placeholder="hunter_..." value={hunterKey} onChange={e => setHunterKey(e.target.value)} />
                </div>
              )}
              {searchProvider === 'apollo' && (
                <div className="input-group">
                  <label className="input-label">Apollo API Key</label>
                  <input className="input" placeholder="apollo_..." value={apolloKey} onChange={e => setApolloKey(e.target.value)} />
                </div>
              )}

              <div className="onboarding-note">
                <Zap size={14} /> Beginner Mode: system keys are used automatically if you skip this.
              </div>

              {providersSaved ? (
                <div className="step-success"><CheckCircle size={18} /> Providers saved!</div>
              ) : (
                <button className="btn btn-secondary" onClick={handleProvidersSave} disabled={saving}>
                  {saving ? <Loader size={15} className="spin-icon" /> : <Key size={15} />} Save Providers
                </button>
              )}
            </div>
          )}

          {/* Step 3: Resume */}
          {step === 3 && (
            <div className="onboarding-step-content">
              <div className="step-header-icon"><FileText size={28} /></div>
              <h2>Add your resume</h2>
              <p className="onboarding-desc">
                JobBus reads your resume to understand your background and personalise every outreach email.
              </p>
              <div className="resume-tabs">
                <button className={`resume-tab-btn ${!resumeFile ? 'active' : ''}`}
                  onClick={() => setResumeFile(null)}>Paste text</button>
                <button className={`resume-tab-btn ${resumeFile ? 'active' : ''}`}
                  onClick={() => document.getElementById('resume-upload').click()}>Upload file</button>
                <input id="resume-upload" type="file" accept=".pdf,.doc,.docx,.txt"
                  style={{ display: 'none' }}
                  onChange={e => { if (e.target.files[0]) setResumeFile(e.target.files[0]); }} />
              </div>
              {resumeFile ? (
                <div className="resume-file-preview">
                  <Upload size={18} />
                  <span className="font-medium">{resumeFile.name}</span>
                  <button className="btn btn-ghost btn-sm" onClick={() => setResumeFile(null)}>Remove</button>
                </div>
              ) : (
                <textarea
                  className="input resume-textarea"
                  placeholder="Paste your resume text here..."
                  rows={10}
                  value={resumeText}
                  onChange={e => setResumeText(e.target.value)}
                />
              )}
              {resumeSaved ? (
                <div className="step-success"><CheckCircle size={18} /> Resume saved!</div>
              ) : (
                <button className="btn btn-secondary" onClick={handleResumeUpload}
                  disabled={uploading || (!resumeText.trim() && !resumeFile)}>
                  {uploading ? <Loader size={15} className="spin-icon" /> : <Upload size={15} />} Save Resume
                </button>
              )}
            </div>
          )}

          {/* Navigation */}
          <div className="onboarding-nav">
            {step > 0 && (
              <button className="btn btn-ghost" onClick={back}>
                <ArrowLeft size={15} /> Back
              </button>
            )}
            <div style={{ flex: 1 }} />
            {!isLast ? (
              <button className="btn btn-primary" onClick={next}>
                {step === 0 ? 'Get Started' : 'Next'} <ArrowRight size={15} />
              </button>
            ) : (
              <button className="btn btn-primary" onClick={handleFinish} disabled={saving}>
                {saving ? <Loader size={15} className="spin-icon" /> : null}
                Go to Dashboard <ArrowRight size={15} />
              </button>
            )}
          </div>

          {/* Skip link */}
          {step > 0 && step < STEPS.length - 1 && (
            <p className="onboarding-skip" onClick={next}>Skip for now →</p>
          )}
        </div>
      </main>
    </div>
  );
}
