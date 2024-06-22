--[[
	Copyright (c) 2012 Carreras Nicolas
	
	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:
	
	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.
	
	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.
--]]
--- Lua INI Parser.
-- It has never been that simple to use INI files with Lua.
--@author Dynodzzo

-- Additions by Special Ed
    -- Sorting section/keys before saving ini files
	-- Expanded pattern used for loading keys (underscores, periods, apostrophes)

-- Additions by Grimmier
	-- Added support for loading and saving files with UTF-8 BOM
	-- Added support for loading and saving files with sections contain () and / characters
	-- Added support for loading and saving files with keys contain () and / characters
	-- Added support for loading and saving files with values are nil
	-- Added support for loading and saving files with duplicate keys


	local LIP = {};

	--- Returns a table containing all the data from the INI file.
	--@param fileName The name of the INI file to parse. [string]
	--@return The table containing all data from the INI file. [table]
	function LIP.load(fileName)
		assert(type(fileName) == 'string', 'Parameter "fileName" must be a string.');
		local file = assert(io.open(fileName, 'rb'), 'Error loading file : ' .. fileName);
		local content = file:read("*all")
		file:close()
	
		-- Check and remove BOM if present
		if content:sub(1, 3) == '\239\187\191' then
			content = content:sub(4)
		end
	
		local data = {};
		local section;
		local count = 0
		local fluff = 5000 -- used to prevent duplicate keys from being overwritten
	
		for line in content:gmatch("[^\r\n]+") do
			local tempSection = line:match('^%[([^%[%]]+)%]$');
			if(tempSection)then
				-- print(tempSection)
				section = tonumber(tempSection) and tonumber(tempSection) or tempSection;
				data[section] = data[section] or {};
				count = 0
			end
			local param, value = line:match("^([%w|_'%(%)%/.%s-]+)=%s-(.+)$");
			-- check for values that are nil
			if param == nil then
				-- if no value was found it didnt set param. lets check for a param with no value and use if found
				param = line:match("^([%w|_'%(%)%/.%s-]+)=$");
				value = ''
			end
			if(param and value ~= nil)then
				if(tonumber(value))then
					value = tonumber(value);
				elseif(value == 'true')then
					value = true;
				elseif(value == 'false')then
					value = false;
				end
				if(tonumber(param))then
					param = tonumber(param);
				end
				if string.find(tostring(param),'Spawn') then
					count =  count + 1
					param = string.format("Spawn%d",count)
				end
				-- check if the key already exists and add a fluff value to it to prevent overwriting
				if data[section][param] ~= nil then
					param = param.."_"..fluff
					fluff = fluff + 1
				end
				data[section][param] = value;
			end
		end
	
		return data;
	end
	
	--- Saves all the data from a table to an INI file.
	--@param fileName The name of the INI file to fill. [string]
	--@param data The table containing all the data to store. [table]
	function LIP.save(fileName, data)
		assert(type(fileName) == 'string', 'Parameter "fileName" must be a string.');
		assert(type(data) == 'table', 'Parameter "data" must be a table.');
		local file = assert(io.open(fileName, 'w+b'), 'Error loading file :' .. fileName);
		local contents = '';
	
		-- sort the section keys
		local sections = {}
		for k, v in pairs(data) do table.insert(sections, k) end
		table.sort(sections)
	
		for _, sectionKey in ipairs(sections) do
			contents = contents .. ('[%s]\n'):format(sectionKey);
			-- sort the keys before writing the file
			local keys = {}
			for k, v in pairs(data[sectionKey]) do table.insert(keys, k) end
			table.sort(keys)
			
			for _, k in ipairs(keys) do
				local ksection = k
				-- check if the key has a fluff value and remove it before writing back to file
				if k:find("_%d+$") then
					local fluff = k:sub(k:find("_%d+$")+1)
					if tonumber(fluff) >= 5000 then
						k = tostring(k):gsub("_(%d+)$","")
					end
				end
				contents = contents .. ('%s=%s\n'):format(k, tostring(data[sectionKey][ksection]));
			end
			contents = contents .. '\n';
		end
		file:write(contents);
		file:close();
	end
	
	return LIP;
	