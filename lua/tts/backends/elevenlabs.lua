local M = {}

function M.is_available()
	local config = require("tts.config").get()

	-- API key is optional for custom endpoints
	local api_url = (config.elevenlabs.api_url or "https://api.elevenlabs.io/v1/text-to-speech/")
		+ config.elevenlabs.voide_id
	if api_url:match("api%.elevenlabs%.io") then
		if not config.elevenlabs.api_key or config.elevenlabs.api_key == "" then
			-- Only log error for elevenlabs's official API
			vim.schedule(function()
				vim.notify("TTS: Eleven labs API key required for api.elevenlabs.com", vim.log.levels.ERROR)
			end)
			return false
		end
	end

	-- Check if curl is available
	if vim.fn.executable("curl") ~= 1 then
		vim.schedule(function()
			vim.notify("TTS: curl not found (required for Eleven labs backend)", vim.log.levels.ERROR)
		end)
		return false
	end

	-- Check for at least one audio player
	local players = { "afplay", "ffplay", "mpv", "mplayer", "cvlc", "vlc", "play" }
	for _, player in ipairs(players) do
		if vim.fn.executable(player) == 1 then
			return true
		end
	end

	vim.schedule(function()
		vim.notify("TTS: No audio player found. Install ffplay, mpv, or afplay", vim.log.levels.ERROR)
	end)
	return false
end

function M.speak(text, opts)
	opts = opts or {}
	local config = require("tts.config").get().elevenlabs

	-- Validate input text
	if not text or text == "" or text:match("^%s*$") then
		vim.schedule(function()
			vim.notify("TTS: No text to speak", vim.log.levels.WARN)
		end)
		return nil
	end

	-- Stop any current playback
	M.stop()

	-- Create temp file for audio
	local temp_file = vim.fn.tempname() .. "." .. (config.format or "mp3")

	-- Build the API request
	local api_url = (config.elevenlabs.api_url or "https://api.elevenlabs.io/v1/text-to-speech/")
		+ config.elevenlabs.voice_id
		+ "?output_format="
		+ (config.format or "mp3_44100_128")

	-- Build headers
	local headers = {
		["xi-api-key"] = config.api_key or "",
		["Content-Type"] = "application/json",
	}

	-- Merge with custom headers
	headers = vim.tbl_extend("force", headers, config.headers or {})

	local data = {
		model_id = config.model or "eleven_multilingual_v2",
		text = text,
		voice_settings = {
			speed = config.speed or 1.0,
			stability = config.stability or 0.5,
			similarity_boost = config.similarity_boost or 0.75,
			style = config.style or 0.0,
			use_speaker_boost = config.use_speaker_boost == nil and true or config.use_speaker_boost,
		},
	}

	-- Build curl command
	local curl_cmd = { "curl", "-s", "-X", "POST", api_url }

	-- Add headers
	for key, value in pairs(headers) do
		table.insert(curl_cmd, "-H")
		table.insert(curl_cmd, key .. ": " .. value)
	end

	-- Add data
	table.insert(curl_cmd, "-d")
	table.insert(curl_cmd, vim.fn.json_encode(data))

	-- Output to file
	table.insert(curl_cmd, "-o")
	table.insert(curl_cmd, temp_file)

	-- Add timeout
	if config.timeout then
		table.insert(curl_cmd, "--max-time")
		table.insert(curl_cmd, tostring(config.timeout))
	end

	-- Debug: Log the curl command for troubleshooting
	-- vim.notify('Debug curl: ' .. table.concat(curl_cmd, ' '), vim.log.levels.DEBUG)

	-- Make the API request
	local stderr_data = {}
	local stdout_data = {}
	local request_job = vim.fn.jobstart(curl_cmd, {
		on_stdout = function(_, data)
			if data and #data > 0 then
				vim.list_extend(stdout_data, data)
			end
		end,
		on_stderr = function(_, data)
			if data and #data > 0 then
				vim.list_extend(stderr_data, data)
			end
		end,
		on_exit = function(_, exit_code)
			if exit_code ~= 0 then
				local error_msg = table.concat(stderr_data, "\n")
				local stdout_msg = table.concat(stdout_data, "\n")
				vim.schedule(function()
					if error_msg ~= "" then
						vim.notify("TTS API error: " .. error_msg, vim.log.levels.ERROR)
					elseif stdout_msg ~= "" then
						vim.notify("TTS API response: " .. stdout_msg, vim.log.levels.ERROR)
					else
						vim.notify("TTS API failed with exit code: " .. exit_code, vim.log.levels.ERROR)
					end
				end)
				vim.fn.delete(temp_file)
				return
			end

			-- Check if file was created and has content
			local file_size = vim.fn.getfsize(temp_file)
			if vim.fn.filereadable(temp_file) ~= 1 or file_size <= 0 then
				vim.schedule(function()
					vim.notify("TTS API returned no audio data", vim.log.levels.ERROR)
				end)
				vim.fn.delete(temp_file)
				return
			end

			-- Check if response might be JSON error (small file)
			if file_size < 1000 then
				local content = vim.fn.readfile(temp_file)
				local content_str = table.concat(content, "\n")
				if content_str:match("^{") then
					-- Parse and show only actual API errors
					local ok, json = pcall(vim.fn.json_decode, content_str)
					if ok and json.error then
						vim.schedule(function()
							vim.notify("TTS API error: " .. (json.error.message or json.error), vim.log.levels.ERROR)
						end)
					end
					vim.fn.delete(temp_file)
					return
				end
			end

			-- Play the audio file
			M._play_audio(temp_file)
		end,
	})

	return request_job
end

function M._play_audio(file)
	if not file or vim.fn.filereadable(file) ~= 1 then
		return
	end

	local player = require("tts.player")
	local handle = player.play(file, {
		on_complete = function()
			vim.defer_fn(function()
				vim.fn.delete(file)
			end, 100)

			vim.api.nvim_exec_autocmds("User", {
				pattern = "TTSPlayEnd",
				data = { backend = "elevenlabs" },
			})
		end,
	})

	if not handle then
		vim.fn.delete(file)
	end
end

function M.stop()
	local player = require("tts.player")
	player.stop()
end

function M.list_voices()
	return {
		{ name = "Denzel", language = "en", note = "Jamaican" },
	}
end

return M

