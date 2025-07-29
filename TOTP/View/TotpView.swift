import Foundation
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

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
                    withAnimation(.spring()) {
                        self.offset = 0
                        self.showingActions = false
                    }
                    self.editing = self.otp
                }) {
                    Image(systemName: "pencil")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.blue, in: Circle())
                }
                
                // Delete button
                Button(action: {
                    withAnimation(.spring()) {
                        self.offset = 0
                        self.showingActions = false
                    }
                    self.deleting = self.otp
                }) {
                    Image(systemName: "trash")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.red, in: Circle())
                }
            }
            .opacity(showingActions ? 1 : 0)
            
            // Main card content
            HStack {
                // Native circular progress indicator
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 4)
                        .frame(width: 60, height: 60)

                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))

                    Text("\(refreshIn)")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(.primary)
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

                VStack(alignment: .leading) {
                    if let code = self.code {
                        Text(self.numberFormatter.string(from: NSNumber(value: code))!)
                            .font(.system(.title2, design: .monospaced))
                            .fontWeight(.semibold)
                            .padding(.bottom, 2)
                    } else {
                        Text("--- ---")
                            .font(.system(.title2, design: .monospaced))
                            .fontWeight(.semibold)
                            .padding(.bottom, 2)
                    }
                    if let issuer = self.otp.issuer {
                        Text(issuer)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                    if let name = self.otp.name {
                        Text(name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.separator.opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
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
                        withAnimation(.spring()) {
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
                    withAnimation(.spring()) {
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
                
                Button(action: {
                    self.deleting = self.otp
                }) {
                    Label("Delete", systemImage: "trash")
                }
                .foregroundColor(.red)
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
