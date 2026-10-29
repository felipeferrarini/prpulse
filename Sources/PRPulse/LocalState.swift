import SwiftUI

/// `@State` is a macro in the current SDK and its plugin ships only with Xcode.
/// This alias resolves to the plain property wrapper so the app builds with the Command Line Tools.
typealias LocalState<Value> = SwiftUI.State<Value>
