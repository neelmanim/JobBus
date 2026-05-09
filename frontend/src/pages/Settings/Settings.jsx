import { useState, useEffect } from 'react';
import { api } from '../../lib/api';
import { useAuth } from '../../contexts/AuthContext';
import { useToast } from '../../contexts/ToastContext';
import {
  Mail, Key, Shield, Eye, EyeOff, Check,
  AlertCircle, Trash2, Send, ToggleLeft, ToggleRight
} from 'lucide-react';
import './Settings.css';

export default function Settings() {
  const { profile, refreshProfile } = useAuth();
  const toast = useToast();
  const [smtpStatus, setSmtpStatus] = useState(null);
  const [showSmtpForm, setShowSmtpForm] = useState(false);
  const [smtpForm, setSmtpForm] = useState({
    email: '', password: '', smtp_host: 'smtp.gmail.com', smtp_port: 587,
  });
  const [showPassword, setShowPassword] = useState(false);
  const [saving, setSaving] = useState(false);
  const [testEmail, setTestEmail] = useState('');
  const [testing, setTesting] = useState(false);

  useEffect(() => { loadStatus(); }, []);

  async function loadStatus() {
    try {
      const status = await api.getSmtpStatus();
      setSmtpStatus(status);
    } catch (err) {
      setSmtpStatus(null);
    }
  }

  async function handleSaveSMTP(e) {
    e.preventDefault();
    setSaving(true);
    try {
      await api.configureSMTP(smtpForm);
      toast.success('SMTP configured successfully');
      setShowSmtpForm(false);
      loadStatus();
    } catch (err) {
      toast.error(err.message || 'Failed to save');
    } finally {
      setSaving(false);
    }
  }

  async function handleDeleteSMTP() {
    try {
      await api.deleteSMTP();
      toast.success('SMTP credentials removed');
      setSmtpStatus(null);
    } catch (err) {
      toast.error(err.message);
    }
  }

  async function handleTestSMTP() {
    if (!testEmail) return;
    setTesting(true);
    try {
      await api.testSMTP(testEmail);
      toast.success('Test email sent! Check your inbox.');
    } catch (err) {
      toast.error(err.message || 'Test failed');
    } finally {
      setTesting(false);
    }
  }

  async function handleModeToggle() {
    const newMode = profile?.mode === 'advanced' ? 'beginner' : 'advanced';
    try {
      await api.updateMode(newMode);
      await refreshProfile();
      toast.success(`Switched to ${newMode} mode`);
    } catch (err) {
      toast.error(err.message);
    }
  }

  return (
    <div className="settings-page">
      <div className="page-header">
        <h1>Settings</h1>
        <p>Configure your email sending and preferences</p>
      </div>

      {/* Mode Toggle */}
      <div className="card settings-section">
        <div className="section-header">
          <div>
            <h3>Interface Mode</h3>
            <p className="text-secondary text-sm">
              Beginner mode hides advanced settings. Switch to Advanced for full control.
            </p>
          </div>
          <button className="mode-toggle" onClick={handleModeToggle}>
            {profile?.mode === 'advanced' ? (
              <><ToggleRight size={24} className="toggle-on" /> Advanced</>
            ) : (
              <><ToggleLeft size={24} /> Beginner</>
            )}
          </button>
        </div>
      </div>

      {/* SMTP Configuration */}
      <div className="card settings-section">
        <div className="section-header">
          <div>
            <h3><Mail size={18} /> Email (SMTP)</h3>
            <p className="text-secondary text-sm">
              Configure your email credentials for sending outreach messages.
            </p>
          </div>
          {smtpStatus?.configured ? (
            <span className="badge badge-success"><Check size={12} /> Connected</span>
          ) : (
            <span className="badge badge-warning"><AlertCircle size={12} /> Not configured</span>
          )}
        </div>

        {smtpStatus?.configured && !showSmtpForm ? (
          <div className="smtp-connected">
            <div className="smtp-info">
              <span className="text-sm"><strong>Email:</strong> {smtpStatus.email || '***'}</span>
              <span className="text-sm"><strong>Host:</strong> {smtpStatus.host || 'smtp.gmail.com'}</span>
            </div>
            <div className="smtp-actions">
              <div className="test-email-group">
                <input
                  className="input"
                  placeholder="test@example.com"
                  value={testEmail}
                  onChange={e => setTestEmail(e.target.value)}
                  style={{ maxWidth: 250 }}
                />
                <button
                  className="btn btn-secondary btn-sm"
                  onClick={handleTestSMTP}
                  disabled={testing || !testEmail}
                >
                  {testing ? <span className="spinner" /> : <><Send size={14} /> Test</>}
                </button>
              </div>
              <button className="btn btn-ghost btn-sm" onClick={() => setShowSmtpForm(true)}>
                Reconfigure
              </button>
              <button className="btn btn-danger btn-sm" onClick={handleDeleteSMTP}>
                <Trash2 size={14} /> Remove
              </button>
            </div>
          </div>
        ) : (
          <form onSubmit={handleSaveSMTP} className="smtp-form">
            <div className="form-grid">
              <div className="input-group">
                <label className="input-label">Email Address</label>
                <input
                  className="input"
                  type="email"
                  placeholder="your.email@gmail.com"
                  value={smtpForm.email}
                  onChange={e => setSmtpForm(p => ({ ...p, email: e.target.value }))}
                  required
                />
              </div>
              <div className="input-group">
                <label className="input-label">App Password</label>
                <div className="password-input">
                  <input
                    className="input"
                    type={showPassword ? 'text' : 'password'}
                    placeholder="Your app-specific password"
                    value={smtpForm.password}
                    onChange={e => setSmtpForm(p => ({ ...p, password: e.target.value }))}
                    required
                  />
                  <button
                    type="button"
                    className="password-toggle"
                    onClick={() => setShowPassword(!showPassword)}
                  >
                    {showPassword ? <EyeOff size={16} /> : <Eye size={16} />}
                  </button>
                </div>
              </div>
              {profile?.mode === 'advanced' && (
                <>
                  <div className="input-group">
                    <label className="input-label">SMTP Host</label>
                    <input
                      className="input"
                      value={smtpForm.smtp_host}
                      onChange={e => setSmtpForm(p => ({ ...p, smtp_host: e.target.value }))}
                    />
                  </div>
                  <div className="input-group">
                    <label className="input-label">SMTP Port</label>
                    <input
                      className="input"
                      type="number"
                      value={smtpForm.smtp_port}
                      onChange={e => setSmtpForm(p => ({ ...p, smtp_port: parseInt(e.target.value) }))}
                    />
                  </div>
                </>
              )}
            </div>
            <div className="smtp-form-hint">
              <Shield size={14} />
              <span>Credentials are encrypted at rest with AES-256. Never stored in plaintext.</span>
            </div>
            <div className="form-actions">
              {smtpStatus?.configured && (
                <button type="button" className="btn btn-ghost" onClick={() => setShowSmtpForm(false)}>
                  Cancel
                </button>
              )}
              <button type="submit" className="btn btn-primary" disabled={saving}>
                {saving ? <span className="spinner" /> : 'Save Credentials'}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}
