SomaFM Mini Player for Apple Silicon
====================================

Project purpose
---------------

This repository tracks work to update the original SomaFM mini player so it can run on modern Apple silicon based Mac computers.

Upstream project:
https://github.com/ealeksandrov/SomaFM-miniplayer

Working project:
https://github.com/matthewbohl/SomaFM-miniplayer-apple-silicon

Current local state
-------------------

This workspace started as a fresh git repository on branch `main`. The upstream SomaFM miniplayer source has been imported, and the `origin` remote is configured for the working GitHub repository.

Development loop
----------------

Each task should begin by checking repository status, then loading local project context from this file, AGENTS.md, and the relevant source/build/test files.

After context is loaded:

1. Review the request.
2. Propose a primary solution.
3. Propose an alternative solution.
4. Implement only after the proposal is accepted, unless the user explicitly asks to proceed immediately.
5. Update documentation.
6. Add or update tests when behavior changes.
7. Verify with the relevant build, test, or manual check.
8. Commit and push, keeping no more than five committed-but-unpushed changes outstanding.

Command line options
--------------------

The application is a macOS menu-bar app and does not currently expose application command line options.

Keep this section updated if command line flags, helper commands, packaging commands, or launch arguments are added.

Known commands
--------------

Repository status:

    git status --short --branch

List project files:

    rg --files

Show configured remotes:

    git remote -v

Build the app for Apple silicon without code signing:

    xcodebuild -project SomaFM.xcodeproj -scheme SomaFM -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build

Run the build smoke test:

    Scripts/verify-arm64-debug-build.sh

Configure local signing:

    cp Config/Signing.local.example.xcconfig Config/Signing.local.xcconfig

Then edit `Config/Signing.local.xcconfig` with your Apple Developer team ID and bundle IDs. The local signing file is ignored by git and must not be committed.

Build with local signing enabled:

    xcodebuild -project SomaFM.xcodeproj -scheme SomaFM -configuration Debug -destination 'platform=macOS,arch=arm64' build

Open the project in Xcode:

    open SomaFM.xcodeproj

Modernization notes
-------------------

Apple silicon modernization should prioritize:

- native arm64 builds where possible
- universal binaries when compatibility requires both x86_64 and arm64
- current macOS signing and packaging expectations
- dependency updates with minimal behavior changes
- preserving the original mini player experience

Current modernization baseline:

- Xcode 27 beta is the active local toolchain.
- The macOS deployment target is now 12.0 because Xcode 27 rejects 10.12.
- Swift project settings are updated from Swift 4 to Swift 5.
- Carthage dependencies were removed from the build.
- Reachability.swift was replaced with Network.framework path monitoring.
- MediaKeyTap was removed from the build for now, so global media key support is temporarily disabled.
- A no-sign arm64 Debug build succeeds.
- Signing settings are routed through `Config/Signing.xcconfig`; personal values belong only in ignored `Config/Signing.local.xcconfig`.
- Remaining known warnings include deprecated NSUserNotification usage, AVPlayerItem timedMetadata usage, and the legacy launch-at-login query path.

Open setup items
----------------

- Replace NSUserNotification with UserNotifications.
- Replace timedMetadata polling with AVPlayerItemMetadataOutput.
- Revisit launch-at-login implementation for modern ServiceManagement APIs.
- Decide whether to restore media key support with maintained source, a local compatibility layer, or a documented non-goal.
- Add XCTest coverage around model decoding, settings, URL construction, and channel sorting.
- Add packaging documentation.
