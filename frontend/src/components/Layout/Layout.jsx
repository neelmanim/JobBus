import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import { useAuth } from '../../contexts/AuthContext';
import {
  LayoutDashboard, Target, Send, Settings, Shield,
  FileText, LogOut, ChevronRight, Zap, Menu, X
} from 'lucide-react';
import { useState } from 'react';
import './Layout.css';

const NAV_ITEMS = [
  { to: '/', icon: LayoutDashboard, label: 'Dashboard' },
  { to: '/opportunities', icon: Target, label: 'Opportunities' },
  { to: '/campaigns', icon: Send, label: 'Campaigns' },
  { to: '/resume', icon: FileText, label: 'Resume' },
  { to: '/settings', icon: Settings, label: 'Settings' },
];

export default function Layout() {
  const { profile, signOut, isAdmin } = useAuth();
  const navigate = useNavigate();
  const [mobileOpen, setMobileOpen] = useState(false);

  const handleSignOut = async () => {
    await signOut();
    navigate('/login');
  };

  return (
    <div className="layout">
      {/* Mobile header */}
      <header className="mobile-header">
        <button className="btn-icon btn-ghost" onClick={() => setMobileOpen(!mobileOpen)}>
          {mobileOpen ? <X size={20} /> : <Menu size={20} />}
        </button>
        <div className="mobile-logo">
          <Zap size={18} className="logo-icon" />
          <span>JobBus</span>
        </div>
        <div style={{ width: 36 }} />
      </header>

      {/* Sidebar */}
      <aside className={`sidebar ${mobileOpen ? 'sidebar-open' : ''}`}>
        <div className="sidebar-logo">
          <div className="logo-mark">
            <Zap size={20} />
          </div>
          <div>
            <h1 className="logo-text">JobBus</h1>
            <p className="logo-sub">Career Outreach</p>
          </div>
        </div>

        <nav className="sidebar-nav">
          {NAV_ITEMS.map(item => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.to === '/'}
              className={({ isActive }) => `nav-link ${isActive ? 'active' : ''}`}
              onClick={() => setMobileOpen(false)}
            >
              <item.icon size={18} />
              <span>{item.label}</span>
              <ChevronRight size={14} className="nav-arrow" />
            </NavLink>
          ))}

          {isAdmin && (
            <NavLink
              to="/admin"
              className={({ isActive }) => `nav-link ${isActive ? 'active' : ''}`}
              onClick={() => setMobileOpen(false)}
            >
              <Shield size={18} />
              <span>Admin</span>
              <ChevronRight size={14} className="nav-arrow" />
            </NavLink>
          )}
        </nav>

        <div className="sidebar-footer">
          <div className="user-pill">
            <div className="user-avatar">
              {profile?.display_name?.[0] || profile?.email?.[0] || '?'}
            </div>
            <div className="user-info">
              <span className="user-name truncate">{profile?.display_name || 'User'}</span>
              <span className="user-mode">{profile?.mode || 'beginner'}</span>
            </div>
          </div>
          <button className="btn-ghost btn-icon" onClick={handleSignOut} title="Sign out">
            <LogOut size={16} />
          </button>
        </div>
      </aside>

      {/* Overlay for mobile */}
      {mobileOpen && <div className="sidebar-overlay" onClick={() => setMobileOpen(false)} />}

      {/* Main content */}
      <main className="main-content">
        <Outlet />
      </main>
    </div>
  );
}
