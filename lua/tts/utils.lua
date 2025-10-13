local M = {}

function M.preprocess_text(text)
  local config = require('tts.config').get()
  local preprocessing = config.preprocessing
  
  if not preprocessing or not text then
    return text
  end
  
  -- Clean markdown first (before code cleaning)
  if preprocessing.clean_markdown then
    text = M.clean_markdown_text(text)
  end
  
  -- Apply content filtering based on filtering level
  if preprocessing.filtering_level and preprocessing.filtering_level ~= 'none' then
    local level = preprocessing.filtering_level
    
    -- Always clean paths and URLs for minimal level and above
    if level == 'minimal' or level == 'moderate' or level == 'aggressive' then
      text = M.clean_paths_and_urls(text)
    end
    
    -- Clean smart content for moderate and aggressive levels
    if level == 'moderate' or level == 'aggressive' then
      text = M.clean_smart_content(text)
    end
    
    -- Clean code-specific content for aggressive level
    if level == 'aggressive' then
      local filetype = vim.bo.filetype
      text = M.clean_code_specific_content(text, filetype)
    end
  end
  
  if preprocessing.clean_code then
    text = M.clean_code_text(text)
  end
  
  if preprocessing.expand_abbreviations then
    text = M.expand_abbreviations(text)
  end
  
  if preprocessing.replacements then
    for pattern, replacement in pairs(preprocessing.replacements) do
      text = text:gsub(pattern, replacement)
    end
  end
  
  local filetype = vim.bo.filetype
  if preprocessing.languages and preprocessing.languages[filetype] then
    for pattern, replacement in pairs(preprocessing.languages[filetype]) do
      text = text:gsub(pattern, replacement)
    end
  end
  
  -- Final cleanup
  text = text:gsub('%s+', ' ')  -- Normalize whitespace
  text = text:gsub('^%s*[%-%*%+]%s+', '')  -- Remove leading list markers
  text = text:gsub('%.%s*[%-%*%+]%s+', '. ')  -- Clean up ". -" to ". "
  text = vim.trim(text)
  
  return text
end

function M.clean_markdown_text(text)
  -- Preserve original text for fallback
  local original = text
  
  local config = require('tts.config').get()
  local preprocessing = config.preprocessing
  
  -- Handle code blocks based on configuration
  if preprocessing.skip_code_blocks then
    -- Remove code blocks entirely (default behavior)
    text = text:gsub('```[^\\n]*\\n.-\\n```', ' ')
    text = text:gsub('~~~[^\\n]*\\n.-\\n~~~', ' ')
    text = text:gsub('`([^`]+)`', ' ')
  else
    -- Replace with verbal indicators (for users who want code read)
    text = text:gsub('```[^\\n]*\\n.-\\n```', ' code block ')
    text = text:gsub('~~~[^\\n]*\\n.-\\n~~~', ' code block ')
    text = text:gsub('`([^`]+)`', ' code ')
  end
  
  -- Remove images
  text = text:gsub('!%[.-%]%(.-%)', '')
  
  -- Convert links to just the link text
  text = text:gsub('%[([^%]]+)%]%([^%)]+%)', '%1')
  
  -- Remove reference-style links
  text = text:gsub('%[([^%]]+)%]%[[^%]]*%]', '%1')
  text = text:gsub('^%[[^%]]+%]:%s*.*$', '')
  
  -- Remove HTML tags
  text = text:gsub('<[^>]+>', '')
  
  -- Remove markdown headers (keep the text)
  text = text:gsub('^#+%s*(.-)$', '%1')
  text = text:gsub('\n#+%s*', '\n')
  
  -- Remove horizontal rules
  text = text:gsub('^%-%-%-+%s*$', '')
  text = text:gsub('^%*%*%*+%s*$', '')
  text = text:gsub('^___+%s*$', '')
  
  -- Remove blockquotes
  text = text:gsub('^>+%s*', '')
  text = text:gsub('\n>+%s*', '\n')
  
  -- Remove emphasis markers (bold, italic) - non-greedy matching
  text = text:gsub('%*%*%*(.-)%*%*%*', '%1')  -- Bold + italic
  text = text:gsub('%*%*(.-)%*%*', '%1')  -- Bold  
  text = text:gsub('__(.-)__', '%1')  -- Bold
  text = text:gsub('%*([^%*]+)%*', '%1')  -- Italic (non-greedy)
  text = text:gsub('_([^_]+)_', '%1')  -- Italic (non-greedy)
  text = text:gsub('~~(.-)~~', '%1')  -- Strikethrough
  
  -- Remove list markers but add pauses between items for better speech flow
  text = text:gsub('^%s*[%-%*%+]%s+', '')
  text = text:gsub('\n%s*[%-%*%+]%s+', '. ')  -- Add period for pause between list items
  
  -- Remove numbered list markers and add pauses
  text = text:gsub('^%s*%d+%.%s+', '')
  text = text:gsub('\n%s*%d+%.%s+', '. ')  -- Add period for pause between numbered items
  
  -- Remove task list markers
  text = text:gsub('%[[ x]%]%s*', '')
  
  -- Remove emoji shortcodes
  text = text:gsub(':[%w_%-]+:', '')
  
  -- Clean up URLs but keep surrounding text
  text = text:gsub('https?://[%w%-%._~:/%?#%[%]@!%$&\'%(%)%*%+,;=]+', ' ')
  text = text:gsub('www%.[%w%-%._~:/%?#%[%]@!%$&\'%(%)%*%+,;=]+', ' ')
  text = text:gsub('ftp://[%w%-%._~:/%?#%[%]@!%$&\'%(%)%*%+,;=]+', ' ')
  
  -- Don't remove file paths too aggressively - they might be part of sentences
  -- Only remove obvious ones
  text = text:gsub('%s/[%w%-%._~/]+%.%w+', ' ')  -- Remove paths with extensions
  text = text:gsub('^/[%w%-%._~/]+%.%w+', '')    -- At start of line
  
  -- Final safety check - if we've removed everything, return the original
  if text:match('^%s*$') then
    return original
  end
  
  return text
end

function M.clean_code_text(text)
  -- Remove comments (various languages)
  text = text:gsub('//.-\\n', '\\n')  -- C-style comments
  text = text:gsub('//.-$', '')
  text = text:gsub('/%*.-%*/', ' ')  -- Multi-line C comments
  text = text:gsub('#.-\\n', '\\n')  -- Python/Shell comments
  text = text:gsub('#.-$', '')
  text = text:gsub('%-%-.-\\n', '\\n')  -- Lua comments
  text = text:gsub('%-%-.-$', '')
  text = text:gsub('""".-"""', ' ')  -- Python docstrings
  text = text:gsub("'''.-'''", ' ')

  -- Remove common code syntax
  text = text:gsub('::', ' ')  -- C++ scope resolution
  text = text:gsub('%->', ' ')  -- C pointer access
  text = text:gsub('=>', ' ')  -- Arrow functions
  text = text:gsub('<=', ' less than or equal ')
  text = text:gsub('>=', ' greater than or equal ')
  text = text:gsub('==', ' equals ')
  text = text:gsub('!=', ' not equal ')
  text = text:gsub('&&', ' and ')
  text = text:gsub('||', ' or ')
  text = text:gsub('<<', ' ')  -- Bit shift
  text = text:gsub('>>', ' ')

  -- Remove import/include statements
  text = text:gsub('import%s+[%w%.]+', '')
  text = text:gsub('from%s+[%w%.]+%s+import%s+[%w%.]+', '')
  text = text:gsub('#include%s*[<"].-[>"]', '')
  text = text:gsub('require%(["\'][^"\']+["\']%)', '')

  -- Remove function signatures and type annotations
  text = text:gsub(':%s*[%w%[%]%|%<%>]+%s*[%=%,%)%{]', ' ')  -- Type annotations
  text = text:gsub('function%s*%(.-%)%s*{?', '')
  text = text:gsub('def%s+%w+%s*%(.-%)%s*:', '')

  -- Remove variable declarations
  text = text:gsub('const%s+', '')
  text = text:gsub('let%s+', '')
  text = text:gsub('var%s+', '')
  text = text:gsub('local%s+', '')

  -- Remove special characters used in code
  text = text:gsub(';', '.')  -- Semicolons to periods
  text = text:gsub(':', '.')  -- Colons to periods (except in sentences)
  text = text:gsub('{', '')
  text = text:gsub('}', '')
  text = text:gsub('%[', '')
  text = text:gsub('%]', '')
  text = text:gsub('%(', '')
  text = text:gsub('%)', '')

  return text
end

function M.clean_paths_and_urls(text)
  -- Remove file paths (Unix, Windows, relative) - be very conservative to avoid false positives like "line/paragraph"
  -- Only match paths with extensions or multiple directory separators
  text = text:gsub('[%w%-%._~:/]+/[%w%-%._~:/]+%.%w+', ' file path ')  -- Unix paths with extensions (e.g., path/to/file.txt)
  text = text:gsub('[A-Za-z]:[\\][%w%-%._~:\\]+', ' file path ')  -- Windows paths
  text = text:gsub('[%w%-%._~]+/[%w%-%._~]+/[%w%-%._~]+', ' file path ')  -- Paths with at least 2 slashes (e.g., path/to/dir)
  text = text:gsub('%./[%w%-%._~/]+', ' file path ')  -- Relative paths starting with ./
  text = text:gsub('%.%./[%w%-%._~/]+', ' file path ')  -- Parent paths starting with ../
  
  -- Remove URLs more comprehensively
  text = text:gsub('https?://[%w%-%._~:/?%#[%]@!%$&\'%(%)*%+,;=]+', ' url ')
  text = text:gsub('www%.[%w%-%._~:/?%#[%]@!%$&\'%(%)*%+,;=]+', ' url ')
  text = text:gsub('ftp://[%w%-%._~:/?%#[%]@!%$&\'%(%)*%+,;=]+', ' url ')
  
  -- Remove git references
  text = text:gsub('[%w%-%._]+@{%w+}', ' git reference ')  -- branch@{upstream}
  text = text:gsub('HEAD[~^]%d+', ' git reference ')  -- HEAD~1, HEAD^2
  text = text:gsub('[a-f0-9]{7,40}', ' commit hash ')  -- Git commit hashes
  
  -- Remove network paths
  text = text:gsub('\\\\[%w%-%._$]+\\[%w%-%._$]+', ' network path ')  -- Windows UNC paths
  text = text:gsub('smb://[%w%-%._~:/?%#[%]@!%$&\'%(%)*%+,;=]+', ' network path ')
  
  return text
end

function M.clean_smart_content(text)
  -- Remove UUIDs
  text = text:gsub('[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}', ' uuid ')
  
  -- Remove binary/hex data
  text = text:gsub('0[xX][a-fA-F0-9]+', ' hex value ')
  text = text:gsub('U%+[a-fA-F0-9]{1,6}', ' unicode character ')
  
  -- Remove version numbers and semver
  text = text:gsub('v%d+%.%d+%.%d+', ' version ')
  text = text:gsub('%d+%.%d+%.%d+', ' version ')
  text = text:gsub('[~^]%d+%.%d+%.%d+', ' version range ')
  
  -- Remove hashes and checksums
  text = text:gsub('[a-fA-F0-9]{32,64}', ' hash ')
  
  -- Remove email addresses
  text = text:gsub('[%w%-%._]+@[%w%-%._]+%.%w+', ' email address ')
  
  -- Remove IP addresses
  text = text:gsub('%d+%.%d+%.%d+%.%d+', ' ip address ')
  
  return text
end

function M.clean_code_specific_content(text, filetype)
  if not filetype then
    return text
  end
  
  -- File-specific cleaning
  if filetype == 'javascript' or filetype == 'typescript' then
    -- Remove npm package references
    text = text:gsub('npm%s+install%s+[%w%-%._@/]+', ' package installation ')
    text = text:gsub('require%(["\'][^"\']+["\']%)', ' module import ')
    text = text:gsub('import.*from.*["\'][^"\']+["\']', ' module import ')
    
  elseif filetype == 'python' then
    -- Remove pip references
    text = text:gsub('pip%s+install%s+[%w%-%._=]+', ' package installation ')
    text = text:gsub('from%s+[%w%.]+%s+import', ' import ')
    text = text:gsub('import%s+[%w%.]+', ' import ')
    
  elseif filetype == 'lua' then
    -- Remove Lua-specific patterns
    text = text:gsub('local%s+[%w_]+%s*=', ' variable ')
    text = text:gsub('require%(["\'][^"\']+["\']%)', ' module ')
    
  elseif filetype == 'rust' then
    -- Remove Cargo/crates references
    text = text:gsub('cargo%s+[%w]+', ' cargo command ')
    text = text:gsub('use%s+[%w:]+;', ' import ')
    text = text:gsub('extern%s+crate%s+[%w]+;', ' external crate ')
    
  elseif filetype == 'go' then
    -- Remove Go-specific patterns
    text = text:gsub('go%s+[%w]+', ' go command ')
    text = text:gsub('import%s+%(["\'][^"\']+["\']%)', ' import ')
    
  elseif filetype == 'java' then
    -- Remove Java/Maven references
    text = text:gsub('import%s+[%w%.]+;', ' import ')
    text = text:gsub('package%s+[%w%.]+;', ' package ')
    text = text:gsub('mvn%s+[%w]+', ' maven command ')
  end
  
  return text
end

function M.expand_abbreviations(text)
  local abbreviations = {
    ['e%.g%.'] = 'for example',
    ['i%.e%.'] = 'that is',
    ['etc%.'] = 'etcetera',
    ['vs%.'] = 'versus',
    ['Dr%.'] = 'Doctor',
    ['Mr%.'] = 'Mister',
    ['Mrs%.'] = 'Missus',
    ['Ms%.'] = 'Miss',
    ['Prof%.'] = 'Professor',
    ['Sr%.'] = 'Senior',
    ['Jr%.'] = 'Junior',
  }
  
  for pattern, replacement in pairs(abbreviations) do
    text = text:gsub(pattern, replacement)
  end
  
  return text
end

function M.chunk_text(text, chunk_size)
  chunk_size = chunk_size or 500
  local chunks = {}
  local current_pos = 1
  local text_len = #text
  
  while current_pos <= text_len do
    local chunk_end = math.min(current_pos + chunk_size - 1, text_len)
    
    if chunk_end < text_len then
      local space_pos = text:find('%s', chunk_end)
      if space_pos and space_pos - chunk_end < 50 then
        chunk_end = space_pos - 1
      elseif chunk_end > current_pos then
        for i = chunk_end, current_pos, -1 do
          if text:sub(i, i):match('%s') then
            chunk_end = i - 1
            break
          end
        end
      end
    end
    
    local chunk = text:sub(current_pos, chunk_end)
    table.insert(chunks, vim.trim(chunk))
    current_pos = chunk_end + 1
    
    while current_pos <= text_len and text:sub(current_pos, current_pos):match('%s') do
      current_pos = current_pos + 1
    end
  end
  
  return chunks
end

function M.notify(message, level)
  level = level or vim.log.levels.INFO
  local config = require('tts.config').get().notifications
  
  if level < config.level then
    return
  end
  
  if config.use_notify then
    local ok, notify = pcall(require, 'notify')
    if ok then
      notify(message, level, {
        title = 'TTS',
        timeout = 3000,
        render = 'default'
      })
      return
    end
  end
  
  vim.notify('[TTS] ' .. message, level)
end

function M.progress(message, percentage)
  local config = require('tts.config').get().playback
  
  if not config.show_progress then
    return
  end
  
  if percentage then
    message = string.format('%s (%.0f%%)', message, percentage)
  end
  
  vim.g.tts_progress = message
  vim.cmd('redrawstatus')
end



return M