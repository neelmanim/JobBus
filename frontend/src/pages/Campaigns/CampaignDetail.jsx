import { useState, useEffect, useCallback } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { api } from '../../lib/api';
import { useToast } from '../../contexts/ToastContext';
import {
  ArrowLeft, Users, FileText, Send, BarChart3,
  Play, Pause, Square, RefreshCw, Plus, Check, X,
  AlertCircle, CheckCircle, Mail, Zap, Search,
  ChevronDown, ChevronUp, Clock, ThumbsUp, ThumbsDown,
  MessageSquare, TrendingUp, Loader, Shield, Edit3,
  Star, AlertTriangle
} from 'lucide-react';
import './CampaignDetail.css';

const TABS = [
  { id: 'contacts', label: 'Contacts',  icon: Users },
  { id: 'drafts',   label: 'Drafts',    icon: FileText },
  { id: 'send',     label: 'Send',      icon: Send },
  { id: 'outcomes', label: 'Outcomes',  icon: BarChart3 },
];

const OUTCOME_OPTIONS = [
  { id: 'replied',   label: 'Replied',         icon: MessageSquare, color: 'var(--color-success)' },
  { id: 'interview', label: 'Interview',        icon: TrendingUp,    color: 'var(--brand-accent)' },
  { id: 'bounced',   label: 'Bounced',          icon: AlertCircle,   color: 'var(--color-danger)' },
  { id: 'no_response', label: 'No Response',   icon: Clock,         color: 'var(--text-tertiary)' },
  { id: 'opted_out', label: 'Opted Out',        icon: X,             color: 'var(--color-warning)' },
];

function QualityBadge({ score }) {
  if (score == null) return null;
  const cls = score >= 80 ? 'tier-high' : score >= 60 ? 'tier-medium' : 'tier-low';
  return <span className={`badge ${cls}`}>{score}%</span>;
}

function DraftCard({ draft, campaignId, onRefresh }) {
  const toast = useToast();
  const [expanded, setExpanded] = useState(false);
  const [approving, setApproving] = useState(false);
  const [editMode, setEditMode] = useState(false);
  const [editedBody, setEditedBody] = useState(draft.body || '');

  async function handleAction(action) {
    setApproving(true);
    try {
      await api.approveDraft(campaignId, { draft_id: draft.id, action, body: editMode ? editedBody : undefined });
      toast.success(action === 'approve' ? 'Draft approved ✓' : 'Draft rejected');
      onRefresh();
    } catch (err) {
      toast.error(err.message || 'Failed');
    } finally {
      setApproving(false);
      setEditMode(false);
    }
  }

  const statusColor = {
    draft: 'var(--color-info)',
    approved: 'var(--color-success)',
    rejected: 'var(--color-danger)',
    sent: 'var(--brand-accent)',
  }[draft.status] || 'var(--text-tertiary)';

  return (
    <div className={`draft-card ${draft.status}`}>
      <div className="draft-card-header" onClick={() => setExpanded(e => !e)}>
        <div className="draft-card-meta">
          <span className="draft-contact">{draft.contact_name || draft.contact_email || 'Unknown contact'}</span>
          <span className="draft-company">{draft.contact_company}</span>
        </div>
        <div className="draft-card-right">
          <QualityBadge score={draft.quality_score} />
          <span className="badge" style={{ background: `${statusColor}18`, color: statusColor }}>{draft.status}</span>
          {expanded ? <ChevronUp size={15} /> : <ChevronDown size={15} />}
        </div>
      </div>

      {expanded && (
        <div className="draft-card-body">
          <div className="draft-subject">
            <strong>Subject:</strong> {draft.subject}
          </div>

          {editMode ? (
            <textarea
              className="input draft-edit-area"
              value={editedBody}
              onChange={e => setEditedBody(e.target.value)}
              rows={8}
            />
          ) : (
            <div className="draft-body-preview">{draft.body}</div>
          )}

          {draft.quality_issues?.length > 0 && (
            <div className="quality-issues">
              {draft.quality_issues.map((iss, i) => (
                <div key={i} className="quality-issue">
                  <AlertTriangle size={12} />
                  <span>{iss.message}</span>
                </div>
              ))}
            </div>
          )}

          {draft.status === 'draft' && (
            <div className="draft-actions">
              <button className="btn btn-ghost btn-sm" onClick={() => setEditMode(e => !e)}>
                <Edit3 size={13} /> {editMode ? 'Cancel Edit' : 'Edit'}
              </button>
              <button className="btn btn-danger btn-sm" onClick={() => handleAction('reject')}
                disabled={approving}>
                <ThumbsDown size={13} /> Reject
              </button>
              <button className="btn btn-primary btn-sm" onClick={() => handleAction('approve')}
                disabled={approving}>
                {approving ? <span className="spinner" style={{ width: 14, height: 14 }} /> : <><ThumbsUp size={13} /> Approve</>}
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function OutcomeRow({ contact, campaignId, currentOutcome, onUpdate }) {
  const toast = useToast();
  const [setting, setSetting] = useState(false);

  async function setOutcome(outcome) {
    setSetting(true);
    try {
      await api.recordOutcome(campaignId, { contact_id: contact.id, outcome });
      toast.success('Outcome recorded');
      onUpdate();
    } catch (err) {
      toast.error(err.message);
    } finally {
      setSetting(false);
    }
  }

  return (
    <div className="outcome-row">
      <div className="outcome-contact">
        <span className="font-medium">{contact.first_name} {contact.last_name}</span>
        <span className="text-sm text-secondary">{contact.title} @ {contact.company}</span>
      </div>
      <div className="outcome-buttons">
        {OUTCOME_OPTIONS.map(opt => (
          <button
            key={opt.id}
            className={`outcome-btn ${currentOutcome === opt.id ? 'active' : ''}`}
            style={currentOutcome === opt.id ? { borderColor: opt.color, color: opt.color } : {}}
            onClick={() => setOutcome(opt.id)}
            disabled={setting}
            title={opt.label}
          >
            <opt.icon size={13} /> {opt.label}
          </button>
        ))}
      </div>
    </div>
  );
}

export default function CampaignDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  const toast = useToast();

  const [campaign, setCampaign] = useState(null);
  const [tab, setTab] = useState('contacts');
  const [loading, setLoading] = useState(true);

  // Contacts tab
  const [contacts, setContacts] = useState([]);
  const [finding, setFinding] = useState(false);
  const [findDomain, setFindDomain] = useState('');

  // Drafts tab
  const [drafts, setDrafts] = useState([]);
  const [generating, setGenerating] = useState(false);
  const [genTone, setGenTone] = useState('professional');

  // Send tab
  const [sendResult, setSendResult] = useState(null);
  const [sending, setSending] = useState(false);
  const [sandboxOverride, setSandboxOverride] = useState(false);

  // Outcomes tab
  const [outcomes, setOutcomes] = useState({});

  const load = useCallback(async () => {
    try {
      const c = await api.getCampaign(id);
      setCampaign(c);
    } catch {
      toast.error('Campaign not found');
      navigate('/campaigns');
    } finally {
      setLoading(false);
    }
  }, [id]);

  const loadContacts = useCallback(async () => {
    try {
      const data = await api.getCampaignContacts(id);
      setContacts(Array.isArray(data) ? data : []);
    } catch { /* silent */ }
  }, [id]);

  const loadDrafts = useCallback(async () => {
    try {
      const data = await api.listDrafts(id);
      setDrafts(Array.isArray(data) ? data : []);
    } catch { /* silent */ }
  }, [id]);

  const loadOutcomes = useCallback(async () => {
    try {
      const data = await api.getCampaignOutcomes(id);
      const map = {};
      (Array.isArray(data) ? data : []).forEach(o => { map[o.contact_id] = o.outcome; });
      setOutcomes(map);
    } catch { /* silent */ }
  }, [id]);

  useEffect(() => { load(); }, [load]);
  useEffect(() => {
    if (tab === 'contacts') loadContacts();
    if (tab === 'drafts')   loadDrafts();
    if (tab === 'outcomes') { loadContacts(); loadOutcomes(); }
  }, [tab]);

  // ── Actions ───────────────────────────────────────────────
  async function handleFindContacts() {
    if (!findDomain && !campaign?.opportunity_id) {
      toast.error('Enter a domain to search');
      return;
    }
    setFinding(true);
    try {
      const r = await api.findContacts({
        opportunity_id: campaign.opportunity_id,
        company: campaign.name,
        domain: findDomain,
      });
      toast.success(`Found ${r.total_found} contacts via ${r.provider_used}`);
      loadContacts();
    } catch (err) {
      toast.error(err.message || 'Search failed');
    } finally {
      setFinding(false);
    }
  }

  async function handleGenerateDrafts() {
    setGenerating(true);
    try {
      const r = await api.generateDrafts(id, { regenerate: false, tone: genTone });
      toast.success(`Generated ${r.generated} draft${r.generated !== 1 ? 's' : ''}`);
      loadDrafts();
      setTab('drafts');
    } catch (err) {
      toast.error(err.message || 'Generation failed');
    } finally {
      setGenerating(false);
    }
  }

  async function handleSendStart(dryRun) {
    setSending(true);
    try {
      const r = await api.sendCampaign(id, { dry_run: dryRun });
      setSendResult(r);
      if (r.blocked) toast.error(r.reason);
      else if (dryRun) toast.success('Preflight check complete');
      else toast.success('Campaign send started');
      load();
    } catch (err) {
      toast.error(err.message || 'Send failed');
    } finally {
      setSending(false);
    }
  }

  async function handleCampaignControl(action) {
    try {
      await api.controlCampaign(id, action);
      toast.success(`Campaign ${action}d`);
      load();
    } catch (err) {
      toast.error(err.message);
    }
  }

  if (loading) {
    return (
      <div className="campaign-detail-loading">
        <div className="spinner" style={{ width: 32, height: 32, borderWidth: 3 }} />
      </div>
    );
  }

  const approvedCount = drafts.filter(d => d.status === 'approved').length;
  const sentCount = drafts.filter(d => d.status === 'sent').length;
  const isSandbox = campaign?.sandbox_mode && !sandboxOverride;

  return (
    <div className="campaign-detail">
      {/* Header */}
      <div className="cd-header">
        <button className="btn btn-ghost btn-sm" onClick={() => navigate('/campaigns')}>
          <ArrowLeft size={15} /> Campaigns
        </button>
        <div className="cd-title">
          <h1>{campaign?.name}</h1>
          <div className="cd-badges">
            <span className={`badge ${
              campaign?.status === 'active' ? 'badge-success' :
              campaign?.status === 'paused' ? 'badge-warning' :
              campaign?.status === 'draft' ? 'badge-info' : 'badge-primary'
            }`}>{campaign?.status}</span>
            {campaign?.sandbox_mode && (
              <span className="badge" style={{ background: 'rgba(245,158,11,0.12)', color: 'var(--color-warning)' }}>
                <Shield size={11} /> Sandbox
              </span>
            )}
          </div>
        </div>
        <div className="cd-controls">
          {campaign?.status === 'active' && (
            <button className="btn btn-secondary btn-sm" onClick={() => handleCampaignControl('pause')}>
              <Pause size={14} /> Pause
            </button>
          )}
          {campaign?.status === 'paused' && (
            <button className="btn btn-primary btn-sm" onClick={() => handleCampaignControl('resume')}>
              <Play size={14} /> Resume
            </button>
          )}
          {(campaign?.status === 'active' || campaign?.status === 'paused') && (
            <button className="btn btn-danger btn-sm" onClick={() => handleCampaignControl('stop')}>
              <Square size={14} /> Stop
            </button>
          )}
        </div>
      </div>

      {/* Stats Strip */}
      <div className="cd-stats">
        {[
          { label: 'Contacts', value: contacts.length, icon: Users },
          { label: 'Drafts', value: drafts.length, icon: FileText },
          { label: 'Approved', value: approvedCount, icon: CheckCircle },
          { label: 'Sent', value: sentCount, icon: Send },
          { label: 'Replies', value: campaign?.total_replies || 0, icon: MessageSquare },
        ].map(s => (
          <div key={s.label} className="cd-stat">
            <s.icon size={15} />
            <span className="cd-stat-value">{s.value}</span>
            <span className="cd-stat-label">{s.label}</span>
          </div>
        ))}
      </div>

      {/* Tabs */}
      <div className="cd-tabs">
        {TABS.map(t => (
          <button
            key={t.id}
            className={`cd-tab ${tab === t.id ? 'active' : ''}`}
            onClick={() => setTab(t.id)}
          >
            <t.icon size={14} /> {t.label}
          </button>
        ))}
      </div>

      {/* ── Contacts Tab ───────────────────────────────────── */}
      {tab === 'contacts' && (
        <div className="cd-panel">
          <div className="cd-panel-header">
            <h3>Contacts ({contacts.length})</h3>
            <div className="cd-panel-actions">
              <input
                className="input"
                placeholder="Domain (e.g. stripe.com)"
                value={findDomain}
                onChange={e => setFindDomain(e.target.value)}
                style={{ width: 220 }}
              />
              <button className="btn btn-primary btn-sm" onClick={handleFindContacts} disabled={finding}>
                {finding
                  ? <span className="spinner" style={{ width: 14, height: 14 }} />
                  : <><Search size={13} /> Find Contacts</>}
              </button>
            </div>
          </div>
          {contacts.length === 0 ? (
            <div className="cd-empty">
              <Users size={28} />
              <p>No contacts yet. Use <strong>Find Contacts</strong> to search via Hunter/Apollo, or add manually.</p>
            </div>
          ) : (
            <div className="table-container">
              <table>
                <thead>
                  <tr>
                    <th>Name</th><th>Title</th><th>Company</th><th>Email</th><th>Source</th><th>Persona</th>
                  </tr>
                </thead>
                <tbody>
                  {contacts.map(c => (
                    <tr key={c.id}>
                      <td className="font-medium">{c.first_name} {c.last_name}</td>
                      <td className="text-secondary">{c.title}</td>
                      <td>{c.company}</td>
                      <td className="text-secondary">{c.email || '—'}</td>
                      <td><span className="badge badge-info">{c.source}</span></td>
                      <td><span className="badge badge-primary">{c.persona_type?.replace('_', ' ')}</span></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          {contacts.length > 0 && drafts.length === 0 && (
            <div className="generate-cta">
              <div>
                <p className="font-medium">Ready to generate drafts?</p>
                <p className="text-sm text-secondary">AI will write a personalised email for each contact.</p>
              </div>
              <div className="generate-controls">
                <select className="input" value={genTone} onChange={e => setGenTone(e.target.value)} style={{ width: 160 }}>
                  <option value="professional">Professional</option>
                  <option value="conversational">Conversational</option>
                  <option value="concise">Concise</option>
                  <option value="enthusiastic">Enthusiastic</option>
                </select>
                <button className="btn btn-primary" onClick={handleGenerateDrafts} disabled={generating}>
                  {generating
                    ? <><span className="spinner" style={{ width: 14, height: 14 }} /> Generating…</>
                    : <><Zap size={14} /> Generate Drafts</>}
                </button>
              </div>
            </div>
          )}
        </div>
      )}

      {/* ── Drafts Tab ─────────────────────────────────────── */}
      {tab === 'drafts' && (
        <div className="cd-panel">
          <div className="cd-panel-header">
            <h3>Drafts ({drafts.length})</h3>
            <div className="cd-panel-actions">
              <select className="input" value={genTone} onChange={e => setGenTone(e.target.value)} style={{ width: 160 }}>
                <option value="professional">Professional</option>
                <option value="conversational">Conversational</option>
                <option value="concise">Concise</option>
                <option value="enthusiastic">Enthusiastic</option>
              </select>
              <button className="btn btn-secondary btn-sm" onClick={handleGenerateDrafts} disabled={generating}>
                {generating
                  ? <span className="spinner" style={{ width: 14, height: 14 }} />
                  : <><RefreshCw size={13} /> Re-generate</>}
              </button>
            </div>
          </div>

          {drafts.length === 0 ? (
            <div className="cd-empty">
              <FileText size={28} />
              <p>No drafts yet. Go to the Contacts tab and click <strong>Generate Drafts</strong>.</p>
            </div>
          ) : (
            <div className="drafts-list">
              <div className="drafts-summary">
                <span>{drafts.filter(d => d.status === 'approved').length} approved</span>
                <span>{drafts.filter(d => d.status === 'draft').length} pending review</span>
                <span>{drafts.filter(d => d.status === 'rejected').length} rejected</span>
              </div>
              {drafts.map(d => (
                <DraftCard key={d.id} draft={d} campaignId={id} onRefresh={loadDrafts} />
              ))}
            </div>
          )}
        </div>
      )}

      {/* ── Send Tab ───────────────────────────────────────── */}
      {tab === 'send' && (
        <div className="cd-panel">
          <div className="cd-panel-header">
            <h3>Send Campaign</h3>
          </div>

          {/* Sandbox Warning */}
          {campaign?.sandbox_mode && (
            <div className="sandbox-banner">
              <Shield size={18} />
              <div>
                <p className="font-medium">Sandbox Mode is ON</p>
                <p className="text-sm">Emails will be previewed but NOT sent. Disable sandbox in Settings → Campaign Defaults to go live.</p>
              </div>
            </div>
          )}

          {/* Readiness Check */}
          <div className="readiness-list">
            {[
              { label: 'Contacts added', ok: contacts.length > 0, val: `${contacts.length} contacts` },
              { label: 'Drafts generated', ok: drafts.length > 0, val: `${drafts.length} drafts` },
              { label: 'Drafts approved', ok: approvedCount > 0, val: `${approvedCount} approved` },
              { label: 'SMTP configured', ok: true, val: 'Check Settings' },
            ].map(item => (
              <div key={item.label} className="readiness-item">
                {item.ok
                  ? <CheckCircle size={16} style={{ color: 'var(--color-success)' }} />
                  : <AlertCircle size={16} style={{ color: 'var(--color-warning)' }} />}
                <span>{item.label}</span>
                <span className="text-secondary text-sm" style={{ marginLeft: 'auto' }}>{item.val}</span>
              </div>
            ))}
          </div>

          {/* Send Result */}
          {sendResult && !sendResult.blocked && (
            <div className="send-result">
              <CheckCircle size={16} style={{ color: 'var(--color-success)' }} />
              <div>
                <p className="font-medium">{sendResult.dry_run ? 'Preflight OK' : 'Send started'}</p>
                {sendResult.approved_count != null && (
                  <p className="text-sm text-secondary">{sendResult.approved_count} emails queued</p>
                )}
              </div>
            </div>
          )}

          {sendResult?.blocked && (
            <div className="send-blocked">
              <Shield size={16} />
              <p>{sendResult.reason}</p>
            </div>
          )}

          <div className="send-actions">
            <button className="btn btn-secondary" onClick={() => handleSendStart(true)} disabled={sending}>
              {sending ? <span className="spinner" style={{ width: 16, height: 16 }} /> : <><CheckCircle size={15} /> Preflight Check</>}
            </button>
            <button
              className="btn btn-primary"
              onClick={() => handleSendStart(false)}
              disabled={sending || approvedCount === 0}
            >
              {sending ? <span className="spinner" style={{ width: 16, height: 16 }} /> : <><Send size={15} /> Start Send</>}
            </button>
          </div>
        </div>
      )}

      {/* ── Outcomes Tab ───────────────────────────────────── */}
      {tab === 'outcomes' && (
        <div className="cd-panel">
          <div className="cd-panel-header">
            <h3>Track Outcomes</h3>
          </div>

          {/* Summary pills */}
          <div className="outcomes-summary">
            {OUTCOME_OPTIONS.map(opt => {
              const count = Object.values(outcomes).filter(v => v === opt.id).length;
              return (
                <div key={opt.id} className="outcome-summary-pill" style={{ borderColor: `${opt.color}30`, color: opt.color }}>
                  <opt.icon size={13} />
                  <span className="font-semibold">{count}</span>
                  <span>{opt.label}</span>
                </div>
              );
            })}
          </div>

          {contacts.length === 0 ? (
            <div className="cd-empty">
              <BarChart3 size={28} />
              <p>No contacts yet to track outcomes for.</p>
            </div>
          ) : (
            <div className="outcomes-list">
              {contacts.map(c => (
                <OutcomeRow
                  key={c.id}
                  contact={c}
                  campaignId={id}
                  currentOutcome={outcomes[c.id]}
                  onUpdate={loadOutcomes}
                />
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
