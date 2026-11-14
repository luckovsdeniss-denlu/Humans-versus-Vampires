# Humans vs Vampires (Godot 4.3, Android)

8-player map: **6 humans** each build their own base and survive; **2 vampires** hunt them at night.
You play one slot (human or vampire); the other 7 are AI bots.

- **Humans**: walk near trees to gather wood, build walls (4) and turrets (15) around your core. Close yourself in at night — survive 5 nights to win. STAKE next to your own wall removes it (refund 2).
- **Vampires**: only strong at night (sun burns outside the central crypt). Bite humans, smash walls. Win by eliminating all humans.
- Controls: touch joystick + buttons. Desktop: WASD, Space (stake/bite), Q/1 wall, E/2 turret.

## Build the APK
Push to GitHub: the `Build Android APK` workflow produces `humans-vs-vampires.apk` as an artifact.
Locally: install Godot 4.3 + export templates + Android SDK, then
`godot --headless --export-debug Android build/humans-vs-vampires.apk`.
