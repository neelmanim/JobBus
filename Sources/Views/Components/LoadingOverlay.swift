import SwiftUI

// MARK: - Loading Phase
enum LoadingPhase: String {
    case parsing = "Analyzing"
    case searching = "Discovering"
    case enriching = "Enriching"
    case composing = "Composing"
    case sending = "Sending"
    
    var icon: String {
        switch self {
        case .parsing: return "doc.text.magnifyingglass"
        case .searching: return "person.3.fill"
        case .enriching: return "envelope.badge.person.crop"
        case .composing: return "envelope.open.fill"
        case .sending: return "paperplane.fill"
        }
    }
    
    var gradientColors: [Color] {
        switch self {
        case .parsing: return [Color(hex: "#f59e0b"), Color(hex: "#ef4444")]
        case .searching: return [Color(hex: "#8b5cf6"), Color(hex: "#6366f1")]
        case .enriching: return [Color(hex: "#3b82f6"), Color(hex: "#06b6d4")]
        case .composing: return [Color(hex: "#8b5cf6"), Color(hex: "#ec4899")]
        case .sending: return [Color(hex: "#10b981"), Color(hex: "#3b82f6")]
        }
    }
}

// MARK: - Loading Overlay View
struct LoadingOverlay: View {
    let message: String
    var phase: LoadingPhase = .searching
    var progress: Int = 0
    var total: Int = 0
    
    @State private var ring1Pulse = false
    @State private var ring2Pulse = false
    @State private var ring3Pulse = false
    @State private var iconRotation = false
    @State private var shimmerOffset: CGFloat = -200
    
    private var hasProgress: Bool { total > 0 }
    private var progressFraction: Double { hasProgress ? Double(progress) / Double(max(1, total)) : 0 }
    
    var body: some View {
        VStack(spacing: 20) {
            // Animated icon with pulse rings
            ZStack {
                // Ring 3 (outer)
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: phase.gradientColors.map { $0.opacity(0.15) },
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: 90, height: 90)
                    .scaleEffect(ring3Pulse ? 1.15 : 0.85)
                    .opacity(ring3Pulse ? 0.0 : 0.6)
                
                // Ring 2 (middle)
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: phase.gradientColors.map { $0.opacity(0.25) },
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 68, height: 68)
                    .scaleEffect(ring2Pulse ? 1.1 : 0.9)
                    .opacity(ring2Pulse ? 0.0 : 0.8)
                
                // Ring 1 (inner glow)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: phase.gradientColors.map { $0.opacity(0.1) } + [.clear],
                            center: .center, startRadius: 10, endRadius: 30
                        )
                    )
                    .frame(width: 52, height: 52)
                    .scaleEffect(ring1Pulse ? 1.05 : 0.95)
                
                // Icon
                Image(systemName: phase.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: phase.gradientColors,
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse.byLayer, options: .repeating)
            }
            .frame(width: 100, height: 100)
            
            // Phase label
            Text(phase.rawValue)
                .font(.caption.weight(.semibold))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(
                    LinearGradient(
                        colors: phase.gradientColors,
                        startPoint: .leading, endPoint: .trailing
                    )
                )
            
            // Message with shimmer
            Text(message)
                .font(.callout.weight(.medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 280)
            
            // Progress bar (shown during enrichment / batch operations)
            if hasProgress {
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Track
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 6)
                            
                            // Fill
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: phase.gradientColors,
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .frame(width: max(6, geo.size.width * progressFraction), height: 6)
                                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progressFraction)
                        }
                    }
                    .frame(height: 6)
                    .frame(maxWidth: 220)
                    
                    Text("\(progress)/\(total)")
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: phase.gradientColors.first?.opacity(0.08) ?? .clear, radius: 20, y: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            LinearGradient(
                                colors: phase.gradientColors.map { $0.opacity(0.15) },
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false)) {
                ring3Pulse = true
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false).delay(0.3)) {
                ring2Pulse = true
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                ring1Pulse = true
            }
        }
    }
}

// MARK: - Inline Loading Indicator (for buttons and small areas)
struct InlineLoadingIndicator: View {
    let message: String
    var phase: LoadingPhase = .searching
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: phase.icon)
                .font(.caption)
                .foregroundStyle(
                    LinearGradient(
                        colors: phase.gradientColors,
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .symbolEffect(.pulse.byLayer, options: .repeating)
            
            Text(message)
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
