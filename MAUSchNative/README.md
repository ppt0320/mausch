# MAU$ch Native shell

This Xcode project is a first native SwiftUI container for the existing MAU$ch web app. It loads the current published app at:

https://ppt0320.github.io/mausch/

## Open
1. Open `MAUSchNative.xcodeproj` in Xcode.
2. Select the MAU$ch target.
3. In Signing & Capabilities, choose your Apple development team.
4. Run on an iPhone simulator or a connected device. The target is configured for Mac Catalyst as well.

## Important data note
This first version embeds the published web app in WKWebView. WKWebView has its own website storage; it does not automatically share Safari/Chrome IndexedDB or iCloud data. The app's Supabase sign-in/sync flow must be completed and tested before treating data as synchronized between devices. Do not clear website data or uninstall the current web app while validating.

## Current scope
- SwiftUI app entry point
- WKWebView wrapper for iOS and Mac Catalyst
- Existing web app remains the source of the current screens and workflows

The web app's file-upload/receipt picker and authentication callback behavior still need device testing in the native container.
