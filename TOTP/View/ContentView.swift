import Combine
import CryptoKit
import SwiftUI
import CloudKit

#if canImport(UIKit)
    import UIKit
#endif

@available(iOS 26.0, macOS 26.0, *)
public struct ContentView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var dataManager = SharedDataManager.shared
    @State private var accounts: [OtpModel] = []
    @State var addingAccount = false
    @State var editingAccount: OtpModel?
    @State var deletingAccount: OtpModel?
    @State var showCopiedToast = false
    @State var search = ""
    @State private var showingErrorAlert = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                // GitHub-style gray background
                #if os(iOS)
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                #else
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
                #endif
                
                VStack {
                    GeometryReader { geometry in
                        ScrollView {
                            ZStack {
                                // Content when accounts exist or loading
                                if !self.accounts.isEmpty || dataManager.isLoading {
                                    VStack {
                                        let searchField = self.search.trimmingCharacters(
                                            in: .whitespacesAndNewlines)
                                        LazyVGrid(
                                            columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: geometry.size.width > 768 ? 3 : 1),
                                            alignment: .center,
                                            spacing: 12
                                        ) {
                                            ForEach(
                                                searchField.isEmpty
                                                    ? self.accounts
                                                    : self.accounts
                                                        .filter {
                                                            $0.name?.localizedCaseInsensitiveContains(
                                                                searchField) ?? false
                                                                || $0
                                                                    .issuer?
                                                                    .localizedCaseInsensitiveContains(
                                                                        searchField) ?? false
                                                        }
                                            ) { account in
                                                TOtpView(
                                                    otp: account,
                                                    cutoff: geometry.size.width,
                                                    deleting: $deletingAccount,
                                                    editing: $editingAccount,
                                                    toast: $showCopiedToast
                                                )
                                                // Force view recreation when account data changes
                                                .id("\(account.id)-\(account.issuer ?? "")-\(account.name ?? "")-\(account.prefix ?? "")-\(account.entry.hashValue)")
                                                .transition(
                                                    AnyTransition.asymmetric(
                                                        insertion: AnyTransition.move(edge: .leading),
                                                        removal: AnyTransition.move(edge: .trailing)
                                                    ).combined(with: AnyTransition.opacity)
                                                )
                                            }
                                        }
                                        .padding(.top)
                                        .padding(.horizontal, geometry.size.width > 768 ? 40 : 20)
                                        .frame(minWidth: geometry.size.width, maxWidth: geometry.size.width)

                                        // Loading indicator
                                        if dataManager.isLoading {
                                            VStack(spacing: 12) {
                                                ProgressView()
                                                    .scaleEffect(1.3)
                                                    .tint(.blue)
                                                Text("Loading accounts...")
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                        }

                                        // Instructions for existing accounts
                                        if !self.accounts.isEmpty {
                                            Spacer()
                                                .frame(height: 20)
                                        }
                                    }
                                }
                                
                                // Empty state - properly centered
                                if self.accounts.isEmpty && !dataManager.isLoading {
                                    VStack(spacing: 24) {
                                        Image(systemName: "lock.shield.fill")
                                            .font(.system(size: 70))
                                            .fontWeight(.light)
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: [.blue, .cyan],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .symbolEffect(.pulse.byLayer, options: .repeating)
                                        VStack(spacing: 8) {
                                            Text("No TOTP accounts")
                                                .font(.title2)
                                                .fontWeight(.semibold)
                                            Text("Add your first account to get started")
                                                .font(.body)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                                }
                            }
                        }
                        .refreshable {
                            dataManager.loadAccounts()
                        }
                        
                        // Toast message overlay
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Code copied to clipboard")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                                .background {
                                    Capsule()
                                        .fill(Color(.secondarySystemGroupedBackground))
                                }
                                .clipShape(Capsule())
                                Spacer()
                            }
                            .opacity(self.showCopiedToast ? 1.0 : 0.0)
                            .scaleEffect(self.showCopiedToast ? 1.0 : 0.8)
                            .animation(.smooth(duration: 0.25), value: self.showCopiedToast)
                            .allowsHitTesting(false)
                            .padding()
                        }
                    }
                }
                
                // Floating Action Button (iOS only)
                #if os(iOS)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            self.addingAccount = true
                        }) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .frame(width: 52, height: 52)
                        }
                        .buttonStyle(.plain)
                        .background {
                            Circle()
                                .fill(.background)
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.8),
                                            .white.opacity(0.2)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.5
                                )
                        }
                        .glassEffect(.regular.interactive())
                        .clipShape(Circle())
                        .sensoryFeedback(.impact(flexibility: .soft), trigger: addingAccount)
                        .padding(.trailing, 24)
                        .padding(.bottom, 32)
                    }
                }
                #endif
            }
            .navigationTitle("TOTP Passwords")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
            #elseif os(macOS)
                .toolbar {
                    ToolbarItem(placement: .secondaryAction) {
                        Button(action: {
                            dataManager.loadAccounts()
                        }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .help("Refresh accounts")
                        .disabled(dataManager.isLoading)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            self.addingAccount = true
                        }) {
                            Label("Add Account", systemImage: "plus")
                        }
                        .help("Add new TOTP account")
                    }
                }
            #endif
        }
        .onAppear {
            self.accounts = dataManager.accounts
        }
        .onReceive(dataManager.$accounts) { newAccounts in
            withAnimation(.smooth(duration: 0.3)) {
                self.accounts = newAccounts
            }
        }
        .onReceive(dataManager.$error) { error in
            if error != nil {
                showingErrorAlert = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Data Error", isPresented: $showingErrorAlert) {
            Button("OK") {
                dataManager.error = nil
            }
        } message: {
            Text(dataManager.error?.localizedDescription ?? "An unknown error occurred")
        }
        .alert(item: $deletingAccount) { (item: OtpModel) in
            var alertText: String
            switch (item.issuer, item.name) {
            case let (.some(issuer), .some(name)):
                alertText = "the account \"\(name)\" for \"\(issuer)\""
            case let (.none, .some(name)):
                alertText = "the account \"\(name)\""
            case let (.some(issuer), .none):
                alertText = "the account for \"\(issuer)\""
            case (.none, .none):
                alertText = "this account"
            }
            return Alert(
                title: Text("Confirm Delete"),
                message: Text("Are you sure that you want to DELETE \(alertText)"),
                primaryButton: .destructive(Text("Delete").bold()) {
                    dataManager.deleteAccount(item)
                    withAnimation(.smooth(duration: 1)) {
                        self.accounts.removeAll(where: { $0.id == item.id })
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $addingAccount) {
            AddingPageView(
                accounts: $accounts, addingAccount: $addingAccount, dataManager: dataManager
            )
            .preferredColorScheme(self.colorScheme)
        }
        .sheet(item: $editingAccount) { account in
            AddingPageView(
                accounts: $accounts, addingAccount: $addingAccount, dataManager: dataManager, editingAccount: account
            )
            .preferredColorScheme(self.colorScheme)
            .onDisappear {
                editingAccount = nil
            }
        }
    }
}

struct ContentViewPreviewLight: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.light)
    }
}

struct ContentViewPreviewDark: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.dark)
    }
}

// Preview with empty state
struct ContentViewEmptyPreview: PreviewProvider {
    static var previews: some View {
        Group {
            ContentViewEmpty()
                .preferredColorScheme(.light)
                .previewDisplayName("Empty State - Light")
            
            ContentViewEmpty()
                .preferredColorScheme(.dark)
                .previewDisplayName("Empty State - Dark")
        }
    }
}

// Preview with sample data
struct ContentViewWithDataPreview: PreviewProvider {
    static var previews: some View {
        Group {
            ContentViewWithSampleData()
                .preferredColorScheme(.light)
                .previewDisplayName("With Data - Light")
            
            ContentViewWithSampleData()
                .preferredColorScheme(.dark)
                .previewDisplayName("With Data - Dark")
        }
    }
}

// Mock view for empty state
@available(iOS 26.0, macOS 26.0, *)
struct ContentViewEmpty: View {
    @State private var accounts: [OtpModel] = []
    @State var addingAccount = false
    @State var deletingAccount: OtpModel?
    @State var showCopiedToast = false
    @State var search = ""
    @State private var showingErrorAlert = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationStack {
            ZStack {
                // GitHub-style gray background
                #if os(iOS)
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                #else
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
                #endif
                
                VStack {
                    GeometryReader { geometry in
                        ScrollView {
                            ZStack {
                                // Empty state - properly centered
                                VStack(spacing: 24) {
                                    Image(systemName: "lock.shield.fill")
                                        .font(.system(size: 70))
                                        .fontWeight(.light)
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [.blue, .cyan],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .symbolEffect(.pulse.byLayer, options: .repeating)
                                    VStack(spacing: 8) {
                                        Text("No TOTP accounts")
                                            .font(.title2)
                                            .fontWeight(.semibold)
                                        Text("Add your first account to get started")
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                            }
                        }
                        .refreshable {
                            // Mock refresh action
                        }
                    }
                }
                
                // Floating Action Button (iOS only)
                #if os(iOS)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            self.addingAccount = true
                        }) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .frame(width: 52, height: 52)
                        }
                        .buttonStyle(.plain)
                        .background {
                            Circle()
                                .fill(.background)
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.8),
                                            .white.opacity(0.2)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.5
                                )
                        }
                        .glassEffect(.regular.interactive())
                        .clipShape(Circle())
                        .padding(.trailing, 24)
                        .padding(.bottom, 32)
                    }
                }
                #endif
            }
            .navigationTitle("TOTP Passwords")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
            #endif
        }
    }
}

// Mock view with sample data
@available(iOS 26.0, macOS 26.0, *)
struct ContentViewWithSampleData: View {
    @State private var accounts: [MockOtpModel] = [
        MockOtpModel(id: "1", name: "john.doe@gmail.com", issuer: "Google", currentCode: "123456"),
        MockOtpModel(id: "2", name: "GitHub", issuer: "GitHub", currentCode: "789012"),
        MockOtpModel(id: "3", name: "AWS Console", issuer: "Amazon", currentCode: "345678"),
        MockOtpModel(id: "4", name: "work@company.com", issuer: "Microsoft", currentCode: "901234"),
        MockOtpModel(id: "5", name: "Discord", issuer: "Discord", currentCode: "567890")
    ]
    @State var addingAccount = false
    @State var editingAccount: MockOtpModel?
    @State var deletingAccount: MockOtpModel?
    @State var showCopiedToast = false
    @State var search = ""
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationStack {
            ZStack {
                // GitHub-style gray background
                #if os(iOS)
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                #else
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
                #endif
                
                VStack {
                    GeometryReader { geometry in
                        ScrollView {
                            ZStack {
                                VStack {
                                    let searchField = self.search.trimmingCharacters(
                                        in: .whitespacesAndNewlines)
                                    LazyVGrid(
                                        columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: geometry.size.width > 768 ? 3 : 1),
                                        alignment: .center,
                                        spacing: 12
                                    ) {
                                        ForEach(accounts) { account in
                                            MockTotpView(
                                                otp: account,
                                                cutoff: geometry.size.width,
                                                deleting: $deletingAccount,
                                                editing: $editingAccount,
                                                toast: $showCopiedToast
                                            )
                                        }
                                    }
                                    .padding(.top)
                                    .padding(.horizontal, geometry.size.width > 768 ? 40 : 20)
                                    .frame(minWidth: geometry.size.width, maxWidth: geometry.size.width)

                                    Spacer()
                                        .frame(height: 20)
                                }
                            }
                        }
                        .refreshable {
                            // Mock refresh action
                        }
                        
                        // Toast message overlay
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text("Code copied to clipboard")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background {
                                        Capsule()
                                            .fill(.background.secondary)
                                    }
                                    .clipShape(Capsule())
                                Spacer()
                            }
                            .opacity(self.showCopiedToast ? 0.95 : 0.0)
                            .scaleEffect(self.showCopiedToast ? 1.0 : 0.9)
                            .animation(.smooth(duration: 0.25), value: showCopiedToast)
                            .allowsHitTesting(false)
                            .padding()
                        }
                    }
                }
                
                // Floating Action Button (iOS only)
                #if os(iOS)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            self.addingAccount = true
                        }) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .frame(width: 52, height: 52)
                        }
                        .buttonStyle(.plain)
                        .background {
                            Circle()
                                .fill(.background)
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.8),
                                            .white.opacity(0.2)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.5
                                )
                        }
                        .glassEffect(.regular.interactive())
                        .clipShape(Circle())
                        .padding(.trailing, 24)
                        .padding(.bottom, 32)
                    }
                }
                #endif
            }
            .navigationTitle("TOTP Passwords")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
            #endif
        }
    }
}

// Mock data models for preview
@available(iOS 26.0, macOS 26.0, *)
struct MockOtpModel: Identifiable {
    let id: String
    let name: String
    let issuer: String
    let currentCode: String
}

// Mock TOTP view for preview with Liquid Glass
@available(iOS 26.0, macOS 26.0, *)
struct MockTotpView: View {
    let otp: MockOtpModel
    let cutoff: CGFloat
    @Binding var deleting: MockOtpModel?
    @Binding var editing: MockOtpModel?
    @Binding var toast: Bool
    @State private var offset: CGFloat = 0.0
    @State private var showingActions = false
    
    var body: some View {
        ZStack {
            // Background action buttons with Liquid Glass
            HStack {
                Spacer()
                
                // Edit button
                Button(action: {
                    withAnimation(.smooth(duration: 0.3)) {
                        self.offset = 0
                        self.showingActions = false
                    }
                    // Mock edit action
                }) {
                    Image(systemName: "pencil")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                
                // Delete button
                Button(action: {
                    withAnimation(.smooth(duration: 0.3)) {
                        self.offset = 0
                        self.showingActions = false
                    }
                    // Mock delete action
                }) {
                    Image(systemName: "trash")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(
                            LinearGradient(
                                colors: [.red, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .opacity(showingActions ? 1 : 0)
            .scaleEffect(showingActions ? 1.0 : 0.95)
            .animation(.smooth(duration: 0.2), value: showingActions)
            
            // Main card content with Liquid Glass
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(otp.issuer)
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text(otp.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 12, height: 12)
                }
                
                HStack {
                    Text(otp.currentCode)
                        .font(.system(.title, design: .monospaced))
                        .fontWeight(.bold)
                        .tracking(2)
                        .contentTransition(.numericText())
                    Spacer()
                    ZStack {
                        Circle()
                            .stroke(.quaternary, lineWidth: 3)
                            .frame(width: 28, height: 28)
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .frame(width: 28, height: 28)
                            .rotationEffect(.degrees(-90))
                    }
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .offset(x: self.offset)
            .gesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onChanged { value in
                        // Only allow left swipe (negative translation)
                        if value.translation.width < 0 {
                            self.offset = max(value.translation.width, -130) // Limit to -130 points
                            self.showingActions = self.offset < -60
                        }
                    }
                    .onEnded { value in
                        withAnimation(.smooth(duration: 0.3)) {
                            if value.translation.width < -60 {
                                // Show actions
                                self.offset = -130
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
                    // Mock copy action
                    toast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        toast = false
                    }
                }
            }
        }
        .clipped()
    }
}
