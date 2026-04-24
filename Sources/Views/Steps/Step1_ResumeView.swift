import SwiftUI
import UniformTypeIdentifiers

// MARK: - Step 1: Resume Upload
struct Step1_ResumeView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var isDragging = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("Upload Your Resume")
                        .font(.largeTitle.bold())
                    Text("Drop your PDF or DOCX and AI will analyze your profile")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 32)
                
                // Drop Zone
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                        .foregroundColor(isDragging ? Color(hex: "#8b5cf6") : .gray.opacity(0.4))
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(isDragging ? Color(hex: "#8b5cf6").opacity(0.08) : Color.clear)
                        )
                    
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 48))
                            .foregroundColor(isDragging ? Color(hex: "#8b5cf6") : .gray)
                        
                        Text("Drop your resume here")
                            .font(.title3.weight(.medium))
                        
                        Text("PDF or DOCX format")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        
                        Button("Browse Files") {
                            openFilePicker()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: "#8b5cf6"))
                    }
                }
                .frame(height: 220)
                .padding(.horizontal, 40)
                .onDrop(of: [UTType.pdf, UTType.data], isTargeted: $isDragging) { providers in
                    handleDrop(providers: providers)
                    return true
                }
                
                // Loading State
                if vm.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(vm.loadingMessage)
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
                
                // AI Analysis Result
                if let profile = vm.resumeProfile {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("AI Analysis", systemImage: "sparkles")
                            .font(.title3.bold())
                            .foregroundColor(Color(hex: "#8b5cf6"))
                        
                        Divider()
                        
                        InfoRow(label: "Name", value: profile.name)
                        InfoRow(label: "Role", value: profile.currentRole)
                        InfoRow(label: "Experience", value: "\(profile.yearsExperience) years")
                        InfoRow(label: "Education", value: profile.education)
                        
                        Text("Skills")
                            .font(.subheadline.bold())
                            .padding(.top, 4)
                        
                        FlowLayout(spacing: 6) {
                            ForEach(profile.skills, id: \.self) { skill in
                                Text(skill)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(hex: "#8b5cf6").opacity(0.15))
                                    .foregroundColor(Color(hex: "#8b5cf6"))
                                    .cornerRadius(12)
                            }
                        }
                        
                        if !profile.industries.isEmpty {
                            Text("Industries")
                                .font(.subheadline.bold())
                            
                            FlowLayout(spacing: 6) {
                                ForEach(profile.industries, id: \.self) { industry in
                                    Text(industry)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color(hex: "#3b82f6").opacity(0.15))
                                        .foregroundColor(Color(hex: "#3b82f6"))
                                        .cornerRadius(12)
                                }
                            }
                        }
                    }
                    .padding(20)
                    .background(.regularMaterial)
                    .cornerRadius(12)
                    .padding(.horizontal, 40)
                    
                    Button {
                        vm.currentStep = .strategy
                    } label: {
                        Label("Continue to Strategy", systemImage: "arrow.right")
                            .font(.body.bold())
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#8b5cf6"))
                }
                
                Spacer(minLength: 32)
            }
        }
    }
    
    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.pdf, UTType(filenameExtension: "docx")!]
        panel.allowsMultipleSelection = false
        panel.message = "Select your resume (PDF or DOCX)"
        
        if panel.runModal() == .OK, let url = panel.url {
            Task { await vm.parseResume(from: url) }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.data.identifier) { item, _ in
                if let url = item as? URL {
                    let ext = url.pathExtension.lowercased()
                    if ext == "pdf" || ext == "docx" || ext == "doc" {
                        Task { @MainActor in await vm.parseResume(from: url) }
                    }
                }
            }
        }
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .font(.subheadline)
        }
    }
}

// MARK: - Flow Layout for Tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        
        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
