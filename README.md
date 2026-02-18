# 🚀 Space Shooter - FPS Mod for Luanti

A wave-based first-person space shooter mod for [Luanti](https://www.luanti.org/) (formerly Minetest). Fight off alien invaders in a space station arena!

## Features

- **3 Weapons**: Laser Gun (rapid fire), Plasma Rifle (high damage), Rocket Launcher (splash damage)
- **3 Enemy Types**: Alien Grunts, Elite Aliens, and Boss Aliens
- **Wave System**: Endless waves of increasing difficulty with boss waves every 5th round
- **Combo System**: Chain kills for score multipliers (up to 5x)
- **Pickups**: Health packs, ammo crates, and shield pickups dropped by enemies
- **Custom HUD**: Score, wave counter, ammo display, shield indicator, combo tracker
- **Auto-generated Arena**: Space station arena with pillars for cover, glass windows, and spawn pads
- **Particle Effects**: Muzzle flashes, projectile trails, explosions, and ambient space particles

## How to Play

1. Install the mod in your Luanti `mods/` folder
2. Enable the mod in your world settings
3. Join the game and type `/space_shooter` to start
4. Use **left-click** to fire your equipped weapon
5. Switch weapons with **hotbar keys (1-3)**:
   - Slot 1: Laser Gun — fast, low damage, generous ammo
   - Slot 2: Plasma Rifle — medium speed, high damage
   - Slot 3: Rocket Launcher — slow, massive splash damage
6. Survive as many waves as you can!
7. Type `/space_quit` to end your game

## Commands

| Command | Description |
|---|---|
| `/space_shooter` | Start a new game |
| `/space_quit` | End current game |

## Wave Progression

- Base aliens increase by 2 per wave
- Elite aliens appear from Wave 3+
- Boss aliens appear every 5th wave
- Ammo is replenished between waves
- Player heals 5 HP between waves

## Installation

```
cd ~/.luanti/mods/
# Copy or clone the space_shooter folder here
```

Make sure the mod is enabled in your world's mod settings.

## No Dependencies

This mod has **no dependencies** — it works standalone with any Luanti game or even with no game at all.

## License

Code: MIT  
Textures: CC0 (Public Domain)
