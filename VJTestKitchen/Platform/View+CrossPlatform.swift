import SwiftUI
#if os(iOS)
import UIKit
#endif

// Cross-platform wrappers for the SwiftUI modifiers that are iOS-only. Each is a
// no-op (or the nearest macOS equivalent) on macOS, so the ~12 view files that
// use them stay free of `#if os(...)` fences — the platform split lives here.

// MARK: - Navigation

extension View {
    /// `.navigationBarTitleDisplayMode(.inline)` on iOS; no-op on macOS (macOS
    /// nav titles have no display-mode concept).
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

// MARK: - Text input

/// The subset of `UIKeyboardType` the app actually uses, expressed platform-free
/// so call sites compile on macOS (where soft keyboards don't exist).
enum PlatformKeyboardType {
    case numbersAndPunctuation, emailAddress, decimalPad, numberPad

    #if os(iOS)
    var uiKeyboardType: UIKeyboardType {
        switch self {
        case .numbersAndPunctuation: .numbersAndPunctuation
        case .emailAddress: .emailAddress
        case .decimalPad: .decimalPad
        case .numberPad: .numberPad
        }
    }
    #endif
}

/// The subset of `TextInputAutocapitalization` the app uses, platform-free.
enum PlatformTextCase {
    case never, words

    #if os(iOS)
    var textInputAutocapitalization: TextInputAutocapitalization {
        switch self {
        case .never: .never
        case .words: .words
        }
    }
    #endif
}

extension View {
    /// Applies a soft-keyboard type on iOS; no-op on macOS.
    @ViewBuilder
    func platformKeyboardType(_ type: PlatformKeyboardType) -> some View {
        #if os(iOS)
        self.keyboardType(type.uiKeyboardType)
        #else
        self
        #endif
    }

    /// Applies autocapitalization behavior on iOS; no-op on macOS.
    @ViewBuilder
    func platformAutocapitalization(_ mode: PlatformTextCase) -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(mode.textInputAutocapitalization)
        #else
        self
        #endif
    }
}

// MARK: - Presentation

extension View {
    /// `.presentationDetents([.medium, .large])` on iOS; no-op on macOS (sheets
    /// there aren't detent-resizable).
    @ViewBuilder
    func platformMediumLargeDetents() -> some View {
        #if os(iOS)
        self.presentationDetents([.medium, .large])
        #else
        self
        #endif
    }

    /// A full-screen modal on iOS (`.fullScreenCover`), which has no macOS
    /// equivalent, so macOS falls back to a standard `.sheet`.
    @ViewBuilder
    func platformFullScreenCover<Cover: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Cover
    ) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented, content: content)
        #endif
    }
}

// MARK: - Lists

extension View {
    /// `.insetGrouped` on iOS (no such style on macOS), where `.inset` is the
    /// closest native grouped look.
    @ViewBuilder
    func platformInsetGroupedListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.inset)
        #endif
    }
}

// MARK: - Toolbar placements

extension ToolbarItemPlacement {
    /// Primary/trailing action slot: `.topBarTrailing` on iOS, `.primaryAction`
    /// on macOS.
    static var platformPrimaryAction: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }

    /// Leading slot for a Cancel/dismiss control: `.topBarLeading` on iOS,
    /// `.cancellationAction` on macOS (where it takes the standard cancel slot).
    static var platformCancellation: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .cancellationAction
        #endif
    }

    /// Leading slot for a non-cancel control (e.g. an overflow menu):
    /// `.topBarLeading` on iOS, `.automatic` on macOS.
    static var platformLeading: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .automatic
        #endif
    }
}
