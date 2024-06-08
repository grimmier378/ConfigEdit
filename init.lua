--[[ 
	Title: Config GUI Script 
	Author: Grimmier 
	Description: GUI for dynamically loading and editing Lua, INI, and CFG config files. 
]]

-- Load Libraries 
local mq = require('mq') 
local ImGui = require('ImGui') 
local LoadTheme = require('lib.theme_loader') 
local Icon = require('mq.ICONS') 
local lfs = require('lfs') 
local LIP = require('lib.lip')

-- Variables 
local script = 'ConfigEditor' -- Change this to the name of your script 
local themeName = 'Default' 
local gIcon = Icon.MD_SETTINGS -- Gear Icon for Settings 
local themeID = 1 
local theme, defaults, settings = {}, {}, {} 
local RUNNING = true 
local showMainGUI, showConfigGUI, showSaveFileSelector, showOpenFileSelector = true, false, false, false
local scale = 1 
local aSize, locked, hasThemeZ = false, false, false 
local configData = {} 
local configFilePath = string.format('%s/', mq.TLO.MacroQuest.Path()) -- Default config folder path prefix 
local currentDirectory = mq.TLO.MacroQuest.Path() 
local saveConfigDirectory = mq.TLO.MacroQuest.Path() 
local selectedFile = nil 
local inputBuffer = {} 
local childHeight = 300 
local fileType = "Lua" -- Options: "Lua", "Ini", "Cfg"
local searchFilter = ""
local createBackup = false
local viewDocument = false -- Toggle for document view mode

-- GUI Settings 
local winFlags = bit32.bor(ImGuiWindowFlags.None)
local getSortedPairs

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

-- Function to check if a file exists
local function File_Exists(name) 
	local f = io.open(name, "r") 
	if f ~= nil then io.close(f) return true else return false end 
end

-- Function to load the theme from a file
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

-- Function to load settings from a file
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

-- Function to restructure INI data into a format suitable for GUI display
local function restructureIniData(data)
	local flatData = {}
	for section, values in pairs(data) do
		if type(values) == "table" then
			flatData[section] = {}
			for key, value in pairs(values) do
				table.insert(flatData[section], { key = key, value = value })
			end
		else
			table.insert(flatData, { section = "", key = section, value = values })
		end
	end
	return flatData
end

-- Function to clear configuration data and input buffers
local function clearConfigData()
	configData = {}
	inputBuffer = {}
end

-- Function to load configuration data based on file type
local function loadConfig() 
	if File_Exists(configFilePath) then 
		if fileType == "Ini" and not viewDocument then 
			configData = restructureIniData(LIP.load(configFilePath)) 
		elseif fileType == "Cfg" or fileType == "Log" or viewDocument then
			configData = {}
			for line in io.lines(configFilePath) do
				table.insert(configData, line)
			end
		else 
			-- Attempt to load the Lua config file with pcall
			local success, result = pcall(dofile, configFilePath)
			if success then
				if type(result) == "table" then
					configData = result
				else
					-- If the result is not a table, switch to document mode and load as text
					viewDocument = true
					configData = {}
					for line in io.lines(configFilePath) do
						table.insert(configData, line)
					end
				end
			else
				-- If loading fails, switch to document mode and load as text
				viewDocument = true
				configData = {}
				for line in io.lines(configFilePath) do
					table.insert(configData, line)
				end
			end
		end 
	else 
		configData = {} 
		mq.pickle(configFilePath, configData) 
	end 
	inputBuffer = {} -- Clear the input buffer 
end


-- Function to convert value to string
local function valueToString(value) 
	if type(value) == "function" then 
		return "function() return true end" 
	elseif type(value) == "table" then 
		return "Table" 
	elseif value == nil then 
		return "nil"
	else 
		return tostring(value) 
	end 
end

-- Function to convert string back to original value type
local function stringToValue(value, originalType) 
	if value == "nil" then
		return nil
	elseif originalType == "number" then 
		return tonumber(value) 
	elseif originalType == "boolean" then 
		return value == "true" 
	elseif originalType == "function" then 
		return load("return " .. value)() 
	else 
		return value 
	end 
end

-- Function to save configuration data based on file type
local function saveConfig(savePath) 
	if viewDocument then
		local f = io.open(savePath, "w")
		for _, line in ipairs(configData) do
			f:write(line .. "\n")
		end
		f:close()
	elseif fileType == "Ini" then 
		local iniData = {}
		for section, entries in pairs(configData) do
			iniData[section] = {}
			for _, entry in ipairs(entries) do
				iniData[section][entry.key] = entry.value
			end
		end
		LIP.save(savePath, iniData)
	elseif fileType == "Cfg" or fileType == "Log" then
		local f = io.open(savePath, "w")
		for _, line in ipairs(configData) do
			f:write(line .. "\n")
		end
		f:close()
	else 
		for key, value in pairs(inputBuffer) do 
			local keys = {} 
			for match in string.gmatch(key, "([^%.]+)") do 
				table.insert(keys, match) 
			end

			local current = configData 
			for i = 1, #keys - 1 do 
				if current[keys[i]] == nil then 
					current[keys[i]] = {} 
				end 
				current = current[keys[i]] 
			end

			if tonumber(keys[#keys]) then 
				current[tonumber(keys[#keys])] = stringToValue(value, type(current[tonumber(keys[#keys])])) 
			else 
				current[keys[#keys]] = stringToValue(value, type(current[keys[#keys]])) 
			end 
		end
		mq.pickle(savePath, configData) 
	end 
	configFilePath = savePath 
	loadConfig() 
end

-- Function to check if a key-value pair matches the search filter
local function matchesFilter(key, value)
	local filter = searchFilter:lower()
	if type(key) == "number" then
		key = tostring(key)
	end
	if key:lower():find(filter) then
		return true
	end
	if type(value) == "string" and value:lower():find(filter) then
		return true
	elseif type(value) == "table" then
		for k, v in pairs(value) do
			if matchesFilter(k, v) then
				return true
			end
		end
	end
	return false
end

-- Function to get sorted pairs
function getSortedPairs(t)
	local sortedKeys = {}
	if t == nil then
		return function () end
	end
	for k in pairs(t) do
		table.insert(sortedKeys, k)
	end
	table.sort(sortedKeys)

	local i = 0
	local iter = function ()
		i = i + 1
		if sortedKeys[i] == nil then
			return nil
		else
			return sortedKeys[i], t[sortedKeys[i]]
		end
	end

	return iter
end

-- Function to draw key-value pairs for INI files
local function drawIniKeyValueSection(section, data, baseKey, depth)
	local i = 1
	while i <= #data do
		local entry = data[i]
		ImGui.Indent(depth * 10)
		local valueStr = valueToString(entry.value)
		local inputIdKey = baseKey .. section .. "_" .. i .. "_key"
		local inputIdValue = baseKey .. section .. "_" .. i .. "_value"

		if inputBuffer[inputIdKey] == nil then
			inputBuffer[inputIdKey] = entry.key
		end
		if inputBuffer[inputIdValue] == nil then
			inputBuffer[inputIdValue] = valueStr
		end
        
		ImGui.SetNextItemWidth(200)
		inputBuffer[inputIdKey] = ImGui.InputText("##" .. inputIdKey, inputBuffer[inputIdKey])
		ImGui.SameLine()
		ImGui.Text(" = ")
		ImGui.SameLine()
		ImGui.SetNextItemWidth(200)
		inputBuffer[inputIdValue] = ImGui.InputText("##" .. inputIdValue, inputBuffer[inputIdValue])
		ImGui.SameLine()

		if ImGui.Button(Icon.MD_DELETE .. "##" .. inputIdKey) then
			table.remove(data, i)
			inputBuffer[inputIdKey] = nil
			inputBuffer[inputIdValue] = nil
		else
			entry.key = inputBuffer[inputIdKey]
			entry.value = stringToValue(inputBuffer[inputIdValue], type(entry.value))
			i = i + 1
		end

		ImGui.Unindent(depth * 10)
	end

	if ImGui.Button("Add Row##" .. section) then
		table.insert(data, { key = "NewKey", value = "NewValue" })
		local newIndex = #data
		inputBuffer[baseKey .. section .. "_" .. newIndex .. "_key"] = "NewKey"
		inputBuffer[baseKey .. section .. "_" .. newIndex .. "_value"] = "NewValue"
	end
end

-- Function to draw key-value pairs for Lua files
local function drawLuaKeyValueSection(section, data, baseKey, depth) 
	for key, value in pairs(data) do 
		if type(value) == "table" then 
			drawLuaSection(key, value, baseKey) 
		else 
			ImGui.Text(key) 
			ImGui.SameLine() 
			ImGui.PushItemWidth(-1) 
			local valueStr = valueToString(value) 
			local inputId = baseKey .. key 
			if inputBuffer[inputId] == nil then 
				inputBuffer[inputId] = valueStr 
			end 
			inputBuffer[inputId] = ImGui.InputText(inputId, inputBuffer[inputId]) 
			if inputBuffer[inputId] ~= valueStr then 
				data[key] = stringToValue(inputBuffer[inputId], type(value)) 
			end 
			ImGui.PopItemWidth() 
		end 
	end 
end

-- Function to draw nested sections for INI files
local function drawIniNestedSection(data, baseKey, depth)
	for section, entries in pairs(data) do
		drawIniSection(section, entries, baseKey, depth + 1)
		ImGui.Dummy(10, 20)
	end
end

-- Function to draw table sections for Lua files
local function drawLuaTableSection(section, data, baseKey) 
	ImGui.Columns(3, "table_columns", true) 
	for i = 1, #data do 
		ImGui.Text(tostring(i)) 
		ImGui.NextColumn() 
		ImGui.PushItemWidth(-1) 
		local itemValue = valueToString(data[i]) 
		local inputId = baseKey .. section .. "." .. i 
		if inputBuffer[inputId] == nil then 
			inputBuffer[inputId] = itemValue 
		end 
		inputBuffer[inputId] = ImGui.InputText(inputId, inputBuffer[inputId]) 
		if inputBuffer[inputId] ~= itemValue then 
			data[i] = stringToValue(inputBuffer[inputId], type(data[i])) 
		end 
		ImGui.PopItemWidth() 
		ImGui.NextColumn() 
		if ImGui.Button("Remove##" .. i) then 
			table.remove(data, i) 
			inputBuffer[inputId] = nil -- Remove the item from the input buffer 
			for j = i, #data do 
				local oldInputId = baseKey .. section .. "." .. (j + 1) 
				local newInputId = baseKey .. section .. "." .. j 
				inputBuffer[newInputId] = inputBuffer[oldInputId] 
				inputBuffer[oldInputId] = nil 
			end 
		end 
		ImGui.NextColumn() 
	end 
	ImGui.Columns(1) 
	if ImGui.Button("Add Item##" .. section) then 
		table.insert(data, "") 
	end 
end

-- Function to draw nested sections for Lua files
local function drawLuaNestedSection(data, baseKey, depth)
	for key, value in getSortedPairs(data) do 
		if type(value) == "table" then 
			drawLuaSection(key, value, baseKey) 
		else 
			drawLuaKeyValueSection(key, { [key] = value }, baseKey) 
		end 
	end 
end

-- Function to draw a section for INI files
function drawIniSection(section, data, baseKey, depth)
	if type(section) ~= "string" then
		section = tostring(section)
	end
	local fullKey = baseKey .. section .. "."
	if searchFilter == "" or matchesFilter(section, data) then
		ImGui.Indent(depth * 10)
		if ImGui.CollapsingHeader(section .. "##" .. fullKey) then
			ImGui.Separator()
			drawIniKeyValueSection(section, data, baseKey, depth + 1)
			ImGui.Separator()
		end
		ImGui.Unindent(depth * 10)
	end
end

-- Function to draw a section for Lua files
function drawLuaSection(section, data, baseKey, depth)
	if type(section) ~= "string" then 
		section = tostring(section) 
	end 
	local fullKey = baseKey .. section .. "." 
	if searchFilter == "" or matchesFilter(section, data) then
		if ImGui.CollapsingHeader(section) then 
			ImGui.Separator() 
			-- ImGui.BeginChild("Child_"..section, ImVec2(0, childHeight), bit32.bor(ImGuiChildFlags.Border)) 
			if type(data) == "table" then 
				if next(data) ~= nil and type(next(data)) == "number" and type(data[next(data)]) ~= "table" then 
					drawLuaTableSection(section, data, fullKey) 
					ImGui.Dummy(10, 20)
				else 
					drawLuaNestedSection(data, fullKey) 
					ImGui.Dummy(10, 20)
				end 
			end 
			-- ImGui.EndChild() 
			ImGui.Dummy(10, 20)
			ImGui.Separator() 
		end 
	end
end

-- Function to draw the general section for Lua files
local function drawGeneralSection(data, baseKey)
	if searchFilter == "" or matchesFilter("Generic", data) then
		if ImGui.CollapsingHeader("Generic") then
			ImGui.Separator()
			-- ImGui.BeginChild("Child_General", ImVec2(0, childHeight - 30), bit32.bor(ImGuiChildFlags.Border))
			drawLuaKeyValueSection("Generic", data, baseKey)
			-- ImGui.EndChild()
			ImGui.Dummy(10, 20)
			ImGui.Separator()
		end
	end
end

-- Function to draw multiline input box for CFG files
local function drawDocumentEditor()
	local cfgText = table.concat(configData, "\n")
	local inputText = ImGui.InputTextMultiline("##cfgEditor", cfgText, -1, -1 )
	if inputText ~= cfgText then
		configData = {}
		for line in inputText:gmatch("[^\r\n]+") do
			table.insert(configData, line)
		end
	end
end

-- Function to draw the configuration GUI
local function drawConfigGUI() 
	if viewDocument then
		drawDocumentEditor()
	else
		if fileType == "Ini" then
			for section, entries in getSortedPairs(configData) do
				drawIniSection(section, entries, "", 0)
			end
		elseif fileType == "Cfg" or fileType == "Log" then
			drawDocumentEditor()
		else
			local generalData = {} 
			ImGui.Separator() 
			for key, value in getSortedPairs(configData) do 
				if type(value) == "function" then 
					generalData[key] = tostring(value) 
				elseif type(value) == "table" then 
					drawLuaSection(key, value, "") 
				else 
					generalData[key] = value 
				end 
			end 
			if next(generalData) ~= nil then 
				drawGeneralSection(generalData, "") 
			end 
		end
	end
end

-- Function to get the contents of a directory
local function getDirectoryContents(path) 
	local folders = {} 
	local files = {} 
	for file in lfs.dir(path) do 
		if file ~= "." and file ~= ".." then 
			local f = path .. '/' .. file 
			local attr = lfs.attributes(f) 
			if attr.mode == "directory" then 
				table.insert(folders, file) 
			elseif attr.mode == "file" and ((fileType == "Ini" and file:match("%.ini$")) or (fileType == "Cfg" and file:match("%.cfg$")) or (fileType == "Log" and file:match("%.log$")) or (fileType == "Lua" and file:match("%.lua$"))) then 
				table.insert(files, file) 
			end 
		end 
	end 
	return folders, files 
end

-- Function to draw the file selector
local function drawFileSelector() 

	local folders, files = getDirectoryContents(currentDirectory) 
	if currentDirectory ~= mq.TLO.MacroQuest.Path() then
		if ImGui.Button("Back") then 
			currentDirectory = currentDirectory:match("(.*)/[^/]+$") 
		end
		ImGui.SameLine()
	end 
	local tmpFolder = currentDirectory:gsub(mq.TLO.MacroQuest.Path().."/", "") 
	ImGui.SetNextItemWidth(180) 
	if ImGui.BeginCombo("Folders", tmpFolder) then 
		for _, folder in ipairs(folders) do 
			if ImGui.Selectable(folder) then 
				currentDirectory = currentDirectory .. '/' .. folder 
			end 
		end 
		ImGui.EndCombo() 
	end 

	local tmpfile = configFilePath:gsub(currentDirectory.."/", "") 
	ImGui.SetNextItemWidth(180) 
	if ImGui.BeginCombo("Files", tmpfile or "Select a file") then 
		for _, file in ipairs(files) do 
			if ImGui.Selectable(file) then 
				selectedFile = file 
				configFilePath = currentDirectory .. '/' .. selectedFile 
				clearConfigData() -- Clear the previous config data and input buffer
				loadConfig() 
				showOpenFileSelector = false
			end 
		end 
		ImGui.EndCombo() 
	end 
	
end

-- Function to draw the save file selector
local function drawSaveFileSelector() 
	local folders = getDirectoryContents(saveConfigDirectory) 
	ImGui.Text("Save Directory: " .. saveConfigDirectory) 
	if saveConfigDirectory ~= mq.TLO.MacroQuest.Path() and ImGui.Button("Back") then 
		saveConfigDirectory = saveConfigDirectory:match("(.*)/[^/]+$") 
	end
	local tmpFolder = saveConfigDirectory:gsub(mq.TLO.MacroQuest.Path().."/", "") 
	ImGui.SetNextItemWidth(120) 
	if ImGui.BeginCombo("Folders", tmpFolder or "Select a folder") then 
		for _, folder in ipairs(folders) do 
			if ImGui.Selectable(folder) then 
				saveConfigDirectory = saveConfigDirectory .. '/' .. folder 
			end 
		end 
		ImGui.EndCombo() 
	end
	if ImGui.Button("Save") then
		if selectedFile ~= nil then
			local savePath = saveConfigDirectory .. '/' .. selectedFile
			if createBackup then
				savePath = saveConfigDirectory .. '/' .. selectedFile:gsub("%.", "_backup%.") 
			else
				savePath = saveConfigDirectory .. '/' .. selectedFile 
			end
			saveConfig(savePath) 
			configFilePath = savePath 
			loadConfig() 
			showSaveFileSelector = false 
		end
	end 
end

-- Main function to draw the GUI
	local function Draw_GUI() 
		if showMainGUI then 
			local winName = string.format('%s##Main2', script) 
			local ColorCount, StyleCount = LoadTheme.StartTheme(theme.Theme[themeID]) 
			local openMain, showMain = ImGui.Begin(winName, true, bit32.bor(winFlags, ImGuiWindowFlags.MenuBar)) 
			if not openMain then 
				showMainGUI = false 
			end 
			if showMain then 
				if ImGui.BeginMenuBar() then 
					if ImGui.BeginMenu("File") then 
						if selectedFile ~= nil then
							if ImGui.MenuItem("Save") then 
								showSaveFileSelector = true
							end
							if ImGui.MenuItem("Create Backup") then 
								createBackup = true
								showSaveFileSelector = true
							end
						end
						ImGui.SeparatorText("Open File Type")
						if ImGui.MenuItem("Open file *.cfg", nil) then
							showOpenFileSelector = false
							fileType = "Cfg"
							clearConfigData()
							showOpenFileSelector = true
						end
						if ImGui.MenuItem("Open File *.ini", nil) then
							showOpenFileSelector = false
							fileType = "Ini"
							clearConfigData()
							showOpenFileSelector = true
						end
						if ImGui.MenuItem("Open File *.lua", nil) then
							showOpenFileSelector = false
							fileType = "Lua"
							clearConfigData()
							showOpenFileSelector = true
						end
						if ImGui.MenuItem("Open File *.log", nil) then
							showOpenFileSelector = false
							fileType = "Log"
							clearConfigData()
							showOpenFileSelector = true
						end
						ImGui.Separator()
						if ImGui.MenuItem("Exit") then 
							showMainGUI = false 
						end
						ImGui.EndMenu()
					end
					if ImGui.BeginMenu("Options") then
						if ImGui.MenuItem("Document View", nil, viewDocument) then
							viewDocument = not viewDocument
							if selectedFile then
								loadConfig()
							end
						end
						if ImGui.MenuItem("Window Settings") then 
							showConfigGUI = true
						end
						ImGui.EndMenu()
					end
					ImGui.EndMenuBar() 
				end
				ImGui.SetWindowFontScale(scale) 
	
				ImGui.Text("Config File: " .. (configFilePath or "None")) 
				ImGui.Separator() 
				ImGui.Text("Mode: " .. fileType)
				
				-- local sizeX, sizeY = ImGui.GetContentRegionAvail()
				-- sizeY = math.max(sizeY, 100) -- Ensure a minimum height to prevent issues
				-- sizeX = math.max(sizeX, 100) -- Ensure a minimum width to prevent issues
				if selectedFile then
				searchFilter = ImGui.InputTextWithHint("##search", "Search...", searchFilter):lower()
				if ImGui.BeginChild("ConfigEditor##"..script, ImVec2(0,0), bit32.bor(ImGuiChildFlags.Border)) then
					ImGui.SeparatorText("Config File")
					if configFilePath and configFilePath ~= "" then
						-- childHeight = (sizeY - 60) * .5
						drawConfigGUI()
					end
					-- ImGui.EndChild()
				end
				ImGui.EndChild()
			end
				ImGui.SetWindowFontScale(1)
			end
			LoadTheme.EndTheme(ColorCount, StyleCount)
			ImGui.End()
		end
	
		if showConfigGUI then
			local winName = string.format('%s Config##Config', script)
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
		
		if showSaveFileSelector then
			if not showSaveFileSelector then return end
			ImGui.SetNextWindowPos(500, 300, ImGuiCond.Appearing)
			local winName = string.format('%s Save##Save', script)
			local ColCntExp, StyCntExp = LoadTheme.StartTheme(theme.Theme[themeID])
			local openSaveConfig, showSaveConfig = ImGui.Begin(winName, true, bit32.bor(ImGuiWindowFlags.NoCollapse, ImGuiWindowFlags.AlwaysAutoResize))
			if not openSaveConfig then
				showSaveFileSelector = false
			end
			if showSaveConfig then
				drawSaveFileSelector()
			end
			LoadTheme.EndTheme(ColCntExp, StyCntExp)
			ImGui.End()
		end
	
		if showOpenFileSelector then
			if not showOpenFileSelector then return end
			local winName = string.format('%s Open##Open', script)
			ImGui.SetNextWindowPos(500, 300, ImGuiCond.Appearing)
			local ColCntOpn, StyCntOpn = LoadTheme.StartTheme(theme.Theme[themeID])
			local openOpenConfig, showOpenWin = ImGui.Begin(winName, true, bit32.bor(ImGuiWindowFlags.NoCollapse, ImGuiWindowFlags.AlwaysAutoResize))
			if not openOpenConfig then
				showOpenFileSelector = false
			end
			if showOpenWin then
				if ImGui.Button("Cancel") then showOpenFileSelector = false end
				drawFileSelector()
	
			end
			LoadTheme.EndTheme(ColCntOpn, StyCntOpn)
			ImGui.End()
		end
	end

-- Function to initialize the script
local function Init() 
	loadSettings() 
	if File_Exists(themezDir) then 
		hasThemeZ = true 
	end 
	mq.imgui.init('ConfigEdit', Draw_GUI) 
end

-- Main loop function to keep the script running
local function Loop() 
	while RUNNING do 
		RUNNING = showMainGUI 
		winFlags = locked and bit32.bor(ImGuiWindowFlags.NoMove, ImGuiWindowFlags.NoDocking) or bit32.bor(ImGuiWindowFlags.NoDocking) 
		winFlags = aSize and bit32.bor(winFlags, ImGuiWindowFlags.AlwaysAutoResize) or winFlags 
		mq.delay(100) 
	end 
end

Init() 
Loop()
