# Tiny Heist

A first-person sneaking game made with Godot 4.7. Break into a museum at night, steal at least **$4,000**, and get back to the getaway van without a guard catching you.

## Run

Open the folder in Godot 4.7 and press Play, or run `godot --path .`

## Controls

| Key | Action |
| --- | --- |
| WASD / arrows | Move |
| Shift | Sprint (fast but loud: guards hear it) |
| Ctrl / C | Sneak (slow, silent, harder to spot) |
| Space | Jump |
| E | Grab loot |
| Esc / P | Pause |

## How it plays

- **Guards** patrol set routes with flashlights. When one sees you, their **?** fills up the detection meter. Closer and in the light means faster; sneaking halves it. At 100% they shout **!** and chase you. If one reaches you, you're **BUSTED**.
- **Noise:** sprinting, walking near guards, hard landings, and grabbing loot make guards come to check it out.
- **Laser door:** the vault's beams blink on and off. Touching a live beam sets off the alarm, and every guard heads to where you are.
- **Loot:** gold bars ($500), ruby gems ($1,000), and the Big Diamond ($5,000) inside the vault.
- **Stars:** ★ escape, ★ steal the Big Diamond, ★ never get spotted.

## Code

Everything is built in code from `scripts/`:

- `level.gd`: the ASCII museum map, guard patrol routes, loot values, and grid pathfinding (`AStarGrid2D`)
- `player.gd`: first-person movement, noise, grabbing, and the blocky bobbing arms
- `guard.gd`: vision cone and line of sight, suspicion, patrol/investigate/chase states
- `laser_door.gd`, `loot.gd`: interactables
- `game.gd`: wires one heist together (alarm, win/lose); `hud.gd`: overlay; `main.gd`: menus and pause

To change the museum, edit `Level.MAP` and `Level.PATROLS`.
