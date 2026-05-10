import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider, useAuth } from './contexts/AuthContext';
import { ToastProvider } from './contexts/ToastContext';
import Layout from './components/Layout/Layout';
import Login from './pages/Login/Login';
import Dashboard from './pages/Dashboard/Dashboard';
import Opportunities from './pages/Opportunities/Opportunities';
import Campaigns from './pages/Campaigns/Campaigns';
import CampaignDetail from './pages/Campaigns/CampaignDetail';
import Resume from './pages/Resume/Resume';
import Settings from './pages/Settings/Settings';
import Admin from './pages/Admin/Admin';
import Onboarding from './pages/Onboarding/Onboarding';

/* ── Route Guards ────────────────────────────────────────── */
function ProtectedRoute({ children }) {
  const { session, profile, loading } = useAuth();

  if (loading) {
    return (
      <div className="app-loading">
        <div className="spinner" style={{ width: 32, height: 32, borderWidth: 3 }} />
      </div>
    );
  }

  if (!session) return <Navigate to="/login" replace />;

  // New users who haven't completed onboarding → redirect to wizard
  if (profile && profile.onboarding_complete === false) {
    return <Navigate to="/onboarding" replace />;
  }

  return children;
}

function OnboardingRoute({ children }) {
  const { session, profile, loading } = useAuth();
  if (loading) return <div className="app-loading"><div className="spinner" style={{ width: 32, height: 32, borderWidth: 3 }} /></div>;
  if (!session) return <Navigate to="/login" replace />;
  // Already onboarded → send to dashboard
  if (profile?.onboarding_complete === true) return <Navigate to="/" replace />;
  return children;
}

function AdminRoute({ children }) {
  const { isAdmin, loading } = useAuth();
  if (loading) return null;
  if (!isAdmin) return <Navigate to="/" replace />;
  return children;
}

function PublicRoute({ children }) {
  const { session, loading } = useAuth();
  if (loading) {
    return (
      <div className="app-loading">
        <div className="spinner" style={{ width: 32, height: 32, borderWidth: 3 }} />
      </div>
    );
  }
  if (session) return <Navigate to="/" replace />;
  return children;
}

/* ── Router ──────────────────────────────────────────────── */
function AppRoutes() {
  return (
    <Routes>
      {/* Public */}
      <Route path="/login" element={<PublicRoute><Login /></PublicRoute>} />

      {/* Onboarding — authenticated but outside main layout */}
      <Route path="/onboarding" element={<OnboardingRoute><Onboarding /></OnboardingRoute>} />

      {/* App shell */}
      <Route element={<ProtectedRoute><Layout /></ProtectedRoute>}>
        <Route index element={<Dashboard />} />
        <Route path="opportunities" element={<Opportunities />} />
        <Route path="campaigns" element={<Campaigns />} />
        <Route path="campaigns/:id" element={<CampaignDetail />} />
        <Route path="resume" element={<Resume />} />
        <Route path="settings" element={<Settings />} />
        <Route
          path="admin"
          element={<AdminRoute><Admin /></AdminRoute>}
        />
      </Route>

      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

export default function App() {
  return (
    <BrowserRouter>
      <ToastProvider>
        <AuthProvider>
          <AppRoutes />
        </AuthProvider>
      </ToastProvider>
    </BrowserRouter>
  );
}
