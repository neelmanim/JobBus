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
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Text("AI Email Drafts")
                    .font(.largeTitle.bold())
                
                if vm.isLoading {
                    ProgressView(value: Double(vm.drafts.count), total: Double(max(1, vm.contacts.filter { $0.isSelected }.count)))
                    Text(vm.loadingMessage)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                
                // Stats
                HStack(spacing: 20) {
                    StatBadge(label: "Approved", count: approvedCount, color: "#10b981")
                    StatBadge(label: "Pending", count: pendingCount, color: "#f59e0b")
                    StatBadge(label: "Needs Review", count: reviewCount, color: "#ef4444")
                    StatBadge(label: "Total", count: vm.drafts.count, color: "#8b5cf6")
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 12)
            
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
                                        contact: contact, resume: profile, ai: vm.aiProvider
                                    ) {
                                        vm.drafts[index] = newDraft
                                        vm.drafts[index].regenerateCount += 1
                                    }
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
            
            // Bottom Bar
            HStack {
                let minReviews = 10
                if reviewedCount < minReviews {
                    Text("Review at least \(minReviews - reviewedCount) more drafts to enable Approve All")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                Spacer()
                
                Button("Approve All Remaining") {
                    for i in vm.drafts.indices {
                        if vm.drafts[i].status == .pending {
                            vm.drafts[i].status = .approved
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(reviewedCount < 10)
                
                Button {
                    vm.currentStep = .send
                } label: {
                    Label("Ready to Send", systemImage: "paperplane.fill")
                        .font(.body.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#8b5cf6"))
                .disabled(approvedCount == 0)
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
                
                // Quality badge
                Image(systemName: draft.qualityScore.grade.icon)
                    .foregroundColor(Color(hex: draft.qualityScore.grade.colorHex))
                
                // Status
                if draft.status == .approved {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            
            Text(draft.subject)
                .font(.body.weight(.semibold))
            
            Text(draft.body.prefix(120) + (draft.body.count > 120 ? "..." : ""))
                .font(.callout)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                
                Button(action: onRegenerate) {
                    Label("Regenerate", systemImage: "arrow.counterclockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(draft.status == .generating)
                
                Spacer()
                
                if draft.status != .approved {
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
                .stroke(draft.status == .approved ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
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
    @State private var subject: String = ""
    @State private var emailBody: String = ""
    @Environment(\.dismiss) var dismiss
    let onSave: (String, String) -> Void
    
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
        .onAppear {
            subject = draft.subject
            emailBody = draft.body
        }
    }
}
