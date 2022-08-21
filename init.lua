real_stamina = {}

STAMINA_TICK = 1		-- time in seconds after that 1 stamina point is taken
STAMINA_TICK_MIN = 0		-- stamina ticks won't reduce stamina below this level
STAMINA_HEALTH_TICK = 10		-- time in seconds after player gets healed/damaged
STAMINA_MOVE_TICK = 0.3		-- time in seconds after the movement is checked

STAMINA_VISUAL_MAX = 20		-- hud bar extends only to 20

SPRINT_SPEED = 0.9		-- how much faster player can run if satiated
SPRINT_JUMP = 0.1		-- how much higher player can jump if satiated

local function get_int_attribute(player, key)
   local level_m = player:get_meta()
   if level_m and level_m:get_int(key) then
      return level_m:get_int(key)
   end
end

local function stamina_update_level(player, level)
   if not player:get_meta() then
      return
   end
   local old = get_int_attribute(player, "real_stamina:level")

   if level == old then  -- To suppress HUD update
      return
   end

   player:get_meta():set_int("real_stamina:level", level)

   player:hud_change(player:get_meta():get_int("real_stamina:hud_id"), "number", math.min(STAMINA_VISUAL_MAX, level))
end

-- global function for mods to amend stamina level
real_stamina.change = function(player, change)
   local name = player:get_player_name()
   if not name or not change or change == 0 then
      return false
   end
   local level = get_int_attribute(player, "real_stamina:level") + change
   if level < 0 then level = 0 end
   if level > STAMINA_VISUAL_MAX then level = STAMINA_VISUAL_MAX end
   stamina_update_level(player, level)
   return true
end

-- Sprint settings and function
local enable_sprint = minetest.setting_getbool("sprint") ~= false
local enable_sprint_particles = minetest.setting_getbool("sprint_particles") ~= false
local armor_mod = minetest.get_modpath("3d_armor")

function set_sprinting(player, sprinting)
   local name = player:get_player_name()
   local def = {}
   -- Get player physics from 3d_armor mod
   if armor_mod and armor and armor.def then
      def.speed = armor.def[name].speed
      def.jump = armor.def[name].jump
      def.gravity = armor.def[name].gravity
   end

   def.speed = def.speed or 1
   def.jump = def.jump or 1
   def.gravity = def.gravity or 1

   if sprinting == true then
      def.speed = def.speed + SPRINT_SPEED
      def.jump = def.jump + SPRINT_JUMP
      player:set_fov(1.05, true, .1)
      player:get_meta():set_int("real_stamina:sprinting", 1)
   else
      player:set_fov(1.0, true, .1)
      player:get_meta():set_int("real_stamina:sprinting", 0)
   end

   player:set_physics_override({
         speed = def.speed,
         jump = def.jump,
         gravity = def.gravity
   })
end

-- Time based stamina functions
local stamina_timer = 0
local health_timer = 0
local action_timer = 0

local function stamina_globaltimer(dtime)
   stamina_timer = stamina_timer + dtime*12
   health_timer = health_timer + dtime
   action_timer = action_timer + dtime

   if action_timer > STAMINA_MOVE_TICK then
      for _,player in ipairs(minetest.get_connected_players()) do
         local controls = player:get_player_control()

         local level = get_int_attribute(player, "real_stamina:level")
         if controls.aux1 and controls.up
            and get_int_attribute(player, "real_stamina:level") <= 0 then
            player:get_meta():set_int("real_stamina:exhausted", 1)
         end

         --- START sprint
         if enable_sprint then
            -- check if player can sprint (stamina must be over 6 points)

            if controls.aux1 and controls.up
               and not minetest.check_player_privs(player, {fast = true})
               and get_int_attribute(player, "real_stamina:level") > 0 and player:get_meta():get_int("real_stamina:exhausted") == 0 then
               -- create particles behind player when sprinting
               if enable_sprint_particles then

                  local pos = player:getpos()
                  local node = minetest.get_node({
                        x = pos.x, y = pos.y - 1, z = pos.z})

                  if node.name ~= "air" then

                     minetest.add_particlespawner({
                           amount = 5,
                           time = 0.01,
                           minpos = {x = pos.x - 0.25, y = pos.y + 0.1, z = pos.z - 0.25},
                           maxpos = {x = pos.x + 0.25, y = pos.y + 0.1, z = pos.z + 0.25},
                           minvel = {x = -0.5, y = 1, z = -0.5},
                           maxvel = {x = 0.5, y = 2, z = 0.5},
                           minacc = {x = 0, y = -5, z = 0},
                           maxacc = {x = 0, y = -12, z = 0},
                           minexptime = 0.25,
                           maxexptime = 0.5,
                           minsize = 0.5,
                           maxsize = 1.0,
                           vertical = false,
                           collisiondetection = false,
                           texture = "default_dirt.png",
                     })

                  end
               end
               stamina_update_level(player, level - 1)
            end
         end
         -- END sprint

      end
      action_timer = 0
   end
   
   for _,player in ipairs(minetest.get_connected_players()) do
      local controls = player:get_player_control()

      local level = get_int_attribute(player, "real_stamina:level")
      if controls.aux1 and controls.up
         and get_int_attribute(player, "real_stamina:level") <= 0 then
         player:get_meta():set_int("real_stamina:exhausted", 1)
      end

      --- START sprint
      if enable_sprint then
         -- check if player can sprint (stamina must be over 6 points)

         if controls.aux1 and controls.up
            and not minetest.check_player_privs(player, {fast = true})
            and player:get_meta():get_int("real_stamina:level") > 0 and player:get_meta():get_int("real_stamina:exhausted") == 0 then
            set_sprinting(player, true)
         else
            set_sprinting(player, false)
         end
      end
      -- END sprint

   end


   -- lower saturation by 1 point after STAMINA_TICK second(s)
   if stamina_timer > STAMINA_TICK then
      for _,player in ipairs(minetest.get_connected_players()) do
         local h = get_int_attribute(player, "real_stamina:level")
         if h < 20 then
            if player:get_meta():get_int("real_stamina:sprinting") == 0 then
               stamina_update_level(player, h + 1)
            end
         else
            player:get_meta():set_int("real_stamina:exhausted", 0);
         end
      end
      stamina_timer = 0
   end
end

-- stamina is disabled if damage is disabled
if minetest.setting_getbool("enable_damage") and minetest.is_yes(minetest.setting_get("enable_stamina") or "1") then
   minetest.register_on_joinplayer(function(player)
         local level = STAMINA_VISUAL_MAX -- TODO
         if get_int_attribute(player, "real_stamina:level") then
            level = math.min(get_int_attribute(player, "real_stamina:level"), STAMINA_VISUAL_MAX)
         else
            player:get_meta():set_int("real_stamina:level", level)
         end
         local id = player:hud_add({
               name = "stamina",
               hud_elem_type = "statbar",
               position = {x = 0.5, y = 1},
               size = {x = 24, y = 24},
               text = "stamina_hud_fg.png",
               number = level,
               alignment = {x = -1, y = -1},
               offset = {x = -266, y = -110},
               max = 0,
         })
         player:get_meta():set_int("real_stamina:hud_id", id)
         if not get_int_attribute(player, "real_stamina:exhausted") then
            player:get_meta():set_int("real_stamina:exhausted", 0)
         end
         if not get_int_attribute(player, "real_stamina:sprinting") then
            player:get_meta():set_int("real_stamina:sprinting", 0)
         end
   end)

   minetest.register_globalstep(stamina_globaltimer)

   minetest.register_on_respawnplayer(function(player)
         stamina_update_level(player, STAMINA_VISUAL_MAX)
   end)
end
