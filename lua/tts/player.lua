local M = {}
local current_job = nil
local current_player = nil
local DEBUG = true

local function debug_log(msg)
	if DEBUG then
		vim.notify('[TTS DEBUG] ' .. msg, vim.log.levels.DEBUG)
	end
end

local function detect_player()
	local config = require('tts.config').get().playback

	if config.player ~= 'auto' then
		if vim.fn.executable(config.player) == 1 then
			debug_log('detect_player: using configured player "' .. config.player .. '"')
			return config.player
		else
			debug_log('detect_player: configured player "' .. config.player .. '" not executable')
		end
	end

	local players = { 'afplay', 'mpv', 'ffplay', 'play' }

	for _, player in ipairs(players) do
		if vim.fn.executable(player) == 1 then
			debug_log('detect_player: auto-detected player "' .. player .. '"')
			return player
		end
	end

	debug_log('detect_player: no player found')
	return nil
end

function M.play(audio_source, opts)
	opts = opts or {}
	local state = require('tts.state')

	debug_log('M.play called with: ' .. vim.inspect({audio_source = audio_source, opts = opts}))
	debug_log('Current state: ' .. state.get_state() .. ', can_play: ' .. tostring(state.can_play()))

	if not state.can_play() and not opts.force then
		debug_log('Cannot play, calling stop()')
		M.stop()
	end

	local player = detect_player()
	if not player then
		debug_log('M.play: NO PLAYER DETECTED - returning nil')
		vim.notify('TTS: No audio player found (tried afplay, mpv, ffplay, play)', vim.log.levels.ERROR)
		return nil
	end

	current_player = player
	debug_log('M.play: using player "' .. player .. '"')

	if player == 'afplay' then
		return M._play_with_afplay(audio_source, opts)
	elseif player == 'mpv' then
		return M._play_with_mpv(audio_source, opts)
	elseif player == 'ffplay' then
		return M._play_with_ffplay(audio_source, opts)
	elseif player == 'play' then
		return M._play_with_sox(audio_source, opts)
	end
end

function M._play_with_afplay(file, opts)
	local args = { file }

	if opts.volume then
		table.insert(args, '-v')
		table.insert(args, tostring(opts.volume))
	end

	debug_log('_play_with_afplay: spawning afplay with args: ' .. vim.inspect(args))

	current_job = vim.loop.spawn('afplay', {
		args = args
	}, function(code)
		debug_log('_play_with_afplay: on_exit callback, code=' .. code)
		current_job = nil
		vim.schedule(function()
			if code == 0 then
				local state = require('tts.state')
				state.transition('idle')
				debug_log('_play_with_afplay: playback completed successfully, state -> idle')
			else
				debug_log('_play_with_afplay: playback failed with code=' .. code)
			end
			if opts.on_complete then
				opts.on_complete(code)
			end
		end)
	end)

	if current_job then
		debug_log('_play_with_afplay: SUCCESS - job spawned')
	else
		debug_log('_play_with_afplay: FAILED - job is nil, spawn returned nothing')
	end

	return {
		stop = function()
			M.stop()
		end
	}
end

function M._play_with_mpv(file, opts)
	local args = {
		'--no-video',
		'--no-terminal',
		'--force-window=no'
	}

	if opts.volume then
		table.insert(args, '--volume=' .. tostring(opts.volume * 100))
	end

	if opts.speed then
		table.insert(args, '--speed=' .. tostring(opts.speed))
	end

	table.insert(args, file)

	debug_log('_play_with_mpv: spawning mpv with args: ' .. vim.inspect(args))

	current_job = vim.loop.spawn('mpv', {
		args = args
	}, function(code)
		debug_log('_play_with_mpv: on_exit callback, code=' .. code)
		current_job = nil
		vim.schedule(function()
			if code == 0 then
				local state = require('tts.state')
				state.transition('idle')
				debug_log('_play_with_mpv: playback completed successfully, state -> idle')
			else
				debug_log('_play_with_mpv: playback failed with code=' .. code)
			end
			if opts.on_complete then
				opts.on_complete(code)
			end
		end)
	end)

	if current_job then
		debug_log('_play_with_mpv: SUCCESS - job spawned')
	else
		debug_log('_play_with_mpv: FAILED - job is nil, spawn returned nothing')
	end

	return {
		stop = function()
			M.stop()
		end
	}
end

function M._play_with_ffplay(file, opts)
	local args = {
		'-nodisp',
		'-autoexit',
		'-loglevel', 'quiet'
	}

	if opts.volume then
		table.insert(args, '-volume')
		table.insert(args, tostring(math.floor(opts.volume * 100)))
	end

	table.insert(args, file)

	debug_log('_play_with_ffplay: spawning ffplay with args: ' .. vim.inspect(args))

	current_job = vim.loop.spawn('ffplay', {
		args = args
	}, function(code)
		debug_log('_play_with_ffplay: on_exit callback, code=' .. code)
		current_job = nil
		vim.schedule(function()
			if code == 0 then
				local state = require('tts.state')
				state.transition('idle')
				debug_log('_play_with_ffplay: playback completed successfully, state -> idle')
			else
				debug_log('_play_with_ffplay: playback failed with code=' .. code)
			end
			if opts.on_complete then
				opts.on_complete(code)
			end
		end)
	end)

	if current_job then
		debug_log('_play_with_ffplay: SUCCESS - job spawned')
	else
		debug_log('_play_with_ffplay: FAILED - job is nil, spawn returned nothing')
	end

	return {
		stop = function()
			M.stop()
		end
	}
end

function M._play_with_sox(file, opts)
	local args = { file }

	if opts.volume then
		table.insert(args, 'vol')
		table.insert(args, tostring(opts.volume))
	end

	debug_log('_play_with_sox: spawning play(sox) with args: ' .. vim.inspect(args))

	current_job = vim.loop.spawn('play', {
		args = args
	}, function(code)
		debug_log('_play_with_sox: on_exit callback, code=' .. code)
		current_job = nil
		vim.schedule(function()
			if code == 0 then
				local state = require('tts.state')
				state.transition('idle')
				debug_log('_play_with_sox: playback completed successfully, state -> idle')
			else
				debug_log('_play_with_sox: playback failed with code=' .. code)
			end
			if opts.on_complete then
				opts.on_complete(code)
			end
		end)
	end)

	if current_job then
		debug_log('_play_with_sox: SUCCESS - job spawned')
	else
		debug_log('_play_with_sox: FAILED - job is nil, spawn returned nothing')
	end

	return {
		stop = function()
			M.stop()
		end
	}
end



function M.stop()
	if current_job then
		if not current_job:is_closing() then
			current_job:kill('sigterm')
		end
		current_job = nil
	end

	local state = require('tts.state')
	state.transition('stopped')

	return true
end

function M.is_playing()
	return current_job ~= nil
end

function M.get_current_player()
	return current_player
end

return M

