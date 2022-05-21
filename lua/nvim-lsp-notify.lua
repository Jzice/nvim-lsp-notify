local M = {}

local options = {
	debug = false,
	messages = {
		start = 'Initializing...',
		finish = 'Started!',
		report = 'Loading...',
	}
}

local notifications = {}

local function format_err(err)
	local err_lines = {
		'Code: '..err.code,
		'Message:',
		err.message,
		'Data:',
		vim.inspect(err.data)
	}
	return table.concat(err_lines, '\n')
end

local function show_notification(key, title, message, level)
	if notifications[key] ~= nil then
		if notifications[key].close ~= nil then
			notifications[key].close()
		end
		notifications[key] = nil
	end
	local new_notification = vim.notify(message, level, {
		title = title
	})
	if new_notification ~= nil then 
		notifications[key] = new_notification
	end
end

local function on_progress(err, msg, info)

	local key = tostring(info.client_id)
	local lsp_name = vim.lsp.get_client_by_id(info.client_id).name

	if err then
		show_notification(key, lsp_name, format_err(err), vim.log.levels.ERROR)
		return
	end
	
	if options.debug then
		show_notification(key, lsp_name, vim.inspect(msg), vim.log.levels.DEBUG)
		show_notification(key, lsp_name, vim.inspect(info), vim.log.levels.DEBUG)
	end

	local task = msg.token
	local value = msg.value

	if not task then
		return
	end
	
	if value.kind == 'begin' then
		local message = nil
		if value.title then
			message = value.title
		end
		if value.message then
			if message then
				message = message..'\n'
			end
			message = message..value.message
		end
		show_notification(key, lsp_name, message or options.messages.start, vim.log.levels.INFO)
	elseif value.kind == 'report' then
		local message = value.message or options.messages.report
		show_notification(key, lsp_name, message, vim.log.levels.INFO)
	elseif value.kind == 'end' then
		show_notification(key, lsp_name, value.message or options.messages.finish, vim.log.levels.INFO)
	else	
		if value.done then
			show_notification(key, lsp_name, value.message or options.messages.finish, vim.log.levels.INFO)
		else
			show_notification(key, lsp_name, value.message or options.messages.report, vim.log.levels.INFO)
		end
	end
end

local function is_installed()
	return vim.lsp.handlers['$/progress'] == on_progress
end

local client_notifs = {}

local function get_notif_data(client_id, token)
    if not client_notifs[client_id] then
        client_notifs[client_id] = {}
    end

    if not client_notifs[client_id][token] then
        client_notifs[client_id][token] = {}
    end

    return client_notifs[client_id][token]
end

local spinner_frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" }

local function update_spinner(client_id, token)
    local notif_data = get_notif_data(client_id, token)

    if notif_data.spinner then
        local new_spinner = (notif_data.spinner + 1) % #spinner_frames
        notif_data.spinner = new_spinner

        notif_data.notification = vim.notify(nil, nil, {
            hide_from_history = true,
            icon = spinner_frames[new_spinner],
            replace = notif_data.notification,
        })

        vim.defer_fn(function()
            update_spinner(client_id, token)
        end, 100)
    end
end

local function format_title(title, client_name)
    return client_name .. (#title > 0 and ": " .. title or "")
end

local function format_message(message, percentage)
    return (percentage and percentage .. "%\t" or "") .. (message or "")
end

--local function setup_lsp_notify_status()
    -- vim.lsp.handlers["$/progress"] = function(_, result, ctx)
     local function on_progress2(_, result, ctx)
        local client_id = ctx.client_id

        local val = result.value

        if not val.kind then
            return
        end

        local notif_data = get_notif_data(client_id, result.token)

        if val.kind == "begin" then
            local message = format_message(val.message, val.percentage)

            notif_data.notification = vim.notify(message, "info", {
                title = format_title(val.title, vim.lsp.get_client_by_id(client_id).name),
                icon = spinner_frames[1],
                timeout = false,
                hide_from_history = false,
            })

            notif_data.spinner = 1
            update_spinner(client_id, result.token)
        elseif val.kind == "report" and notif_data then
            notif_data.notification = vim.notify(format_message(val.message, val.percentage), "info", {
                replace = notif_data.notification,
                hide_from_history = false,
            })
        elseif val.kind == "end" and notif_data then
            notif_data.notification =
            vim.notify(val.message and format_message(val.message) or "Complete", "info", {
                icon = "",
                replace = notif_data.notification,
                timeout = 3000,
            })

            notif_data.spinner = nil
        end
    end

function M.setup(opts)
	options = vim.tbl_deep_extend('force', options, opts or {})

	if not is_installed() then
		vim.lsp.handlers['$/progress'] = on_progress2
	end

	--setup_lsp_notify_status()
end

return M
