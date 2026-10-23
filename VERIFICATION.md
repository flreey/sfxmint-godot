# Verification — 0.2.2

This record separates automated fixture checks, native platform checks and production verification.

## Tested

- macOS ARM64 with Godot 4.6 and 4.7: 37 focused client checks, native editor import, generation UI against a local fixture service, WAV/OGG preview/import and export isolation.
- Slow HTTP preview downloads, repeated play while loading, switching during an in-flight request, stale response rejection, failure/retry state, visible import stages and restoring older drafts into an editable description.
- Sound, Ambience and BGM fixture flows; versions with deliberately different lengths; favorite persistence; source WAV conversion/upload and preservation of source-specific rights.
- Task/account isolation, ambiguous-submission recovery, polling backoff, quota errors, duplicate import lookup, safe filenames and manifest protection.
- Real SFXMint Sound generation: four returned candidates, decoded native playback and import with a provenance manifest. The account key was supplied through the process environment and was not packaged or saved in the project.
- Credential-helper unit validation and a disposable macOS Keychain save/read/delete round trip. Existing user credentials were not replaced.
- Release ZIPs: clean installation and the demo's local audio remaining playable after the addon is removed. Helper binaries and task/key cache are not game dependencies.

## Platform limits

| Target | Status |
| --- | --- |
| macOS ARM64, Godot 4.7 | Native editor and visual verification |
| macOS ARM64, Godot 4.6 | Native headless editor and package verification |
| macOS x86_64 | Helper cross-compiled; native behavior unverified |
| Windows x86_64 | Helper cross-compiled; native behavior unverified |
| Linux x86_64 / ARM64 | Helpers cross-compiled for glibc 2.28+; native desktop/Secret Service behavior unverified |

Unsupported helper targets use session-only connection. The cross-platform helper build is not evidence of native credential integration on that platform.

Actual microphone capture and OS permission prompts, forced OS credential denial, a complete manual mouse pass and a light-theme pass remain unverified. Ambience/BGM and uploads were tested with local fixtures; the recorded production generation smoke covered Sound.

Technical decoding, player state and import checks do not establish human listening acceptance or semantic sound quality. The example audio is an explicitly labelled procedural tone.

## Reproduce

See the development commands in [README.md](README.md). The tests use a loopback fixture service and do not require a production API key, purchase or generation request.
