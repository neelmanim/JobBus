import SwiftUI

// MARK: - Main View
struct MainView: View {
    @EnvironmentObject var vm: AppViewModel
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(alignment: .leading, spacing: 0) {
                // App Header
                HStack(spacing: 10) {
                    Image(systemName: "bus.fill")
                        .font(.title2)
                        .foregroundStyle(.linearGradient(
                            colors: [Color(hex: "#8b5cf6"), Color(hex: "#3b82f6")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                    Text("Job Bus")
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
                
                // Step Navigation
                ForEach(AppStep.allCases) { step in
                    StepNavItem(
                        step: step,
                        isActive: vm.currentStep == step,
                        isComplete: step.rawValue < vm.currentStep.rawValue
                    ) {
                        if step.rawValue <= vm.currentStep.rawValue {
                            vm.currentStep = step
                        }
                    }
                }
                
                Spacer()
                
                // Sandbox Banner
                if vm.settings.sandboxMode {
                    HStack {
                        Image(systemName: "flask.fill")
                        Text("SANDBOX MODE")
                            .font(.caption.bold())
                    }
                    .foregroundColor(.orange)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(8)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                
                // Settings Button
                Divider()
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    HStack {
                        Image(systemName: "gearshape.fill")
                        Text("Settings")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .frame(minWidth: 200)
        } detail: {
            // Content Area
            ZStack {
                switch vm.currentStep {
                case .resume:
                    Step1_ResumeView()
                case .strategy:
                    Step2_StrategyView()
                case .contacts:
                    Step3_ContactsView()
                case .drafts:
                    Step4_DraftsView()
                case .send:
                    Step5_SendView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert("Error", isPresented: $vm.showError) {
            Button("OK") { vm.showError = false }
        } message: {
            Text(vm.errorMessage ?? "An unknown error occurred.")
        }
    }
}

// MARK: - Step Navigation Item
struct StepNavItem: View {
    let step: AppStep
    let isActive: Bool
    let isComplete: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isActive ? Color(hex: "#8b5cf6") : isComplete ? Color(hex: "#10b981") : Color.gray.opacity(0.3))
                        .frame(width: 28, height: 28)
                    
                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: step.icon)
                            .font(.caption)
                            .foregroundColor(isActive ? .white : .secondary)
                    }
                }
                
                Text(step.title)
                    .font(.body.weight(isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .primary : .secondary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(isActive ? Color(hex: "#8b5cf6").opacity(0.12) : Color.clear)
            .cornerRadius(8)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .disabled(!isComplete && !isActive && step.rawValue > (isComplete ? step.rawValue : 0))
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
