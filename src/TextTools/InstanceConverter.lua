local APIDumpStatic = require(script.Parent.Parent:WaitForChild("APIDumpStatic"))

local function getWriteSafePropertiesSet(className: string)
	local propertiesSet = {}
	local classAPI = APIDumpStatic.Classes[className]
	for name, info in classAPI:Properties() do
		if info.Security == "None" or (info.Security.Read == "None" and info.Security.Write == "None") then
			local isScriptable = not table.find(info.Tags or {}, "NotScriptable")
			local isDeprecated = table.find(info.Tags or {}, "Hidden")
			local isReadOnly = table.find(info.Tags or {}, "ReadOnly")

			if isScriptable and not isDeprecated and not isReadOnly then
				propertiesSet[name] = info
			end
		end
	end
	return propertiesSet
end

local function convert(instance: Instance, className: string)
	local fromProperties = getWriteSafePropertiesSet(instance.ClassName)
	local toProperties = getWriteSafePropertiesSet(className)

	local new = Instance.new(className)
	for property, _ in toProperties do
		if fromProperties[property] then
			(new :: any)[property] = (instance :: any)[property]
		end
	end

	return new
end

return convert
