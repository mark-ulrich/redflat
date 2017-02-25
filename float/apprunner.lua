-----------------------------------------------------------------------------------------------------------------------
--                                        RedFlat application launcher widget                                        --
-----------------------------------------------------------------------------------------------------------------------
-- Widget with application list and quick search
-- Application list generated by redflat.dfparser
-----------------------------------------------------------------------------------------------------------------------
-- Some code was taken from
------ awful.menubar v3.5.2
------ (c) 2009, 2011-2012 Antonio Terceiro, Alexander Yakushev
-----------------------------------------------------------------------------------------------------------------------

-- Grab environment
-----------------------------------------------------------------------------------------------------------------------
local setmetatable = setmetatable
local type = type

local awful = require("awful")
local beautiful = require("beautiful")
local wibox = require("wibox")

local svgbox = require("redflat.gauge.svgbox")
local dfparser = require("redflat.service.dfparser")
local redutil = require("redflat.util")
local decoration = require("redflat.float.decoration")
local redtip = require("redflat.float.hotkeys")

-- Initialize tables and vars for module
-----------------------------------------------------------------------------------------------------------------------
local apprunner = { applist = {}, command = "" }

local programs = {}
local lastquery = nil

-- key bindings
apprunner.keys = {
	{
		{}, "Down", function() apprunner:down() end,
		{ description = "Select next item", group = "Navigation" }
	},
	{
		{}, "Up", function() apprunner:up() end,
		{ description = "Select previous item", group = "Navigation" }
	},
	{
		{ "Mod4" }, "F1", function() redtip:show() end,
		{ description = "Show hotkeys helper", group = "Help" }
	},
}

-- Generate default theme vars
-----------------------------------------------------------------------------------------------------------------------
local function default_style()
	local style = {
		itemnum          = 5,
		geometry         = { width = 620, height = 520 },
		border_margin    = { 10, 10, 10, 10 },
		title_height     = 48,
		prompt_height    = 35,
		title_icon       = nil,
		icon_margin      = { 8, 12, 0, 0 },
		icon_style       = {},
		list_text_vgap   = 4,
		list_icon_margin = { 6, 12, 6, 6 },
		name_font        = "Sans 12",
		comment_font     = "Sans 12",
		border_width     = 2,
		keytip           = { geometry = { width = 400, height = 300 } },
		dimage           = redutil.placeholder(),
		color            = { border = "#575757", text = "#aaaaaa", highlight = "#eeeeee", main = "#b1222b",
		                     bg = "#161616", bg_second = "#181818", wibox = "#202020", icon = "a0a0a0" }
	}
	return redutil.table.merge(style, redutil.check(beautiful, "float.apprunner") or {})
end

-- Support functions
-----------------------------------------------------------------------------------------------------------------------

-- Fuction to build list item
--------------------------------------------------------------------------------
local function construct_item(style)
	local item = {
		icon    = wibox.widget.imagebox(),
		name    = wibox.widget.textbox(),
		comment = wibox.widget.textbox(),
		bg      = style.color.bg,
		cmd     = ""
	}

	item.name:set_font(style.name_font)
	item.comment:set_font(style.comment_font)

	-- Construct item layouts
	------------------------------------------------------------
	local text_vertical = wibox.layout.align.vertical()
	local text_horizontal = wibox.layout.align.horizontal()
	text_horizontal:set_left(text_vertical)
	text_vertical:set_top(wibox.container.margin(item.name, 0, 0, style.list_text_vgap))
	text_vertical:set_middle(item.comment)

	local item_horizontal  = wibox.layout.align.horizontal()
	item_horizontal:set_left(wibox.container.margin(item.icon, unpack(style.list_icon_margin)))
	item_horizontal:set_middle(text_horizontal)

	item.layout = wibox.container.background(item_horizontal, item.bg)

	-- Item functions
	------------------------------------------------------------
	function item:set(args)
		local args = args or {}

		local name_text = awful.util.escape(args.Name) or ""
		item.name:set_text(name_text)

		local comment_text = args.Comment and awful.util.escape(args.Comment)
		                     or args.Name and "No description"
		                     or ""
		item.comment:set_text(comment_text)

		item.icon:set_image(args.icon_path or style.dimage)
		item.icon:set_visible((args.Name))

		item.cmd = args.cmdline
	end

	function item:set_bg(color)
		item.bg = color
		item.layout:set_bg(color)
	end

	function item:set_select()
		item.layout:set_bg(style.color.main)
		item.layout:set_fg(style.color.highlight)
	end

	function item:set_unselect()
		item.layout:set_bg(item.bg)
		item.layout:set_fg(style.color.text)
	end

	function item:run()
		awful.spawn(item.cmd)
	end

	------------------------------------------------------------
	return item
end

-- Fuction to build application list
--------------------------------------------------------------------------------
local function construct_list(num, progs, style)
	local list = { selected = 1, position = 1 }

	-- Construct application list
	------------------------------------------------------------
	local list_layout = wibox.layout.flex.vertical()
	list.layout = wibox.container.background(list_layout, style.color.bg)

	list.items = {}
	for i = 1, num do
		list.items[i] = construct_item(style)
		list.items[i]:set_bg((i % 2) == 1 and style.color.bg or style.color.bg_second)
		list_layout:add(list.items[i].layout)
	end

	-- Application list functions
	------------------------------------------------------------
	function list:set_select(index)
		list.items[list.selected]:set_unselect()
		list.selected = index
		list.items[list.selected]:set_select()
	end

	function list:update(t)
		for i = list.position, (list.position - 1 + num) do list.items[i - list.position + 1]:set(t[i]) end
		list:set_select(list.selected)
	end

	-- First run actions
	------------------------------------------------------------
	list:update(progs)
	list:set_select(1)

	------------------------------------------------------------
	return list
end

-- Sort function
--------------------------------------------------------------------------------
local function sort_by_query(t, query)
	l = string.len(query)
	local function s(a, b)
		return string.lower(string.sub(a.Name, 1, l)) == query and string.lower(string.sub(b.Name, 1, l)) ~= query
	end
	table.sort(t, s)
end

-- Function to filter application list by quick search input
--------------------------------------------------------------------------------
local function list_filtrate(query)
	if lastquery ~= query then
		programs.current = {}

		for i, p in ipairs(programs.all) do
			if string.match(string.lower(p.Name), query) then
				table.insert(programs.current, p)
			end
		end

		sort_by_query(programs.current, query)

		apprunner.applist.position = 1
		apprunner.applist:update(programs.current)
		apprunner.applist:set_select(1)
		lastquery = query
	end
end

-- Functions to navigate through application list
-----------------------------------------------------------------------------------------------------------------------
function apprunner:down()
	if self.applist.selected < math.min(self.itemnum, #programs.current) then
		self.applist:set_select(self.applist.selected + 1)
	elseif self.applist.selected + self.applist.position - 1 < #programs.current then
		self.applist.position = self.applist.position + 1
		self.applist:update(programs.current)
	end
end

function apprunner:up()
	if self.applist.selected > 1 then
		self.applist:set_select(self.applist.selected - 1)
	elseif self.applist.position > 1 then
		self.applist.position = self.applist.position - 1
		self.applist:update(programs.current)
	end
end

-- Keypress handler
-----------------------------------------------------------------------------------------------------------------------
local function keypressed_callback(mod, key, comm)
	for _, k in ipairs(apprunner.keys) do
		if redutil.key.match_prompt(k, mod, key) then k[3](); return true end
	end
	return false
end

-- Initialize apprunner widget
-----------------------------------------------------------------------------------------------------------------------
function apprunner:init()

	-- Initialize vars
	--------------------------------------------------------------------------------
	local style = default_style()
	self.itemnum = style.itemnum
	self.keytip = style.keytip

	-- get full application list
	programs.all = dfparser.program_list(style.icon_style)
	programs.current = awful.util.table.clone(programs.all)

	-- Create quick search widget
	--------------------------------------------------------------------------------
	self.textbox = wibox.widget.textbox()
	self.textbox:set_ellipsize("start")
	self.decorated_widget = decoration.textfield(self.textbox, style.field)

	-- Build application list
	--------------------------------------------------------------------------------
	self.applist = construct_list(apprunner.itemnum, programs.current, style)

	-- Construct widget layouts
	--------------------------------------------------------------------------------
	local prompt_width = style.geometry.width - 2 * style.border_margin[1]
	                     - style.title_height - style.icon_margin[1] - style.icon_margin[2]
	local prompt_layout = wibox.container.constraint(self.decorated_widget, "exact", prompt_width, style.prompt_height)

	local prompt_vertical = wibox.layout.align.vertical()
	prompt_vertical:set_expand("outside")
	prompt_vertical:set_middle(prompt_layout)

	local prompt_area_horizontal = wibox.layout.align.horizontal()
	local title_image = svgbox(style.title_icon)
	title_image:set_color(style.color.icon)
	prompt_area_horizontal:set_left(wibox.container.margin(title_image, unpack(style.icon_margin)))
	prompt_area_horizontal:set_right(prompt_vertical)

	local prompt_area_layout = wibox.container.constraint(prompt_area_horizontal, "exact", nil, style.title_height)

	area_vertical = wibox.layout.align.vertical()
	area_vertical:set_top(prompt_area_layout)
	area_vertical:set_middle(wibox.container.margin(self.applist.layout, 0, 0, style.border_margin[3]))
	local area_layout = wibox.container.margin(area_vertical, unpack(style.border_margin))

	-- Create floating wibox for apprunner widget
	--------------------------------------------------------------------------------
	self.wibox = wibox({
		ontop        = true,
		bg           = style.color.wibox,
		border_width = style.border_width,
		border_color = style.color.border
	})

	self.wibox:set_widget(area_layout)
	self.wibox:geometry(style.geometry)
end

-- Show apprunner widget
-- Wibox appears on call and hides after "enter" or "esc" pressed
-----------------------------------------------------------------------------------------------------------------------
function apprunner:show()
	if not self.wibox then
		self:init()
	else
		list_filtrate("")
		self.applist:set_select(1)
	end

	redutil.placement.centered(self.wibox, nil, mouse.screen.workarea)
	self.wibox.visible = true
	redtip:set_pack("Apprunner widget", self.keys, self.keytip.column, self.keytip.geometry)

	return awful.prompt.run({
		prompt = "",
		textbox = self.textbox,
		exe_callback = function () self.applist.items[self.applist.selected]:run() end,
		done_callback = function () self:hide() end,
		keypressed_callback = keypressed_callback,
		changed_callback = list_filtrate,
	})
end

function apprunner:hide()
	self.wibox.visible = false
	redtip:remove_pack()
end

-- Set user hotkeys
-----------------------------------------------------------------------------------------------------------------------
function apprunner:set_keys(keys)
	self.keys = keys
end

-- End
-----------------------------------------------------------------------------------------------------------------------
return apprunner
