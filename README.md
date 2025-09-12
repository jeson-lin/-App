# my_app (Minimal Flutter Project for Codemagic)

This repo intentionally omits platform folders. Codemagic will auto-create `android/`
via `flutter create . --platforms=android` before building.

## How to use
1. Upload this to a new GitHub repository.
2. Connect the repo in Codemagic.
3. Select the `Build Android Debug (auto-create platforms)` workflow.
4. Start build.
5. Download `app-debug.apk` from Artifacts and install it on your phone.

You can edit `lib/main.dart` directly on GitHub and trigger a new build.