# SFXMint for Godot 0.2.3

Search, audition, generate and import Sound, Ambience and BGM from a native Godot bottom dock. Requires Godot 4.6 or later.

## Start

1. Enable **Project → Project Settings → Plugins → SFXMint**.
2. Open the **SFXMint** bottom dock and enlarge it by dragging its upper edge.
3. In **Library**, search and import sounds without an account.
4. For generation, use **Connect account** with your own SFXMint API key. Each generation uses your account's displayed allowance or paid credits/plan.

The description is directly editable. Select a candidate/version, listen, then import. Preview and import downloads display their state. Imported audio remains playable offline when this plugin is removed.

The hosted API is `https://sfxmint.com`; users do not deploy a backend. Release ZIPs contain no precompiled programs and use session-only account connections. **Remember on this device** is disabled unless you separately build a credential helper from source into `bin/`. Keys are never stored in project files.

## Documentation and support

- [Full guide and source](https://github.com/flreey/sfxmint-godot)
- [Verification and supported platforms](https://github.com/flreey/sfxmint-godot/blob/main/VERIFICATION.md)
- [Downloads](https://github.com/flreey/sfxmint-godot/releases)
- [Report an issue](https://github.com/flreey/sfxmint-godot/issues)
- [Create an API key](https://sfxmint.com/dashboard/keys)
- [Generation pricing](https://sfxmint.com/pricing)

Plugin code is MIT; see `LICENSE.txt` and `THIRD_PARTY_NOTICES.txt`. AI coding tools assisted plugin development. Original SFXMint audio is AI-generated/CC0; uploaded-source derivatives retain source-specific rights. Check each imported file's manifest. The example tone is procedural audio.

Native behavior is verified on macOS ARM64 with Godot 4.6/4.7. Native OS behavior on other desktop targets remains unverified. Microphone permission/capture behavior is not included in the verified feature set.
