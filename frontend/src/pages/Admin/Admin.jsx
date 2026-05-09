import { useState, useEffect } from 'react';
import { api } from '../../lib/api';
import { useToast } from '../../contexts/ToastContext';
import {
  Users, UserPlus, Shield, Copy, Check, Ban, RefreshCw,
  Activity, ChevronRight, X, Eye
} from 'lucide-react';
import './Admin.css';

export default function Admin() {
  const toast = useToast();
  const [tab, setTab] = useState('users');
  const [users, setUsers] = useState([]);
  const [invites, setInvites] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showInviteModal, setShowInviteModal] = useState(false);
  const [inviteEmail, setInviteEmail] = useState('');
  const [creating, setCreating] = useState(false);
  const [selectedUser, setSelectedUser] = useState(null);

  useEffect(() => {
    if (tab === 'users') loadUsers();
    else loadInvites();
  }, [tab]);

  async function loadUsers() {
    setLoading(true);
    try {
      const data = await api.listUsers();
      setUsers(Array.isArray(data) ? data : []);
    } catch (err) {
      toast.error('Failed to load users');
    } finally {
      setLoading(false);
    }
  }

  async function loadInvites() {
    setLoading(true);
    try {
      const data = await api.listInvites();
      setInvites(Array.isArray(data) ? data : []);
    } catch (err) {
      toast.error('Failed to load invites');
    } finally {
      setLoading(false);
    }
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
    } catch (err) {
      toast.error(err.message);
    } finally {
      setCreating(false);
    }
  }

  async function handleDeactivate(userId) {
    try {
      await api.deactivateUser(userId);
      toast.success('User deactivated');
      loadUsers();
    } catch (err) {
      toast.error(err.message);
    }
  }

  async function handleReactivate(userId) {
    try {
      await api.reactivateUser(userId);
      toast.success('User reactivated');
      loadUsers();
    } catch (err) {
      toast.error(err.message);
    }
  }

  function copyInviteCode(code) {
    navigator.clipboard.writeText(code);
    toast.success('Copied to clipboard');
  }

  return (
    <div className="admin-page">
      <div className="page-header flex justify-between items-center">
        <div>
          <h1>Admin Panel</h1>
          <p>Manage users and invite codes</p>
        </div>
        <button className="btn btn-primary" onClick={() => setShowInviteModal(true)}>
          <UserPlus size={16} /> Create Invite
        </button>
      </div>

      {/* Tabs */}
      <div className="admin-tabs">
        <button
          className={`tab ${tab === 'users' ? 'tab-active' : ''}`}
          onClick={() => setTab('users')}
        >
          <Users size={16} /> Users
        </button>
        <button
          className={`tab ${tab === 'invites' ? 'tab-active' : ''}`}
          onClick={() => setTab('invites')}
        >
          <Shield size={16} /> Invite Codes
        </button>
      </div>

      {/* Users Table */}
      {tab === 'users' && (
        <div className="table-container">
          <table>
            <thead>
              <tr>
                <th>User</th>
                <th>Mode</th>
                <th>Status</th>
                <th>Joined</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr><td colSpan={5} style={{ textAlign: 'center', padding: 40 }}>
                  <span className="spinner" style={{ margin: '0 auto' }} />
                </td></tr>
              ) : users.length === 0 ? (
                <tr><td colSpan={5} style={{ textAlign: 'center', padding: 40, color: 'var(--text-tertiary)' }}>
                  No users yet
                </td></tr>
              ) : users.map(user => (
                <tr key={user.id}>
                  <td>
                    <div className="user-cell">
                      <div className="user-avatar-sm">{user.display_name?.[0] || user.email?.[0] || '?'}</div>
                      <div>
                        <span className="font-medium">{user.display_name || 'Unknown'}</span>
                        <span className="text-sm text-secondary" style={{ display: 'block' }}>
                          {user.email}
                        </span>
                      </div>
                    </div>
                  </td>
                  <td>
                    <span className="badge badge-primary">{user.mode || 'beginner'}</span>
                  </td>
                  <td>
                    <span className={`badge ${user.is_active !== false ? 'badge-success' : 'badge-danger'}`}>
                      {user.is_active !== false ? 'Active' : 'Deactivated'}
                    </span>
                  </td>
                  <td className="text-sm text-secondary">
                    {user.created_at ? new Date(user.created_at).toLocaleDateString() : '—'}
                  </td>
                  <td>
                    <div className="action-btns">
                      {user.is_active !== false ? (
                        <button className="btn btn-ghost btn-sm" onClick={() => handleDeactivate(user.id)}>
                          <Ban size={14} /> Deactivate
                        </button>
                      ) : (
                        <button className="btn btn-ghost btn-sm" onClick={() => handleReactivate(user.id)}>
                          <RefreshCw size={14} /> Reactivate
                        </button>
                      )}
                    </div>
                  </td>
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
            <thead>
              <tr>
                <th>Code</th>
                <th>Email</th>
                <th>Status</th>
                <th>Created</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr><td colSpan={5} style={{ textAlign: 'center', padding: 40 }}>
                  <span className="spinner" style={{ margin: '0 auto' }} />
                </td></tr>
              ) : invites.length === 0 ? (
                <tr><td colSpan={5} style={{ textAlign: 'center', padding: 40, color: 'var(--text-tertiary)' }}>
                  No invite codes
                </td></tr>
              ) : invites.map(inv => (
                <tr key={inv.code || inv.id}>
                  <td>
                    <code className="invite-code">{inv.code}</code>
                  </td>
                  <td className="text-sm text-secondary">{inv.email || '—'}</td>
                  <td>
                    <span className={`badge ${inv.used ? 'badge-success' : 'badge-info'}`}>
                      {inv.used ? 'Used' : 'Available'}
                    </span>
                  </td>
                  <td className="text-sm text-secondary">
                    {inv.created_at ? new Date(inv.created_at).toLocaleDateString() : '—'}
                  </td>
                  <td>
                    {!inv.used && (
                      <button className="btn btn-ghost btn-sm" onClick={() => copyInviteCode(inv.code)}>
                        <Copy size={14} /> Copy
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Create Invite Modal */}
      {showInviteModal && (
        <div className="modal-overlay" onClick={() => setShowInviteModal(false)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <h2>Create Invite Code</h2>
              <button className="btn-ghost btn-icon" onClick={() => setShowInviteModal(false)}>
                <X size={18} />
              </button>
            </div>
            <form onSubmit={handleCreateInvite} className="modal-form">
              <div className="input-group">
                <label className="input-label">Email (optional)</label>
                <input
                  className="input"
                  type="email"
                  placeholder="restrict to specific email"
                  value={inviteEmail}
                  onChange={e => setInviteEmail(e.target.value)}
                />
                <span className="text-sm text-tertiary">
                  Leave empty to create a universal invite code.
                </span>
              </div>
              <div className="modal-actions">
                <button type="button" className="btn btn-secondary" onClick={() => setShowInviteModal(false)}>
                  Cancel
                </button>
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
