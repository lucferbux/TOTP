import Foundation
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

@available(iOS 26.0, macOS 26.0, *)
public struct TOtpView: View {
    private let timer = Timer.publish(every: 1, on: .main, in: .common)
    private var numberFormatter: NumberFormatter = {
        var formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter
    }()

    private var cutoff: CGFloat
    @State private var otp: OtpModel
    @State private var code: UInt64?
    @State private var progress: Double = 1.0
    @State private var refreshIn: Int
    @State private var offset: CGFloat = 0.0
    @State private var showingActions = false
    @Binding private var deleting: OtpModel?
    @Binding private var editing: OtpModel?
    @Binding private var toast: Bool

    public init(otp: OtpModel, cutoff: CGFloat, deleting: Binding<OtpModel?>, editing: Binding<OtpModel?>, toast: Binding<Bool>)
    {
        self._otp = State(wrappedValue: otp)
        self._refreshIn = State(wrappedValue: otp.entry.get_display_value())
        self._deleting = deleting
        self._editing = editing
        self._toast = toast
        self.cutoff = cutoff

        let subscription = self.timer.connect()
        switch self.otp.entry {
        case let .hotp(_, digits, _):
            self.numberFormatter.minimumIntegerDigits = digits
            subscription.cancel()
        case let .totp(_, digits, _):
            self.numberFormatter.minimumIntegerDigits = digits
        }
    }
    public var body: some View {
        ZStack {
            // Background action buttons
            HStack {
                Spacer()
                
                // Edit button
                Button(action: {
                    withAnimation(.smooth(duration: 0.3)) {
                        self.offset = 0
                        self.showingActions = false
                    }
                    self.editing = self.otp
                }) {
                    Image(systemName: "pencil")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(.blue.gradient, in: Circle())
                        .glassEffect(.regular.tint(.blue.opacity(0.3)))
                }
                
                // Delete button
                Button(action: {
                    withAnimation(.smooth(duration: 0.3)) {
                        self.offset = 0
                        self.showingActions = false
                    }
                    self.deleting = self.otp
                }) {
                    Image(systemName: "trash")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(.red.gradient, in: Circle())
                        .glassEffect(.regular.tint(.red.opacity(0.3)))
                }
            }
            .opacity(showingActions ? 1 : 0)
            
            // Main card content
            HStack {
                // Native circular progress indicator with Liquid Glass
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 3)
                        .frame(width: 56, height: 56)

                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 56, height: 56)
                        .rotationEffect(.degrees(-90))

                    Text("\(refreshIn)")
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
                .padding(.trailing, 15)
                .onReceive(self.timer) { _ in
                    if case let .totp(_, _, interval) = self.otp.entry {
                        let time = Date().timeIntervalSince1970
                        if time.remainder(dividingBy: interval) == 0 {
                            withAnimation(.linear(duration: 1)) {
                                self.progress = 1.0
                            }
                        } else {
                            let nextUpdate = Double(ceil(time / interval) * interval)
                            withAnimation(.linear(duration: 1)) {
                                self.progress = 1.0 - ((nextUpdate - time) / interval)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let code = self.code {
                        Text(self.numberFormatter.string(from: NSNumber(value: code))!)
                            .font(.system(.title2, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                    } else {
                        Text("--- ---")
                            .font(.system(.title2, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                    }
                    if let issuer = self.otp.issuer {
                        Text(issuer)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                    if let name = self.otp.name {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.systemBackground))
            }
            .glassEffect(.regular.interactive())
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(Rectangle())
            .scaleEffect(deleting?.id == otp.id ? 0.95 : 1.0)
            .offset(x: self.offset)
            .gesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onChanged { value in
                        // Only allow left swipe (negative translation)
                        if value.translation.width < 0 {
                            self.offset = max(value.translation.width, -120) // Limit to -120 points
                            self.showingActions = self.offset < -60
                        }
                    }
                    .onEnded { value in
                        withAnimation(.smooth(duration: 0.35)) {
                            if value.translation.width < -60 {
                                // Show actions
                                self.offset = -120
                                self.showingActions = true
                            } else {
                                // Snap back
                                self.offset = 0
                                self.showingActions = false
                            }
                        }
                    }
            )
            .onTapGesture {
                if showingActions {
                    // Hide actions if they're showing
                    withAnimation(.smooth(duration: 0.3)) {
                        self.offset = 0
                        self.showingActions = false
                    }
                } else {
                    // Copy to clipboard
                    #if canImport(UIKit)
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                    #endif

                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.toast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                self.toast = false
                            }
                        }
                    }
                    let code = self.otp.entry.code()
                    self.code = code
                    self.refreshIn = self.otp.entry.get_display_value()
                    let prefix = self.otp.prefix ?? ""
                    PlatformPasteboard.copyToClipboard("\(prefix)\(code)")
                }
            }
            .contextMenu {
                Button(action: {
                    self.editing = self.otp
                }) {
                    Label("Edit", systemImage: "pencil")
                }
                
                Button(role: .destructive, action: {
                    self.deleting = self.otp
                }) {
                    Label("Delete", systemImage: "trash")
                }
            }
            .onReceive(self.timer) { _ in
                if case .totp = self.otp.entry {
                    self.code = self.otp.entry.code()
                    self.refreshIn = self.otp.entry.get_display_value()
                }
            }
            .frame(minWidth: 250, maxWidth: 325)
        }
        .clipped()
    }
}
