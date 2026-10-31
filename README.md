# SFXMint for Godot

Search, audition, generate and import audio without leaving the Godot editor. A native bottom dock for **sound effects, ambience and background music**.

**Godot 4.6+ · MIT plugin · Free library access · Optional SFXMint account for generation**

![SFXMint Studio in the Godot editor](https://raw.githubusercontent.com/sfxmint/sfxmint-godot/main/docs/media/studio.png)

## Install

1. Download **sfxmint-godot-0.2.3-plugin.zip** from [Releases](https://github.com/sfxmint/sfxmint-godot/releases/latest).
2. Extract it into your Godot project so `addons/sfxmint/plugin.cfg` exists. You can also import the ZIP using Godot's asset installation UI.
3. Enable **Project → Project Settings → Plugins → SFXMint**.
4. Open the **SFXMint** bottom dock and drag its upper edge to give it enough space.

The plugin ZIP installs only `addons/sfxmint/`. The optional **example ZIP** is a separate runnable coin-pickup demo. Neither ZIP contains an API key.

## Find an existing sound

Open **Library**, describe a sound, then search. Category and maximum duration filter results. Choose a result, listen, and click **Import WAV**. Library search, previews and downloads work without a key.

Audio is imported into `res://audio/sfxmint/` by default. Use the folder button to choose another project folder. Existing unchanged imports can be found with **Show in FileSystem**. Imports do not overwrite other files.

## Generate audio

Open **Studio**, click **Connect account**, and enter your own [SFXMint API key](https://sfxmint.com/dashboard/keys). You do not need to run a server. This plugin connects to the hosted SFXMint service at `https://sfxmint.com`.

- **Sound:** short effects, Auto or a supported length up to 10 seconds, with 1/2/4 candidates and optional AI Enhance.
- **Ambience:** a 30-second base with optional detail labels. Longer detail versions and loops appear only when the service returns them.
- **BGM:** a 30-second original with music metadata and a prepared loop when available.

The description is directly editable. Click **Generate** (or Command/Ctrl+Enter) to submit. Each new request uses the allowance shown by your account; paid generation may require a SFXMint plan or credits. The plugin itself is free. See [current SFXMint pricing](https://sfxmint.com/pricing).

Compare the returned candidates with one preview player, star favorites, choose an available version/format, and import the selected audio. Loading previews display their state and cannot replay the previous selection. Importing shows preparing, downloading and importing states. Downloading a locked candidate requires a separate unlock confirmation.

**Start from** can use a library recipe, an owned take or a WAV source. Uploaded/recorded sources require confirmation that you have the rights to use them. Microphone capture requires Godot audio input and OS permission; see the verification limits below.

## Accounts and privacy

Release ZIPs contain no precompiled programs. Account connections last for the current editor session; **Remember on this device** is disabled when no locally built credential helper is installed. Keys are never placed in project files. You can also supply `SFXMINT_API_KEY` through the Godot process environment.

Developers can optionally build a credential helper from the included Rust source for macOS Keychain, Windows Credential Manager or Linux Secret Service. Helpers run only inside the editor, use standard input/output, and have no network behavior. Their Rust source and locked dependencies are in `credential-helper/`. Unsupported platforms or unavailable credential stores fall back to a session-only connection. Helpers are excluded from game exports.

Search descriptions are sent to SFXMint for matching. Generation descriptions and explicitly uploaded/recorded source audio are sent to SFXMint when you request those actions. API keys are sent only to the SFXMint API, never to audio download hosts. Signed audio links are refreshed before download and redirects are refused. SFXMint identifies plugin requests through its client attribution. [SFXMint privacy policy](https://sfxmint.com/privacy).

**Disconnect** clears the in-memory connection; **Remove saved key** removes the system credential. Known task IDs and drafts are cached outside the project, isolated by project, service and account. No key is stored in that cache. Ambiguous generation submissions are not retried automatically: use **Check recent account orders** to recover a request.

## Use imported audio in a game

Each import folder contains the audio plus `sounds.json` and a managed section of `SOUNDS.md`. The manifest records the selected format/version, measured duration, SHA-256 and license/source information.

Use the imported file as an `AudioStreamPlayer`, `AudioStreamPlayer2D` or `AudioStreamPlayer3D` resource. The game plays local audio and does not require this plugin, an account or an internet connection. Removing the plugin leaves imported audio intact.

Coding assistants can read `sounds.json` to connect a selected resource to an existing game event. The plugin does not automatically modify your scenes or start a local MCP server.

## Licenses and AI disclosure

The plugin and credential-helper source are **MIT**. Third-party notices are included. Original SFXMint catalog/generated audio is AI-generated and provided as **CC0 1.0**. Audio derived from user-supplied material retains source-specific rights; do not treat those files as blanket CC0. The manifest records the applicable designation.

AI coding tools assisted development of the plugin and documentation. Screenshots show the running Godot plugin. The example contains a procedural test tone, not a generated catalog sound. Always audition audio for suitability in your game.

## Compatibility and verification

Godot **4.6 and 4.7** are tested on **macOS ARM64**, including native editor import, preview state, ZIP installation and offline demo playback. A real SFXMint Sound generation/download/import has also been verified.

Release ZIPs use session-only connections on all platforms. Optional helper source supports macOS ARM64/x64, Windows x64 and Linux ARM64/x64; Linux requires a working Secret Service. Native UI and credential integration on Intel macOS, Windows and Linux have not yet been verified.

Microphone capture/OS permission behavior and a complete light-theme/manual interaction pass remain unverified. See [VERIFICATION.md](VERIFICATION.md) for tested behavior and limits.

## Example

Extract **sfxmint-godot-0.2.3-example.zip**, open its `project.godot`, and run `example/demo.tscn`. Press **Pick up coin** or Space. A counter increases and the included local tone plays. You can import another sound and run the same scene with it. The example keeps working after removal of the addon.

## Develop

Clone this repository. Godot does not need Rust to use the release ZIP. Building credential helpers from source requires Rust and the appropriate target toolchain:

```sh
python3 scripts/build_helpers.py aarch64-apple-darwin
# Cross compilation, where supported:
# python3 scripts/build_helpers.py x86_64-unknown-linux-gnu --zig
```

Run the local fixture server (Node.js and Wrangler required):

```sh
npx wrangler dev --config tests/wrangler.jsonc --local
```

Then, from another terminal, run tests with the path to an installed Godot executable:

```sh
python3 scripts/test_client.py --godot "$GODOT"
python3 scripts/test_editor.py --godot "$GODOT"
cargo test --manifest-path credential-helper/Cargo.toml
```

The fixture server is loopback-only, uses synthetic keys and never calls production generation. Native editor tests support both session-only installs and optional locally built helpers. Packaging never includes helpers and does not require Rust or a helper build:

```sh
python3 scripts/package.py
python3 scripts/test_package.py --godot "$GODOT"
python3 scripts/test_editor.py --godot "$GODOT" --archive dist/sfxmint-godot-0.2.3-plugin.zip
```

The example source keeps its fixture under `example/audio/`; packaging installs it at `audio/sfxmint/`. Use the example ZIP for the ready-to-run project. Report problems through [GitHub Issues](https://github.com/sfxmint/sfxmint-godot/issues), with your Godot version and operating system. Never include an API key or signed download URL in a report.
