import { useState, useEffect } from 'react';
import { api } from '../../lib/api';
import { useToast } from '../../contexts/ToastContext';
import {
  Plus, Send, Pause, Play, Square, BarChart3,
  Mail, Users, Clock, ChevronRight, X, Trash2
} from 'lucide-react';
import './Campaigns.css';

export default function Campaigns() {
  const toast = useToast();
  const [campaigns, setCampaigns] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showCreate, setShowCreate] = useState(false);
  const [creating, setCreating] = useState(false);
  const [newCampaign, setNewCampaign] = useState({ name: '', description: '', target_role: '' });
  const [expandedId, setExpandedId] = useState(null);

  useEffect(() => { loadCampaigns(); }, []);

  async function loadCampaigns() {
    try {
      const data = await api.listCampaigns();
      setCampaigns(Array.isArray(data) ? data : []);
    } catch (err) {
      toast.error('Failed to load campaigns');
    } finally {
      setLoading(false);
    }
  }

  async function handleCreate(e) {
    e.preventDefault();
    if (!newCampaign.name.trim()) return;
    setCreating(true);
    try {
      await api.createCampaign(newCampaign);
      toast.success('Campaign created');
      setShowCreate(false);
      setNewCampaign({ name: '', description: '', target_role: '' });
      loadCampaigns();
    } catch (err) {
      toast.error(err.message || 'Failed to create campaign');
    } finally {
      setCreating(false);
    }
  }

  async function handleStatusChange(id, status) {
    try {
      await api.updateCampaignStatus(id, status);
      toast.success(`Campaign ${status}`);
      loadCampaigns();
    } catch (err) {
      toast.error(err.message);
    }
  }

  function getStatusBadge(status) {
    const map = {
      draft: 'badge-info',
      active: 'badge-success',
      paused: 'badge-warning',
      completed: 'badge-primary',
      stopped: 'badge-danger',
    };
    return map[status] || 'badge-info';
  }

  return (
    <div className="campaigns-page">
      <div className="page-header flex justify-between items-center">
        <div>
          <h1>Campaigns</h1>
          <p>Manage your outreach campaigns</p>
        </div>
        <button className="btn btn-primary" onClick={() => setShowCreate(true)}>
          <Plus size={16} /> New Campaign
        </button>
      </div>

      {/* Campaign List */}
      {loading ? (
        <div className="campaign-loading">
          {[1,2].map(i => (
            <div key={i} className="card campaign-skeleton">
              <div className="skeleton" style={{ width: '50%', height: 22, marginBottom: 12 }} />
              <div className="skeleton" style={{ width: '30%', height: 16 }} />
            </div>
          ))}
        </div>
      ) : campaigns.length > 0 ? (
        <div className="campaign-list">
          {campaigns.map(c => (
            <div key={c.id} className="card campaign-card">
              <div
                className="campaign-header"
                onClick={() => setExpandedId(expandedId === c.id ? null : c.id)}
              >
                <div className="campaign-info">
                  <h3>{c.name}</h3>
                  <div className="campaign-meta">
                    <span className={`badge ${getStatusBadge(c.status)}`}>{c.status}</span>
                    {c.target_role && <span className="text-sm text-secondary">{c.target_role}</span>}
                  </div>
                </div>
                <div className="campaign-stats">
                  <div className="mini-stat">
                    <Users size={14} />
                    <span>{c.total_contacts || 0}</span>
                  </div>
                  <div className="mini-stat">
                    <Mail size={14} />
                    <span>{c.total_sent || 0}</span>
                  </div>
                  <div className="mini-stat">
                    <BarChart3 size={14} />
                    <span>{c.total_replies || 0}</span>
                  </div>
                  <ChevronRight
                    size={16}
                    className={`expand-arrow ${expandedId === c.id ? 'expanded' : ''}`}
                  />
                </div>
              </div>

              {expandedId === c.id && (
                <div className="campaign-expanded">
                  {c.description && (
                    <p className="campaign-desc text-secondary">{c.description}</p>
                  )}
                  <div className="campaign-actions">
                    {c.status === 'draft' && (
                      <button
                        className="btn btn-primary btn-sm"
                        onClick={() => handleStatusChange(c.id, 'active')}
                      >
                        <Play size={14} /> Start
                      </button>
                    )}
                    {c.status === 'active' && (
                      <button
                        className="btn btn-secondary btn-sm"
                        onClick={() => handleStatusChange(c.id, 'paused')}
                      >
                        <Pause size={14} /> Pause
                      </button>
                    )}
                    {c.status === 'paused' && (
                      <button
                        className="btn btn-primary btn-sm"
                        onClick={() => handleStatusChange(c.id, 'active')}
                      >
                        <Play size={14} /> Resume
                      </button>
                    )}
                    {(c.status === 'active' || c.status === 'paused') && (
                      <button
                        className="btn btn-danger btn-sm"
                        onClick={() => handleStatusChange(c.id, 'stopped')}
                      >
                        <Square size={14} /> Stop
                      </button>
                    )}
                  </div>
                </div>
              )}
            </div>
          ))}
        </div>
      ) : (
        <div className="empty-state">
          <div className="empty-icon"><Send size={32} /></div>
          <h3>No campaigns yet</h3>
          <p>Create your first outreach campaign to start connecting with opportunities.</p>
          <button className="btn btn-primary" onClick={() => setShowCreate(true)} style={{ marginTop: 16 }}>
            <Plus size={16} /> Create Campaign
          </button>
        </div>
      )}

      {/* Create Modal */}
      {showCreate && (
        <div className="modal-overlay" onClick={() => setShowCreate(false)}>
          <div className="modal" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <h2>New Campaign</h2>
              <button className="btn-ghost btn-icon" onClick={() => setShowCreate(false)}>
                <X size={18} />
              </button>
            </div>
            <form onSubmit={handleCreate} className="modal-form">
              <div className="input-group">
                <label className="input-label">Campaign Name *</label>
                <input
                  className="input"
                  placeholder="e.g. Frontend roles at Series B startups"
                  value={newCampaign.name}
                  onChange={e => setNewCampaign(p => ({ ...p, name: e.target.value }))}
                  autoFocus
                />
              </div>
              <div className="input-group">
                <label className="input-label">Target Role</label>
                <input
                  className="input"
                  placeholder="e.g. Senior Frontend Engineer"
                  value={newCampaign.target_role}
                  onChange={e => setNewCampaign(p => ({ ...p, target_role: e.target.value }))}
                />
              </div>
              <div className="input-group">
                <label className="input-label">Description</label>
                <textarea
                  className="input"
                  placeholder="What this campaign is about..."
                  value={newCampaign.description}
                  onChange={e => setNewCampaign(p => ({ ...p, description: e.target.value }))}
                  rows={3}
                />
              </div>
              <div className="modal-actions">
                <button type="button" className="btn btn-secondary" onClick={() => setShowCreate(false)}>
                  Cancel
                </button>
                <button type="submit" className="btn btn-primary" disabled={creating || !newCampaign.name.trim()}>
                  {creating ? <span className="spinner" /> : 'Create Campaign'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
