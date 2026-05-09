import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '../../contexts/AuthContext';
import { api } from '../../lib/api';
import {
  Target, Send, FileText, TrendingUp, Activity,
  ArrowUpRight, Sparkles, Zap, ChevronRight, Upload
} from 'lucide-react';
import './Dashboard.css';

export default function Dashboard() {
  const { profile } = useAuth();
  const [stats, setStats] = useState({ campaigns: 0, opportunities: 0, sent: 0, replies: 0 });
  const [resumeReady, setResumeReady] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadDashboard();
  }, []);

  async function loadDashboard() {
    try {
      const [campaigns, resume] = await Promise.allSettled([
        api.listCampaigns(),
        api.getResumeProfile(),
      ]);

      if (campaigns.status === 'fulfilled' && Array.isArray(campaigns.value)) {
        const c = campaigns.value;
        setStats(prev => ({
          ...prev,
          campaigns: c.length,
          sent: c.reduce((sum, x) => sum + (x.total_sent || 0), 0),
          replies: c.reduce((sum, x) => sum + (x.total_replies || 0), 0),
        }));
      }

      if (resume.status === 'fulfilled' && resume.value) {
        setResumeReady(true);
      }
    } catch (err) {
      console.error('Dashboard load error:', err);
    } finally {
      setLoading(false);
    }
  }

  const greeting = () => {
    const h = new Date().getHours();
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  };

  return (
    <div className="dashboard">
      <div className="page-header">
        <h1>{greeting()}, {profile?.display_name?.split(' ')[0] || 'there'} 👋</h1>
        <p>Here's your career outreach overview</p>
      </div>

      {/* Stats Grid */}
      <div className="stats-grid">
        <StatCard
          icon={<Target size={20} />}
          label="Opportunities"
          value={stats.opportunities}
          change="+0 this week"
          color="primary"
        />
        <StatCard
          icon={<Send size={20} />}
          label="Emails Sent"
          value={stats.sent}
          change="Across all campaigns"
          color="accent"
        />
        <StatCard
          icon={<Activity size={20} />}
          label="Replies"
          value={stats.replies}
          change={stats.sent > 0 ? `${((stats.replies / stats.sent) * 100).toFixed(0)}% rate` : 'No emails yet'}
          color="success"
        />
        <StatCard
          icon={<TrendingUp size={20} />}
          label="Campaigns"
          value={stats.campaigns}
          change="Active campaigns"
          color="info"
        />
      </div>

      {/* Quick Actions + Resume Status */}
      <div className="dashboard-grid">
        {/* Quick Actions */}
        <div className="card quick-actions-card">
          <h3 className="card-title">Quick Actions</h3>
          <div className="actions-list">
            {!resumeReady && (
              <Link to="/resume" className="action-item action-highlight">
                <div className="action-icon upload-icon"><Upload size={18} /></div>
                <div className="action-info">
                  <strong>Upload Resume</strong>
                  <span>Required to start outreach</span>
                </div>
                <ChevronRight size={16} className="text-tertiary" />
              </Link>
            )}
            <Link to="/opportunities" className="action-item">
              <div className="action-icon"><Target size={18} /></div>
              <div className="action-info">
                <strong>Discover Opportunities</strong>
                <span>Search and score job signals</span>
              </div>
              <ChevronRight size={16} className="text-tertiary" />
            </Link>
            <Link to="/campaigns" className="action-item">
              <div className="action-icon"><Send size={18} /></div>
              <div className="action-info">
                <strong>Start a Campaign</strong>
                <span>Create outreach campaign</span>
              </div>
              <ChevronRight size={16} className="text-tertiary" />
            </Link>
            <Link to="/settings" className="action-item">
              <div className="action-icon"><Zap size={18} /></div>
              <div className="action-info">
                <strong>Configure SMTP</strong>
                <span>Set up email sending</span>
              </div>
              <ChevronRight size={16} className="text-tertiary" />
            </Link>
          </div>
        </div>

        {/* Guidance Cards */}
        <div className="card guidance-card">
          <h3 className="card-title">
            <Sparkles size={16} className="text-accent" />
            Guidance
          </h3>
          <div className="guidance-list">
            {!resumeReady ? (
              <div className="guidance-item">
                <div className="guidance-badge badge badge-warning">Step 1</div>
                <div>
                  <strong>Upload your resume</strong>
                  <p>JobBus analyzes your resume to find the best opportunities and craft personalized outreach.</p>
                </div>
              </div>
            ) : (
              <>
                <div className="guidance-item">
                  <div className="guidance-badge badge badge-success">✓</div>
                  <div>
                    <strong>Resume uploaded</strong>
                    <p>Your AI profile is ready. Start discovering opportunities.</p>
                  </div>
                </div>
                <div className="guidance-item">
                  <div className="guidance-badge badge badge-info">Next</div>
                  <div>
                    <strong>Search for opportunities</strong>
                    <p>Use the Opportunities page to find scored, high-signal targets.</p>
                  </div>
                </div>
              </>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

function StatCard({ icon, label, value, change, color }) {
  const colorMap = {
    primary: 'var(--brand-primary)',
    accent: 'var(--brand-accent)',
    success: 'var(--color-success)',
    info: 'var(--color-info)',
  };
  return (
    <div className="stat-card card">
      <div className="stat-header">
        <div className="stat-icon" style={{ color: colorMap[color], background: `${colorMap[color]}15` }}>
          {icon}
        </div>
        <ArrowUpRight size={14} className="text-tertiary" />
      </div>
      <div className="stat-value">{value}</div>
      <div className="stat-label">{label}</div>
      <div className="stat-change text-sm text-tertiary">{change}</div>
    </div>
  );
}
