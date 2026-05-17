import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { api } from '../../lib/api';
import { useAuth } from '../../contexts/AuthContext';
import { useToast } from '../../contexts/ToastContext';
import {
  Search, MapPin, Target, TrendingUp, Building2,
  Briefcase, ExternalLink, Sparkles, Zap, X,
  ChevronRight, Users, Globe, ArrowRight, Loader,
  RefreshCw,
} from 'lucide-react';
import './Opportunities.css';

/* ── Outreach Modal ─────────────────────────────────────────── */
function OutreachModal({ opp, onClose }) {
  const toast = useToast();
  const navigate = useNavigate();
  const [step, setStep] = useState('setup');   // setup | finding | done
  const [domain, setDomain]       = useState(opp.domain || '');
  const [angle, setAngle]         = useState('');
  const [result, setResult]       = useState(null);

  const company = opp.company || opp.company_name || 'Company';
  const title   = opp.title   || opp.role_title   || 'Untitled Role';

  async function handleStart() {
    if (!domain.trim()) { toast.error('Enter a company domain to find contacts'); return; }
    setStep('finding');
    try {
      // 1 — create the campaign
      const campaign = await api.createCampaign({
        name: `${company} — ${title}`,
        outreach_angle: angle || `Outreach for ${title} role at ${company}`,
        sandbox_mode: true,
        opportunity_id: opp.id || null,
      });

      // 2 — waterfall contact search
      const found = await api.findContacts({
        opportunity_id: opp.id || null,
        company,
        domain: domain.trim(),
      });

      // 3 — attach contacts to campaign
      if (found?.contacts?.length) {
        const contactIds = found.contacts.map(c => c.id || c).filter(Boolean);
        if (contactIds.length) {
          await api.addCampaignContacts(campaign.id, contactIds);
        }
      }

      // 4 — auto-generate AI drafts if contacts were found
      let draftsGenerated = 0;
      if (found?.total_found > 0) {
        try {
          const draftResult = await api.generateDrafts(campaign.id, {
            regenerate: false,
            tone: 'professional',
          });
          draftsGenerated = draftResult?.generated || 0;
        } catch (draftErr) {
          // Non-fatal — user can generate manually from Campaign Detail
          console.warn('Auto-draft generation failed:', draftErr.message);
        }
      }

      setResult({ campaign, found, draftsGenerated });
      setStep('done');
    } catch (err) {
      toast.error(err.message || 'Something went wrong');
      setStep('setup');
    }
  }

  return (
    <div className="modal-backdrop" onClick={e => e.target === e.currentTarget && onClose()}>
      <div className="modal outreach-modal">
        {/* Header */}
        <div className="modal-header">
          <div>
            <h2 className="modal-title">Start Outreach</h2>
            <p className="modal-subtitle text-secondary">{title} · {company}</p>
          </div>
          <button className="btn btn-ghost btn-sm icon-only" onClick={onClose}><X size={18} /></button>
        </div>

        {/* Setup Step */}
        {step === 'setup' && (
          <div className="modal-body">
            <div className="outreach-opp-summary">
              <div className={`score-badge ${getTierClass(opp.score || 0)} score-sm`}>{opp.score || '—'}</div>
              <div>
                <p className="font-medium">{company}</p>
                <p className="text-sm text-secondary">{opp.location || 'Remote'}</p>
              </div>
            </div>

            <div className="input-group">
              <label className="input-label">
                <Globe size={14} /> Company Domain <span className="text-danger">*</span>
              </label>
              <input
                className="input"
                placeholder="e.g. google.com, stripe.com"
                value={domain}
                onChange={e => setDomain(e.target.value)}
                autoFocus
              />
              <span className="text-xs text-secondary">The company's own domain — NOT the job board URL. Used to find the right contacts via Hunter → Apollo → RocketReach</span>
            </div>

            <div className="input-group">
              <label className="input-label">Outreach Angle <span className="text-secondary">(optional)</span></label>
              <input
                className="input"
                placeholder={`e.g. Excited by ${company}'s recent Series B — want to discuss the ${title} role`}
                value={angle}
                onChange={e => setAngle(e.target.value)}
              />
              <span className="text-xs text-secondary">The AI uses this to personalise every draft</span>
            </div>

            <div className="outreach-what-happens">
              <p className="text-xs font-medium text-secondary" style={{ marginBottom: 8 }}>WHAT HAPPENS NEXT</p>
              <div className="outreach-steps">
                <div className="outreach-step"><span className="step-num">1</span> Campaign created in <strong>sandbox mode</strong></div>
                <div className="outreach-step"><span className="step-num">2</span> Contacts discovered via waterfall search</div>
                <div className="outreach-step"><span className="step-num">3</span> You land in Campaign Detail to review + approve drafts</div>
              </div>
            </div>

            <div className="modal-footer">
              <button className="btn btn-ghost" onClick={onClose}>Cancel</button>
              <button className="btn btn-primary" onClick={handleStart} disabled={!domain.trim()}>
                <Zap size={15} /> Find Contacts & Start
              </button>
            </div>
          </div>
        )}

        {/* Finding Step */}
        {step === 'finding' && (
          <div className="modal-body modal-loading">
            <div className="finding-animation">
              <Loader size={36} className="spin-icon" style={{ color: 'var(--brand-primary-light)' }} />
            </div>
            <p className="font-medium" style={{ marginTop: 16 }}>Setting up your campaign…</p>
            <p className="text-sm text-secondary">Finding contacts → Generating AI drafts for <strong>{company}</strong></p>
          </div>
        )}

        {/* Done Step */}
        {step === 'done' && result && (
          <div className="modal-body">
            <div className="outreach-success">
              <div className="success-icon">🎯</div>
              <h3>Campaign ready!</h3>
              <div className="success-stats">
                <div className="success-stat">
                  <span className="success-num">{result.found?.total_found || 0}</span>
                  <span className="text-secondary text-sm">contacts found</span>
                </div>
                <div className="success-stat">
                  <span className="success-num">{result.draftsGenerated || 0}</span>
                  <span className="text-secondary text-sm">drafts generated</span>
                </div>
              </div>
              {(result.found?.total_found || 0) === 0 && (
                <div style={{ textAlign: 'center' }}>
                  <p className="text-sm text-secondary" style={{ marginBottom: 8 }}>
                    No contacts found automatically.
                  </p>
                  <p className="text-xs text-secondary">
                    Check that the domain is the <strong>company's own domain</strong> (e.g. <code>google.com</code>), not a job board URL.
                    Then retry from the campaign page.
                  </p>
                  <p className="text-xs text-secondary" style={{ marginTop: 6 }}>
                    Or add contacts manually inside the campaign.
                  </p>
                </div>
              )}
              {result.draftsGenerated > 0 && (
                <p className="text-sm text-secondary" style={{ textAlign: 'center', marginTop: 8 }}>
                  ✓ Drafts are ready to review and approve.
                </p>
              )}
            </div>
            <div className="modal-footer">
              <button className="btn btn-ghost" onClick={onClose}>Close</button>
              <button
                className="btn btn-primary"
                onClick={() => navigate(`/campaigns/${result.campaign.id}`)}
              >
                {result.draftsGenerated > 0 ? 'Review Drafts' : 'Open Campaign'} <ArrowRight size={15} />
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

/* ── Helpers ────────────────────────────────────────────────── */
function getTierClass(score) {
  if (score >= 70) return 'tier-high';
  if (score >= 40) return 'tier-medium';
  return 'tier-low';
}
function getTierLabel(score) {
  if (score >= 70) return 'High';
  if (score >= 40) return 'Medium';
  return 'Low';
}

/* ── Main Page ──────────────────────────────────────────────── */
export default function Opportunities() {
  const toast = useToast();
  const { profile } = useAuth();

  const [query, setQuery]             = useState('');
  const [location, setLocation]       = useState('');
  const [opportunities, setOpportunities] = useState([]);
  const [loading, setLoading]         = useState(false);
  const [autoSearched, setAutoSearched] = useState(false);
  const [searched, setSearched]       = useState(false);
  const [source, setSource]           = useState('');
  const [selectedOpp, setSelectedOpp] = useState(null);
  const [outreachOpp, setOutreachOpp] = useState(null);
  const [showManual, setShowManual]   = useState(false);
  const [manualForm, setManualForm]   = useState({ role_title: '', company_name: '', job_url: '', location: '', is_remote: false });
  const [manualLoading, setManualLoading] = useState(false);

  // ── Auto-load: on mount, fetch previously saved opportunities first.
  // If none exist (or all have score=0 from before the scorer fix), trigger auto-search.
  useEffect(() => {
    async function init() {
      try {
        // 1. Load previously saved opportunities
        const saved = await api.listOpportunities();
        const list = saved?.opportunities || [];

        // Only use saved results if they have actual scores (not all 0 from old broken scorer)
        const hasGoodResults = list.length > 0 && list.some(o => (o.score || 0) > 0);
        if (hasGoodResults) {
          setOpportunities(list);
          setSearched(true);
          return;
        }

        // 2. Auto-search — try resume profile role + location, then default
        let autoQuery = 'software engineer';
        let autoLocation = '';
        try {
          const resumeProfile = await api.getResumeProfile();
          if (resumeProfile?.role) autoQuery = resumeProfile.role;
          if (resumeProfile?.location) autoLocation = resumeProfile.location;
        } catch { /* resume not uploaded yet, use defaults */ }

        setQuery(autoQuery);
        if (autoLocation) setLocation(autoLocation);
        await runSearch(autoQuery, autoLocation);
      } catch (err) {
        // Silently ignore — user can still search manually
      }
    }
    if (!autoSearched) {
      setAutoSearched(true);
      init();
    }
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  async function runSearch(q, loc) {
    if (!q.trim()) return;
    setLoading(true);
    setSearched(true);
    try {
      const results = await api.searchOpportunities(q.trim(), loc);
      const list = Array.isArray(results) ? results : results?.opportunities || [];
      setOpportunities(list);
      setSource(results?.source || '');
      if (list.length === 0) {
        toast.info('No opportunities found — try broader search terms');
      }
    } catch (err) {
      toast.error(err.message || 'Search failed');
      setOpportunities([]);
    } finally {
      setLoading(false);
    }
  }

  async function handleSearch(e) {
    e.preventDefault();
    await runSearch(query, location);
  }

  async function handleManualAdd(e) {
    e.preventDefault();
    if (!manualForm.role_title.trim() || !manualForm.company_name.trim()) return;
    setManualLoading(true);
    try {
      const res = await api.post('/api/opportunities/manual', manualForm);
      const opp = res?.opportunity;
      if (opp) {
        setOpportunities(prev => [opp, ...prev]);
        setSource('manual');
        setSearched(true);
        setShowManual(false);
        setManualForm({ role_title: '', company_name: '', job_url: '', location: '', is_remote: false });
        toast.success(`Added: ${opp.title} @ ${opp.company}`);
      }
    } catch (err) {
      toast.error(err.message || 'Failed to add job');
    } finally {
      setManualLoading(false);
    }
  }

  return (
    <div className="opportunities-page">
      <div className="page-header">
        <h1>Opportunities</h1>
        <p>Discover and score opportunities based on hiring signals</p>
      </div>

      {/* Search Bar */}
      <form onSubmit={handleSearch} className="search-bar">
        <div className="search-field">
          <Search size={18} className="search-icon" />
          <input
            type="text"
            className="input"
            placeholder="Job title, skills, or company..."
            value={query}
            onChange={e => setQuery(e.target.value)}
          />
        </div>
        <div className="search-field location-field">
          <MapPin size={18} className="search-icon" />
          <input
            type="text"
            className="input"
            placeholder="Location (optional)"
            value={location}
            onChange={e => setLocation(e.target.value)}
          />
        </div>
        <button type="submit" className="btn btn-primary" disabled={loading || !query.trim()}>
          {loading ? <span className="spinner" /> : <><Search size={16} /> Search</>}
        </button>
        {opportunities.length > 0 && !loading && (
          <button
            type="button"
            className="btn btn-ghost"
            title="Refresh search"
            onClick={() => runSearch(query, location)}
          >
            <RefreshCw size={16} />
          </button>
        )}
        <button
          type="button"
          className="btn btn-ghost"
          title="Add job manually"
          onClick={() => setShowManual(true)}
          style={{ marginLeft: 'auto' }}
        >
          + Add Manually
        </button>
      </form>

      {/* Manual Entry Modal */}
      {showManual && (
        <div className="modal-backdrop" onClick={e => e.target === e.currentTarget && setShowManual(false)}>
          <div className="modal" style={{ maxWidth: 480 }}>
            <div className="modal-header">
              <div>
                <h2 className="modal-title">Add Job Manually</h2>
                <p className="modal-subtitle text-secondary">Paste a role from any job board</p>
              </div>
              <button className="btn btn-ghost btn-sm icon-only" onClick={() => setShowManual(false)}><X size={18} /></button>
            </div>
            <form className="modal-body" onSubmit={handleManualAdd}>
              <div className="input-group">
                <label className="input-label">Job Title <span className="text-danger">*</span></label>
                <input className="input" placeholder="e.g. Senior Product Manager" value={manualForm.role_title}
                  onChange={e => setManualForm(f => ({ ...f, role_title: e.target.value }))} required />
              </div>
              <div className="input-group">
                <label className="input-label">Company <span className="text-danger">*</span></label>
                <input className="input" placeholder="e.g. Stripe" value={manualForm.company_name}
                  onChange={e => setManualForm(f => ({ ...f, company_name: e.target.value }))} required />
              </div>
              <div className="input-group">
                <label className="input-label">Job URL <span className="text-secondary">(optional)</span></label>
                <input className="input" placeholder="https://..." value={manualForm.job_url}
                  onChange={e => setManualForm(f => ({ ...f, job_url: e.target.value }))} />
              </div>
              <div className="input-group">
                <label className="input-label">Location</label>
                <input className="input" placeholder="e.g. New York, NY or Remote" value={manualForm.location}
                  onChange={e => setManualForm(f => ({ ...f, location: e.target.value }))} />
              </div>
              <div className="input-group" style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
                <input type="checkbox" id="is_remote" checked={manualForm.is_remote}
                  onChange={e => setManualForm(f => ({ ...f, is_remote: e.target.checked }))} />
                <label htmlFor="is_remote" className="input-label" style={{ margin: 0 }}>Remote position</label>
              </div>
              <div className="modal-footer">
                <button type="button" className="btn btn-ghost" onClick={() => setShowManual(false)}>Cancel</button>
                <button type="submit" className="btn btn-primary" disabled={manualLoading || !manualForm.role_title.trim() || !manualForm.company_name.trim()}>
                  {manualLoading ? <span className="spinner" /> : '+ Add Job'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Source badge */}
      {source && !loading && opportunities.length > 0 && (
        <p className="text-xs text-secondary" style={{ marginBottom: 8 }}>
          Results via <strong>{
            source === 'linkedin' ? 'LinkedIn Jobs' :
            source === 'jsearch'  ? 'JSearch (Google for Jobs)' :
            source === 'cache'    ? 'Saved Results' :
            source === 'manual'   ? 'Manual Entry' :
            source
          }</strong>
        </p>
      )}

      {/* Results */}
      {loading ? (
        <div className="opp-loading">
          {[1, 2, 3].map(i => (
            <div key={i} className="card opp-skeleton">
              <div className="skeleton" style={{ width: '60%', height: 20, marginBottom: 12 }} />
              <div className="skeleton" style={{ width: '40%', height: 16, marginBottom: 20 }} />
              <div className="skeleton" style={{ width: '100%', height: 60 }} />
            </div>
          ))}
        </div>
      ) : opportunities.length > 0 ? (
        <div className="opp-grid">
          {opportunities.map((opp, idx) => (
            <div
              key={opp.id || idx}
              className={`card opp-card ${selectedOpp === idx ? 'expanded' : ''}`}
            >
              {/* Card Header — always visible */}
              <div
                className="opp-card-header card-interactive"
                onClick={() => setSelectedOpp(selectedOpp === idx ? null : idx)}
              >
                <div className="opp-info">
                  <h3 className="opp-title">{opp.title || opp.role_title || 'Untitled Role'}</h3>
                  <div className="opp-meta">
                    <span className="opp-company">
                      <Building2 size={14} />
                      {opp.company || opp.company_name || 'Company'}
                    </span>
                    {(opp.location || opp.city) && (
                      <span className="opp-location">
                        <MapPin size={14} />
                        {opp.location || opp.city}
                      </span>
                    )}
                    {opp.is_remote && (
                      <span className="opp-remote-badge">Remote</span>
                    )}
                  </div>
                </div>

                <div className="opp-score-area">
                  <div className={`score-badge ${getTierClass(opp.score || 0)}`}>
                    <span className="score-num">{opp.score || 0}</span>
                    <span className="score-tier">{getTierLabel(opp.score || 0)}</span>
                  </div>
                </div>
              </div>

              {/* Signals */}
              {opp.signals && (
                <div className="signal-grid">
                  {(Array.isArray(opp.signals)
                    ? opp.signals
                    : Object.entries(opp.signals).map(([k, v]) => ({ description: `${k}: ${v}` }))
                  ).map((signal, si) => (
                    <div key={si} className="signal-chip">
                      <span className="signal-check">✓</span>
                      <span>{signal.description || signal}</span>
                      {signal.contribution && (
                        <span className="signal-score">+{signal.contribution}</span>
                      )}
                    </div>
                  ))}
                </div>
              )}

              {/* Expanded Detail */}
              {selectedOpp === idx && (
                <div className="opp-detail">
                  <div className="detail-row">
                    <Briefcase size={14} />
                    <span>Type: {opp.employment_type || 'Full-time'}</span>
                  </div>
                  {opp.salary && (
                    <div className="detail-row">
                      <TrendingUp size={14} />
                      <span>Salary: {opp.salary}</span>
                    </div>
                  )}
                  {(opp.url || opp.job_url) && (
                    <a href={opp.url || opp.job_url} target="_blank" rel="noopener noreferrer"
                      className="btn btn-ghost btn-sm"
                      onClick={e => e.stopPropagation()}>
                      <ExternalLink size={14} /> View Listing
                    </a>
                  )}
                </div>
              )}

              {/* ── Start Outreach CTA ── */}
              <div className="opp-card-footer">
                <button
                  className="btn btn-primary btn-sm outreach-btn"
                  onClick={e => { e.stopPropagation(); setOutreachOpp(opp); }}
                >
                  <Zap size={14} /> Start Outreach
                  <ChevronRight size={14} />
                </button>
              </div>
            </div>
          ))}
        </div>
      ) : searched ? (
        <div className="empty-state">
          <div className="empty-icon"><Target size={32} /></div>
          <h3>No opportunities found</h3>
          <p>Try broadening your search terms or changing the location.</p>
        </div>
      ) : (
        <div className="empty-state">
          <div className="empty-icon"><Sparkles size={32} /></div>
          <h3>Searching for opportunities…</h3>
          <p>Hang tight while we find the best matches.</p>
        </div>
      )}

      {/* Outreach Modal */}
      {outreachOpp && (
        <OutreachModal
          opp={outreachOpp}
          onClose={() => setOutreachOpp(null)}
        />
      )}
    </div>
  );
}
