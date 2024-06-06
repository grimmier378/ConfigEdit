--[[
	Title: Config GUI Script
	Author: Grimmier
	Includes: ImGui, MacroQuest
	Description: GUI for dynamically loading and editing Lua config files.
]]

-- Load Libraries
local mq = require('mq')
local ImGui = require('ImGui')
local LoadTheme = require('lib.theme_loader')
local Icon = require('mq.ICONS')
local lfs = require('lfs')

-- Variables
local script = 'ConfigEditor' -- Change this to the name of your script
local meName -- Character Name
local themeName = 'Default'
local gIcon = Icon.MD_SETTINGS -- Gear Icon for Settings
local themeID = 1
local theme, defaults, settings = {}, {}, {}
local RUNNING = true
local showMainGUI, showConfigGUI = true, false
local scale = 1
local aSize, locked, hasThemeZ = false, false, false
local configData = {}
local configFilePath = string.format('%s/', mq.configDir) -- Default config folder path prefix
local currentDirectory = mq.configDir
local selectedFile = nil

-- GUI Settings
local winFlags = bit32.bor(ImGuiWindowFlags.None)

-- File Paths
local themeFile = string.format('%s/MyUI/MyThemeZ.lua', mq.configDir)
local defaultConfigFile = string.format('%s/MyUI/%s/%s_Configs.lua', mq.configDir, script, script)
local themezDir = mq.luaDir .. '/themez/init.lua'

-- Default Settings
defaults = {
	Scale = 1.0,
	LoadTheme = 'Default',
	locked = false,
	AutoSize = false,
}

local function File_Exists(name)
	local f = io.open(name, "r")
	if f ~= nil then io.close(f) return true else return false end
end

local function loadTheme()
	if File_Exists(themeFile) then
		theme = dofile(themeFile)
	else
		theme = require('themes')
		mq.pickle(themeFile, theme)
	end
	themeName = settings[script].LoadTheme or 'Default'
	if theme and theme.Theme then
		for tID, tData in pairs(theme.Theme) do
			if tData['Name'] == themeName then
				themeID = tID
			end
		end
	end
end

local function loadSettings()
	local newSetting = false
	if not File_Exists(defaultConfigFile) then
		settings[script] = defaults
		mq.pickle(defaultConfigFile, settings)
		loadSettings()
	else
		settings = dofile(defaultConfigFile)
		if settings[script] == nil then
			settings[script] = {}
			settings[script] = defaults
			newSetting = true
		end
	end
	if settings[script].locked == nil then
		settings[script].locked = false
		newSetting = true
	end
	if settings[script].Scale == nil then
		settings[script].Scale = 1
		newSetting = true
	end
	if not settings[script].LoadTheme then
		settings[script].LoadTheme = 'Default'
		newSetting = true
	end
	if settings[script].AutoSize == nil then
		settings[script].AutoSize = aSize
		newSetting = true
	end
	loadTheme()
	aSize = settings[script].AutoSize
	locked = settings[script].locked
	scale = settings[script].Scale
	themeName = settings[script].LoadTheme
	if newSetting then mq.pickle(defaultConfigFile, settings) end
end

local function loadConfig()
	if File_Exists(configFilePath) then
		configData = dofile(configFilePath)
	else
		configData = {}
		mq.pickle(configFilePath, configData)
	end
end

local function saveConfig()
	mq.pickle(configFilePath, configData)
end

local function valueToString(value)
	if type(value) == "function" then
		return "function() return true end"
	elseif type(value) == "table" then
		return "Table"
	else
		return tostring(value)
	end
end

local function drawKeyValueSection(section, data)
	for key, value in pairs(data) do
		if type(value) == "table" then
			drawSection(key, value)
		else
			ImGui.Text(key)
			ImGui.SameLine()
			ImGui.PushItemWidth(-1)
			local valueStr = valueToString(value)
			if ImGui.InputText("##"..key, valueStr, 100) then
				data[key] = valueStr
			end
			ImGui.PopItemWidth()
		end
	end
end

local function drawTableSection(section, data)
	ImGui.Columns(3, "table_columns", true)
	for i, item in ipairs(data) do
		ImGui.Text(tostring(i))
		ImGui.NextColumn()
		ImGui.PushItemWidth(-1)
		local itemValue = valueToString(item)
		if ImGui.InputText("##item"..i, itemValue, 100) then
			data[i] = itemValue
		end
		ImGui.PopItemWidth()
		ImGui.NextColumn()
		if ImGui.Button("Remove##"..i) then
			table.remove(data, i)
		end
		ImGui.NextColumn()
	end
	ImGui.Columns(1)
	if ImGui.Button("Add Item##"..section) then
		table.insert(data, "")
	end
end

local function drawNestedSection(data)
	for key, value in pairs(data) do
		if type(value) == "table" then
			drawSection(key, value)
		else
			drawKeyValueSection(key, { [key] = value })
		end
	end
end

function drawSection(section, data)
	if type(section) ~= "string" then
		section = tostring(section)
	end
	if ImGui.CollapsingHeader(section) then
		ImGui.Separator()
		ImGui.BeginChild("Child_"..section, ImVec2(0, 0), true, ImGuiWindowFlags.Border)
		if type(data) == "table" then
			if next(data) ~= nil and type(next(data)) == "number" then
				drawTableSection(section, data)
			else
				drawNestedSection(data)
			end
		end
		ImGui.EndChild()
		ImGui.Separator()
	end
end

local function drawGeneralSection(data)
	if ImGui.CollapsingHeader("General") then
		ImGui.Separator()
		ImGui.BeginChild("Child_General", ImVec2(0, 0), true, ImGuiWindowFlags.Border)
		drawKeyValueSection("General", data)
		ImGui.EndChild()
		ImGui.Separator()
	end
end

local function drawConfigGUI()
	local generalData = {}
	for key, value in pairs(configData) do
		if type(value) == "function" then
			generalData[key] = tostring(value)
		elseif type(value) == "table" then
			drawSection(key, value)
		else
			generalData[key] = value
		end
	end
	if next(generalData) ~= nil then
		drawGeneralSection(generalData)
	end
	if ImGui.Button("Save Config") then
		saveConfig()
	end
end

local function getDirectoryContents(path)
	local folders = {}
	local files = {}
	for file in lfs.dir(path) do
		if file ~= "." and file ~= ".." then
			local f = path .. '/' .. file
			local attr = lfs.attributes(f)
			if attr.mode == "directory" then
				table.insert(folders, file)
			elseif attr.mode == "file" and file:match("%.lua$") then
				table.insert(files, file)
			end
		end
	end
	return folders, files
end

local function drawFileSelector()
	local folders, files = getDirectoryContents(currentDirectory)

	ImGui.Text("Current Directory: " .. currentDirectory)
	if currentDirectory ~= mq.configDir and ImGui.Button("Back") then
		currentDirectory = currentDirectory:match("(.*)/[^/]+$")
	end

	if ImGui.BeginCombo("Folders", "Select a folder") then
		for _, folder in ipairs(folders) do
			if ImGui.Selectable(folder) then
				currentDirectory = currentDirectory .. '/' .. folder
			end
		end
		ImGui.EndCombo()
	end

	if ImGui.BeginCombo("Files", "Select a file") then
		for _, file in ipairs(files) do
			if ImGui.Selectable(file) then
				selectedFile = file
				configFilePath = currentDirectory .. '/' .. selectedFile
				loadConfig()
			end
		end
		ImGui.EndCombo()
	end
end

local function Draw_GUI()
	if showMainGUI then
		local winName = string.format('%s##Main_%s', script, meName)
		local ColorCount, StyleCount = LoadTheme.StartTheme(theme.Theme[themeID])
		local openMain, showMain = ImGui.Begin(winName, true, winFlags)
		if not openMain then
			showMainGUI = false
		end
		if showMain then
			ImGui.SetWindowFontScale(scale)
			ImGui.Text(gIcon)
			if ImGui.IsItemHovered() then
				ImGui.SetTooltip("Settings")
				if ImGui.IsMouseReleased(0) then
					showConfigGUI = not showConfigGUI
				end
			end
			ImGui.Text("Config File: " .. (configFilePath or "None"))
			drawFileSelector()
			if configFilePath and configFilePath ~= "" then
				drawConfigGUI()
			end
			ImGui.Text("Hello World")
			lIcon = locked and Icon.FA_LOCK or Icon.FA_UNLOCK
			if ImGui.Button(lIcon) then
				locked = not locked
			end
			ImGui.SameLine()
			rIcon = aSize and Icon.FA_EXPAND or Icon.FA_COMPRESS
			if ImGui.Button(rIcon) then
				aSize = not aSize
			end
			local txtLocked = locked and "Unlock Window" or "Lock Window"
			ImGui.Text(txtLocked)
			ImGui.SameLine()
			local txtAutoSize = aSize and "Disable Auto Size" or "Enable Auto Size"
			ImGui.Text(txtAutoSize)
			ImGui.SetWindowFontScale(1)
		end
		LoadTheme.EndTheme(ColorCount, StyleCount)
		ImGui.End()
	end
	if showConfigGUI then
		local winName = string.format('%s Config##Config_%s', script, meName)
		local ColCntConf, StyCntConf = LoadTheme.StartTheme(theme.Theme[themeID])
		local openConfig, showConfig = ImGui.Begin(winName, true, bit32.bor(ImGuiWindowFlags.NoCollapse, ImGuiWindowFlags.AlwaysAutoResize))
		if not openConfig then
			showConfigGUI = false
		end
		if showConfig then
			ImGui.SeparatorText("Config Editor Settings")
			ImGui.SeparatorText("Theme##"..script)
			ImGui.Text("Cur Theme: %s", themeName)
			if ImGui.BeginCombo("Load Theme##"..script, themeName) then
				for k, data in pairs(theme.Theme) do
					local isSelected = data.Name == themeName
					if ImGui.Selectable(data.Name, isSelected) then
						theme.LoadTheme = data.Name
						themeID = k
						themeName = theme.LoadTheme
					end
				end
				ImGui.EndCombo()
			end
			scale = ImGui.SliderFloat("Scale##"..script, scale, 0.5, 2)
			if scale ~= settings[script].Scale then
				if scale < 0.5 then scale = 0.5 end
				if scale > 2 then scale = 2 end
			end
			if hasThemeZ then
				if ImGui.Button('Edit ThemeZ') then
					mq.cmd("/lua run themez")
				end
				ImGui.SameLine()
			end
			if ImGui.Button('Reload Theme File') then
				loadTheme()
			end
			if ImGui.Button("Save & Close") then
				settings = dofile(defaultConfigFile)
				settings[script].Scale = scale
				settings[script].LoadTheme = themeName
				mq.pickle(defaultConfigFile, settings)
				showConfigGUI = false
			end
		end
		LoadTheme.EndTheme(ColCntConf, StyCntConf)
		ImGui.End()
	end
end

local function Init()
	loadSettings()
	meName = mq.TLO.Me.Name()
	if File_Exists(themezDir) then
		hasThemeZ = true
	end
	mq.imgui.init('ConfigEdit', Draw_GUI)
end

local function Loop()
	while RUNNING do
		RUNNING = showMainGUI
		if mq.TLO.EverQuest.GameState() ~= "INGAME" then 
			printf("\aw[\at%s\ax] \arNot in game, \ayTry again later...", script) 
			mq.exit() 
		end
		winFlags = locked and bit32.bor(ImGuiWindowFlags.NoMove) or bit32.bor(ImGuiWindowFlags.None)
		winFlags = aSize and bit32.bor(winFlags, ImGuiWindowFlags.AlwaysAutoResize) or winFlags
		mq.delay(1000)
	end
end

if mq.TLO.EverQuest.GameState() ~= "INGAME" then 
	printf("\aw[\at%s\ax] \arNot in game, \ayTry again later...", script) 
	mq.exit() 
end
Init()
Loop()
