# Tiny Heist

A first-person sneaking game made with Godot 4.7. Break into a museum at night, steal at least **$6,000**, and get back to the getaway van without a guard catching you.

## Run

Open the folder in Godot 4.7 and press Play, or run `godot --path .`

## Controls

| Key | Action |
| --- | --- |
| WASD / arrows | Move |
| Shift | Sprint (fast but loud: guards hear it) |
| Ctrl / C | Sneak (slow, silent, harder to spot) |
| Space | Jump |
| E | Use: grab loot, take keycard, open vault, hide in locker. Hold E on the security panel |
| Q / right-click | Throw a coin to distract guards (you get 5) |
| Esc / P | Pause |

Settings (title or pause menu): **mouse sensitivity**, **field of view**, **camera bob**, and **invert Y**. They save automatically.

## How it plays

- **Guards** (9 of them) patrol with flashlights and scan around with their heads. A **?** means they're getting suspicious; **!** means they're chasing you. Get caught and you're **BUSTED**.
- **Noise:** sprinting, hard landings, and grabbing loot draw guards over. Throw a **coin** to make them look somewhere else.
- **Security cameras** sweep the rooms. Stay in their light too long and the alarm goes off.
- **Laser doors** blink on and off. Time your run, or touch a beam and set off the alarm.
- **Security office:** grab the **keycard** from the desk and hold E on the **security panel** to shut down every camera and laser.
- **The vault** holds the Big Diamond ($5,000). Get in through the keycard door, or dash through the laser door on the east side.
- **Lockers:** hide inside so guards and cameras can't see you. If a guard watches you climb in, they'll drag you out.
- **Loot:** gold bars $500, vases $750, rubies $1,000, famous paintings $1,500, the Big Diamond $5,000.
- **Stars:** ★ escape, ★ steal the Big Diamond, ★ never get spotted. Your best haul is saved.

## Code

Everything is built in code from `scripts/`:

- `level.gd`: the ASCII museum map (legend at the top), patrol routes, loot values, decor, and grid pathfinding (`AStarGrid2D`)
- `player.gd`: movement, noise, interaction (instant and hold), coin throwing, lockers, and the animated arms and camera
- `guard.gd`: vision and line of sight, suspicion, patrol/investigate/chase states, and body animation
- `interactable.gd`: base class for anything you press E on (`loot.gd`, `keycard.gd`, `security_panel.gd`, `locker.gd`, `vault_door.gd`)
- `security_camera.gd`, `laser_door.gd`, `coin.gd`: security and distractions
- `game.gd`: wires one heist together (alarm, objectives, win/lose); `hud.gd`: overlay; `main.gd`: menus; `settings.gd`: saved preferences (autoload)

To change the museum, edit `Level.MAP` and `Level.PATROLS`.
