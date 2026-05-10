import { useState, useEffect } from 'react';
import { api } from '../../lib/api';
import { useToast } from '../../contexts/ToastContext';
import {
  Users, UserPlus, Shield, Copy, Ban, RefreshCw,
  Settings, BarChart2, X, Key, Save, Loader,
  TrendingUp, Mail, Search, Zap, AlertTriangle
} from 'lucide-react';
import './Admin.css';

const TABS = [
  { id: 'users',    label: 'Users',          icon: Users    },
  { id: 'invites',  label: 'Invite Codes',   icon: Shield   },
  { id: 'config',   label: 'Platform Config', icon: Settings },
  { id: 'usage',    label: 'Usage',          icon: BarChart2 },
];

/* ── Platform Config Tab ─────────────────────────────────── */
function PlatformConfig() {
  const toast = useToast();
  const [config, setConfig] = useState({
    system_groq_key: '',
    system_hunter_key: '',
    max_emails_per_user_per_day: '20',
    enable_follow_ups: 'false',
    enable_ollama: 'false',
  });
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => { loadConfig(); }, []);

  async function loadConfig() {
    setLoading(true);
    try {
      const data = await api.getSystemConfig();
      if (data) setConfig(prev => ({ ...prev, ...data }));
    } catch { /* silent */ }
    finally { setLoading(false); }
  }

  async function handleSave() {
    setSaving(true);
    try {
      await api.saveSystemConfig(config);
      toast.success('Platform config saved');
    } catch (err) {
      toast.error(err.message || 'Save failed');
    } finally {
      setSaving(false);
    }
  }

  if (loading) return <div style={{ padding: 40, textAlign: 'center' }}><span className="spinner" style={{ margin: '0 auto' }} /></div>;

  return (
    <div className="config-panel">
      <div className="config-warning">
        <AlertTriangle size={16} />
        <span>These are system-level keys used in Beginner Mode. Treat them as production secrets.</span>
      </div>

      <div className="config-section">
        <h3 className="config-section-title">System API Keys (Beginner Mode)</h3>
        <div className="config-grid">
          <div className="input-group">
            <label className="input-label"><Zap size={13} /> Groq API Key (system fallback)</label>
            <input className="input input-mono" type="password" placeholder="gsk_..."
              value={config.system_groq_key}
              onChange={e => setConfig(p => ({ ...p, system_groq_key: e.target.value }))} />
          </div>
          <div className="input-group">
            <label className="input-label"><Search size={13} /> Hunter API Key (system fallback)</label>
            <input className="input input-mono" type="password" placeholder="hunter_..."
              value={config.system_hunter_key}
              onChange={e => setConfig(p => ({ ...p, system_hunter_key: e.target.value }))} />
          </div>
        </div>
      </div>

      <div className="config-section">
        <h3 className="config-section-title">Global Limits</h3>
        <div className="config-grid">
          <div className="input-group">
            <label className="input-label"><Mail size={13} /> Max Emails Per User / Day</label>
            <input className="input" type="number" min={1} max={200}
              value={config.max_emails_per_user_per_day}
              onChange={e => setConfig(p => ({ ...p, max_emails_per_user_per_day: e.target.value }))} />
          </div>
        </div>
      </div>

      <div className="config-section">
        <h3 className="config-section-title">Feature Flags</h3>
        <div className="flag-list">
          {[
            { key: 'enable_follow_ups', label: 'Enable Follow-up Scheduling' },
            { key: 'enable_ollama',     label: 'Allow Ollama (Local AI)' },
          ].map(f => (
            <label key={f.key} className="flag-row">
              <input type="checkbox"
                checked={config[f.key] === 'true'}
                onChange={e => setConfig(p => ({ ...p, [f.key]: e.target.checked ? 'true' : 'false' }))} />
              <span>{f.label}</span>
            </label>
          ))}
        </div>
      </div>

      <button className="btn btn-primary" onClick={handleSave} disabled={saving} style={{ alignSelf: 'flex-start' }}>
        {saving ? <Loader size={15} className="spin-icon" /> : <Save size={15} />} Save Config
      </button>
    </div>
  );
}

/* ── Usage Tab ───────────────────────────────────────────── */
function UsagePanel() {
  const [usage, setUsage] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => { loadUsage(); }, []);

  async function loadUsage() {
    setLoading(true);
    try {
      const data = await api.getPlatformUsage();
      setUsage(data);
    } catch { setUsage(null); }
    finally { setLoading(false); }
  }

  if (loading) return <div style={{ padding: 40, textAlign: 'center' }}><span className="spinner" style={{ margin: '0 auto' }} /></div>;
  if (!usage)  return <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-tertiary)' }}>Usage data unavailable</div>;

  const metrics = [
    { label: 'Total Users',      value: usage.total_users      ?? '—', icon: Users,     color: 'primary' },
    { label: 'Campaigns',        value: usage.total_campaigns  ?? '—', icon: Zap,       color: 'accent'  },
    { label: 'Emails Sent',      value: usage.total_emails_sent ?? '—', icon: Mail,     color: 'info'    },
    { label: 'Contacts Found',   value: usage.total_contacts   ?? '—', icon: Search,   color: 'success' },
    { label: 'Reply Rate',       value: usage.reply_rate != null ? `${usage.reply_rate}%` : '—', icon: TrendingUp, color: 'success' },
  ];

  return (
    <div className="usage-panel">
      <div className="usage-stats">
        {metrics.map((m, i) => {
          const Icon = m.icon;
          return (
            <div key={i} className={`usage-stat-card usage-color-${m.color}`}>
              <Icon size={20} />
              <div className="usage-num">{m.value}</div>
              <div className="usage-label">{m.label}</div>
            </div>
          );
        })}
      </div>

      {usage.top_users?.length > 0 && (
        <div className="usage-section">
          <h3 className="config-section-title">Top Users by Emails Sent</h3>
          <div className="table-container">
            <table>
              <thead><tr><th>User</th><th>Emails</th><th>Campaigns</th><th>Replies</th></tr></thead>
              <tbody>
                {usage.top_users.map((u, i) => (
                  <tr key={i}>
                    <td><div className="user-cell">
                      <div className="user-avatar-sm">{u.display_name?.[0] || '?'}</div>
                      <div><span className="font-medium">{u.display_name || 'Unknown'}</span><span className="text-sm text-secondary" style={{ display: 'block' }}>{u.email}</span></div>
                    </div></td>
                    <td className="font-medium">{u.emails_sent ?? 0}</td>
                    <td>{u.campaigns ?? 0}</td>
                    <td>{u.replies ?? 0}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}

/* ── Main Admin Page ─────────────────────────────────────── */
export default function Admin() {
  const toast = useToast();
  const [tab, setTab] = useState('users');
  const [users, setUsers] = useState([]);
  const [invites, setInvites] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showInviteModal, setShowInviteModal] = useState(false);
  const [inviteEmail, setInviteEmail] = useState('');
  const [creating, setCreating] = useState(false);

  useEffect(() => {
    if (tab === 'users')   loadUsers();
    if (tab === 'invites') loadInvites();
  }, [tab]);

  async function loadUsers() {
    setLoading(true);
    try { setUsers(Array.isArray(await api.listUsers()) ? await api.listUsers() : []); }
    catch { toast.error('Failed to load users'); }
    finally { setLoading(false); }
  }

  async function loadInvites() {
    setLoading(true);
    try { setInvites(Array.isArray(await api.listInvites()) ? await api.listInvites() : []); }
    catch { toast.error('Failed to load invites'); }
    finally { setLoading(false); }
  }

  async function handleCreateInvite(e) {
    e.preventDefault();
    setCreating(true);
    try {
      const result = await api.createInvite({ email: inviteEmail || undefined });
      toast.success(`Invite created: ${result.code || 'OK'}`);
      setShowInviteModal(false);
      setInviteEmail('');
      if (tab === 'invites') loadInvites();
    } catch (err) { toast.error(err.message); }
    finally { setCreating(false); }
  }

  function copyInviteCode(code) { navigator.clipboard.writeText(code); toast.success('Copied!'); }

  return (
    <div className="admin-page">
      <div className="page-header flex justify-between items-center">
        <div>
          <h1>Admin Panel</h1>
          <p>Manage users, invites, platform configuration and usage</p>
        </div>
        <button className="btn btn-primary" onClick={() => setShowInviteModal(true)}>
          <UserPlus size={16} /> Create Invite
        </button>
      </div>

      {/* Tabs */}
      <div className="admin-tabs">
        {TABS.map(t => {
          const Icon = t.icon;
          return (
            <button key={t.id} className={`tab ${tab === t.id ? 'tab-active' : ''}`} onClick={() => setTab(t.id)}>
              <Icon size={15} /> {t.label}
            </button>
          );
        })}
      </div>

      {/* Users Table */}
      {tab === 'users' && (
        <div className="table-container">
          <table>
            <thead><tr><th>User</th><th>Mode</th><th>Onboarded</th><th>Status</th><th>Joined</th><th>Actions</th></tr></thead>
            <tbody>
              {loading ? (
                <tr><td colSpan={6} style={{ textAlign: 'center', padding: 40 }}><span className="spinner" style={{ margin: '0 auto' }} /></td></tr>
              ) : users.length === 0 ? (
                <tr><td colSpan={6} style={{ textAlign: 'center', padding: 40, color: 'var(--text-tertiary)' }}>No users yet</td></tr>
              ) : users.map(user => (
                <tr key={user.id}>
                  <td><div className="user-cell">
                    <div className="user-avatar-sm">{user.display_name?.[0] || user.email?.[0] || '?'}</div>
                    <div><span className="font-medium">{user.display_name || 'Unknown'}</span>
                      <span className="text-sm text-secondary" style={{ display: 'block' }}>{user.email}</span></div>
                  </div></td>
                  <td><span className="badge badge-primary">{user.mode || 'beginner'}</span></td>
                  <td><span className={`badge ${user.onboarding_complete ? 'badge-success' : 'badge-warning'}`}>{user.onboarding_complete ? '✓' : 'Pending'}</span></td>
                  <td><span className={`badge ${user.is_active !== false ? 'badge-success' : 'badge-danger'}`}>{user.is_active !== false ? 'Active' : 'Deactivated'}</span></td>
                  <td className="text-sm text-secondary">{user.created_at ? new Date(user.created_at).toLocaleDateString() : '—'}</td>
                  <td><div className="action-btns">
                    {user.is_active !== false ? (
                      <button className="btn btn-ghost btn-sm" onClick={async () => { await api.deactivateUser(user.id); toast.success('Deactivated'); loadUsers(); }}>
                        <Ban size={14} /> Deactivate
                      </button>
                    ) : (
                      <button className="btn btn-ghost btn-sm" onClick={async () => { await api.reactivateUser(user.id); toast.success('Reactivated'); loadUsers(); }}>
                        <RefreshCw size={14} /> Reactivate
                      </button>
                    )}
                  </div></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Invites Table */}
      {tab === 'invites' && (
        <div className="table-container">
          <table>
            <thead><tr><th>Code</th><th>Email</th><th>Status</th><th>Created</th><th>Actions</th></tr></thead>
            <tbody>
              {loading ? (
                <tr><td colSpan={5} style={{ textAlign: 'center', padding: 40 }}><span className="spinner" style={{ margin: '0 auto' }} /></td></tr>
              ) : invites.length === 0 ? (
                <tr><td colSpan={5} style={{ textAlign: 'center', padding: 40, color: 'var(--text-tertiary)' }}>No invite codes</td></tr>
              ) : invites.map(inv => (
                <tr key={inv.code || inv.id}>
                  <td><code className="invite-code">{inv.code}</code></td>
                  <td className="text-sm text-secondary">{inv.email || '—'}</td>
                  <td><span className={`badge ${inv.used ? 'badge-success' : 'badge-info'}`}>{inv.used ? 'Used' : 'Available'}</span></td>
                  <td className="text-sm text-secondary">{inv.created_at ? new Date(inv.created_at).toLocaleDateString() : '—'}</td>
                  <td>{!inv.used && <button className="btn btn-ghost btn-sm" onClick={() => copyInviteCode(inv.code)}><Copy size={14} /> Copy</button>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Platform Config */}
      {tab === 'config' && <PlatformConfig />}

      {/* Usage */}
      {tab === 'usage' && <UsagePanel />}

      {/* Create Invite Modal */}
      {showInviteModal && (
        <div className="modal-overlay" onClick={() => setShowInviteModal(false)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <h2>Create Invite Code</h2>
              <button className="btn-ghost btn-icon" onClick={() => setShowInviteModal(false)}><X size={18} /></button>
            </div>
            <form onSubmit={handleCreateInvite} className="modal-form">
              <div className="input-group">
                <label className="input-label">Email (optional)</label>
                <input className="input" type="email" placeholder="restrict to specific email"
                  value={inviteEmail} onChange={e => setInviteEmail(e.target.value)} />
                <span className="text-sm text-tertiary">Leave empty to create a universal invite code.</span>
              </div>
              <div className="modal-actions">
                <button type="button" className="btn btn-secondary" onClick={() => setShowInviteModal(false)}>Cancel</button>
                <button type="submit" className="btn btn-primary" disabled={creating}>
                  {creating ? <span className="spinner" /> : 'Create Invite'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
