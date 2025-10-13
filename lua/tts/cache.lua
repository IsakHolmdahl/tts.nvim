local M = {}
local cache_index = {}
local cache_dir = nil

function M.init()
  local config = require('tts.config').get().cache
  
  if not config.enabled then
    return
  end
  
  cache_dir = config.directory
  
  vim.fn.mkdir(cache_dir, 'p')
  
  M.load_index()
  
  if config.cleanup_on_start then
    M.cleanup()
  end
end

function M.get_path(key)
  if not cache_dir then
    M.init()
  end
  return cache_dir .. '/' .. key .. '.audio'
end

function M.get(key)
  if not cache_dir then
    M.init()
  end
  
  local config = require('tts.config').get().cache
  if not config.enabled then
    return nil
  end
  
  local path = M.get_path(key)
  
  if vim.fn.filereadable(path) == 1 then
    cache_index[key] = {
      path = path,
      last_access = os.time(),
      hits = (cache_index[key] and cache_index[key].hits or 0) + 1
    }
    M.save_index()
    return path
  end
  
  return nil
end

function M.set(key, file_path)
  if not cache_dir then
    M.init()
  end
  
  local config = require('tts.config').get().cache
  if not config.enabled then
    return false
  end
  
  local cache_path = M.get_path(key)
  
  if file_path ~= cache_path then
    vim.fn.system('cp ' .. vim.fn.shellescape(file_path) .. ' ' .. vim.fn.shellescape(cache_path))
    if vim.v.shell_error ~= 0 then
      return false
    end
  end
  
  cache_index[key] = {
    path = cache_path,
    created = os.time(),
    last_access = os.time(),
    size = vim.fn.getfsize(cache_path),
    hits = 0
  }
  
  M.save_index()
  M.check_size()
  
  return true
end

function M.remove(key)
  if cache_index[key] then
    local path = cache_index[key].path
    if vim.fn.filereadable(path) == 1 then
      vim.fn.delete(path)
    end
    cache_index[key] = nil
    M.save_index()
    return true
  end
  return false
end

function M.clear()
  if not cache_dir then
    return
  end
  
  for key, entry in pairs(cache_index) do
    if vim.fn.filereadable(entry.path) == 1 then
      vim.fn.delete(entry.path)
    end
  end
  
  cache_index = {}
  M.save_index()
  
  vim.notify('TTS cache cleared', vim.log.levels.INFO)
end

function M.cleanup()
  if not cache_dir then
    M.init()
  end
  
  local config = require('tts.config').get().cache
  local max_age_seconds = config.max_age * 24 * 60 * 60
  local current_time = os.time()
  local removed_count = 0
  
  for key, entry in pairs(cache_index) do
    local age = current_time - (entry.created or entry.last_access or 0)
    
    if age > max_age_seconds then
      if vim.fn.filereadable(entry.path) == 1 then
        vim.fn.delete(entry.path)
      end
      cache_index[key] = nil
      removed_count = removed_count + 1
    elseif vim.fn.filereadable(entry.path) ~= 1 then
      cache_index[key] = nil
      removed_count = removed_count + 1
    end
  end
  
  if removed_count > 0 then
    M.save_index()
    vim.notify(string.format('TTS cache: removed %d old entries', removed_count), vim.log.levels.INFO)
  end
end

function M.check_size()
  local config = require('tts.config').get().cache
  local max_size_bytes = config.max_size * 1024 * 1024
  
  local total_size = 0
  local entries = {}
  
  for key, entry in pairs(cache_index) do
    total_size = total_size + (entry.size or 0)
    table.insert(entries, {
      key = key,
      entry = entry,
      score = (entry.last_access or 0) + (entry.hits or 0) * 3600
    })
  end
  
  if total_size <= max_size_bytes then
    return
  end
  
  table.sort(entries, function(a, b)
    return a.score < b.score
  end)
  
  while total_size > max_size_bytes and #entries > 0 do
    local oldest = table.remove(entries, 1)
    total_size = total_size - (oldest.entry.size or 0)
    M.remove(oldest.key)
  end
end

function M.save_index()
  if not cache_dir then
    return
  end
  
  local index_file = cache_dir .. '/index.json'
  local data = vim.fn.json_encode(cache_index)
  
  local file = io.open(index_file, 'w')
  if file then
    file:write(data)
    file:close()
  end
end

function M.load_index()
  if not cache_dir then
    return
  end
  
  local index_file = cache_dir .. '/index.json'
  
  if vim.fn.filereadable(index_file) == 1 then
    local file = io.open(index_file, 'r')
    if file then
      local data = file:read('*all')
      file:close()
      
      local ok, loaded_index = pcall(vim.fn.json_decode, data)
      if ok and type(loaded_index) == 'table' then
        cache_index = loaded_index
      end
    end
  end
end

function M.get_stats()
  local total_size = 0
  local total_files = 0
  local total_hits = 0
  
  for _, entry in pairs(cache_index) do
    total_size = total_size + (entry.size or 0)
    total_files = total_files + 1
    total_hits = total_hits + (entry.hits or 0)
  end
  
  return {
    total_size = total_size,
    total_size_mb = total_size / (1024 * 1024),
    total_files = total_files,
    total_hits = total_hits,
    directory = cache_dir
  }
end

function M.generate_key(text, opts)
  opts = opts or {}
  
  local key_parts = {
    text:sub(1, 100),
    opts.voice or 'default',
    opts.rate or 'default',
    opts.backend or 'default'
  }
  
  local key_string = table.concat(key_parts, '|')
  
  local hash = 5381
  for i = 1, #key_string do
    hash = ((hash * 33) + string.byte(key_string, i)) % 2147483647
  end
  
  return string.format('%x', hash)
end

return M