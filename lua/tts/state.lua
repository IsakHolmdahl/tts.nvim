local M = {}

local State = {
  IDLE = 'idle',
  PLAYING = 'playing',
  STOPPED = 'stopped',
  ERROR = 'error'
}

M.State = State

local state = {
  current = State.IDLE,
  previous = nil,
  data = {}
}

local transitions = {
  [State.IDLE] = { State.PLAYING },
  [State.PLAYING] = { State.STOPPED, State.ERROR, State.IDLE },
  [State.STOPPED] = { State.IDLE, State.PLAYING },
  [State.ERROR] = { State.IDLE }
}

local DEBUG = true

local function debug_log(msg)
  if DEBUG then
    vim.notify('[TTS DEBUG] ' .. msg, vim.log.levels.DEBUG)
  end
end

function M.transition(new_state, data)
  if not transitions[state.current] then
    transitions[state.current] = {}
  end
  
  local allowed = transitions[state.current]
  local old_state = state.current
  
  if not vim.tbl_contains(allowed, new_state) then
    debug_log('state.transition: BLOCKED - cannot go from "' .. old_state .. '" to "' .. new_state .. '" (allowed: ' .. vim.inspect(allowed) .. ')')
    return false
  end
  
  state.previous = state.current
  state.current = new_state
  state.data = data or {}
  
  debug_log('state.transition: ' .. old_state .. ' -> ' .. new_state)
  
  M._on_state_change(state.current, state.previous)
  
  return true
end

function M._on_state_change(new_state, old_state)
  local config = require('tts.config').get()
  local hooks = config.hooks
  
  if hooks and hooks.on_state_change then
    local ok, err = pcall(hooks.on_state_change, new_state, old_state)
    if not ok then
      vim.notify('TTS: Error in on_state_change hook: ' .. tostring(err), vim.log.levels.ERROR)
    end
  end
end

function M.get_state()
  return state.current
end

function M.get_data()
  return vim.deepcopy(state.data)
end

function M.is_playing()
  return state.current == State.PLAYING
end

function M.can_play()
  return state.current == State.IDLE or state.current == State.STOPPED
end

function M.reset()
  state.current = State.IDLE
  state.previous = nil
  state.data = {}
end

return M