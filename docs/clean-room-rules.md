# Clean-room Rules

VolDeck is a new project. Background Music and other audio apps can be used as
behavior references, but VolDeck must not become a code, asset, or architecture
copy of them.

## Allowed

- Study public product behavior, menus, settings, and user expectations.
- Study public documentation, public API documentation, and high-level diagrams.
- Write our own notes about what users expect from per-app volume tools.
- Use permissively licensed references only after reviewing their license.
- Use Apple documentation and Apple platform APIs directly.
- Compare feature sets at a product level.

## Prohibited

- Do not copy source code from Background Music or other GPL projects into VolDeck.
- Do not copy icons, images, app names, UI assets, bundle identifiers, or copywriting.
- Do not port GPL implementation details line-by-line or module-by-module.
- Do not reuse build scripts or installer scripts from GPL projects.
- Do not paste third-party code from issues, forums, blogs, or screenshots without an explicit compatible license.
- Do not design VolDeck around a virtual input device just because Background Music does.

## Background Music Boundary

Background Music can teach us what users expect:

- per-app volume sliders
- per-app mute
- boosted volume
- menu bar control
- output switching
- auto-pause music behavior
- install and uninstall expectations

Background Music must not define VolDeck's implementation. VolDeck's core goal
is different: per-app volume without microphone permission, without a virtual
input device, and without visible privacy indicators for the core mixer path.

## Contributor Checklist

Before merging any external-reference-inspired work:

- [ ] The code was written from VolDeck's own design or compatible official documentation.
- [ ] No GPL code, assets, scripts, or copied implementation structure were used.
- [ ] Any third-party library has an approved license and is recorded in the dependency notes.
- [ ] The change does not introduce a virtual input device into the core path.
- [ ] The change does not add microphone or system audio capture permissions without an ADR.
- [ ] The PR description names any external behavior references used.

## Review Rule

If a reviewer cannot tell whether a change is clean-room, pause the change and
write an ADR or research note before continuing.
