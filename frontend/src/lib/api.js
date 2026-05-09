const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:8000';

class ApiClient {
  constructor() {
    this.base = API_BASE;
    this.token = null;
  }

  setToken(token) {
    this.token = token;
  }

  async request(path, options = {}) {
    const url = `${this.base}${path}`;
    const headers = {
      'Content-Type': 'application/json',
      ...options.headers,
    };

    if (this.token) {
      headers['Authorization'] = `Bearer ${this.token}`;
    }

    const res = await fetch(url, { ...options, headers });
    
    if (!res.ok) {
      const errorBody = await res.json().catch(() => ({ detail: res.statusText }));
      const error = new Error(errorBody.detail || `HTTP ${res.status}`);
      error.status = res.status;
      error.body = errorBody;
      throw error;
    }

    if (res.status === 204) return null;
    return res.json();
  }

  get(path) { return this.request(path); }

  post(path, body) {
    return this.request(path, { method: 'POST', body: JSON.stringify(body) });
  }

  put(path, body) {
    return this.request(path, { method: 'PUT', body: JSON.stringify(body) });
  }

  delete(path) {
    return this.request(path, { method: 'DELETE' });
  }

  async upload(path, file) {
    const formData = new FormData();
    formData.append('file', file);
    const headers = {};
    if (this.token) headers['Authorization'] = `Bearer ${this.token}`;
    
    const res = await fetch(`${this.base}${path}`, {
      method: 'POST',
      headers,
      body: formData,
    });

    if (!res.ok) {
      const errorBody = await res.json().catch(() => ({ detail: res.statusText }));
      throw new Error(errorBody.detail || `Upload failed: HTTP ${res.status}`);
    }
    return res.json();
  }

  // ── Auth ──
  validateInvite(code) { return this.post('/api/auth/invite/validate', { code }); }
  createInvite(data) { return this.post('/api/auth/invite/create', data); }
  listInvites() { return this.get('/api/auth/invite/list'); }
  register(data) { return this.post('/api/auth/register', data); }
  getProfile() { return this.get('/api/auth/me'); }
  updateMode(mode) { return this.put('/api/auth/me/mode', { mode }); }
  completeOnboarding(data) { return this.post('/api/auth/me/onboarding', data); }

  // ── Admin ──
  listUsers() { return this.get('/api/admin/users'); }
  getUserActivity(userId) { return this.get(`/api/admin/users/${userId}/activity`); }
  deactivateUser(userId) { return this.post(`/api/admin/users/${userId}/deactivate`); }
  reactivateUser(userId) { return this.post(`/api/admin/users/${userId}/reactivate`); }

  // ── Resume ──
  uploadResume(file) { return this.upload('/api/resume/upload', file); }
  getResumeProfile() { return this.get('/api/resume/profile'); }

  // ── Campaigns ──
  createCampaign(data) { return this.post('/api/campaigns/', data); }
  listCampaigns() { return this.get('/api/campaigns/'); }
  getCampaign(id) { return this.get(`/api/campaigns/${id}`); }
  updateCampaignStatus(id, status) { return this.put(`/api/campaigns/${id}/status`, { status }); }
  addCampaignContacts(id, contacts) { return this.post(`/api/campaigns/${id}/contacts`, { contacts }); }
  getCampaignAnalytics(id) { return this.get(`/api/campaigns/${id}/analytics`); }

  // ── Opportunities ──
  searchOpportunities(query, location) {
    const params = new URLSearchParams();
    if (query) params.set('query', query);
    if (location) params.set('location', location);
    return this.get(`/api/opportunities/search?${params}`);
  }
  listOpportunities() { return this.get('/api/opportunities/'); }
  getOpportunity(id) { return this.get(`/api/opportunities/${id}`); }

  // ── Settings ──
  getSmtpStatus() { return this.get('/api/settings/smtp/status'); }
  configureSMTP(data) { return this.post('/api/settings/smtp/configure', data); }
  deleteSMTP() { return this.delete('/api/settings/smtp'); }
  testSMTP(email) { return this.post('/api/settings/smtp/test', { email }); }

  // ── Health ──
  health() { return this.get('/health'); }
}

export const api = new ApiClient();
