# mz_multichar

`mz_multichar` is the login roster, selection and create-character orchestration resource. Persistent account/character identity, sessions, ownership checks, slots and activation remain owned by `mz_core`; appearance editing remains owned by `mz_creator`.

The client only submits a character ID plus a request correlation ID. The server obtains the account from the current core session, validates ownership and delegates activation through caller-restricted core exports. The UI never proves account ownership, slot entitlement or activation.

Creation reserves a `creating` character in core, opens `mz_creator`, and finalizes/activates only after validated appearance and identity are saved. Cancel archives the pending draft. A creator/resource restart reopens a valid pending creation; an active session never reopens the selector.

Hot switching is deliberately unavailable. `ReturnToCharacterSelection` fails with `hot_switch_not_safe` until all character-scoped runtime cleanup can be proven.

Dependencies: `ox_lib`, `mz_core`, `mz_creator`. Start it after both application resources in the normal resource profile.

## Selection NUI lifecycle

The selector owns only its temporary presentation lifecycle: it waits for the browser-ready callback, obtains the server-owned roster, prepares the configured scene, creates bounded local preview peds, starts its cinematic camera, sends the sanitized `open` message, fades the screen in and requires a `rendered` acknowledgement. Empty rosters render an explicit create-character state.

Preview peds are non-networked client entities. They have no source, session, account or Player State and never become the active player ped. Their appearance comes from the existing server-side `mz_creator` appearance snapshot; the NUI receives only display-safe character fields. `client/preview_peds.lua` owns creation and deletion, `client/camera.lua` owns `CINEMATIC` and `CHARACTER_FOCUS`, and `client/scene.lua` owns bounded loading, fade, focus and the hidden local player used during selection.

Selecting a card only changes the local camera. Entering still submits a character ID plus request correlation ID to the server, where the current account/session, lifecycle and ownership are validated before `ActivateCharacter`. Creating a character closes the NUI and destroys every selector ped/camera before `mz_creator` assumes its independent scene. Canonical spawn remains owned by `mz_core`.

Set `Config.Debug = true` temporarily to record the client/NUI milestones. Ready, render, roster and transition timeouts restore the screen, release NUI focus and remain fail-closed without activating a character. Hot switching remains unavailable.
