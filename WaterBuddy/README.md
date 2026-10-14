# WaterBuddy 💧

A little desktop buddy for macOS that reminds you to drink water.

- Every **2 hours** he walks in from the right edge of the screen (bottom-right corner) and waves with a speech bubble.
- **I drank 💧** → he jumps for joy, then walks off to the right. Next reminder in 2 hours.
- **Snooze** → he looks sad, then walks off to the right. He comes back after the snooze time (15 min by default).
- A 💧 in the menu bar shows the time until the next reminder and how many glasses you've had today, and has settings for the interval, snooze length, sound, pause, and open-at-login.

## Build & run (on your Mac)

Needs macOS 13+ and the Xcode Command Line Tools (`xcode-select --install`).

```bash
./build.sh
open build/WaterBuddy.app
```

On first launch he shows up once so you can see him. To keep it running after a restart, copy the app to `/Applications`, open it from there, and turn on **💧 → Open at Login**.

You can drag him around while he's on screen. He goes back to the corner the next time he shows up.

## Sprites

`source-sprites/` holds the original sheets. `tools/slice_sprites.py` cuts them into the frames in `Resources/sprites/` (already done; re-run only if you change the sheets):

```bash
pip install pillow numpy scipy
python3 tools/slice_sprites.py
```
