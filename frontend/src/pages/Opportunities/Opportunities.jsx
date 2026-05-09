import { useState, useEffect } from 'react';
import { api } from '../../lib/api';
import { useToast } from '../../contexts/ToastContext';
import {
  Search, MapPin, Target, TrendingUp, Building2,
  Users, Briefcase, ChevronDown, ExternalLink, Sparkles,
  Filter, RefreshCw
} from 'lucide-react';
import './Opportunities.css';

export default function Opportunities() {
  const toast = useToast();
  const [query, setQuery] = useState('');
  const [location, setLocation] = useState('');
  const [opportunities, setOpportunities] = useState([]);
  const [loading, setLoading] = useState(false);
  const [searched, setSearched] = useState(false);
  const [selectedOpp, setSelectedOpp] = useState(null);

  async function handleSearch(e) {
    e.preventDefault();
    if (!query.trim()) return;
    setLoading(true);
    setSearched(true);
    try {
      const results = await api.searchOpportunities(query, location);
      setOpportunities(Array.isArray(results) ? results : results?.opportunities || []);
    } catch (err) {
      toast.error(err.message || 'Search failed');
      setOpportunities([]);
    } finally {
      setLoading(false);
    }
  }

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
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>
        <div className="search-field location-field">
          <MapPin size={18} className="search-icon" />
          <input
            type="text"
            className="input"
            placeholder="Location (optional)"
            value={location}
            onChange={(e) => setLocation(e.target.value)}
          />
        </div>
        <button type="submit" className="btn btn-primary" disabled={loading || !query.trim()}>
          {loading ? <span className="spinner" /> : <><Search size={16} /> Search</>}
        </button>
      </form>

      {/* Results */}
      {loading ? (
        <div className="opp-loading">
          {[1,2,3].map(i => (
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
              className="card card-interactive opp-card"
              onClick={() => setSelectedOpp(selectedOpp === idx ? null : idx)}
            >
              <div className="opp-card-header">
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
                  </div>
                </div>

                {/* Score Ring */}
                <div className="opp-score-area">
                  <div className={`score-badge ${getTierClass(opp.score || 0)}`}>
                    <span className="score-num">{opp.score || 0}</span>
                    <span className="score-tier">{getTierLabel(opp.score || 0)}</span>
                  </div>
                </div>
              </div>

              {/* Signal Breakdown */}
              {opp.signals && (
                <div className="signal-grid">
                  {opp.signals.map((signal, si) => (
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
                  {opp.url && (
                    <a href={opp.url} target="_blank" rel="noopener noreferrer" className="btn btn-secondary btn-sm">
                      <ExternalLink size={14} /> View Listing
                    </a>
                  )}
                </div>
              )}
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
          <h3>Search for opportunities</h3>
          <p>Enter a job title or skill to discover scored opportunities with hiring signals.</p>
        </div>
      )}
    </div>
  );
}
