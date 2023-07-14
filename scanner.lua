_addon.name = 'scanner'
_addon.author = 'Akaden; Darkdoom'
_addon.version = '0.2.0.0'
_addon.commands = {'scanner'}

require('logger')
packets = require('packets')
config = require('config')
require('helpers')

local LAST_SCAN_PACKET_DELAY = 1 -- seconds

local addonPath = windower.addon_path:gsub('\\', '/')
local dllPath = addonPath .. 'Widescan.dll'
local WidescanInterface = assert(package.loadlib(dllPath, 'luaopen_Widescan'))()

defaults = {
  autoscan_delay = 30, -- seconds
  autoscan_random = 4, -- seconds
  find_sleep = nil, -- seconds
  play_sound = 'roar',
  filter_map = true,
  log_state = true,
  log_tracking = true,
  log_tracking_delay = 5, -- seconds
}
settings = config.load(defaults)

state = {
  scan_id = 0,
  last_packet_time = nil,
  sound_played = false,

  scan_targets = T{},
  found_target_indices = T{},
  scan_results = {},

  track_info = nil,
  sleeping_til = nil,
}

function alert(message)
  if settings.log_state then
    log(message)
  end
end

function on_found_targets(target_indices)
  if not target_indices then return end

  local me = {x=0, y=0}

  -- find the closest target
  local closest_target_index = nil
  local closest_dist_sqd = nil
  for i, t in ipairs(target_indices) do
    if state.scan_results[t] then
      local d = dist_sqd(me, state.scan_results[t])
      -- print(state.scan_results[t].name, math.sqrt(d), state.scan_results[t].x, state.scan_results[t].y)
      if not closest_target_index or d < closest_dist_sqd then
        closest_target_index = t
        closest_dist_sqd = d
      end
    end
  end

  if not closest_target_index then return end

  local closest_target = state.scan_results[closest_target_index]

  -- play sound effect
  if not state.sound_played and settings.play_sound then
    windower.play_sound(string.format("%s/sounds/%s.wav", windower.addon_path, settings.play_sound))
    state.sound_played = true
  end
  
  -- track target
  if not state.track_data and state.autotrack then
    alert(string.format('Scan complete. Found target! Tracking: %s (%d)', closest_target.name, closest_target_index))
    WidescanInterface.TrackingStartSet(closest_target_index)
  else
    alert(string.format('Scan complete. Found target! %s (%d)', closest_target.name, closest_target_index))
  end
end
function on_no_targets_found()
  alert('Scan complete, no targets found.')
end

function await_scan_completion(scan_id)
  -- wait for a delay in the widescan results packets
  while not (state.last_packet_time == nil or os.time() - state.last_packet_time > LAST_SCAN_PACKET_DELAY or state.scan_id ~= scan_id) do
    coroutine.sleep(0.1)
  end

  -- terminate if the scan id is incorrect
  if state.scan_id ~= scan_id then return end

  -- handle scan completed
  if #state.found_target_indices > 0 then
    on_found_targets(state.found_target_indices)
  else
    on_no_targets_found()
  end
end

function perform_scan(targets, scan_id)
  if not targets or #targets == 0 then return end

  if scan_id == nil then
    -- scan just started
    state.sleeping_til = nil
    state.scan_id = state.scan_id + 1
    scan_id = state.scan_id
  elseif scan_id ~= state.scan_id then 
    -- scan id doesn match, thus the scan was cancelled, abandon scan.
    return
  end

  -- begin the scan. Don't scan if we're tracking or sleeping.
  if not state.track_info and (not state.sleeping_til or os.time() >= state.sleeping_til) then
    local scantype = 'Scanning once'
    if state.autoscan then scantype = 'Scanning' end
    local tracktype = ''
    if state.autotrack then tracktype = ' (auto-track enabled)' end

    alert(string.format('%s%s...', scantype, tracktype))
    state.targets = targets
    
    local p = packets.new('outgoing', 0x0F4)
    packets.inject(p)

    await_scan_completion:schedule(1, scan_id)
  end
  
  -- begin the next scan.
  if state.autoscan then
    local next_scan_time = math.random(settings.autoscan_delay - settings.autoscan_random, settings.autoscan_delay + settings.autoscan_random)
    state.next_scan = os.time() + next_scan_time
    perform_scan:schedule(next_scan_time, targets, scan_id)
  end
end

function stop_all()
  -- increment scan id to prevent the scheduled scan from executing
  state.scan_id = state.scan_id + 1
  state.sleeping_til = nil
  state.next_scan = nil
  if state.autoscan then
    alert("Stopping auto-scan.")
  end
  state.autoscan = false

  -- end tracking
  state.autotrack = false
  local widescanInfo = WidescanInterface.GetWidescanInfo()
  if widescanInfo and widescanInfo.Index > 0 then
    WidescanInterface.TrackingStopSet()
    alert('Stopping track.')
  end
end

windower.register_event('incoming chunk',function(id,data,modified,injected,blocked)
  if S{0x0F4}:contains(id) then -- Widescan result
    if not state.last_packet_time or os.time() - state.last_packet_time > LAST_SCAN_PACKET_DELAY then
      -- clear results
      state.sound_played = false
      state.found_target_indices = T{}
      state.scan_results = {}
    end
    state.last_packet_time = os.time()
    
    local p = packets.parse('incoming', data)
    local name = p['Name']:lower():stripchars(' ')
    if not name or not p.Index or name == '' then return end 
    state.scan_results[p.Index] = {
      x = p['X Offset'], y = p['Y Offset'],
      index = p.Index, level = p.Level, status = p.Status, name = p.Name,
    }

    if state.targets then
      -- match targets by name or index
      for i, t in ipairs(state.targets) do
        if t and t == p.Index then
          state.found_target_indices:append(p.Index)
          return
        elseif t and name:contains(t) then
          state.found_target_indices:append(p.Index)
          return
        end
      end
      if settings.filter_map and state.autoscan then
        -- only filter when autoscan is active
        return true -- block non-target packet from reaching the client
      end
    end
  elseif S{0x0F5}:contains(id) then -- tracking info
    local p = packets.parse('incoming', data)
    if p.Index > 0 then
      -- tracking is enabled

      local _, xo, yo = windower.ffxi.get_map_data(p.X, p.Y, p.Z) 
      state.track_info = {
        x = xo, y = yo,
        world_x = p.X, world_y = p.Y, world_z = p.Z,
        index = p.Index, level = p.Level, status = p.Status,
        name = state.scan_results[p.Index] and state.scan_results[p.Index].name or '---',
      }

      -- log tracking info
      if p.Index > 0 and (state.last_tracking_update == nil or os.time() - state.last_tracking_update >= settings.log_tracking_delay) and settings.log_tracking then         
        local me = windower.ffxi.get_mob_by_target('me')
        local d = ''
        if me then
          d = string.format(' is %d yalms away', math.sqrt(dist_sqd(me, {x=p.X, y=p.Y})))
        end
        alert(string.format('Tracking: %s (%d)%s. Level: %d', state.track_info.name, p.Index, d, p.Level))
        state.last_tracking_update = os.time()
      end
    else
      -- tracking is disabled
      state.track_info = nil
      if state.autoscan and settings.find_sleep then
        state.sleeping_til = os.time() + settings.find_sleep
        alert(string.format('Tracking ended, sleeping autoscan for %d seconds.', settings.find_sleep))
      end
    end
  end
end)

local function parse_targets(args)  
  local targets = T{}
  for i, t in ipairs(args) do
    local nt = tonumber(t)
    if nt then
      targets:append(nt)
    else
      targets:append(t:lower():stripchars(' '))
    end
  end
  return targets
end

windower.register_event('addon command', function(...)
  local args = T{...}
  local cmd = args[1]:lower()
  args:remove(1)
  
  if S{'stop','cancel','c','end','halt'}:contains(cmd) then
    stop_all()
  elseif S{'autoscan','auto','as'}:contains(cmd) then
    if state.track_info then stop_all() end

    state.autotrack = false
    state.autoscan = true
    perform_scan(parse_targets(args))
  elseif S{'autotrack','at'}:contains(cmd) then
    if state.track_info then stop_all() end

    state.autotrack = true
    state.autoscan = true
    perform_scan(parse_targets(args))
  elseif S{'scan','s'}:contains(cmd) then
    if state.track_info then stop_all() end

    state.autotrack = false
    state.autoscan = false
    perform_scan(parse_targets(args))
  elseif S{'track','t'}:contains(cmd) then
    if state.track_info then stop_all() end

    state.autotrack = true
    state.autoscan = false
    perform_scan(parse_targets(args))
  elseif S{'set'}:contains(cmd) and #args >= 1 then
    local subcmd = args[1]:lower()
    args:remove(1)

    if S{'delay'}:contains(subcmd) and args[1] then
      local n = tonumber(args[1])
      if not n then
        log("Auto-scan delay must be a number.")
      elseif n < 0 then
        log("Auto-scan delay must be a number greater than 0.")
      else
        log(string.format("Auto-scan delay is now %d.", n))
        settings.autoscan_delay = n
        settings:save()
      end
    elseif S{'random','wiggle','fuzzy'}:contains(subcmd) and args[1] then
      local n = tonumber(args[1])
      if not n then
        log("Auto-scan wiggle must be a number.")
      elseif n < 0 then
        log("Auto-scan wiggle must be a number greater than 0.")
      elseif n >= settings.autoscan_delay then
        log("Auto-scan wiggle must be a number smaller than Auto-scan delay.")
      else
        log(string.format("Auto-scan wiggle is now %d.", n))
        settings.autoscan_random = n
        settings:save()
      end
    elseif S{'sound', 'alert'}:contains(subcmd) then
      if #args >= 1 then 
        local s = args:concat(' ')

        if not windower.file_exists(string.format("%s/sounds/%s.wav", windower.addon_path, s)) then
          log("Sound file does not exist! (sounds must be put in the 'sounds' folder)")
        else
          log(string.format("Alert sound is now %s.", s))
          settings.play_sound = s
          settings:save()
        end
      else
        log("Alert sound is now off.")
        settings.play_sound = nil
        settings:save()
      end
    elseif S{'filter'}:contains(subcmd) then
      if not args[1] then
        settings.filter_map = not settings.filter_map 
      elseif S{'yes','on','enabled','enable','true'}:contains(args[1]) then
        settings.filter_map = true
      elseif S{'no','off','disabled','disable','false'}:contains(args[1]) then
        settings.filter_map = false
      end
      settings:save()
      log(string.format("Filtering on the in-game map is now turned %s.", settings.filter_map and 'on' or 'off'))
    elseif S{'sleep'}:contains(subcmd) and args[1] then
      local n = tonumber(args[1])
      if not n then
        log("Sleep delay must be a number.")
      elseif n < 0 then
        log("Sleep delay must be a number greater than 0.")
      else
        log(string.format("Scanner will now sleep for %d seconds after a track ends.", n))
        settings.find_sleep = n
        settings:save()
      end
    elseif S{'trackinfo'}:contains(subcmd) then
      if not args[1] then
        settings.log_tracking = not settings.log_tracking 
      elseif S{'yes','on','enabled','enable','true'}:contains(args[1]) then
        settings.log_tracking = true
      elseif S{'no','off','disabled','disable','false'}:contains(args[1]) then
        settings.log_tracking = false
      end
      settings:save()
      log(string.format("Logging tracking info is now turned %s.", settings.log_tracking and 'on' or 'off'))
    elseif S{'trackinfodelay'}:contains(subcmd) and args[1] then
      local n = tonumber(args[1])
      if not n then
        log("Tracking log delay must be a number.")
      elseif n < 0 then
        log("Tracking log delay must be a number greater than 0.")
      else
        log(string.format("Tracking log delay is now set to %d seconds.", n))
        settings.log_tracking_delay = n
        settings:save()
      end
    else
      log("Unknown set command. Usable commands: ")
      log("//scanner set delay # - set the autoscan delay to a new positive integer number of seconds.")
      log("//scanner set wiggle # - set the autoscan delay random \"wiggle\" to a new positive integer number of seconds.")
      log("//scanner set sound sound_name - set the sound effect that plays when a target is found. If left empty, no sound will play.")
      log("//scanner set filter [true|false] - set or toggle filtering in the game UI for widescan targets. If empty, it will toggle.")
      log("//scanner set sleep # - set the number of seconds to sleep after a tracked target is lost (to death or manual cancellation).")
      log("//scanner set trackinfo [true|false] - set or toggle logging for tracked target info. If empty, it will toggle.")
      log("//scanner set trackinfodelay # - set the number of seconds to delay between logged tracking info.")
    end
  else
    if not S{'help','h'}:contains(cmd) then
      log('Unknown command. Usable commands: ')
    else
      log('Usable commands: ')
    end
    log('//scanner autoscan ... - Scan periodically for targets by name or index and alert on finding a target.')
    log('//scanner autotrack ... - Scan periodically for targets by name or index and track the closest target.')
    log('//scanner scan ... - Scan once for targets by name or index and alert on finding a target.')
    log('//scanner track ... - Scan for targets by name or index and track the closest target.')
    log('//scanner stop - Cancel auto-scan and tracked mobs.')
    log('//scanner set delay|wiggle|sound|filter|sleep value - Sets a setting value.')
    log('Note: "..." is a space-separated list of search strings. Partial names match and also Index values.')
  end
end)

windower.register_event('zone change',function(new_id)
  stop_all()
end)

windower.register_event('logout',function()
  stop_all()
end)

windower.register_event('unload', function()
  stop_all()
end)