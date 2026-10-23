# Changelog

## 0.2.2 — 2026-10-23

First public release.

- Native Library, Studio and In project workspace for Godot 4.6+.
- Anonymous library search, audition and safe local audio import.
- Optional account connection for Sound, Ambience and BGM generation.
- Candidate comparison, supported versions/formats, stars and source selection.
- OS credential helpers, session fallback, task recovery and per-file provenance.
- Descriptions remain directly editable, including drafts saved by earlier versions.
- Switching previews clears old audio. Repeated clicks and late responses cannot play a previous selection while the new audio is loading.
- Preview and import actions show preparation/download/import states.
- Plugin ZIP installs only under `addons/sfxmint/`, with documentation and license notices included.

### Verification limits

Godot 4.6/4.7 editor and package checks ran on macOS ARM64. Other desktop helpers are cross-compiled, not natively verified. Real microphone capture and a complete light-theme/manual interaction pass remain unverified.
