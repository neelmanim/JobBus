import { useState, useEffect, useRef } from 'react';
import { api } from '../../lib/api';
import { useToast } from '../../contexts/ToastContext';
import {
  Upload, FileText, CheckCircle, Sparkles, Briefcase,
  Code, GraduationCap, Award, RefreshCw, X
} from 'lucide-react';
import './Resume.css';

export default function Resume() {
  const toast = useToast();
  const fileRef = useRef(null);
  const [profile, setProfile] = useState(null);
  const [loading, setLoading] = useState(true);
  const [uploading, setUploading] = useState(false);
  const [dragOver, setDragOver] = useState(false);

  useEffect(() => { loadProfile(); }, []);

  async function loadProfile() {
    try {
      const data = await api.getResumeProfile();
      setProfile(data);
    } catch (err) {
      if (err.status !== 404) toast.error('Failed to load resume');
    } finally {
      setLoading(false);
    }
  }

  async function handleUpload(file) {
    if (!file) return;
    const validTypes = ['application/pdf', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'];
    if (!validTypes.includes(file.type)) {
      toast.error('Please upload a PDF or DOCX file');
      return;
    }
    if (file.size > 10 * 1024 * 1024) {
      toast.error('File must be under 10MB');
      return;
    }
    setUploading(true);
    try {
      const data = await api.uploadResume(file);
      setProfile(data);
      toast.success('Resume analyzed successfully');
    } catch (err) {
      toast.error(err.message || 'Upload failed');
    } finally {
      setUploading(false);
    }
  }

  function handleDrop(e) {
    e.preventDefault();
    setDragOver(false);
    const file = e.dataTransfer?.files?.[0];
    if (file) handleUpload(file);
  }

  if (loading) {
    return (
      <div className="resume-page">
        <div className="page-header">
          <h1>Resume</h1>
          <p>Your AI-analyzed career profile</p>
        </div>
        <div className="card">
          <div className="skeleton" style={{ width: '60%', height: 24, marginBottom: 16 }} />
          <div className="skeleton" style={{ width: '100%', height: 120 }} />
        </div>
      </div>
    );
  }

  return (
    <div className="resume-page">
      <div className="page-header">
        <h1>Resume</h1>
        <p>Your AI-analyzed career profile</p>
      </div>

      {/* Upload Zone */}
      {!profile ? (
        <div
          className={`upload-zone ${dragOver ? 'upload-zone-active' : ''}`}
          onDragOver={(e) => { e.preventDefault(); setDragOver(true); }}
          onDragLeave={() => setDragOver(false)}
          onDrop={handleDrop}
          onClick={() => fileRef.current?.click()}
        >
          <input
            ref={fileRef}
            type="file"
            accept=".pdf,.docx"
            onChange={(e) => handleUpload(e.target.files?.[0])}
            style={{ display: 'none' }}
          />
          {uploading ? (
            <>
              <div className="spinner" style={{ width: 40, height: 40, borderWidth: 3 }} />
              <h3>Analyzing your resume...</h3>
              <p>AI is extracting skills, experience, and building your profile</p>
            </>
          ) : (
            <>
              <div className="upload-icon-wrap">
                <Upload size={32} />
              </div>
              <h3>Upload your resume</h3>
              <p>Drag & drop a PDF or DOCX file, or click to browse</p>
              <span className="upload-hint">Max 10MB • PDF or DOCX</span>
            </>
          )}
        </div>
      ) : (
        <>
          {/* Profile Card */}
          <div className="card resume-profile">
            <div className="profile-header">
              <div className="profile-avatar">
                {profile.name?.[0] || '?'}
              </div>
              <div className="profile-info">
                <h2>{profile.name || 'Your Name'}</h2>
                <p className="text-secondary">{profile.headline || profile.current_title || 'Professional'}</p>
              </div>
              <div className="profile-actions">
                <button className="btn btn-secondary btn-sm" onClick={() => { setProfile(null); }}>
                  <RefreshCw size={14} /> Re-upload
                </button>
              </div>
            </div>

            {profile.summary && (
              <div className="profile-section">
                <h4><Sparkles size={14} /> AI Summary</h4>
                <p>{profile.summary}</p>
              </div>
            )}

            {profile.skills && profile.skills.length > 0 && (
              <div className="profile-section">
                <h4><Code size={14} /> Skills</h4>
                <div className="skill-tags">
                  {profile.skills.map((skill, i) => (
                    <span key={i} className="skill-tag">{skill}</span>
                  ))}
                </div>
              </div>
            )}

            {profile.experience && profile.experience.length > 0 && (
              <div className="profile-section">
                <h4><Briefcase size={14} /> Experience</h4>
                <div className="experience-list">
                  {profile.experience.map((exp, i) => (
                    <div key={i} className="exp-item">
                      <div className="exp-dot" />
                      <div>
                        <strong>{exp.title || exp.role}</strong>
                        <span className="text-secondary"> at {exp.company}</span>
                        {exp.duration && <span className="exp-duration">{exp.duration}</span>}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {profile.education && profile.education.length > 0 && (
              <div className="profile-section">
                <h4><GraduationCap size={14} /> Education</h4>
                {profile.education.map((edu, i) => (
                  <div key={i} className="edu-item">
                    <strong>{edu.degree}</strong>
                    <span className="text-secondary"> — {edu.institution}</span>
                  </div>
                ))}
              </div>
            )}
          </div>
        </>
      )}
    </div>
  );
}
