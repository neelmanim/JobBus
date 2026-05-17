const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:8000';

class ApiClient {
  constructor() {
    this.base = API_BASE;
    this.token = null;
  }

  setToken(token) { this.token = token; }

  async request(path, options = {}) {
    const url = `${this.base}${path}`;
    const headers = { 'Content-Type': 'application/json', ...options.headers };
    if (this.token) headers['Authorization'] = `Bearer ${this.token}`;
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

  get(path)         { return this.request(path); }
  put(path, body)   { return this.request(path, { method: 'PUT',    body: JSON.stringify(body) }); }
  delete(path)      { return this.request(path, { method: 'DELETE' }); }
  post(path, body, queryStr = '') {
    return this.request(`${path}${queryStr}`, {
      method: 'POST',
      body: body != null ? JSON.stringify(body) : undefined,
    });
  }

  async upload(path, file) {
    const formData = new FormData();
    formData.append('file', file);
    const headers = {};
    if (this.token) headers['Authorization'] = `Bearer ${this.token}`;
    const res = await fetch(`${this.base}${path}`, { method: 'POST', headers, body: formData });
    if (!res.ok) {
      const errorBody = await res.json().catch(() => ({ detail: res.statusText }));
      throw new Error(errorBody.detail || `Upload failed: HTTP ${res.status}`);
    }
    return res.json();
  }

  // ── Auth ──
  validateInvite(code)         { return this.post('/api/auth/invite/validate', { code }); }
  createInvite(data)           { return this.post('/api/auth/invite/create', data); }
  listInvites()                { return this.get('/api/auth/invite/list'); }
  register(inviteCode)         { return this.post(`/api/auth/register?invite_code=${encodeURIComponent(inviteCode)}`); }
  getProfile()                 { return this.get('/api/auth/me'); }
  updateMode(mode)             { return this.put('/api/auth/me/mode', { mode }); }
  completeOnboarding()          { return this.post('/api/auth/me/onboarding', { onboarding_complete: true }); }

  // ── Admin ──
  listUsers()                  { return this.get('/api/admin/users'); }
  getUserActivity(userId)      { return this.get(`/api/admin/users/${userId}/activity`); }
  deactivateUser(userId)       { return this.post(`/api/admin/users/${userId}/deactivate`); }
  reactivateUser(userId)       { return this.post(`/api/admin/users/${userId}/reactivate`); }
  getSystemConfig()            { return this.get('/api/admin/config'); }
  saveSystemConfig(data)       { return this.put('/api/admin/config', data); }
  getPlatformUsage()           { return this.get('/api/admin/usage'); }

  // ── Resume ──
  uploadResume(file)           { return this.upload('/api/resume/upload', file); }
  getResumeProfile()           { return this.get('/api/resume/profile'); }
  saveResumeText(text)         { return this.post('/api/resume/text', { text }); }

  // ── Opportunities ──
  searchOpportunities(query, location) {
    const params = new URLSearchParams();
    if (query)    params.set('query', query);
    if (location) params.set('location', location);
    return this.get(`/api/opportunities/search?${params}`);
  }
  listOpportunities()          { return this.get('/api/opportunities/'); }
  getOpportunity(id)           { return this.get(`/api/opportunities/${id}`); }

  // ── Contacts ──
  listContacts(params = {}) {
    const q = new URLSearchParams(params);
    return this.get(`/api/contacts/${q.toString() ? `?${q}` : ''}`);
  }
  createContact(data)          { return this.post('/api/contacts/', data); }
  bulkCreateContacts(list)     { return this.post('/api/contacts/bulk', list); }
  deleteContact(id)            { return this.delete(`/api/contacts/${id}`); }
  findContacts(opts)           { return this.post('/api/contacts/find', opts); }
  importContactsCSV(file)      { return this.upload('/api/contacts/import-csv', file); }

  // ── Campaigns ──
  createCampaign(data)         { return this.post('/api/campaigns/', data); }
  listCampaigns()              { return this.get('/api/campaigns/'); }
  getCampaign(id)              { return this.get(`/api/campaigns/${id}`); }
  updateCampaignStatus(id, s)  { return this.put(`/api/campaigns/${id}/status`, { status: s }); }
  addCampaignContacts(id, c)   { return this.post(`/api/campaigns/${id}/contacts`, c); }
  getCampaignAnalytics(id)     { return this.get(`/api/campaigns/${id}/analytics`); }
  getCampaignContacts(id)      { return this.get(`/api/campaigns/${id}/contacts`); }

  // ── Campaign Workflow (human-in-the-loop) ──
  generateDrafts(id, opts)     { return this.post(`/api/campaigns/${id}/generate-drafts`, opts); }
  listDrafts(id)               { return this.get(`/api/campaigns/${id}/drafts`); }
  approveDraft(id, data)       { return this.post(`/api/campaigns/${id}/drafts/approve`, data); }
  sendCampaign(id, opts)       { return this.post(`/api/campaigns/${id}/send/start`, opts); }
  controlCampaign(id, action)  { return this.post(`/api/campaigns/${id}/send/${action}`); }
  recordOutcome(id, data)      { return this.post(`/api/campaigns/${id}/outcomes`, data); }
  getCampaignOutcomes(id)      { return this.get(`/api/campaigns/${id}/outcomes`); }

  // ── Settings: SMTP ──
  getSmtpStatus()              { return this.get('/api/settings/smtp/status'); }
  configureSMTP(data)          { return this.post('/api/settings/smtp/configure', data); }
  saveSmtpCredentials(data)    { return this.post('/api/settings/smtp/configure', data); }  // alias for onboarding
  deleteSMTP()                 { return this.delete('/api/settings/smtp'); }
  testSMTP(email)              { return this.post('/api/settings/smtp/test', { email }); }

  // ── Settings: Providers ──
  getProviderStatus()          { return this.get('/api/settings/providers/status'); }
  saveProviderKey(field, val)  { return this.post('/api/settings/providers/key', { field, value: val }); }
  testProviderKey(field)       { return this.post('/api/settings/providers/test', null, `?field=${field}`); }
  setAiProvider(provider)      { return this.put('/api/settings/ai-provider', typeof provider === 'string' ? { ai_provider: provider } : provider); }
  setAIProvider(data)          { return this.put('/api/settings/ai-provider', data); }  // legacy
  setSearchProvider(provider)  { return this.put('/api/settings/search-provider', typeof provider === 'string' ? { search_provider: provider } : provider); }
  getSearchQuota(refresh=false){ return this.get(`/api/settings/search-quota${refresh ? '?refresh=true' : ''}`); }
  getAppInit()                 { return this.get('/api/auth/init'); }

  // ── Settings: Email Style ──
  getEmailStyle()              { return this.get('/api/settings/email-style'); }
  updateEmailStyle(data)       { return this.put('/api/settings/email-style', data); }

  // ── Settings: Campaign Defaults ──
  getCampaignDefaults()        { return this.get('/api/settings/campaign-defaults'); }
  updateCampaignDefaults(data) { return this.put('/api/settings/campaign-defaults', data); }

  // ── Health ──
  health()                     { return this.get('/health'); }
}

export const api = new ApiClient();
