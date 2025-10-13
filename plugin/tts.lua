if vim.g.loaded_tts then
	return
end
vim.g.loaded_tts = true

if vim.fn.has('nvim-0.7') ~= 1 then
	vim.api.nvim_err_writeln('tts.nvim requires Neovim 0.7+')
	return
end

local function setup_lazy_loading()
	local tts_loaded = false

	local function ensure_loaded()
		if not tts_loaded then
			require('tts')
			tts_loaded = true
		end
	end

	local commands = {
		'TTS',
		'TTSPlay',
		'TTSStop',

		'TTSQueue',
		'TTSClear',
		'TTSNext',
		'TTSPrev',
		'TTSBackend',
		'TTSVoices',
		'TTSSetVoice',
		'TTSClearCache',
		'TTSMotion'
	}

	for _, cmd in ipairs(commands) do
		vim.api.nvim_create_user_command(cmd, function(...)
			ensure_loaded()
			vim.cmd(cmd .. ' ' .. (... and (...).args or ''))
		end, { nargs = '*', range = true })
	end
end

setup_lazy_loading()

