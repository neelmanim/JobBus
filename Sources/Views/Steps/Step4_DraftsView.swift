import SwiftUI

// MARK: - Step 4: Draft Review
struct Step4_DraftsView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var selectedDraft: EmailDraft?
    @State private var editingBody = ""
    @State private var editingSubject = ""
    @State private var reviewedCount = 0
    
    var pendingCount: Int { vm.drafts.filter { $0.status == .pending }.count }
    var approvedCount: Int { vm.drafts.filter { $0.status == .approved }.count }
    var reviewCount: Int { vm.drafts.filter { $0.status == .review }.count }
    var failedCount: Int { vm.drafts.filter { $0.status == .failed }.count }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Text("AI Email Drafts")
                    .font(.largeTitle.bold())
                
                if vm.isGenerating {
                    VStack(spacing: 8) {
                        let totalContacts = vm.contacts.filter { $0.isSelected && !$0.email.isEmpty }.count
                        ProgressView(value: Double(vm.drafts.count), total: Double(max(1, totalContacts)))
                            .tint(Color(hex: "#8b5cf6"))
                        
                        Text(vm.loadingMessage)
                            .font(.callout)
                            .foregroundColor(.secondary)
                        
                        Button {
                            vm.cancelGeneration()
                        } label: {
                            Label("Cancel Generation", systemImage: "xmark.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .padding(.horizontal, 40)
                }
                
                // Stats
                HStack(spacing: 20) {
                    StatBadge(label: "Approved", count: approvedCount, color: "#10b981")
                    StatBadge(label: "Pending", count: pendingCount, color: "#f59e0b")
                    StatBadge(label: "Needs Review", count: reviewCount, color: "#ef4444")
                    if failedCount > 0 {
                        StatBadge(label: "Failed", count: failedCount, color: "#dc2626")
                    }
                    StatBadge(label: "Total", count: vm.drafts.count, color: "#8b5cf6")
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 12)
            
            if vm.drafts.isEmpty && !vm.isGenerating {
                // Empty state
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("No drafts yet")
                        .font(.title2.weight(.medium))
                        .foregroundColor(.secondary)
                    Text("Go to Contacts and click Compose Emails to generate AI-powered email drafts.")
                        .font(.callout)
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 350)
                }
                Spacer()
            } else {
                // Draft List
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(vm.drafts.enumerated()), id: \.element.id) { index, draft in
                            DraftCard(
                                draft: draft,
                                onApprove: {
                                    vm.drafts[index].status = .approved
                                    reviewedCount += 1
                                },
                                onReject: {
                                    vm.drafts[index].status = .rejected
                                },
                                onEdit: {
                                    selectedDraft = draft
                                    editingSubject = draft.subject
                                    editingBody = draft.body
                                },
                                onRegenerate: {
                                    Task {
                                        guard let contact = vm.contacts.first(where: { $0.id == draft.contactId }),
                                              let profile = vm.resumeProfile else { return }
                                        vm.drafts[index].status = .generating
                                        if let newDraft = try? await vm.emailWriter.compose(
                                            contact: contact, resume: profile, ai: vm.aiProvider,
                                            customInstructions: vm.settings.customPromptInstructions,
                                            sampleEmails: vm.settings.sampleEmails
                                        ) {
                                            vm.drafts[index] = newDraft
                                            vm.drafts[index].regenerateCount += 1
                                        } else {
                                            vm.drafts[index].status = .failed
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            
            // Bottom Bar
            HStack {
                if !vm.drafts.isEmpty {
                    let minReviews = min(10, vm.drafts.count)
                    if reviewedCount < minReviews && vm.drafts.count > 10 {
                        Text("Review at least \(minReviews - reviewedCount) more drafts to enable Approve All")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Spacer()
                
                if !vm.drafts.isEmpty {
                    Button("Approve All Remaining") {
                        for i in vm.drafts.indices {
                            if vm.drafts[i].status == .pending {
                                vm.drafts[i].status = .approved
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.drafts.count > 10 && reviewedCount < 10)
                    .help("Approve all drafts you haven't reviewed yet. Review at least 10 first to ensure quality.")
                    
                    Button {
                        vm.currentStep = .send
                    } label: {
                        Label("Ready to Send", systemImage: "paperplane.fill")
                            .font(.body.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#8b5cf6"))
                    .disabled(approvedCount == 0)
                    .help("\(approvedCount) emails approved and ready to send")
                }
            }
            .padding(16)
            .background(.bar)
        }
        .sheet(item: $selectedDraft) { draft in
            EditDraftSheet(draft: draft) { newSubject, newBody in
                if let i = vm.drafts.firstIndex(where: { $0.id == draft.id }) {
                    vm.drafts[i].subject = newSubject
                    vm.drafts[i].body = newBody
                    vm.drafts[i].status = .approved
                    vm.drafts[i].htmlBody = EmailTemplateBuilder.buildHTML(
                        body: newBody,
                        signature: EmailSignature(
                            name: vm.settings.signatureName,
                            title: vm.settings.signatureTitle,
                            linkedin: vm.settings.signatureLinkedin,
                            phone: vm.settings.signaturePhone
                        )
                    )
                    reviewedCount += 1
                }
            }
        }
    }
}

// MARK: - Draft Card
struct DraftCard: View {
    let draft: EmailDraft
    let onApprove: () -> Void
    let onReject: () -> Void
    let onEdit: () -> Void
    let onRegenerate: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(draft.recipientType.label)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: "#8b5cf6").opacity(0.15))
                    .foregroundColor(Color(hex: "#8b5cf6"))
                    .cornerRadius(8)
                
                Text("To: \(draft.recipientName)")
                    .font(.subheadline.weight(.medium))
                Text("— \(draft.recipientTitle) @ \(draft.recipientCompany)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Resume attachment indicator
                if draft.shouldAttachResume {
                    HStack(spacing: 3) {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                        Text("Resume")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundColor(Color(hex: "#3b82f6"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(hex: "#3b82f6").opacity(0.1))
                    .cornerRadius(4)
                }
                
                // Quality badge
                if draft.status != .failed {
                    HStack(spacing: 3) {
                        Image(systemName: draft.qualityScore.grade.icon)
                        Text("\(draft.qualityScore.score)/11")
                            .font(.caption2.monospaced())
                    }
                    .foregroundColor(Color(hex: draft.qualityScore.grade.colorHex))
                    .help("Quality score: \(draft.qualityScore.score)/11 — checks name match, company mention, length, CTA, and more")
                }
                
                // Status indicator
                switch draft.status {
                case .approved:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                case .generating:
                    ProgressView()
                        .controlSize(.small)
                case .rejected:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                default:
                    EmptyView()
                }
            }
            
            if draft.status == .failed {
                Text(draft.subject)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.red)
            } else {
                Text(draft.subject)
                    .font(.body.weight(.semibold))
            }
            
            Text(draft.body.prefix(120) + (draft.body.count > 120 ? "..." : ""))
                .font(.callout)
                .foregroundColor(draft.status == .failed ? .red.opacity(0.7) : .secondary)
                .lineLimit(2)
            
            // Quality bar
            if draft.status != .failed {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.15))
                            .frame(height: 3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: draft.qualityScore.grade.colorHex))
                            .frame(width: geo.size.width * CGFloat(draft.qualityScore.score) / 11.0, height: 3)
                    }
                }
                .frame(height: 3)
            }
            
            HStack(spacing: 8) {
                if draft.status != .failed {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                
                Button(action: onRegenerate) {
                    HStack(spacing: 4) {
                        Label("Regenerate", systemImage: "arrow.counterclockwise")
                            .font(.caption)
                        if draft.regenerateCount > 0 {
                            Text("(\(draft.regenerateCount))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(draft.status == .generating)
                .help("Re-generate this email using AI. The new version may score differently.")
                
                Spacer()
                
                if draft.status != .approved && draft.status != .failed {
                    Button(action: onApprove) {
                        Label("Approve", systemImage: "checkmark")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    draft.status == .approved ? Color.green.opacity(0.3)
                    : draft.status == .failed ? Color.red.opacity(0.3)
                    : Color.clear,
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Stat Badge
struct StatBadge: View {
    let label: String
    let count: Int
    let color: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)").font(.title3.bold()).foregroundColor(Color(hex: color))
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }
}

// MARK: - Edit Draft Sheet
struct EditDraftSheet: View {
    let draft: EmailDraft
    @State private var subject: String
    @State private var emailBody: String
    @Environment(\.dismiss) var dismiss
    let onSave: (String, String) -> Void
    
    init(draft: EmailDraft, onSave: @escaping (String, String) -> Void) {
        self.draft = draft
        self.onSave = onSave
        // Initialize @State directly from draft — .onAppear is unreliable in sheets
        _subject = State(initialValue: draft.subject)
        _emailBody = State(initialValue: draft.body)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Email to \(draft.recipientName)")
                .font(.title3.bold())
            
            TextField("Subject", text: $subject)
                .textFieldStyle(.roundedBorder)
            
            TextEditor(text: $emailBody)
                .font(.body)
                .frame(minHeight: 250)
                .border(Color.gray.opacity(0.3))
                .cornerRadius(6)
            
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.bordered)
                Button("Save & Approve") {
                    onSave(subject, emailBody)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#8b5cf6"))
            }
        }
        .padding(24)
        .frame(width: 650, height: 500)
    }
}
