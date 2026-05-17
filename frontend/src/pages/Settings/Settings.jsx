import { useState, useEffect, useCallback, useRef } from 'react';
import { useSearchParams } from 'react-router-dom';
import { api } from '../../lib/api';
import { useAuth } from '../../contexts/AuthContext';
import { useToast } from '../../contexts/ToastContext';
import {
  Mail, Key, Shield, Eye, EyeOff, Check, AlertCircle,
  Trash2, Send, ToggleLeft, ToggleRight, Zap, Search,
  Brain, Settings as SettingsIcon, Loader, RefreshCw,
  ChevronDown, Pencil, CheckCircle, XCircle, Clock
} from 'lucide-react';
import './Settings.css';

const TABS = [
  { id: 'smtp',      label: 'Email (SMTP)',     icon: Mail },
  { id: 'providers', label: 'AI & Search',       icon: Brain },
  { id: 'style',     label: 'Email Style',       icon: Pencil },
  { id: 'defaults',  label: 'Campaign Defaults', icon: SettingsIcon },
];

const AI_PROVIDERS = [
  { id: 'groq',   label: 'Groq',   desc: 'Ultra-fast, free tier — great for high volume', field: 'groq_key',   placeholder: 'gsk_...' },
  { id: 'openai', label: 'OpenAI', desc: 'GPT-4o for highest quality drafts',              field: 'openai_key', placeholder: 'sk-...' },
  { id: 'gemini', label: 'Gemini', desc: 'Google Gemini 2.0 Flash — balanced speed/quality', field: 'gemini_key', placeholder: 'AIza...' },
  { id: 'ollama', label: 'Ollama', desc: 'Run models locally (no API key needed)',         field: 'ollama_url', placeholder: 'http://localhost:11434' },
];

const SEARCH_PROVIDERS = [
  { id: 'hunter',      label: 'Hunter.io',    desc: 'Domain-based email finder (free tier: 25/mo)', field: 'hunter_key',      placeholder: 'hnt_...' },
  { id: 'apollo',      label: 'Apollo.io',    desc: '200M+ contacts database, title/seniority filter', field: 'apollo_key', placeholder: 'your_apollo_api_key' },
  { id: 'rocketreach', label: 'RocketReach',  desc: 'Best for executive discovery',              field: 'rocketreach_key', placeholder: 'your_rocketreach_key' },
];

const AI_MODELS = {
  groq:   [{ id: 'auto', label: 'Auto (Fast)' }, { id: 'quality', label: 'High Quality (70B)' }],
  openai: [{ id: 'auto', label: 'GPT-4o mini (Fast)' }, { id: 'quality', label: 'GPT-4o (Best)' }],
  gemini: [{ id: 'auto', label: 'Gemini 2.0 Flash' }],
  ollama: [{ id: 'auto', label: 'Default Model' }],
};

// hasKey = true but untested → show a muted green check (key IS saved, just not verified yet)
function StatusDot({ ok, loading }) {
  if (loading) return <Loader size={14} className="spin-icon" />;
  if (ok === true)  return <CheckCircle size={14} style={{ color: 'var(--color-success)' }} />;
  if (ok === false) return <XCircle size={14} style={{ color: 'var(--color-danger)' }} />;
  return <Check size={14} style={{ color: 'var(--color-success)', opacity: 0.7 }} />;
}

function ProviderKeyRow({ prov, savedKeys, onSave, onTest, testingField }) {
  const [val, setVal]       = useState('');
  const [show, setShow]     = useState(false);
  const [saving, setSaving] = useState(false);
  const hasKey = !!savedKeys[prov.field];
  // null = untested, true = ok, false = failed
  const testResult = hasKey ? savedKeys[`${prov.field}_ok`] : undefined;

  async function save() {
    if (!val.trim()) return;
    setSaving(true);
    await onSave(prov.field, val.trim());
    setVal('');
    setSaving(false);
    // Automatically test after save so the status dot fills in immediately
    onTest(prov.field);
  }

  return (
    <div className="provider-row">
      <div className="provider-row-header">
        <div>
          <span className="provider-name">{prov.label}</span>
          <span className="provider-desc">{prov.desc}</span>
        </div>
        <div className="provider-status-group">
          {hasKey && (
            <span className={`provider-status-chip ${
              testResult === false ? 'chip-fail' : 'chip-ok'
            }`}>
              <StatusDot ok={testResult} loading={testingField === prov.field} />
              {testingField === prov.field ? 'Testing…' :
               testResult === true  ? 'Connected' :
               testResult === false ? 'Failed' :
               'Configured'}
            </span>
          )}
          {hasKey && (
            <button className="btn btn-ghost btn-sm" onClick={() => onTest(prov.field)}
              disabled={testingField === prov.field} title="Test connection">
              <RefreshCw size={13} /> Test
            </button>
          )}
        </div>
      </div>
      <div className="provider-key-input">
        <div className="password-input">
          <input
            className="input"
            type={show ? 'text' : 'password'}
            placeholder={hasKey ? '••••••••••••••••  (tap Save to update)' : prov.placeholder}
            value={val}
            onChange={e => setVal(e.target.value)}
          />
          <button type="button" className="password-toggle" onClick={() => setShow(s => !s)}>
            {show ? <EyeOff size={15} /> : <Eye size={15} />}
          </button>
        </div>
        <button className="btn btn-secondary btn-sm" onClick={save} disabled={saving || !val.trim()}>
          {saving ? <span className="spinner" style={{ width: 14, height: 14 }} /> : hasKey ? 'Update' : 'Save'}
        </button>
      </div>
    </div>
  );
}

export default function Settings() {
  const { profile, refreshProfile, patchProfile } = useAuth();
  const toast = useToast();
  const [searchParams] = useSearchParams();
  const [tab, setTab] = useState(() => searchParams.get('tab') || 'smtp');

  // ── SMTP ─────────────────────────────────────────────────
  const [smtpStatus, setSmtpStatus] = useState(null);
  const [showSmtpForm, setShowSmtpForm] = useState(false);
  const [smtpForm, setSmtpForm] = useState({ smtp_user: '', smtp_pass: '', smtp_host: 'smtp.gmail.com', smtp_port: 587, sender_name: '' });
  const [showPassword, setShowPassword] = useState(false);
  const [savingSmtp, setSavingSmtp] = useState(false);
  const [testEmail, setTestEmail] = useState('');
  const [testingSmtp, setTestingSmtp] = useState(false);

  // ── Providers ─────────────────────────────────────────────
  const [providerStatus, setProviderStatus] = useState({});
  const [testingField, setTestingField] = useState(null);
  const [aiProvider, setAiProvider] = useState('groq');
  const [aiModel, setAiModel] = useState('auto');
  const [searchProvider, setSearchProvider] = useState('hunter');
  const [savingPref, setSavingPref] = useState(false);
  const autoTestedRef = useRef(false);
  const [quota, setQuota] = useState(null);
  const [quotaLoading, setQuotaLoading] = useState(false);
  const [initializing, setInitializing] = useState(true); // single loading gate

  // ── Email Style ───────────────────────────────────────────
  const [style, setStyle] = useState({ signature_name: '', signature_title: '', signature_linkedin: '', custom_instructions: '' });
  const [savingStyle, setSavingStyle] = useState(false);

  // ── Campaign Defaults ─────────────────────────────────────
  const [defaults, setDefaults] = useState({ send_delay_seconds: 120, max_emails_per_day: 20, sandbox_mode: true });
  const [savingDefaults, setSavingDefaults] = useState(false);

  // ── Parallel initializer: one round-trip instead of 3+ sequential ───
  useEffect(() => {
    (async () => {
      try {
        // Fire all independent fetches at the same time
        const [initData, quotaData] = await Promise.all([
          api.getAppInit(),
          api.getSearchQuota(),
        ]);

        // SMTP
        if (initData?.smtp) setSmtpStatus(initData.smtp.configured ? initData.smtp : null);

        // Providers
        const prov = initData?.providers || {};
        setProviderStatus(prov);
        setAiProvider(initData?.style?.ai_provider || prov.ai_provider || 'groq');
        setAiModel(initData?.style?.ai_model || prov.ai_model || 'auto');
        setSearchProvider(initData?.style?.search_provider || prov.search_provider || 'hunter');

        // Style
        if (initData?.style) setStyle(s => ({ ...s, ...initData.style }));

        // Quota
        if (quotaData) setQuota(quotaData);

        // Auto-test configured providers once (background, after UI renders)
        if (!autoTestedRef.current) {
          autoTestedRef.current = true;
          setTimeout(async () => {
            const allFields = [
              ...AI_PROVIDERS.map(p => p.field),
              ...SEARCH_PROVIDERS.map(p => p.field),
            ];
            for (const field of allFields) {
              if (prov[field]) {
                await new Promise(r => setTimeout(r, 400));
                handleTestKey(field, true);
              }
            }
          }, 500);
        }
      } catch (e) {
        // Fallback: load individually if /init fails
        loadSmtpStatus();
        loadProviderStatus();
        loadEmailStyle();
      } finally {
        setInitializing(false);
      }
    })();
  }, []);

  // ── Individual loaders (fallback + save handlers) ──────────────
  async function loadSmtpStatus() {
    try { setSmtpStatus(await api.getSmtpStatus()); } catch { setSmtpStatus(null); }
  }
  async function loadProviderStatus() {
    try {
      const data = await api.getProviderStatus();
      setProviderStatus(data || {});
      if (data?.hunter_key) loadQuota();
      setAiProvider(data.ai_provider || 'groq');
      setAiModel(data.ai_model || 'auto');
      setSearchProvider(data.search_provider || 'hunter');
    } catch { /* silent */ }
  }
  async function loadEmailStyle() {
    try {
      const d = await api.getEmailStyle();
      if (d) setStyle(s => ({ ...s, ...d }));
    } catch {}
  }

  async function loadQuota(forceRefresh = false) {
    setQuotaLoading(true);
    try {
      const q = await api.getSearchQuota(forceRefresh);
      setQuota(q);
    } catch {}
    setQuotaLoading(false);
  }

  // ── SMTP Handlers ─────────────────────────────────────────
  async function handleSaveSMTP(e) {
    e.preventDefault();
    setSavingSmtp(true);
    try {
      await api.configureSMTP(smtpForm);
      toast.success('SMTP configured ✓');
      setShowSmtpForm(false);
      loadSmtpStatus();
    } catch (err) { toast.error(err.message || 'Failed to save'); }
    finally { setSavingSmtp(false); }
  }
  async function handleTestSMTP() {
    if (!testEmail) return;
    setTestingSmtp(true);
    try { await api.testSMTP(testEmail); toast.success('Test email sent! Check your inbox.'); }
    catch (err) { toast.error(err.message || 'Test failed'); }
    finally { setTestingSmtp(false); }
  }
  async function handleDeleteSMTP() {
    try { await api.deleteSMTP(); toast.success('SMTP removed'); setSmtpStatus(null); }
    catch (err) { toast.error(err.message); }
  }

  // ── Provider Handlers ─────────────────────────────────────
  async function handleSaveKey(field, value) {
    try {
      await api.saveProviderKey(field, value);
      toast.success(`${field.replace('_key', '').replace('_url', '')} key saved`);
      loadProviderStatus();
    } catch (err) { toast.error(err.message || 'Failed to save key'); }
  }
  async function handleTestKey(field, silent = false) {
    setTestingField(field);
    try {
      const r = await api.testProviderKey(field);
      const label = field.replace('_key', '').replace('_url', '');
      if (!silent) {
        if (r.success) toast.success(`${label} connected ✓`);
        else           toast.error(`${label} test failed — check your key`);
      }
      // Persist test result into providerStatus so chip updates immediately
      setProviderStatus(prev => ({ ...prev, [`${field}_ok`]: r.success }));
    } catch (err) { if (!silent) toast.error(err.message); }
    finally { setTestingField(null); }
  }
  async function handleSaveAIPref() {
    setSavingPref(true);
    try {
      // Backend expects { ai_provider, model } and { search_provider }
      await api.setAIProvider({ ai_provider: aiProvider, model: aiModel });
      await api.setSearchProvider({ search_provider: searchProvider });
      toast.success('Provider preferences saved');
    } catch (err) { toast.error(err.message); }
    finally { setSavingPref(false); }
  }

  // ── Style Handlers ────────────────────────────────────────
  async function handleSaveStyle(e) {
    e.preventDefault();
    setSavingStyle(true);
    try { await api.updateEmailStyle(style); toast.success('Email style saved'); }
    catch (err) { toast.error(err.message); }
    finally { setSavingStyle(false); }
  }

  // ── Defaults Handlers ─────────────────────────────────────
  async function handleSaveDefaults(e) {
    e.preventDefault();
    if (defaults.send_delay_seconds < 60) { toast.error('Minimum send delay is 60 seconds'); return; }
    setSavingDefaults(true);
    try { await api.updateCampaignDefaults(defaults); toast.success('Defaults saved'); }
    catch (err) { toast.error(err.message); }
    finally { setSavingDefaults(false); }
  }

  async function handleModeToggle() {
    const newMode = profile?.mode === 'advanced' ? 'beginner' : 'advanced';
    try {
      const updatedProfile = await api.updateMode(newMode);
      // Patch in-memory immediately so the button label flips at once.
      // The backend returns the full updated profile, so no extra GET needed.
      patchProfile(updatedProfile);
      toast.success(`Switched to ${newMode} mode`);
    } catch (err) { toast.error(err.message); }
  }

  return (
    <div className="settings-page">
      <div className="page-header flex justify-between items-center">
        <div>
          <h1>Settings</h1>
          <p>Configure providers, email sending, and preferences</p>
        </div>
        <button className="mode-toggle-btn" onClick={handleModeToggle}>
          {profile?.mode === 'advanced'
            ? <><ToggleRight size={22} className="toggle-on" /> Advanced</>
            : <><ToggleLeft size={22} /> Beginner</>
          }
        </button>
      </div>

      {/* Tab Bar */}
      <div className="settings-tabs">
        {TABS.map(t => (
          <button
            key={t.id}
            className={`settings-tab ${tab === t.id ? 'active' : ''}`}
            onClick={() => setTab(t.id)}
          >
            <t.icon size={15} />
            {t.label}
          </button>
        ))}
      </div>

      {/* ── SMTP Tab ─────────────────────────────────────── */}
      {tab === 'smtp' && (
        <div className="card settings-section">
          <div className="section-header">
            <div>
              <h3><Mail size={16} /> Email (SMTP)</h3>
              <p className="text-secondary text-sm">Connect your email to send outreach. Gmail App Passwords work great.</p>
            </div>
            {smtpStatus?.configured
              ? <span className="badge badge-success"><Check size={12} /> Connected</span>
              : <span className="badge badge-warning"><AlertCircle size={12} /> Not configured</span>}
          </div>

          {smtpStatus?.configured && !showSmtpForm ? (
            <div className="smtp-connected">
              <div className="smtp-info">
                <span className="text-sm"><strong>Email:</strong> {smtpStatus.email || '***'}</span>
                <span className="text-sm"><strong>Host:</strong> {smtpStatus.host || 'smtp.gmail.com'}</span>
              </div>
              <div className="smtp-actions">
                <div className="test-email-group">
                  <input className="input" placeholder="test@example.com"
                    value={testEmail} onChange={e => setTestEmail(e.target.value)} style={{ maxWidth: 240 }} />
                  <button className="btn btn-secondary btn-sm" onClick={handleTestSMTP}
                    disabled={testingSmtp || !testEmail}>
                    {testingSmtp ? <span className="spinner" style={{ width: 14, height: 14 }} /> : <><Send size={13} /> Test</>}
                  </button>
                </div>
                <button className="btn btn-ghost btn-sm" onClick={() => setShowSmtpForm(true)}>Reconfigure</button>
                <button className="btn btn-danger btn-sm" onClick={handleDeleteSMTP}><Trash2 size={13} /> Remove</button>
              </div>
            </div>
          ) : (
            <form onSubmit={handleSaveSMTP} className="smtp-form">
              <div className="form-grid">
                <div className="input-group">
                  <label className="input-label">Email Address</label>
                  <input className="input" type="email" placeholder="your@gmail.com"
                    value={smtpForm.smtp_user} onChange={e => setSmtpForm(p => ({ ...p, smtp_user: e.target.value }))} required />
                </div>
                <div className="input-group">
                  <label className="input-label">App Password</label>
                  <div className="password-input">
                    <input
                      className="input"
                      type={showPassword ? 'text' : 'password'}
                      placeholder="Gmail App Password (16 chars)"
                      value={smtpForm.smtp_pass}
                      onChange={e => setSmtpForm(p => ({ ...p, smtp_pass: e.target.value }))}
                      required
                    />
                    <button type="button" className="password-toggle" onClick={() => setShowPassword(s => !s)}>
                      {showPassword ? <EyeOff size={15} /> : <Eye size={15} />}
                    </button>
                  </div>
                </div>
                {profile?.mode === 'advanced' && (<>
                  <div className="input-group">
                    <label className="input-label">SMTP Host</label>
                    <input className="input" value={smtpForm.smtp_host}
                      onChange={e => setSmtpForm(p => ({ ...p, smtp_host: e.target.value }))} />
                  </div>
                  <div className="input-group">
                    <label className="input-label">SMTP Port</label>
                    <input className="input" type="number" value={smtpForm.smtp_port}
                      onChange={e => setSmtpForm(p => ({ ...p, smtp_port: parseInt(e.target.value) }))} />
                  </div>
                </>)}
              </div>
              <div className="smtp-form-hint">
                <Shield size={13} />
                <span>Encrypted at rest with AES-256. Never stored in plaintext.</span>
              </div>
              <div className="form-actions">
                {smtpStatus?.configured && (
                  <button type="button" className="btn btn-ghost" onClick={() => setShowSmtpForm(false)}>Cancel</button>
                )}
                <button type="submit" className="btn btn-primary" disabled={savingSmtp}>
                  {savingSmtp ? <span className="spinner" style={{ width: 16, height: 16 }} /> : 'Save Credentials'}
                </button>
              </div>
            </form>
          )}
        </div>
      )}

      {/* ── Providers Tab ─────────────────────────────────── */}
      {tab === 'providers' && (
        <div className="providers-tab">
          {/* AI Providers */}
          <div className="card settings-section">
            <div className="section-header">
              <div>
                <h3><Brain size={16} /> AI Provider</h3>
                <p className="text-secondary text-sm">
                  Choose which model writes your emails. Groq is free and fast — a great starting point.
                </p>
              </div>
            </div>

            <div className="provider-list">
              {AI_PROVIDERS.map(prov => (
                <ProviderKeyRow key={prov.id} prov={prov}
                  savedKeys={providerStatus} onSave={handleSaveKey} onTest={handleTestKey}
                  testingField={testingField} />
              ))}
            </div>

            <div className="pref-row">
              <div className="input-group" style={{ flex: 1 }}>
                <label className="input-label">Active AI Provider</label>
                <select className="input" value={aiProvider} onChange={e => setAiProvider(e.target.value)}>
                  {AI_PROVIDERS.map(p => <option key={p.id} value={p.id}>{p.label}</option>)}
                </select>
              </div>
              <div className="input-group" style={{ flex: 1 }}>
                <label className="input-label">Model Tier</label>
                <select className="input" value={aiModel} onChange={e => setAiModel(e.target.value)}>
                  {(AI_MODELS[aiProvider] || AI_MODELS.groq).map(m => (
                    <option key={m.id} value={m.id}>{m.label}</option>
                  ))}
                </select>
              </div>
            </div>

            <div className="beginner-notice">
              <Zap size={14} />
              <span>No key? We'll use our system Groq key so you can start immediately.</span>
            </div>
          </div>

          {/* Search Providers */}
          <div className="card settings-section">
            <div className="section-header">
              <div>
                <h3><Search size={16} /> Contact Search</h3>
                <p className="text-secondary text-sm">
                  Waterfall strategy: Hunter → Apollo → RocketReach. Add keys to activate each layer.
                </p>
              </div>
            </div>

            <div className="provider-list">
              {SEARCH_PROVIDERS.map(prov => (
                <ProviderKeyRow key={prov.id} prov={prov}
                  savedKeys={providerStatus} onSave={handleSaveKey} onTest={handleTestKey}
                  testingField={testingField} />
              ))}
            </div>

            <div className="pref-row">
              <div className="input-group" style={{ flex: 1 }}>
                <label className="input-label">Primary Search Provider</label>
                <select className="input" value={searchProvider} onChange={e => setSearchProvider(e.target.value)}>
                  {SEARCH_PROVIDERS.map(p => <option key={p.id} value={p.id}>{p.label}</option>)}
                </select>
              </div>
            </div>

            {/* ── Hunter Quota Bar ─────────────────────────────── */}
            {quota?.hunter?.configured && (() => {
              const h = quota.hunter;
              const used  = h.searches_used      ?? 0;
              const avail = h.searches_available  ?? 0;
              const total = h.searches_total      ?? (used + avail);
              const pct   = total > 0 ? Math.round((used / total) * 100) : 0;
              const color = avail > 10 ? 'var(--color-success)' : avail > 4 ? 'var(--color-warning)' : 'var(--color-danger)';
              return (
                <div style={{ marginTop: 16, padding: '12px 16px', background: 'var(--surface-secondary)', borderRadius: 10, border: '1px solid var(--border-subtle)' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
                    <div>
                      <span className="text-sm" style={{ fontWeight: 600 }}>Hunter.io Credits</span>
                      <span className="text-xs text-secondary" style={{ marginLeft: 8 }}>
                        {h.plan} plan · {used} used / {total} total · <strong style={{ color }}>{avail} remaining</strong>
                      </span>
                    </div>
                    <button className="btn btn-ghost btn-sm" onClick={() => loadQuota(true)} disabled={quotaLoading} title="Refresh quota">
                      <RefreshCw size={12} className={quotaLoading ? 'spin-icon' : ''} />
                    </button>
                  </div>
                  <div style={{ background: 'var(--surface-tertiary)', borderRadius: 6, height: 8, overflow: 'hidden' }}>
                    <div style={{ width: `${pct}%`, height: '100%', background: color, borderRadius: 6, transition: 'width 0.4s ease' }} />
                  </div>
                  {avail < 5 && (
                    <p className="text-xs" style={{ color: 'var(--color-danger)', marginTop: 6 }}>
                      ⚠️ Only {avail} searches left this month. Cached contacts will be used for repeat domains automatically.
                    </p>
                  )}
                  {quota.cached && (
                    <p className="text-xs text-secondary" style={{ marginTop: 4 }}>
                      <Clock size={10} style={{ marginRight: 3 }} />
                      Quota cached · <button className="btn-link text-xs" onClick={() => loadQuota(true)}>Refresh now</button>
                    </p>
                  )}
                </div>
              );
            })()}
          </div>

          <div className="form-actions" style={{ justifyContent: 'flex-end' }}>
            <button className="btn btn-primary" onClick={handleSaveAIPref} disabled={savingPref}>
              {savingPref ? <span className="spinner" style={{ width: 16, height: 16 }} /> : 'Save Preferences'}
            </button>
          </div>
        </div>
      )}

      {/* ── Email Style Tab ────────────────────────────────── */}
      {tab === 'style' && (
        <div className="card settings-section">
          <div className="section-header">
            <div>
              <h3><Pencil size={16} /> Email Style</h3>
              <p className="text-secondary text-sm">Set your signature and guide the AI on tone and voice.</p>
            </div>
          </div>
          <form onSubmit={handleSaveStyle} className="smtp-form">
            <div className="form-grid">
              <div className="input-group">
                <label className="input-label">Your Name (for signature)</label>
                <input className="input" placeholder="Jane Doe" value={style.signature_name}
                  onChange={e => setStyle(p => ({ ...p, signature_name: e.target.value }))} />
              </div>
              <div className="input-group">
                <label className="input-label">Title (for signature)</label>
                <input className="input" placeholder="Full-Stack Engineer" value={style.signature_title}
                  onChange={e => setStyle(p => ({ ...p, signature_title: e.target.value }))} />
              </div>
              <div className="input-group">
                <label className="input-label">LinkedIn URL</label>
                <input className="input" placeholder="linkedin.com/in/yourhandle" value={style.signature_linkedin}
                  onChange={e => setStyle(p => ({ ...p, signature_linkedin: e.target.value }))} />
              </div>
            </div>
            <div className="input-group" style={{ marginTop: 16 }}>
              <label className="input-label">Custom AI Instructions</label>
              <textarea className="input" rows={4}
                placeholder="e.g. Keep emails under 120 words. Always reference one specific thing about the company. Never use phrases like 'I hope this finds you well'."
                value={style.custom_instructions}
                onChange={e => setStyle(p => ({ ...p, custom_instructions: e.target.value }))} />
              <span className="text-sm text-secondary" style={{ marginTop: 4 }}>
                These instructions are appended to every email generation prompt.
              </span>
            </div>
            <div className="form-actions">
              <button type="submit" className="btn btn-primary" disabled={savingStyle}>
                {savingStyle ? <span className="spinner" style={{ width: 16, height: 16 }} /> : 'Save Style'}
              </button>
            </div>
          </form>
        </div>
      )}

      {/* ── Campaign Defaults Tab ─────────────────────────── */}
      {tab === 'defaults' && (
        <div className="card settings-section">
          <div className="section-header">
            <div>
              <h3><SettingsIcon size={16} /> Campaign Defaults</h3>
              <p className="text-secondary text-sm">These apply to all new campaigns. Override per-campaign in Campaign Detail.</p>
            </div>
          </div>
          <form onSubmit={handleSaveDefaults} className="smtp-form">
            <div className="form-grid">
              <div className="input-group">
                <label className="input-label">Send Delay (seconds between emails)</label>
                <input className="input" type="number" min={60} max={3600}
                  value={defaults.send_delay_seconds}
                  onChange={e => setDefaults(p => ({ ...p, send_delay_seconds: +e.target.value }))} />
                <span className="text-sm text-secondary">Minimum: 60s. Recommended: 120–300s.</span>
              </div>
              <div className="input-group">
                <label className="input-label">Max Emails Per Day</label>
                <input className="input" type="number" min={1} max={100}
                  value={defaults.max_emails_per_day}
                  onChange={e => setDefaults(p => ({ ...p, max_emails_per_day: +e.target.value }))} />
                <span className="text-sm text-secondary">Stay under 50/day to protect your domain reputation.</span>
              </div>
            </div>
            <div className="sandbox-toggle-row">
              <div>
                <span className="font-medium">Sandbox Mode (default ON)</span>
                <p className="text-sm text-secondary">When on, emails are previewed but NOT sent. Always start here.</p>
              </div>
              <button type="button" className="mode-toggle-btn"
                onClick={() => setDefaults(p => ({ ...p, sandbox_mode: !p.sandbox_mode }))}>
                {defaults.sandbox_mode
                  ? <><ToggleRight size={22} className="toggle-on" /> Sandbox ON</>
                  : <><ToggleLeft size={22} /> Sandbox OFF</>}
              </button>
            </div>
            <div className="form-actions">
              <button type="submit" className="btn btn-primary" disabled={savingDefaults}>
                {savingDefaults ? <span className="spinner" style={{ width: 16, height: 16 }} /> : 'Save Defaults'}
              </button>
            </div>
          </form>
        </div>
      )}
    </div>
  );
}
