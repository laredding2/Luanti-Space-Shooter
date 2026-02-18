-- ============================================================================
-- SPACE SHOOTER - FPS Space Shooter Mod for Luanti
-- ============================================================================
-- A wave-based first-person space shooter with laser weapons, alien enemies,
-- pickups, HUD, scoring, and a space arena environment.
-- ============================================================================

local modname = core.get_current_modname()
local modpath = core.get_modpath(modname)

-- ============================================================================
-- PLAYER STATE
-- ============================================================================
local player_state = {}

local function init_player_state(player_name)
    player_state[player_name] = {
        score = 0,
        wave = 0,
        kills = 0,
        ammo_laser = 100,
        ammo_plasma = 30,
        ammo_rocket = 10,
        ammo_railgun = 0,
        railgun_unlocked = false,
        shield = 0,
        in_game = false,
        wave_active = false,
        enemies_alive = 0,
        enemies_to_spawn = 0,
        spawn_timer = 0,
        hud_ids = {},
        combo = 0,
        combo_timer = 0,
        arena_center = nil,
    }
end

-- ============================================================================
-- NODES
-- ============================================================================

-- Space background block (dark, non-walkable)
core.register_node("space_shooter:space", {
    description = "Deep Space",
    tiles = {"space_shooter_space.png"},
    drawtype = "normal",
    paramtype = "light",
    light_source = 0,
    walkable = false,
    pointable = false,
    diggable = false,
    buildable_to = true,
    groups = {not_in_creative_inventory = 1},
})

-- Arena floor
core.register_node("space_shooter:floor", {
    description = "Station Floor",
    tiles = {"space_shooter_floor.png"},
    groups = {cracky = 1, not_in_creative_inventory = 1},
    sounds = {
        footstep = {name = "default_metal_footstep", gain = 0.4},
    },
})

-- Arena wall
core.register_node("space_shooter:wall", {
    description = "Station Wall",
    tiles = {"space_shooter_wall.png"},
    groups = {cracky = 1, not_in_creative_inventory = 1},
})

-- Glass
core.register_node("space_shooter:glass", {
    description = "Station Glass",
    tiles = {"space_shooter_glass.png"},
    drawtype = "glasslike",
    paramtype = "light",
    sunlight_propagates = true,
    use_texture_alpha = "blend",
    groups = {cracky = 1, not_in_creative_inventory = 1},
})

-- Arena barrier (invisible boundary)
core.register_node("space_shooter:barrier", {
    description = "Arena Barrier",
    tiles = {"space_shooter_barrier.png"},
    drawtype = "glasslike",
    paramtype = "light",
    use_texture_alpha = "blend",
    walkable = true,
    pointable = false,
    diggable = false,
    groups = {not_in_creative_inventory = 1},
})

-- Spawn pad
core.register_node("space_shooter:spawn_pad", {
    description = "Alien Spawn Pad",
    tiles = {"space_shooter_spawn_pad.png"},
    light_source = 8,
    groups = {cracky = 1, not_in_creative_inventory = 1},
})

-- ============================================================================
-- PROJECTILE ENTITIES
-- ============================================================================

-- Generic projectile logic
local function register_projectile(name, def)
    core.register_entity("space_shooter:" .. name, {
        initial_properties = {
            physical = false,
            collide_with_objects = false,
            collisionbox = {-0.1, -0.1, -0.1, 0.1, 0.1, 0.1},
            visual = "sprite",
            visual_size = def.size or {x = 0.3, y = 0.3},
            textures = {def.texture},
            glow = def.glow or 14,
            static_save = false,
            pointable = false,
        },
        _damage = def.damage or 2,
        _owner = "",
        _lifetime = 0,
        _max_life = def.max_life or 4,
        _is_enemy = def.is_enemy or false,
        _splash = def.splash or 0,
        _trail = def.trail or nil,

        on_activate = function(self, staticdata, dtime_s)
            -- Remove after timeout
        end,

        on_step = function(self, dtime)
            self._lifetime = self._lifetime + dtime
            if self._lifetime > self._max_life then
                self.object:remove()
                return
            end

            local pos = self.object:get_pos()
            if not pos then return end

            -- Particle trail
            if self._trail then
                core.add_particle({
                    pos = pos,
                    velocity = {x = 0, y = 0, z = 0},
                    acceleration = {x = 0, y = 0, z = 0},
                    expirationtime = 0.3,
                    size = 2,
                    texture = self._trail,
                    glow = 14,
                })
            end

            -- Raycast for collision
            local vel = self.object:get_velocity()
            if not vel then return end
            local speed = vector.length(vel)
            local dir = vector.normalize(vel)
            local ray_end = vector.add(pos, vector.multiply(dir, math.max(speed * dtime, 0.5)))

            local ray = core.raycast(pos, ray_end, true, false)
            for hit in ray do
                if hit.type == "object" then
                    local obj = hit.ref
                    if obj and obj ~= self.object then
                        local lua = obj:get_luaentity()
                        -- Player projectiles hit enemies, enemy projectiles hit players
                        if self._is_enemy then
                            if obj:is_player() then
                                local pname = obj:get_player_name()
                                local state = player_state[pname]
                                if state and state.in_game then
                                    local dmg = self._damage
                                    if state.shield > 0 then
                                        local absorbed = math.min(state.shield, dmg)
                                        state.shield = state.shield - absorbed
                                        dmg = dmg - absorbed
                                    end
                                    if dmg > 0 then
                                        obj:set_hp(obj:get_hp() - dmg, {type = "punch"})
                                    end
                                    self:_do_hit_effect(pos)
                                    self.object:remove()
                                    return
                                end
                            end
                        else
                            if lua and (lua.name == "space_shooter:alien"
                                    or lua.name == "space_shooter:alien_elite"
                                    or lua.name == "space_shooter:alien_boss") then
                                -- Damage the alien
                                lua._hp = lua._hp - self._damage

                                -- Splash damage
                                if self._splash > 0 then
                                    self:_do_explosion(pos)
                                end

                                if lua._hp <= 0 then
                                    lua:_die(self._owner)
                                else
                                    -- Hit flash
                                    obj:set_properties({
                                        damage_texture_modifier = "^[brighten"
                                    })
                                end

                                self:_do_hit_effect(pos)
                                self.object:remove()
                                return
                            end
                        end
                    end
                elseif hit.type == "node" then
                    local node = core.get_node(hit.under)
                    if node.name ~= "air" and node.name ~= "space_shooter:space"
                       and node.name ~= "space_shooter:barrier" then
                        if self._splash > 0 then
                            self:_do_explosion(pos)
                        end
                        self:_do_hit_effect(pos)
                        self.object:remove()
                        return
                    end
                end
            end
        end,

        _do_hit_effect = function(self, pos)
            core.add_particlespawner({
                amount = 8,
                time = 0.1,
                pos = pos,
                radius = 0.3,
                velocity = {min = {x = -2, y = -2, z = -2}, max = {x = 2, y = 2, z = 2}},
                acceleration = {x = 0, y = 0, z = 0},
                exptime = {min = 0.2, max = 0.5},
                size = {min = 1, max = 3},
                texture = "space_shooter_explosion.png",
                glow = 14,
            })
        end,

        _do_explosion = function(self, pos)
            core.add_particlespawner({
                amount = 25,
                time = 0.2,
                pos = pos,
                radius = 1,
                velocity = {min = {x = -4, y = -4, z = -4}, max = {x = 4, y = 4, z = 4}},
                exptime = {min = 0.3, max = 0.8},
                size = {min = 2, max = 5},
                texture = "space_shooter_explosion.png",
                glow = 14,
            })
            -- Splash damage to nearby aliens
            local objs = core.get_objects_inside_radius(pos, self._splash)
            for _, obj in ipairs(objs) do
                if obj ~= self.object then
                    local lua = obj:get_luaentity()
                    if lua and (lua.name == "space_shooter:alien"
                            or lua.name == "space_shooter:alien_elite"
                            or lua.name == "space_shooter:alien_boss") then
                        lua._hp = lua._hp - math.floor(self._damage * 0.5)
                        if lua._hp <= 0 then
                            lua:_die(self._owner)
                        end
                    end
                end
            end
        end,
    })
end

register_projectile("laser_bolt", {
    texture = "space_shooter_laser_bolt.png",
    damage = 3,
    size = {x = 0.3, y = 0.3},
    glow = 14,
    trail = "space_shooter_muzzle.png",
})

register_projectile("plasma_bolt", {
    texture = "space_shooter_plasma_bolt.png",
    damage = 8,
    size = {x = 0.4, y = 0.4},
    glow = 14,
    trail = "space_shooter_plasma_bolt.png",
})

register_projectile("rocket", {
    texture = "space_shooter_rocket.png",
    damage = 20,
    size = {x = 0.5, y = 0.3},
    glow = 14,
    splash = 3,
    trail = "space_shooter_explosion.png",
    max_life = 6,
})

register_projectile("alien_bolt", {
    texture = "space_shooter_alien_bolt.png",
    damage = 2,
    size = {x = 0.3, y = 0.3},
    glow = 14,
    is_enemy = true,
})

-- ============================================================================
-- WEAPONS (Tools)
-- ============================================================================

local function shoot_projectile(player, proj_name, speed, spread)
    local pos = player:get_pos()
    pos.y = pos.y + 1.625  -- eye height
    local dir = player:get_look_dir()

    -- Add spread
    if spread and spread > 0 then
        dir.x = dir.x + (math.random() - 0.5) * spread
        dir.y = dir.y + (math.random() - 0.5) * spread
        dir.z = dir.z + (math.random() - 0.5) * spread
        dir = vector.normalize(dir)
    end

    local spawn_pos = vector.add(pos, vector.multiply(dir, 1.5))
    local obj = core.add_entity(spawn_pos, "space_shooter:" .. proj_name)
    if obj then
        obj:set_velocity(vector.multiply(dir, speed))
        local lua = obj:get_luaentity()
        if lua then
            lua._owner = player:get_player_name()
        end
    end

    -- Muzzle flash
    core.add_particle({
        pos = vector.add(pos, vector.multiply(dir, 1.2)),
        velocity = vector.multiply(dir, 2),
        expirationtime = 0.1,
        size = 4,
        texture = "space_shooter_muzzle.png",
        glow = 14,
        playername = player:get_player_name(),
    })
end

core.register_tool("space_shooter:laser_gun", {
    description = "Laser Gun\nFast fire rate, low damage\nLeft-click to shoot",
    inventory_image = "space_shooter_laser_gun.png",
    range = 0,
    groups = {not_in_creative_inventory = 1},
    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        local state = player_state[name]
        if not state or not state.in_game then return end

        if state.ammo_laser <= 0 then
            core.chat_send_player(name, core.colorize("#ff5555", "Out of laser ammo!"))
            return
        end

        state.ammo_laser = state.ammo_laser - 1
        shoot_projectile(user, "laser_bolt", 30, 0.02)
        return itemstack
    end,
})

core.register_tool("space_shooter:plasma_rifle", {
    description = "Plasma Rifle\nMedium fire rate, high damage\nLeft-click to shoot",
    inventory_image = "space_shooter_plasma_rifle.png",
    range = 0,
    groups = {not_in_creative_inventory = 1},
    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        local state = player_state[name]
        if not state or not state.in_game then return end

        if state.ammo_plasma <= 0 then
            core.chat_send_player(name, core.colorize("#5555ff", "Out of plasma ammo!"))
            return
        end

        state.ammo_plasma = state.ammo_plasma - 1
        shoot_projectile(user, "plasma_bolt", 25, 0.03)
        return itemstack
    end,
})

core.register_tool("space_shooter:rocket_launcher", {
    description = "Rocket Launcher\nSlow fire, massive splash damage\nLeft-click to shoot",
    inventory_image = "space_shooter_rocket_launcher.png",
    range = 0,
    groups = {not_in_creative_inventory = 1},
    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        local state = player_state[name]
        if not state or not state.in_game then return end

        if state.ammo_rocket <= 0 then
            core.chat_send_player(name, core.colorize("#ffaa00", "Out of rockets!"))
            return
        end

        state.ammo_rocket = state.ammo_rocket - 1
        shoot_projectile(user, "rocket", 18, 0.01)
        return itemstack
    end,
})

-- Railgun: fires a penetrating beam that one-shots every enemy it touches
local function fire_railgun(player)
    local name = player:get_player_name()
    local pos = player:get_pos()
    pos.y = pos.y + 1.625  -- eye height
    local dir = player:get_look_dir()

    -- The beam extends very far (100 nodes)
    local beam_end = vector.add(pos, vector.multiply(dir, 100))
    local beam_start = vector.add(pos, vector.multiply(dir, 1.5))

    -- Visual beam: spawn particles along the ray path
    local beam_length = 100
    local step = 1.5
    for dist = 0, beam_length, step do
        local p = vector.add(beam_start, vector.multiply(dir, dist))
        -- Check if we hit a solid node (stop the beam visuals there)
        local node = core.get_node(vector.round(p))
        if node.name ~= "air" and node.name ~= "space_shooter:space"
           and node.name ~= "space_shooter:barrier"
           and node.name ~= "space_shooter:glass"
           and node.name ~= "ignore" then
            beam_end = p
            break
        end
        core.add_particle({
            pos = p,
            velocity = {x = 0, y = 0, z = 0},
            expirationtime = 0.4,
            size = 3,
            texture = "space_shooter_railgun_beam.png",
            glow = 14,
        })
    end

    -- Bright muzzle flash
    core.add_particlespawner({
        amount = 15,
        time = 0.1,
        pos = beam_start,
        radius = 0.3,
        velocity = {min = {x = -2, y = -2, z = -2}, max = {x = 2, y = 2, z = 2}},
        exptime = {min = 0.1, max = 0.3},
        size = {min = 3, max = 6},
        texture = "space_shooter_railgun_beam.png",
        glow = 14,
    })

    -- Find ALL enemies along the beam path and kill them
    -- Use a wide search radius around the beam line
    local state = player_state[name]
    local kills = 0
    local search_center = vector.add(beam_start, vector.multiply(dir, 50))
    local all_objs = core.get_objects_inside_radius(search_center, 60)

    for _, obj in ipairs(all_objs) do
        if not obj:is_player() then
            local lua = obj:get_luaentity()
            if lua and (lua.name == "space_shooter:alien"
                    or lua.name == "space_shooter:alien_elite"
                    or lua.name == "space_shooter:alien_boss") then
                local obj_pos = obj:get_pos()
                if obj_pos then
                    -- Check if this enemy is close to the beam line
                    -- Project enemy position onto the beam ray
                    local to_obj = vector.subtract(obj_pos, beam_start)
                    local proj_length = vector.dot(to_obj, dir)

                    -- Only consider enemies in front of the player
                    if proj_length > 0 then
                        -- Find the closest point on the beam to this enemy
                        local closest_on_beam = vector.add(beam_start, vector.multiply(dir, proj_length))
                        local dist_to_beam = vector.distance(obj_pos, closest_on_beam)

                        -- Hit if within 1.5 nodes of the beam (generous hitbox)
                        if dist_to_beam < 1.5 then
                            -- Instant kill regardless of HP
                            kills = kills + 1
                            lua:_die(name)
                        end
                    end
                end
            end
        end
    end

    if kills > 0 then
        core.chat_send_player(name,
            core.colorize("#00ffff", "RAILGUN: " .. kills .. " alien" ..
            (kills > 1 and "s" or "") .. " vaporized!"))
    end
end

core.register_tool("space_shooter:railgun", {
    description = "Railgun\nPenetrating beam, instant kill\nUnlocks at Wave 10\nLeft-click to fire",
    inventory_image = "space_shooter_railgun.png",
    range = 0,
    groups = {not_in_creative_inventory = 1},
    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        local state = player_state[name]
        if not state or not state.in_game then return end

        if not state.railgun_unlocked then
            core.chat_send_player(name, core.colorize("#888888", "Railgun unlocks at Wave 10!"))
            return
        end

        if state.ammo_railgun <= 0 then
            core.chat_send_player(name, core.colorize("#00ffff", "Out of railgun ammo!"))
            return
        end

        state.ammo_railgun = state.ammo_railgun - 1
        fire_railgun(user)
        return itemstack
    end,
})

-- ============================================================================
-- ALIEN ENEMIES
-- ============================================================================

local function register_alien(name, def)
    core.register_entity("space_shooter:" .. name, {
        initial_properties = {
            physical = true,
            collide_with_objects = true,
            collisionbox = def.box or {-0.4, -0.5, -0.4, 0.4, 0.8, 0.4},
            selectionbox = def.box or {-0.4, -0.5, -0.4, 0.4, 0.8, 0.4},
            visual = "sprite",
            visual_size = def.size or {x = 1, y = 1},
            textures = {def.texture},
            glow = 10,
            static_save = false,
            hp_max = def.hp,
            pointable = true,
            makes_footstep_sound = false,
        },
        _hp = def.hp,
        _max_hp = def.hp,
        _damage = def.damage or 2,
        _speed = def.speed or 3,
        _score_value = def.score or 100,
        _target = nil,
        _attack_timer = 0,
        _attack_interval = def.attack_interval or 2,
        _move_timer = 0,
        _strafe_dir = 1,

        on_activate = function(self, staticdata, dtime_s)
            self._hp = def.hp
            -- Spawn effect
            local pos = self.object:get_pos()
            if pos then
                core.add_particlespawner({
                    amount = 15,
                    time = 0.3,
                    pos = pos,
                    radius = 0.5,
                    velocity = {min = {x = -2, y = 0, z = -2}, max = {x = 2, y = 3, z = 2}},
                    exptime = {min = 0.3, max = 0.7},
                    size = {min = 1, max = 3},
                    texture = "space_shooter_alien_bolt.png",
                    glow = 14,
                })
            end
        end,

        on_step = function(self, dtime)
            local pos = self.object:get_pos()
            if not pos then return end

            -- Find nearest player target
            local nearest = nil
            local nearest_dist = 999

            for pname, state in pairs(player_state) do
                if state.in_game then
                    local player = core.get_player_by_name(pname)
                    if player then
                        local pp = player:get_pos()
                        local dist = vector.distance(pos, pp)
                        if dist < nearest_dist then
                            nearest = player
                            nearest_dist = dist
                        end
                    end
                end
            end

            if not nearest then return end

            local target_pos = nearest:get_pos()
            target_pos.y = target_pos.y + 1  -- Aim at body

            -- Movement AI
            self._move_timer = self._move_timer + dtime
            if self._move_timer > 2 then
                self._move_timer = 0
                self._strafe_dir = -self._strafe_dir
            end

            local dir_to_player = vector.direction(pos, target_pos)
            local move_vel = {x = 0, y = 0, z = 0}

            if nearest_dist > 8 then
                -- Move toward player
                move_vel = vector.multiply(dir_to_player, self._speed)
            elseif nearest_dist < 4 then
                -- Retreat
                move_vel = vector.multiply(dir_to_player, -self._speed * 0.5)
            end

            -- Add strafing
            local strafe = {
                x = -dir_to_player.z * self._strafe_dir * self._speed * 0.4,
                y = 0,
                z = dir_to_player.x * self._strafe_dir * self._speed * 0.4,
            }
            move_vel = vector.add(move_vel, strafe)
            move_vel.y = 0  -- Keep on ground level

            self.object:set_velocity(move_vel)

            -- Face the player
            local yaw = math.atan2(dir_to_player.z, dir_to_player.x) - math.pi / 2
            self.object:set_yaw(yaw)

            -- Attack
            self._attack_timer = self._attack_timer + dtime
            if self._attack_timer >= self._attack_interval and nearest_dist < 30 then
                self._attack_timer = 0
                -- Shoot at player
                local shoot_dir = vector.direction(pos, target_pos)
                -- Add inaccuracy
                shoot_dir.x = shoot_dir.x + (math.random() - 0.5) * 0.15
                shoot_dir.y = shoot_dir.y + (math.random() - 0.5) * 0.15
                shoot_dir.z = shoot_dir.z + (math.random() - 0.5) * 0.15
                shoot_dir = vector.normalize(shoot_dir)

                local bolt_pos = vector.add(pos, vector.multiply(shoot_dir, 1))
                bolt_pos.y = bolt_pos.y + 0.5
                local bolt = core.add_entity(bolt_pos, "space_shooter:alien_bolt")
                if bolt then
                    bolt:set_velocity(vector.multiply(shoot_dir, 15))
                end
            end
        end,

        on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
            -- Direct melee punch fallback
            if puncher and puncher:is_player() then
                self._hp = self._hp - 1
                if self._hp <= 0 then
                    self:_die(puncher:get_player_name())
                end
            end
            return true  -- Override default damage
        end,

        _die = function(self, killer_name)
            local pos = self.object:get_pos()
            if pos then
                -- Death explosion
                core.add_particlespawner({
                    amount = 20,
                    time = 0.2,
                    pos = pos,
                    radius = 0.5,
                    velocity = {min = {x = -3, y = -1, z = -3}, max = {x = 3, y = 4, z = 3}},
                    exptime = {min = 0.3, max = 1.0},
                    size = {min = 2, max = 5},
                    texture = "space_shooter_explosion.png",
                    glow = 14,
                })

                -- Chance to drop pickup
                local roll = math.random(1, 100)
                if roll <= 20 then
                    -- Health pack
                    local drop = core.add_entity(pos, "space_shooter:pickup_health")
                elseif roll <= 40 then
                    -- Ammo
                    local drop = core.add_entity(pos, "space_shooter:pickup_ammo")
                elseif roll <= 50 then
                    -- Shield
                    local drop = core.add_entity(pos, "space_shooter:pickup_shield")
                end
            end

            -- Update killer's score
            if killer_name then
                local state = player_state[killer_name]
                if state then
                    state.combo = state.combo + 1
                    state.combo_timer = 3
                    local combo_mult = math.min(state.combo, 5)
                    local score_gain = self._score_value * combo_mult
                    state.score = state.score + score_gain
                    state.kills = state.kills + 1
                    state.enemies_alive = math.max(0, state.enemies_alive - 1)

                    if combo_mult > 1 then
                        core.chat_send_player(killer_name,
                            core.colorize("#ffaa00", "COMBO x" .. combo_mult .. "! +" .. score_gain .. " pts"))
                    end
                end
            end

            self.object:remove()
        end,
    })
end

register_alien("alien", {
    texture = "space_shooter_alien.png",
    hp = 10,
    damage = 2,
    speed = 3,
    score = 100,
    attack_interval = 2.5,
    size = {x = 1, y = 1},
    box = {-0.4, -0.5, -0.4, 0.4, 0.8, 0.4},
})

register_alien("alien_elite", {
    texture = "space_shooter_alien_elite.png",
    hp = 25,
    damage = 4,
    speed = 4,
    score = 300,
    attack_interval = 1.5,
    size = {x = 1.2, y = 1.2},
    box = {-0.5, -0.5, -0.5, 0.5, 1.0, 0.5},
})

register_alien("alien_boss", {
    texture = "space_shooter_alien_boss.png",
    hp = 100,
    damage = 8,
    speed = 2,
    score = 1000,
    attack_interval = 1.0,
    size = {x = 2, y = 2},
    box = {-0.8, -0.5, -0.8, 0.8, 1.5, 0.8},
})

-- ============================================================================
-- PICKUPS
-- ============================================================================

local function register_pickup(name, def)
    core.register_entity("space_shooter:" .. name, {
        initial_properties = {
            physical = false,
            collisionbox = {-0.3, -0.3, -0.3, 0.3, 0.3, 0.3},
            visual = "sprite",
            visual_size = {x = 0.5, y = 0.5},
            textures = {def.texture},
            glow = 12,
            static_save = false,
            automatic_rotate = 2,
        },
        _lifetime = 0,

        on_step = function(self, dtime)
            self._lifetime = self._lifetime + dtime
            if self._lifetime > 15 then
                self.object:remove()
                return
            end

            local pos = self.object:get_pos()
            if not pos then return end

            -- Bob up and down
            local y_offset = math.sin(self._lifetime * 3) * 0.1
            self.object:set_velocity({x = 0, y = y_offset, z = 0})

            -- Check for player collision
            for _, player in ipairs(core.get_connected_players()) do
                local pname = player:get_player_name()
                local state = player_state[pname]
                if state and state.in_game then
                    local pp = player:get_pos()
                    pp.y = pp.y + 1
                    if vector.distance(pos, pp) < 1.5 then
                        def.on_pickup(player, state)
                        -- Pickup effect
                        core.add_particlespawner({
                            amount = 10,
                            time = 0.1,
                            pos = pos,
                            radius = 0.3,
                            velocity = {min = {x = -1, y = 1, z = -1}, max = {x = 1, y = 3, z = 1}},
                            exptime = {min = 0.2, max = 0.5},
                            size = {min = 1, max = 2},
                            texture = def.texture,
                            glow = 14,
                        })
                        self.object:remove()
                        return
                    end
                end
            end
        end,
    })
end

register_pickup("pickup_health", {
    texture = "space_shooter_health_pack.png",
    on_pickup = function(player, state)
        local hp = player:get_hp()
        player:set_hp(math.min(hp + 8, 20))
        core.chat_send_player(player:get_player_name(),
            core.colorize("#55ff55", "+8 Health"))
    end,
})

register_pickup("pickup_ammo", {
    texture = "space_shooter_ammo_pack.png",
    on_pickup = function(player, state)
        state.ammo_laser = state.ammo_laser + 30
        state.ammo_plasma = state.ammo_plasma + 10
        state.ammo_rocket = state.ammo_rocket + 3
        if state.railgun_unlocked then
            state.ammo_railgun = state.ammo_railgun + 2
        end
        local msg = "+30 Laser / +10 Plasma / +3 Rockets"
        if state.railgun_unlocked then
            msg = msg .. " / +2 Railgun"
        end
        core.chat_send_player(player:get_player_name(),
            core.colorize("#ffff55", msg))
    end,
})

register_pickup("pickup_shield", {
    texture = "space_shooter_shield.png",
    on_pickup = function(player, state)
        state.shield = math.min(state.shield + 10, 20)
        core.chat_send_player(player:get_player_name(),
            core.colorize("#5555ff", "+10 Shield"))
    end,
})

-- ============================================================================
-- ARENA GENERATION
-- ============================================================================

local ARENA_SIZE = 25  -- half-size of arena
local ARENA_HEIGHT = 8

local function generate_arena(center)
    local cx, cy, cz = center.x, center.y, center.z

    -- Clear area and fill with space
    for x = cx - ARENA_SIZE - 2, cx + ARENA_SIZE + 2 do
        for z = cz - ARENA_SIZE - 2, cz + ARENA_SIZE + 2 do
            for y = cy - 1, cy + ARENA_HEIGHT + 1 do
                core.set_node({x = x, y = y, z = z}, {name = "air"})
            end
        end
    end

    -- Floor
    for x = cx - ARENA_SIZE, cx + ARENA_SIZE do
        for z = cz - ARENA_SIZE, cz + ARENA_SIZE do
            core.set_node({x = x, y = cy - 1, z = z}, {name = "space_shooter:floor"})
        end
    end

    -- Walls
    for x = cx - ARENA_SIZE - 1, cx + ARENA_SIZE + 1 do
        for y = cy, cy + ARENA_HEIGHT do
            core.set_node({x = x, y = y, z = cz - ARENA_SIZE - 1}, {name = "space_shooter:wall"})
            core.set_node({x = x, y = y, z = cz + ARENA_SIZE + 1}, {name = "space_shooter:wall"})
        end
    end
    for z = cz - ARENA_SIZE - 1, cz + ARENA_SIZE + 1 do
        for y = cy, cy + ARENA_HEIGHT do
            core.set_node({x = cx - ARENA_SIZE - 1, y = y, z = z}, {name = "space_shooter:wall"})
            core.set_node({x = cx + ARENA_SIZE + 1, y = y, z = z}, {name = "space_shooter:wall"})
        end
    end

    -- Glass sections in walls (windows to space)
    for i = -ARENA_SIZE + 3, ARENA_SIZE - 3, 6 do
        for y = cy + 2, cy + ARENA_HEIGHT - 1 do
            for off = -1, 1 do
                core.set_node({x = cx + i + off, y = y, z = cz - ARENA_SIZE - 1}, {name = "space_shooter:glass"})
                core.set_node({x = cx + i + off, y = y, z = cz + ARENA_SIZE + 1}, {name = "space_shooter:glass"})
                core.set_node({x = cx - ARENA_SIZE - 1, y = y, z = cz + i + off}, {name = "space_shooter:glass"})
                core.set_node({x = cx + ARENA_SIZE + 1, y = y, z = cz + i + off}, {name = "space_shooter:glass"})
            end
        end
    end

    -- Cover blocks (pillars for tactical gameplay)
    local pillar_positions = {
        {cx - 10, cz - 10}, {cx + 10, cz - 10},
        {cx - 10, cz + 10}, {cx + 10, cz + 10},
        {cx, cz - 15}, {cx, cz + 15},
        {cx - 15, cz}, {cx + 15, cz},
    }
    for _, pp in ipairs(pillar_positions) do
        for y = cy, cy + 3 do
            core.set_node({x = pp[1], y = y, z = pp[2]}, {name = "space_shooter:wall"})
            core.set_node({x = pp[1] + 1, y = y, z = pp[2]}, {name = "space_shooter:wall"})
            core.set_node({x = pp[1], y = y, z = pp[2] + 1}, {name = "space_shooter:wall"})
            core.set_node({x = pp[1] + 1, y = y, z = pp[2] + 1}, {name = "space_shooter:wall"})
        end
    end

    -- Spawn pads (enemy spawn locations)
    local spawn_pads = {
        {cx - 20, cy - 1, cz - 20},
        {cx + 20, cy - 1, cz - 20},
        {cx - 20, cy - 1, cz + 20},
        {cx + 20, cy - 1, cz + 20},
        {cx, cy - 1, cz - 22},
        {cx, cy - 1, cz + 22},
        {cx - 22, cy - 1, cz},
        {cx + 22, cy - 1, cz},
    }
    for _, sp in ipairs(spawn_pads) do
        core.set_node({x = sp[1], y = sp[2], z = sp[3]}, {name = "space_shooter:spawn_pad"})
    end

    return spawn_pads
end

-- ============================================================================
-- HUD SYSTEM
-- ============================================================================

local function setup_hud(player, state)
    local name = player:get_player_name()
    local ids = {}

    -- Crosshair
    ids.crosshair = player:hud_add({
        hud_elem_type = "image",
        position = {x = 0.5, y = 0.5},
        scale = {x = 2, y = 2},
        text = "space_shooter_crosshair.png",
        alignment = {x = 0, y = 0},
        offset = {x = 0, y = 0},
    })

    -- Score
    ids.score = player:hud_add({
        hud_elem_type = "text",
        position = {x = 0.5, y = 0.02},
        text = "SCORE: 0",
        number = 0x55FF55,
        alignment = {x = 0, y = 0},
        offset = {x = 0, y = 0},
        size = {x = 2, y = 2},
    })

    -- Wave
    ids.wave = player:hud_add({
        hud_elem_type = "text",
        position = {x = 0.5, y = 0.06},
        text = "WAVE: 0",
        number = 0xFFAA00,
        alignment = {x = 0, y = 0},
        offset = {x = 0, y = 0},
        size = {x = 1.5, y = 1.5},
    })

    -- Ammo
    ids.ammo = player:hud_add({
        hud_elem_type = "text",
        position = {x = 0.98, y = 0.92},
        text = "LASER:100 | PLASMA:30 | ROCKETS:10",
        number = 0xFFFF55,
        alignment = {x = 1, y = 0},
        offset = {x = -10, y = 0},
        size = {x = 1, y = 1},
    })

    -- Shield
    ids.shield = player:hud_add({
        hud_elem_type = "text",
        position = {x = 0.02, y = 0.92},
        text = "SHIELD: 0",
        number = 0x5599FF,
        alignment = {x = -1, y = 0},
        offset = {x = 10, y = 0},
        size = {x = 1.2, y = 1.2},
    })

    -- Enemies remaining
    ids.enemies = player:hud_add({
        hud_elem_type = "text",
        position = {x = 0.98, y = 0.06},
        text = "ALIENS: 0",
        number = 0xFF5555,
        alignment = {x = 1, y = 0},
        offset = {x = -10, y = 0},
        size = {x = 1.2, y = 1.2},
    })

    -- Combo
    ids.combo = player:hud_add({
        hud_elem_type = "text",
        position = {x = 0.5, y = 0.12},
        text = "",
        number = 0xFFAA00,
        alignment = {x = 0, y = 0},
        offset = {x = 0, y = 0},
        size = {x = 2, y = 2},
    })

    state.hud_ids = ids
end

local function update_hud(player, state)
    if not state.hud_ids.score then return end

    player:hud_change(state.hud_ids.score, "text", "SCORE: " .. state.score)
    player:hud_change(state.hud_ids.wave, "text", "WAVE: " .. state.wave)
    local ammo_text = "LASER:" .. state.ammo_laser ..
        " | PLASMA:" .. state.ammo_plasma ..
        " | ROCKETS:" .. state.ammo_rocket
    if state.railgun_unlocked then
        ammo_text = ammo_text .. " | RAILGUN:" .. state.ammo_railgun
    end
    player:hud_change(state.hud_ids.ammo, "text", ammo_text)
    player:hud_change(state.hud_ids.shield, "text", "SHIELD: " .. state.shield)

    local enemies_text = "ALIENS: " .. state.enemies_alive
    if state.enemies_to_spawn > 0 then
        enemies_text = enemies_text .. " (+" .. state.enemies_to_spawn .. " incoming)"
    end
    player:hud_change(state.hud_ids.enemies, "text", enemies_text)

    if state.combo > 1 and state.combo_timer > 0 then
        player:hud_change(state.hud_ids.combo, "text", "COMBO x" .. state.combo)
    else
        player:hud_change(state.hud_ids.combo, "text", "")
    end
end

local function remove_hud(player, state)
    for _, id in pairs(state.hud_ids) do
        if id then
            player:hud_remove(id)
        end
    end
    state.hud_ids = {}
end

-- ============================================================================
-- WAVE SYSTEM
-- ============================================================================

local function get_spawn_positions(center)
    local positions = {}
    local offsets = {
        {-20, 0, -20}, {20, 0, -20}, {-20, 0, 20}, {20, 0, 20},
        {0, 0, -22}, {0, 0, 22}, {-22, 0, 0}, {22, 0, 0},
    }
    for _, off in ipairs(offsets) do
        table.insert(positions, {
            x = center.x + off[1],
            y = center.y + 1,
            z = center.z + off[3],
        })
    end
    return positions
end

local function start_wave(player_name)
    local state = player_state[player_name]
    if not state then return end

    state.wave = state.wave + 1
    state.wave_active = true
    state.spawn_timer = 0

    -- Calculate enemies for this wave
    local base_count = 3 + state.wave * 2
    local elite_count = math.floor(state.wave / 3)
    local boss_count = 0
    if state.wave % 5 == 0 then
        boss_count = math.floor(state.wave / 5)
    end

    state.enemies_to_spawn = base_count + elite_count + boss_count
    state.enemies_alive = 0
    state._spawn_queue = {}

    -- Build spawn queue
    for i = 1, base_count do
        table.insert(state._spawn_queue, "space_shooter:alien")
    end
    for i = 1, elite_count do
        table.insert(state._spawn_queue, "space_shooter:alien_elite")
    end
    for i = 1, boss_count do
        table.insert(state._spawn_queue, "space_shooter:alien_boss")
    end

    -- Bonus ammo each wave
    state.ammo_laser = state.ammo_laser + 20
    state.ammo_plasma = state.ammo_plasma + 5
    state.ammo_rocket = state.ammo_rocket + 2

    -- Railgun unlocks at wave 10
    if state.wave >= 10 and not state.railgun_unlocked then
        state.railgun_unlocked = true
        state.ammo_railgun = 5
        -- Give the railgun to the player
        local player = core.get_player_by_name(player_name)
        if player then
            player:get_inventory():add_item("main", "space_shooter:railgun")
        end
        core.chat_send_player(player_name,
            core.colorize("#00ffff", "*** RAILGUN UNLOCKED! *** 5 rounds loaded. One shot, one kill... through EVERYTHING."))
    elseif state.railgun_unlocked then
        state.ammo_railgun = state.ammo_railgun + 1
    end

    core.chat_send_player(player_name,
        core.colorize("#ff5555", "=== WAVE " .. state.wave .. " === " ..
        state.enemies_to_spawn .. " aliens incoming!"))
end

-- ============================================================================
-- GAME MANAGEMENT
-- ============================================================================

local function give_weapons(player)
    local inv = player:get_inventory()
    inv:set_list("main", {})
    inv:add_item("main", "space_shooter:laser_gun")
    inv:add_item("main", "space_shooter:plasma_rifle")
    inv:add_item("main", "space_shooter:rocket_launcher")
end

local function start_game(player)
    local name = player:get_player_name()
    init_player_state(name)
    local state = player_state[name]

    -- Set player properties
    player:set_hp(20)
    player:set_properties({
        hp_max = 20,
    })

    -- Build arena at player location
    local pos = player:get_pos()
    local center = {x = math.floor(pos.x), y = math.floor(pos.y), z = math.floor(pos.z)}
    generate_arena(center)
    state.arena_center = center

    -- Teleport player to center
    player:set_pos({x = center.x, y = center.y + 1, z = center.z})

    -- Give weapons
    give_weapons(player)

    -- Setup HUD
    setup_hud(player, state)

    -- Disable default HUD elements for cleaner look
    player:hud_set_flags({
        crosshair = false,
        minimap = false,
    })

    state.in_game = true
    state.wave = 0

    core.chat_send_player(name, core.colorize("#55ff55",
        "=== SPACE SHOOTER ==="))
    core.chat_send_player(name, core.colorize("#aaaaaa",
        "Survive waves of alien invaders!"))
    core.chat_send_player(name, core.colorize("#aaaaaa",
        "Use left-click to fire your equipped weapon."))
    core.chat_send_player(name, core.colorize("#aaaaaa",
        "Switch weapons with the hotbar (1-3)."))

    -- Start first wave after short delay
    core.after(3, function()
        local s = player_state[name]
        if s and s.in_game then
            start_wave(name)
        end
    end)
end

local function end_game(player)
    local name = player:get_player_name()
    local state = player_state[name]
    if not state then return end

    core.chat_send_player(name, core.colorize("#ff5555", "=== GAME OVER ==="))
    core.chat_send_player(name, core.colorize("#ffff55",
        "Final Score: " .. state.score ..
        " | Waves: " .. state.wave ..
        " | Kills: " .. state.kills))

    -- Remove all enemies
    for _, obj in ipairs(core.get_objects_inside_radius(
            state.arena_center or player:get_pos(), ARENA_SIZE * 2)) do
        if not obj:is_player() then
            obj:remove()
        end
    end

    -- Restore HUD
    remove_hud(player, state)
    player:hud_set_flags({
        crosshair = true,
        minimap = true,
    })

    -- Clear inventory
    player:get_inventory():set_list("main", {})
    player:set_hp(20)

    state.in_game = false
end

-- ============================================================================
-- CHAT COMMANDS
-- ============================================================================

core.register_chatcommand("space_shooter", {
    description = "Start a Space Shooter game!",
    func = function(name, param)
        local player = core.get_player_by_name(name)
        if not player then return false, "Player not found" end

        local state = player_state[name]
        if state and state.in_game then
            return false, "You're already in a game! Use /space_quit to quit."
        end

        start_game(player)
        return true, "Game started!"
    end,
})

core.register_chatcommand("space_quit", {
    description = "Quit the current Space Shooter game",
    func = function(name, param)
        local player = core.get_player_by_name(name)
        if not player then return false, "Player not found" end

        local state = player_state[name]
        if not state or not state.in_game then
            return false, "You're not in a game!"
        end

        end_game(player)
        return true, "Game ended."
    end,
})

-- ============================================================================
-- GLOBAL STEP (Main game loop)
-- ============================================================================

local tick_timer = 0

core.register_globalstep(function(dtime)
    tick_timer = tick_timer + dtime

    for name, state in pairs(player_state) do
        if state.in_game then
            local player = core.get_player_by_name(name)
            if not player then
                state.in_game = false
            else
                -- Check if player died
                if player:get_hp() <= 0 then
                    end_game(player)
                else
                    -- Combo timer decay
                    if state.combo_timer > 0 then
                        state.combo_timer = state.combo_timer - dtime
                        if state.combo_timer <= 0 then
                            state.combo = 0
                        end
                    end

                    -- Spawn enemies from queue
                    if state.wave_active and state._spawn_queue and #state._spawn_queue > 0 then
                        state.spawn_timer = state.spawn_timer + dtime
                        if state.spawn_timer >= 1.5 then  -- Spawn interval
                            state.spawn_timer = 0
                            local spawn_positions = get_spawn_positions(state.arena_center)
                            local sp = spawn_positions[math.random(#spawn_positions)]
                            local etype = table.remove(state._spawn_queue, 1)
                            core.add_entity(sp, etype)
                            state.enemies_alive = state.enemies_alive + 1
                            state.enemies_to_spawn = #state._spawn_queue
                        end
                    end

                    -- Check if wave is complete
                    if state.wave_active and state.enemies_alive <= 0
                       and (not state._spawn_queue or #state._spawn_queue == 0) then
                        state.wave_active = false
                        core.chat_send_player(name,
                            core.colorize("#55ff55", "Wave " .. state.wave .. " complete!"))

                        -- Heal player between waves
                        player:set_hp(math.min(player:get_hp() + 5, 20))

                        -- Start next wave after delay
                        core.after(4, function()
                            local s = player_state[name]
                            if s and s.in_game then
                                start_wave(name)
                            end
                        end)
                    end

                    -- Update HUD periodically (not every frame for performance)
                    if tick_timer >= 0.2 then
                        update_hud(player, state)
                    end

                    -- Background space particles
                    if tick_timer >= 1 then
                        local pp = player:get_pos()
                        core.add_particlespawner({
                            amount = 3,
                            time = 1,
                            pos = {
                                min = {x = pp.x - 30, y = pp.y + 10, z = pp.z - 30},
                                max = {x = pp.x + 30, y = pp.y + 20, z = pp.z + 30},
                            },
                            velocity = {min = {x = -0.1, y = -0.5, z = -0.1}, max = {x = 0.1, y = -0.1, z = 0.1}},
                            exptime = {min = 3, max = 6},
                            size = {min = 0.5, max = 1.5},
                            texture = "space_shooter_star.png",
                            glow = 14,
                            playername = name,
                        })
                    end
                end
            end
        end
    end

    if tick_timer >= 1 then
        tick_timer = 0
    end
end)

-- ============================================================================
-- PLAYER JOIN / LEAVE
-- ============================================================================

core.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    init_player_state(name)
    core.chat_send_player(name, core.colorize("#55ff55",
        "Welcome to SPACE SHOOTER! Type /space_shooter to start a game!"))
end)

core.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    local state = player_state[name]
    if state and state.in_game then
        -- Clean up enemies
        if state.arena_center then
            for _, obj in ipairs(core.get_objects_inside_radius(state.arena_center, ARENA_SIZE * 2)) do
                if not obj:is_player() then
                    obj:remove()
                end
            end
        end
    end
    player_state[name] = nil
end)

core.register_on_dieplayer(function(player)
    local name = player:get_player_name()
    local state = player_state[name]
    if state and state.in_game then
        end_game(player)
    end
end)

-- ============================================================================
-- Disable node interaction during game
-- ============================================================================

core.register_on_placenode(function(pos, newnode, placer)
    if placer and placer:is_player() then
        local state = player_state[placer:get_player_name()]
        if state and state.in_game then
            core.remove_node(pos)
            return true
        end
    end
end)

core.register_on_dignode(function(pos, oldnode, digger)
    if digger and digger:is_player() then
        local state = player_state[digger:get_player_name()]
        if state and state.in_game then
            core.set_node(pos, oldnode)
            return true
        end
    end
end)

core.log("action", "[space_shooter] FPS Space Shooter mod loaded!")
