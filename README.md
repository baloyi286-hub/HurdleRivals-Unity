# Hurdle Rivals (Godot 4)

Two-player 3D split-screen hurdles racing prototype for Android TV.

## Gameplay
- Two independent 3D views, side by side
- Automatic forward running, steering, jump, push and obstacle stuns
- First racer across the finish wins; press Enter to restart
- Keyboard: Player 1 A/D steer, W jump, S push; Player 2 arrow keys
- Experimental phone controller: open the LAN address displayed on TV, select player and tap controls

## Android TV APK via GitHub Actions
Open **Actions → Godot Android TV APK → Run workflow**, then download the APK artifact.
The build uses Godot 4.4.1, Android SDK, and an automatically generated debug signing key.
No Unity installation or Unity licensing secrets are required.

**Note:** This is an initial playable prototype, not the final polished game. The phone controller currently uses HTTP requests, not WebSockets; QR code pairing, character animation, collision/physics polish and Android TV testing are still pending.

## Desktop development
Install Godot 4.4.1 (standard edition), import project.godot and run the main scene.
