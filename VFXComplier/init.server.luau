-- || Services || --
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local Selection = game:GetService("Selection")
local Debris = game:GetService("Debris")

-- || Imports || --
local toolbar = plugin:CreateToolbar("MeshEmitter " .. string.gsub(script.Name, string.split(script.Name, " ")[1], ""))

local generateBtn = toolbar:CreateButton(
	"Generate VFX",
	"One-click: generate a complete VFX ModuleScript from MoonAnimator2 save files or Eclipse Animator projects. Supports Beam, ParticleEmitter, Lights, Animations, CameraRig cutscenes.",
	"rbxassetid://135308249378556"
)

local generateNoCutsceneBtn = toolbar:CreateButton(
	"Generate VFX (No Cutscene)",
	"Generate a world-only VFX ModuleScript: skips camera cutscene, FOV, Vignette/ScreenCover UI and Lighting effects.",
	"rbxassetid://135308249378556"
)

local installPayloadBtn = toolbar:CreateButton(
	"Get Module",
	"Install/update the Payload libraries (VFXPayload utilities + universal VFX caller) next to your ForgeVFX module.",
	"rbxassetid://135308249378556"
)

local settingsBtn = toolbar:CreateButton(
	"Settings",
	"Configure the ForgeVFX module location used by generated code and Install Payload.",
	"rbxassetid://135308249378556"
)

function SearchInstance(InstanceNames)
	local Result = game
	local Started = false
	for i, v in pairs(InstanceNames) do
		if Started then
			if Result == nil then
				warn(">>> Please Open the file in MoonAnimator2 and Import again for Vignette Effect!")
				return nil
			end
			if v == "CurrentCamera" and Result == workspace then
				Result = workspace:FindFirstChildWhichIsA("Camera")
			else
				Result = Result:FindFirstChild(v)
			end
		end
		if v == "Workspace" or v == "workspace" or v == "DataModel" or v == "game" then
			Started = true
		end
	end
	return Result
end

local function cloneAttributes(source: Instance, target: Instance)
	for _, attrName in ipairs(source:GetAttributes()) do
		local value = source:GetAttribute(attrName)
		target:SetAttribute(attrName, value)
	end
end

function frameToTime(frame, fps)
	if fps <= 0 then
		return 0
	end
	return frame / fps
end


-- GENERATE VFX MODULE (New!)
-- One-click: Moon Animator save → Model + self-contained ModuleScript
-- Supports: BasePart, Beam, ParticleEmitter, Trail, Lights,
--           CameraEffects, Atmosphere, Vignette, ScreenCover, Lighting
--           Animations (Humanoid/AnimationController), CameraRig cutscenes
-- ============================================================

-- Helper: get path parts from root (exclusive) down to inst (inclusive)
local function getRelativePath(inst, root)
	local parts = {}
	local current = inst
	while current and current ~= root and current ~= game do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end
	return parts
end

-- Helper: convert path parts to a Lua accessor string like model.Fx.Box["2"].Beam1
local function pathToLuaAccessor(parts, base)
	base = base or "model"
	local result = base
	for _, p in ipairs(parts) do
		if p:match("^[%a_][%w_]*$") then
			result = result .. "." .. p
		else
			result = result .. '["' .. p:gsub('"', '\\"') .. '"]'
		end
	end
	return result
end

-- Helper: make a valid Lua identifier from a string
local function sanitizeVarName(str)
	str = str:gsub("[^%w_]", "_")
	if str:match("^%d") then
		str = "_" .. str
	end
	return str
end

-- Helper: fix Moon Animator easing style names to Roblox EasingStyle names
local function fixEaseStyle(style)
	if style == "Circ" then
		return "Circular"
	elseif style == "Expo" or style == "Sextic" then
		return "Exponential"
	else
		return style
	end
end

-- Helper: Roblox has no OutIn easing direction; InOut is the closest
local function fixEaseDirection(direction)
	if direction == "OutIn" then
		return "InOut"
	end
	return direction
end

-- Helper: convert a Roblox value to its Lua code string representation
local function valueToLuaCode(val, valClassName)
	if valClassName == "CFrameValue" or typeof(val) == "CFrame" then
		local comps = { val:GetComponents() }
		local strs = {}
		for _, c in ipairs(comps) do
			strs[#strs + 1] = string.format("%.4g", c)
		end
		return "CFrame.new(" .. table.concat(strs, ", ") .. ")"
	elseif valClassName == "Vector3Value" or typeof(val) == "Vector3" then
		return string.format("Vector3.new(%.4g, %.4g, %.4g)", val.X, val.Y, val.Z)
	elseif valClassName == "Color3Value" or typeof(val) == "Color3" then
		return string.format("Color3.new(%.4g, %.4g, %.4g)", val.R, val.G, val.B)
	elseif valClassName == "NumberValue" or typeof(val) == "number" then
		return string.format("%.4g", val)
	elseif valClassName == "BoolValue" or typeof(val) == "boolean" then
		return tostring(val)
	elseif valClassName == "IntValue" then
		return tostring(val)
	elseif valClassName == "StringValue" or typeof(val) == "string" then
		return string.format("%q", val)
	end
	return tostring(val)
end

-- Helper: find nearest BasePart ancestor (stops at workspace)
local function findBasePartAncestor(inst)
	local current = inst
	while current and current ~= workspace and current ~= game do
		if current:IsA("BasePart") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function promptCloneRigsSync()
	local coreGui = game:GetService("CoreGui")
	local sg = Instance.new("ScreenGui")
	sg.Name = "MeshEmitterClonePrompt"
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.new(0, 0, 0)
	bg.BackgroundTransparency = 0.5
	bg.Parent = sg

	local uiCornerBg = Instance.new("UICorner")
	uiCornerBg.Parent = bg

	local modal = Instance.new("Frame")
	modal.Size = UDim2.new(0, 360, 0, 180)
	modal.Position = UDim2.new(0.5, -180, 0.5, -90)
	modal.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	modal.BorderSizePixel = 0
	modal.Parent = bg

	local uiCornerModal = Instance.new("UICorner")
	uiCornerModal.CornerRadius = UDim.new(0, 8)
	uiCornerModal.Parent = modal

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -20, 0, 100)
	title.Position = UDim2.new(0, 10, 0, 10)
	title.Text = "Clone character Rigs into the generated VFX?\n*(CameraRigs are always cloned)*"
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextScaled = true
	title.Font = Enum.Font.GothamBold
	title.BackgroundTransparency = 1
	title.Parent = modal

	local yesBtn = Instance.new("TextButton")
	yesBtn.Size = UDim2.new(0.5, -20, 0, 45)
	yesBtn.Position = UDim2.new(0, 10, 1, -55)
	yesBtn.Text = "Yes"
	yesBtn.Font = Enum.Font.GothamBold
	yesBtn.TextSize = 20
	yesBtn.TextColor3 = Color3.new(1, 1, 1)
	yesBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 70)
	yesBtn.Parent = modal
	local uiYes = Instance.new("UICorner", yesBtn)

	local noBtn = Instance.new("TextButton")
	noBtn.Size = UDim2.new(0.5, -20, 0, 45)
	noBtn.Position = UDim2.new(0.5, 10, 1, -55)
	noBtn.Text = "No"
	noBtn.Font = Enum.Font.GothamBold
	noBtn.TextSize = 20
	noBtn.TextColor3 = Color3.new(1, 1, 1)
	noBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	noBtn.Parent = modal
	local uiNo = Instance.new("UICorner", noBtn)

	sg.Parent = coreGui

	local bindable = Instance.new("BindableEvent")
	local result = false

	yesBtn.MouseButton1Click:Connect(function()
		result = true
		bindable:Fire()
	end)
	noBtn.MouseButton1Click:Connect(function()
		result = false
		bindable:Fire()
	end)

	bindable.Event:Wait()
	bindable:Destroy()
	sg:Destroy()

	return result
end

-- Helper: detect if a rig is a CameraRig (has CamPart child)
local function isCameraRig(instance)
	if not instance then
		return false
	end
	if instance:FindFirstChild("CamPart") then
		return true
	end
	-- Also check by name
	if instance.Name == "CameraRig" or instance.Name == "Camera Rig" then
		return true
	end
	return false
end

-- Helper: detect if a rig has animation capability (Humanoid or AnimationController)
local function hasAnimator(instance)
	if not instance then
		return false
	end
	if instance:FindFirstChildWhichIsA("Humanoid") then
		return true
	end
	if instance:FindFirstChildWhichIsA("AnimationController") then
		return true
	end
	return false
end

-- || Settings / Path helpers || --
local SETTING_KEY = "MeshEmitter_ForgeVFXPath"
local DEFAULT_FORGEVFX_PATH = "ReplicatedStorage.ForgeVFX"
local STORAGE_SETTING_KEY = "MeshEmitter_VFXStoragePath"
local DEFAULT_VFX_STORAGE_PATH = "ReplicatedStorage.VFX"

local function getForgeVFXPath()
	local saved = plugin:GetSetting(SETTING_KEY)
	if type(saved) == "string" and saved ~= "" then
		return saved
	end
	return DEFAULT_FORGEVFX_PATH
end

local function getVFXStoragePath()
	local saved = plugin:GetSetting(STORAGE_SETTING_KEY)
	if type(saved) == "string" and saved ~= "" then
		return saved
	end
	return DEFAULT_VFX_STORAGE_PATH
end

-- "ReplicatedStorage.Modules.ForgeVFX" -> {"ReplicatedStorage", "Modules", "ForgeVFX"} or nil, err
local function parseForgeVFXPath(pathStr)
	local segments = string.split(pathStr, ".")
	if #segments < 2 then
		return nil, "Path needs at least Service.ModuleName (e.g. ReplicatedStorage.ForgeVFX)"
	end
	local okSvc = pcall(function()
		return game:GetService(segments[1])
	end)
	if not okSvc then
		return nil, "Unknown service: " .. tostring(segments[1])
	end
	return segments
end

-- Build a require-expression string for generated code, e.g.
-- game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("ForgeVFX")
local function segmentsToRequireExpr(segments, lastIndex)
	lastIndex = lastIndex or #segments
	local expr = 'game:GetService("' .. segments[1] .. '")'
	for i = 2, lastIndex do
		expr = expr .. ':WaitForChild("' .. segments[i] .. '")'
	end
	return expr
end

-- Runtime lookup of the PARENT container of the ForgeVFX module (for Install Payload)
local function resolveForgeVFXParent(segments)
	local ok, current = pcall(function()
		return game:GetService(segments[1])
	end)
	if not ok or not current then
		return nil
	end
	for i = 2, #segments - 1 do
		current = current:FindFirstChild(segments[i])
		if not current then
			return nil
		end
	end
	return current
end

-- || Payload library source (installed by the Install Payload button) || --
local PAYLOAD_SOURCE = table.concat({
	"-- VFXPayload: shared runtime utilities for generated VFXPlayer modules",
	"-- Installed by the MeshEmitter plugin. Re-run Install Payload to update.",
	"local TweenService = game:GetService('TweenService')",
	"",
	"local module = {}",
	"",
	"function module.setProperty(obj, prop, val, delayTime)",
	"\tif delayTime > 0 then",
	"\t\ttask.delay(delayTime, function() if obj then obj[prop] = val end end)",
	"\telse",
	"\t\tif obj then obj[prop] = val end",
	"\tend",
	"end",
	"",
	"function module.tweenProperty(obj, prop, fromVal, toVal, delayTime, dur, style, dir)",
	"\tlocal function go()",
	"\t\tif not obj then return end",
	"\t\tobj[prop] = fromVal",
	"\t\tTweenService:Create(obj, TweenInfo.new(dur, Enum.EasingStyle[style], Enum.EasingDirection[dir]), {[prop] = toVal}):Play()",
	"\tend",
	"\tif delayTime > 0 then task.delay(delayTime, go) else go() end",
	"end",
	"",
	"function module.playKeyframes(obj, prop, propType, keyframes, baseRoot)",
	"\tfor i = 1, #keyframes do",
	"\t\tlocal kf = keyframes[i]",
	"\t\tlocal nextKf = keyframes[i + 1]",
	"\t\tlocal t, v, style, dir = kf[1], kf[2], kf[3], kf[4]",
	"\t\tif not nextKf then",
	"\t\t\tmodule.setProperty(obj, prop, v, t)",
	"\t\t\tbreak",
	"\t\tend",
	"\t\tlocal t2, v2 = nextKf[1], nextKf[2]",
	"\t\tlocal dur = math.max(0.001, t2 - t)",
	"\t\tlocal info = TweenInfo.new(dur, Enum.EasingStyle[style], Enum.EasingDirection[dir])",
	"\t\tlocal function go()",
	"\t\t\tif not obj then return end",
	"\t\t\tif propType == 'boolean' then",
	"\t\t\t\tobj[prop] = v",
	"\t\t\telseif propType == 'NumberSequence' then",
	"\t\t\t\tlocal nv = Instance.new('NumberValue'); nv.Value = v",
	"\t\t\t\tnv.Changed:Connect(function(val) if obj then obj[prop] = NumberSequence.new({NumberSequenceKeypoint.new(0, val), NumberSequenceKeypoint.new(1, val)}) end end)",
	"\t\t\t\tlocal tw = TweenService:Create(nv, info, {Value = v2})",
	"\t\t\t\ttw.Completed:Once(function() nv:Destroy() end); tw:Play()",
	"\t\t\telseif propType == 'ColorSequence' then",
	"\t\t\t\tlocal cv = Instance.new('Color3Value'); cv.Value = v",
	"\t\t\t\tcv.Changed:Connect(function(val) if obj then obj[prop] = ColorSequence.new(val) end end)",
	"\t\t\t\tlocal tw = TweenService:Create(cv, info, {Value = v2})",
	"\t\t\t\ttw.Completed:Once(function() cv:Destroy() end); tw:Play()",
	"\t\t\telseif propType == 'RelCFrame' then",
	"\t\t\t\tif baseRoot then",
	"\t\t\t\t\tlocal nv = Instance.new('NumberValue'); nv.Value = 0; local conn",
	"\t\t\t\t\tconn = nv.Changed:Connect(function(a) if obj and baseRoot then obj.CFrame = baseRoot.CFrame * v:Lerp(v2, a) end end)",
	"\t\t\t\t\tlocal tw = TweenService:Create(nv, info, {Value = 1})",
	"\t\t\t\t\ttw.Completed:Once(function() conn:Disconnect() nv:Destroy() end); tw:Play()",
	"\t\t\t\tend",
	"\t\t\telse",
	"\t\t\t\tobj[prop] = v",
	"\t\t\t\tTweenService:Create(obj, info, {[prop] = v2}):Play()",
	"\t\t\tend",
	"\t\tend",
	"\t\tif t > 0 then task.delay(t, go) else go() end",
	"\tend",
	"end",
	"",
	"function module.safeEmit(instance, count)",
	"\tif instance and instance:IsA('ParticleEmitter') then instance:Emit(count) end",
	"end",
	"",
	"return module",
}, "\n")

-- || Universal VFX caller module source (storage path baked in at install time) || --
local function buildVFXSource(storageSegments)
	local fullPath = table.concat(storageSegments, ".")
	local lines = {}
	local function add(line)
		lines[#lines + 1] = line
	end
	add("-- VFX: universal caller for plugin-generated VFXPlayer modules")
	add("-- Installed by the MeshEmitter plugin. Re-run Get Module to update.")
	add("local module = {}")
	add("")
	add("local function getStorage()")
	add('\tlocal current = game:GetService("' .. storageSegments[1] .. '")')
	for i = 2, #storageSegments do
		add('\tcurrent = current and current:FindFirstChild("' .. storageSegments[i] .. '")')
	end
	add("\treturn current")
	add("end")
	add("")
	add("local function resolvePlayer(target)")
	add("\tif typeof(target) == 'string' then")
	add("\t\tlocal storage = getStorage()")
	add("\t\tif not storage then")
	add('\t\t\twarn("[VFX] Storage folder not found (' .. fullPath .. '). Check plugin Settings.")')
	add("\t\t\treturn nil")
	add("\t\tend")
	add("\t\tlocal found = storage:FindFirstChild(target) or storage:FindFirstChild(target .. '_VFX')")
	add("\t\tif not found then")
	add("\t\t\twarn(\"[VFX] No VFX named '\" .. target .. \"' in \" .. storage:GetFullName())")
	add("\t\t\treturn nil")
	add("\t\tend")
	add("\t\ttarget = found")
	add("\tend")
	add("\tif typeof(target) ~= 'Instance' then")
	add("\t\treturn nil")
	add("\tend")
	add("\tif target:IsA('ModuleScript') then")
	add("\t\treturn target")
	add("\tend")
	add("\tlocal player = target:FindFirstChild('VFXPlayer')")
	add("\tif player then")
	add("\t\treturn player")
	add("\tend")
	add("\twarn('[VFX] No VFXPlayer module inside: ' .. target:GetFullName())")
	add("\treturn nil")
	add("end")
	add("")
	add("-- Returns the required VFXPlayer table for a name / model / ModuleScript (or nil)")
	add("function module.Get(target)")
	add("\tlocal player = resolvePlayer(target)")
	add("\tif not player then")
	add("\t\treturn nil")
	add("\tend")
	add("\treturn require(player)")
	add("end")
	add("")
	add("-- Universal play: VFX.Play('Slash' or model, rootPart, offset, lifeTime, config)")
	add("function module.Play(target, rootPart, offset, lifeTime, config)")
	add("\tlocal vfx = module.Get(target)")
	add("\tif not vfx then")
	add("\t\treturn nil")
	add("\tend")
	add("\treturn vfx.Play(rootPart, offset, lifeTime, config)")
	add("end")
	add("")
	add("return module")
	return table.concat(lines, "\n")
end

installPayloadBtn.Click:Connect(function()
	local segments, err = parseForgeVFXPath(getForgeVFXPath())
	if not segments then
		warn(">> [InstallPayload] Invalid ForgeVFX path setting: " .. tostring(err))
		return
	end
	local parent = resolveForgeVFXParent(segments)
	if not parent then
		warn(">> [InstallPayload] Could not resolve parent of: " .. getForgeVFXPath() .. " - create the folder chain first or fix Settings.")
		return
	end

	local recording = ChangeHistoryService:TryBeginRecording("MeshEmitter Install Payload")

	local payloadFolder = parent:FindFirstChild("Payload")
	if not payloadFolder or not payloadFolder:IsA("Folder") then
		payloadFolder = Instance.new("Folder")
		payloadFolder.Name = "Payload"
		payloadFolder.Parent = parent
	end
	local mod = payloadFolder:FindFirstChild("VFXPayload")
	if not mod or not mod:IsA("ModuleScript") then
		mod = Instance.new("ModuleScript")
		mod.Name = "VFXPayload"
		mod.Parent = payloadFolder
	end
	mod.Source = PAYLOAD_SOURCE

	local storageSegments = parseForgeVFXPath(getVFXStoragePath()) or string.split(DEFAULT_VFX_STORAGE_PATH, ".")
	local vfxMod = payloadFolder:FindFirstChild("VFX")
	if not vfxMod or not vfxMod:IsA("ModuleScript") then
		vfxMod = Instance.new("ModuleScript")
		vfxMod.Name = "VFX"
		vfxMod.Parent = payloadFolder
	end
	vfxMod.Source = buildVFXSource(storageSegments)

	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	print(">> [GetModule] Installed/updated VFXPayload + VFX in", payloadFolder:GetFullName())
	Selection:Set({ vfxMod })
end)

-- || Settings widget || --
local settingsWidget = plugin:CreateDockWidgetPluginGui(
	"MeshEmitterSettings",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 340, 215, 300, 195)
)
settingsWidget.Title = "MeshEmitter Settings"

local settingsFrame = Instance.new("Frame")
settingsFrame.Size = UDim2.new(1, 0, 1, 0)
settingsFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
settingsFrame.BorderSizePixel = 0
settingsFrame.Parent = settingsWidget

local pathLabel = Instance.new("TextLabel")
pathLabel.Size = UDim2.new(1, -20, 0, 20)
pathLabel.Position = UDim2.new(0, 10, 0, 10)
pathLabel.Text = "ForgeVFX module path (Service.Child.ModuleName):"
pathLabel.TextColor3 = Color3.new(1, 1, 1)
pathLabel.TextXAlignment = Enum.TextXAlignment.Left
pathLabel.Font = Enum.Font.GothamBold
pathLabel.TextSize = 13
pathLabel.BackgroundTransparency = 1
pathLabel.Parent = settingsFrame

local pathBox = Instance.new("TextBox")
pathBox.Size = UDim2.new(1, -20, 0, 30)
pathBox.Position = UDim2.new(0, 10, 0, 35)
pathBox.Text = getForgeVFXPath()
pathBox.ClearTextOnFocus = false
pathBox.TextColor3 = Color3.new(1, 1, 1)
pathBox.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
pathBox.Font = Enum.Font.Code
pathBox.TextSize = 14
pathBox.TextXAlignment = Enum.TextXAlignment.Left
pathBox.Parent = settingsFrame
local uiPathBox = Instance.new("UICorner", pathBox)

local storageLabel = Instance.new("TextLabel")
storageLabel.Size = UDim2.new(1, -20, 0, 20)
storageLabel.Position = UDim2.new(0, 10, 0, 72)
storageLabel.Text = "VFX storage folder (for VFX.Play by name):"
storageLabel.TextColor3 = Color3.new(1, 1, 1)
storageLabel.TextXAlignment = Enum.TextXAlignment.Left
storageLabel.Font = Enum.Font.GothamBold
storageLabel.TextSize = 13
storageLabel.BackgroundTransparency = 1
storageLabel.Parent = settingsFrame

local storageBox = Instance.new("TextBox")
storageBox.Size = UDim2.new(1, -20, 0, 30)
storageBox.Position = UDim2.new(0, 10, 0, 95)
storageBox.Text = getVFXStoragePath()
storageBox.ClearTextOnFocus = false
storageBox.TextColor3 = Color3.new(1, 1, 1)
storageBox.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
storageBox.Font = Enum.Font.Code
storageBox.TextSize = 14
storageBox.TextXAlignment = Enum.TextXAlignment.Left
storageBox.Parent = settingsFrame
local uiStorageBox = Instance.new("UICorner", storageBox)

local saveButton = Instance.new("TextButton")
saveButton.Size = UDim2.new(0, 100, 0, 28)
saveButton.Position = UDim2.new(0, 10, 0, 135)
saveButton.Text = "Save"
saveButton.Font = Enum.Font.GothamBold
saveButton.TextSize = 16
saveButton.TextColor3 = Color3.new(1, 1, 1)
saveButton.BackgroundColor3 = Color3.fromRGB(40, 160, 70)
saveButton.Parent = settingsFrame
local uiSaveBtn = Instance.new("UICorner", saveButton)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -20, 0, 20)
statusLabel.Position = UDim2.new(0, 10, 0, 168)
statusLabel.Text = ""
statusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 13
statusLabel.BackgroundTransparency = 1
statusLabel.Parent = settingsFrame

saveButton.MouseButton1Click:Connect(function()
	local forgeText = pathBox.Text
	local segments, err = parseForgeVFXPath(forgeText)
	if not segments then
		statusLabel.Text = "Invalid ForgeVFX path: " .. tostring(err)
		return
	end
	local storageText = storageBox.Text
	local storageSegments, storageErr = parseForgeVFXPath(storageText)
	if not storageSegments then
		statusLabel.Text = "Invalid storage path: " .. tostring(storageErr)
		return
	end
	plugin:SetSetting(SETTING_KEY, forgeText)
	plugin:SetSetting(STORAGE_SETTING_KEY, storageText)
	statusLabel.Text = "Saved both paths. Re-run Get Module to apply."
end)

settingsBtn.Click:Connect(function()
	pathBox.Text = getForgeVFXPath()
	storageBox.Text = getVFXStoragePath()
	settingsWidget.Enabled = not settingsWidget.Enabled
end)

-- ============================================================
-- Animation sources: Moon Animator 2 saves and Eclipse Animator projects
-- Both are read into one shape, so generation doesn't care which animator made them:
--   { object, name, fps,
--     rigs   = { {instance} },
--     items  = { {label, isCamera, instance, properties = { {name, keyframes} }} },
--     events = { {Frame, String} } }
--   keyframes = { {Frame, Value, ValueClass, Style, Direction} }  (Moon-style ease names)
-- ============================================================

-- Moon keyframe folders hold Values["i"] at frame N + i (grouped keyframes hold several)
local function readMoonKeyframes(propertyOBJ)
	local frameFolders = {}
	for _, v in pairs(propertyOBJ:GetChildren()) do
		if v:IsA("Folder") and v.Name ~= "default" and tonumber(v.Name) ~= nil then
			frameFolders[#frameFolders + 1] = v
		end
	end
	table.sort(frameFolders, function(a, b)
		return tonumber(a.Name) < tonumber(b.Name)
	end)

	local keyframes = {}
	for _, framedata in ipairs(frameFolders) do
		local Frame = tonumber(framedata.Name)
		local Values = framedata:FindFirstChild("Values")
		if not Values or not Values:FindFirstChild("0") then
			continue
		end
		local Eases = framedata:FindFirstChild("Eases")
		local offsets = {}
		for _, Value in ipairs(Values:GetChildren()) do
			local offset = tonumber(Value.Name)
			if offset then
				offsets[#offsets + 1] = { offset = offset, object = Value }
			end
		end
		table.sort(offsets, function(a, b)
			return a.offset < b.offset
		end)

		for _, entry in ipairs(offsets) do
			local EaseStyle = "Linear"
			local EaseDirection = "In"
			local Ease = Eases and Eases:FindFirstChild(tostring(entry.offset))
			if Ease then
				local TypeInst = Ease:FindFirstChild("Type")
				if TypeInst then
					EaseStyle = TypeInst.Value
				end
				local Params = Ease:FindFirstChild("Params")
				local DirInst = Params and Params:FindFirstChild("Direction")
				if DirInst then
					EaseDirection = DirInst.Value
				end
			end
			keyframes[#keyframes + 1] = {
				Frame = Frame + entry.offset,
				Value = entry.object.Value,
				ValueClass = entry.object.ClassName,
				Style = EaseStyle,
				Direction = EaseDirection,
			}
		end
	end
	return keyframes
end

local function readMoonSave(SaveOBJ)
	local ok, Decoded = pcall(function()
		return HttpService:JSONDecode(SaveOBJ.Value)
	end)
	if not ok or type(Decoded) ~= "table" then
		return nil, "Failed to decode"
	end

	local Items = Decoded.Items
	local Information = Decoded.Information
	if not Items or not Information then
		return nil, "Invalid save file"
	end

	local Source = {
		object = SaveOBJ,
		name = SaveOBJ.Name,
		fps = tonumber(Information.FPS) or 60,
		rigs = {},
		items = {},
		events = {},
	}

	for idx, Item in ipairs(Items) do
		local DataInstance = SaveOBJ:FindFirstChild(tostring(idx))
		if not DataInstance then
			continue
		end
		local ItemType = Item.Path.ItemType
		local InstanceNames = Item.Path.InstanceNames

		if ItemType == "Rig" then
			if DataInstance:FindFirstChild("Rig") then
				Source.rigs[#Source.rigs + 1] = { instance = SearchInstance(InstanceNames) }
			end
			continue
		end

		local item = {
			label = table.concat(InstanceNames, "."),
			isCamera = ItemType == "Camera",
			instance = ItemType == "Camera" and workspace.CurrentCamera or SearchInstance(InstanceNames),
			properties = {},
		}
		for _, propertyOBJ in pairs(DataInstance:GetChildren()) do
			if propertyOBJ.Name == "Rig" or propertyOBJ.Name == "AttachToPart" then
				continue
			end
			item.properties[#item.properties + 1] = {
				name = propertyOBJ.Name,
				keyframes = readMoonKeyframes(propertyOBJ),
			}
		end
		Source.items[#Source.items + 1] = item
	end

	-- Moon markers: codeBegin runs at the marker's frame, codeEnd when the marker ends (frame + width)
	for _, OBJ in pairs(SaveOBJ:GetDescendants()) do
		if OBJ.Name == "codeBegin" or OBJ.Name == "codeEnd" then
			local Frame = tonumber(OBJ.Parent.Name)
			if Frame then
				if OBJ.Name == "codeEnd" then
					local width = OBJ.Parent:FindFirstChild("width")
					Frame += width and tonumber(width.Value) or 0
				end
				Source.events[#Source.events + 1] = { Frame = Frame, String = OBJ.Value }
			end
		end
	end

	return Source
end

-- || Eclipse Animator projects (ServerStorage["Eclipse Animator Saves"].EclipseAnimator_Saves) || --

local ECLIPSE_STYLES = {
	Linear = true,
	Constant = true,
	Sine = true,
	Quad = true,
	Cubic = true,
	Quart = true,
	Quint = true,
	Sextic = true,
	Expo = true,
	Circ = true,
	Back = true,
	Bounce = true,
	Elastic = true,
}
local ECLIPSE_STYLE_ALIASES = { Sinusoidal = "Sine", Exponential = "Expo", Circular = "Circ", CubicV2 = "Cubic" }

-- Eclipse chunked text: a StringValue, or a Folder of StringValues joined in name order
local function eclipseReadChunks(node)
	if node:IsA("StringValue") then
		return node.Value
	end
	local chunks = node:GetChildren()
	table.sort(chunks, function(a, b)
		return a.Name < b.Name
	end)
	local text = {}
	for _, chunk in ipairs(chunks) do
		if chunk:IsA("StringValue") then
			text[#text + 1] = chunk.Value
		end
	end
	return table.concat(text)
end

local function eclipseText(folder, name)
	local node = folder:FindFirstChild(name)
	return node and eclipseReadChunks(node) or ""
end

-- EclipseKeyframeData values: {"T":[key, value, ...]}, {"C":[cframe]}, {"V":[vector]}, {"E":[enum, item]}
local function eclipseKeyDecode(value)
	if typeof(value) ~= "table" then
		return value
	end
	if value.T then
		local out = {}
		for index = 1, #value.T, 2 do
			out[value.T[index]] = eclipseKeyDecode(value.T[index + 1])
		end
		return out
	elseif value.C then
		return CFrame.new(table.unpack(value.C))
	elseif value.V then
		return Vector3.new(table.unpack(value.V))
	elseif value.E then
		local ok, item = pcall(function()
			return Enum[value.E[1]][value.E[2]]
		end)
		return ok and item or nil
	end
	return nil
end

-- EclipseProperties values: {"t":"cf","v":[...]}, {"t":"table","v":[[key, value], ...]}, ...
local function eclipseDocDecode(value)
	if type(value) ~= "table" then
		return value
	end
	local t, v = value.t, value.v
	if t == "cf" then
		return CFrame.new(table.unpack(v))
	elseif t == "v3" then
		return Vector3.new(table.unpack(v))
	elseif t == "Color3" then
		return Color3.new(table.unpack(v))
	elseif t == "Vector2" then
		return Vector2.new(table.unpack(v))
	elseif t == "NumberRange" then
		return NumberRange.new(table.unpack(v))
	elseif t == "UDim" then
		return UDim.new(table.unpack(v))
	elseif t == "UDim2" then
		return UDim2.new(table.unpack(v))
	elseif t == "Rect" then
		return Rect.new(table.unpack(v))
	elseif t == "BrickColor" then
		return BrickColor.new(v)
	elseif t == "NumberSequence" then
		local keys = {}
		for _, key in ipairs(v) do
			keys[#keys + 1] = NumberSequenceKeypoint.new(key[1], key[2], key[3] or 0)
		end
		return NumberSequence.new(keys)
	elseif t == "ColorSequence" then
		local keys = {}
		for _, key in ipairs(v) do
			keys[#keys + 1] = ColorSequenceKeypoint.new(key[1], eclipseDocDecode(key[2]))
		end
		return ColorSequence.new(keys)
	elseif t == "enum" then
		local ok, item = pcall(function()
			return Enum[value.e][v]
		end)
		return ok and item or nil
	end
	local result = {}
	for _, entry in ipairs(type(v) == "table" and v or {}) do
		result[entry[1]] = eclipseDocDecode(entry[2])
	end
	return result
end

-- Eclipse easing -> Moon-style names (fixEaseStyle/fixEaseDirection map them to Roblox later)
local function eclipseEase(key)
	local style = key.EasingStyle
	local native = typeof(style) == "EnumItem"
	if native then
		style = style.Name
	end
	style = ECLIPSE_STYLE_ALIASES[style] or style or "Bezier"
	local direction = key.EasingDirection
	if typeof(direction) == "EnumItem" then
		direction = direction.Name
	end
	direction = direction or "Automatic"

	if style == "Bezier" then
		-- Eclipse's default curve (0.42, 0, 0.58, 1) is an ease-in-out
		return "Sine", "InOut"
	end
	if not ECLIPSE_STYLES[style] then
		return "Linear", "In"
	end
	if direction == "Automatic" then
		direction = (style == "Back" or style == "Bounce" or style == "Elastic") and "Out" or "In"
	end
	if native and style == "Cubic" and (direction == "In" or direction == "Out") then
		-- Roblox pose easing names Cubic In/Out the other way round from TweenService
		direction = direction == "In" and "Out" or "In"
	end
	return style, direction
end

local function clockNumber(value)
	if typeof(value) == "number" then
		return value
	end
	if typeof(value) ~= "string" then
		return nil
	end
	local number = tonumber(value)
	if number then
		return number
	end
	local h, m, s = value:match("^%s*(%d+):(%d+):?([%d%.]*)%s*$")
	if not h then
		return nil
	end
	return tonumber(h) + tonumber(m) / 60 + (tonumber(s) or 0) / 3600
end

-- The exact value of an Eclipse property key (PropertyValue, or decoded from its C0 carrier)
local function eclipsePropertyValue(object, id, key)
	local c0 = key.C0
	if object:IsA("Lighting") and (id == "ClockTime" or id == "TimeOfDay") then
		return clockNumber(key.PropertyValue) or (typeof(c0) == "CFrame" and c0.X) or nil
	end
	local value = key.PropertyValue
	if value == nil and typeof(c0) == "CFrame" then
		local live
		pcall(function()
			live = object[id]
		end)
		local kind = typeof(live)
		if kind == "number" then
			value = c0.X
		elseif kind == "Vector3" then
			value = c0.Position
		elseif kind == "Vector2" then
			value = Vector2.new(c0.X, c0.Y)
		elseif kind == "Color3" then
			value = Color3.new(math.clamp(c0.X, 0, 1), math.clamp(c0.Y, 0, 1), math.clamp(c0.Z, 0, 1))
		elseif kind == "CFrame" then
			value = c0
		end
	end
	-- Sequences and ranges are animated as one value, the same way Moon stores them
	if typeof(value) == "NumberSequence" or typeof(value) == "ColorSequence" then
		value = value.Keypoints[1].Value
	elseif typeof(value) == "NumberRange" then
		value = value.Min
	end
	return value
end

-- Lua expression that reaches `instance` (workspace.X.Y / game:GetService("Lighting").X)
local function luaPathOf(instance)
	local parts = {}
	local node = instance
	while node and node.Parent ~= game do
		table.insert(parts, 1, node.Name)
		node = node.Parent
	end
	if not node then
		return nil
	end
	local code = node == workspace and "workspace" or ('game:GetService("' .. node.ClassName .. '")')
	for _, name in ipairs(parts) do
		if name:match("^[%a_][%w_]*$") then
			code = code .. "." .. name
		else
			code = code .. '["' .. (name:gsub('"', '\\"')) .. '"]'
		end
	end
	return code
end

-- Eclipse's own VFX emits and sound events become event code, like Moon's codeBegin
local function eclipseEventExtras(event, object)
	local lines = {}

	local okEmits, emits = pcall(function()
		return HttpService:JSONDecode(eclipseText(event, "Emits"))
	end)
	if object and okEmits and type(emits) == "table" then
		for _, row in ipairs(emits) do
			if type(row) ~= "table" then
				continue
			end
			local node = object
			for _, step in ipairs(type(row.Path) == "table" and row.Path or {}) do
				local count, found = 0, nil
				for _, child in ipairs(node:GetChildren()) do
					if child.Name == step.Name and child.ClassName == step.Class then
						count += 1
						if count == (tonumber(step.Index) or 1) then
							found = child
							break
						end
					end
				end
				node = found
				if not node then
					break
				end
			end
			if not node then
				continue
			end
			local targets = { node }
			if row.Mode == "Selected" then
				for _, child in ipairs(node:GetChildren()) do
					targets[#targets + 1] = child
				end
			elseif row.Mode ~= "Exact" then
				for _, descendant in ipairs(node:GetDescendants()) do
					targets[#targets + 1] = descendant
				end
			end
			local action = row.Action or "Emit"
			for _, target in ipairs(targets) do
				local path = luaPathOf(target)
				if not path then
					continue
				end
				if action == "Emit" and target:IsA("ParticleEmitter") then
					local count = math.clamp(math.floor(tonumber(target:GetAttribute("EmitCount")) or 1), 1, 100000)
					lines[#lines + 1] = path .. ":Emit(" .. count .. ")"
				elseif
					(action == "Enable" or action == "Disable")
					and (target:IsA("ParticleEmitter") or target:IsA("Beam") or target:IsA("Trail"))
				then
					lines[#lines + 1] = path .. ".Enabled = " .. tostring(action == "Enable")
				end
			end
		end
	end

	local sounds = event:FindFirstChild("Sounds")
	if sounds then
		local list = sounds:GetChildren()
		table.sort(list, function(a, b)
			return a.Name < b.Name
		end)
		for _, sound in ipairs(list) do
			local id = sound:GetAttribute("AudioId")
			if type(id) == "string" and id ~= "" and not id:find("^eclipse%-local%-audio:") then
				lines[#lines + 1] = string.format(
					"do local s = Instance.new('Sound') s.SoundId = %q s.Volume = %s s.PlaybackSpeed = %s s.Parent = model:FindFirstChild('RootPart') or model s:Play() Debris:AddItem(s, %s) end",
					id,
					tostring(tonumber(sound:GetAttribute("Volume")) or 0.5),
					tostring(tonumber(sound:GetAttribute("Speed")) or 1),
					tostring(math.max(1, (tonumber(sound:GetAttribute("Duration")) or 0) + 1))
				)
			end
		end
	end

	return table.concat(lines, "\n")
end

local function followEclipsePath(root, json)
	if type(json) ~= "string" then
		return nil
	end
	local ok, path = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	if not ok or type(path) ~= "table" then
		return nil
	end
	local node = root
	for _, step in ipairs(path) do
		if type(step) ~= "table" or step.link then
			return nil
		end
		local count, found = 0, nil
		for _, child in ipairs(node:GetChildren()) do
			if child.Name == step.name and child.ClassName == step.class then
				count += 1
				if count == step.index then
					found = child
					break
				end
			end
		end
		if not found then
			return nil
		end
		node = found
	end
	return node
end

-- Finds the object an Eclipse "Rigs" entry animates, the same way Eclipse links it
local function resolveEclipseEntry(entry, isCamera)
	local function usable(object)
		return object and object.Parent and (not isCamera or object:FindFirstChild("CamPart") ~= nil)
	end
	local reference = entry:FindFirstChild("Rig")
	local object = reference and reference:IsA("ObjectValue") and reference.Value
	if usable(object) then
		return object
	end
	object = followEclipsePath(game, entry:GetAttribute("RigGamePath"))
	if usable(object) and object.ClassName == entry:GetAttribute("RigClass") then
		return object
	end
	local id = entry:GetAttribute("RigId")
	local name = entry:GetAttribute("RigName") or entry.Name
	local class = entry:GetAttribute("RigClass")
	local byName
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if id and descendant:GetAttribute("EclipseTrackId") == id and usable(descendant) then
			return descendant
		end
		if not isCamera and descendant.Name == name and (not class or descendant.ClassName == class) then
			if byName then
				byName = false
			elseif byName == nil then
				byName = descendant
			end
		end
	end
	return byName or nil
end

-- Moon's rig test: a Model whose PrimaryPart drives joints
local function isRigModel(object)
	if not object:IsA("Model") then
		return false
	end
	local primary = object.PrimaryPart
	if not primary or not primary.Parent then
		return false
	end
	if primary:FindFirstChildOfClass("Bone") then
		return true
	end
	for _, descendant in ipairs(object:GetDescendants()) do
		if descendant:IsA("Motor6D") and descendant.Part0 == primary and descendant.Part1 and descendant.Part1.Parent then
			return true
		end
		if descendant:IsA("AnimationConstraint") and descendant.Attachment0 and descendant.Attachment0.Parent == primary then
			return true
		end
	end
	return false
end

-- FOV keys of an Eclipse camera: FovPart's C0.Y is the offset from the camera's default FOV
local function eclipseCameraFov(entry, sequence, cameraRig)
	local data = sequence:FindFirstChild("EclipseKeyframeData")
	if not data then
		return {}
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(eclipseReadChunks(data))
	end)
	if not ok or type(decoded) ~= "table" or type(decoded.tracks) ~= "table" then
		return {}
	end
	local default = tonumber(entry:GetAttribute("CameraDefaultFOV")) or 70
	local holder = cameraRig and cameraRig:FindFirstChild("FieldOfView")
	local defaultValue = holder and holder:FindFirstChild("default")
	if defaultValue and defaultValue:IsA("NumberValue") then
		default = defaultValue.Value
	end

	local keyframes = {}
	for _, track in ipairs(decoded.tracks) do
		local last = type(track.path) == "table" and track.path[#track.path]
		if type(last) == "table" and last.name == "FovPart" and type(track.keys) == "table" then
			for _, record in ipairs(track.keys) do
				local key = eclipseKeyDecode(record.data)
				if type(key) == "table" and typeof(key.C0) == "CFrame" and not key.Disabled then
					local style, direction = eclipseEase(key)
					keyframes[#keyframes + 1] = {
						Frame = record.frame,
						Value = math.clamp(default + key.C0.Y, 1, 120),
						Style = style,
						Direction = direction,
					}
				end
			end
		end
	end
	table.sort(keyframes, function(a, b)
		return a.Frame < b.Frame
	end)
	return keyframes
end

local function findEclipseProject(object)
	local node = object
	while node and node ~= game do
		if node:IsA("Folder") and node:GetAttribute("EclipseSave") == true and node:FindFirstChild("Rigs") then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function readEclipseProject(project)
	local fps = project:GetAttribute("FPS")
	if typeof(fps) ~= "number" or fps < 1 or fps > 1000 or fps % 1 ~= 0 then
		fps = 60
	end
	local Source = { object = project, name = project.Name, fps = fps, rigs = {}, items = {}, events = {} }

	local entries = project.Rigs:GetChildren()
	table.sort(entries, function(a, b)
		local first = tonumber(a:GetAttribute("Order")) or math.huge
		local second = tonumber(b:GetAttribute("Order")) or math.huge
		if first ~= second then
			return first < second
		end
		return a.Name < b.Name
	end)

	for _, entry in ipairs(entries) do
		local sequence = entry:FindFirstChild("Animation")
		if not sequence then
			continue
		end
		local isCamera = entry:GetAttribute("EclipseCamera") == true
		local object = resolveEclipseEntry(entry, isCamera)
		local label = project.Name .. " > " .. entry.Name

		-- Events: CodeBegin at Frame, CodeEnd at Frame + Duration (disabled tracks/events don't run)
		local events = sequence:FindFirstChild("EclipseEvents")
		if events and events:GetAttribute("Enabled") ~= false then
			for _, event in ipairs(events:GetChildren()) do
				local frame = event:GetAttribute("Frame")
				if not event:IsA("Folder") or typeof(frame) ~= "number" or event:GetAttribute("Enabled") == false then
					continue
				end
				frame = math.max(0, math.floor(frame + 0.5))
				local duration = math.max(0, math.floor((tonumber(event:GetAttribute("Duration")) or 0) + 0.5))
				local codeBegin = eclipseText(event, "CodeBegin")
				local extras = eclipseEventExtras(event, object)
				if extras ~= "" then
					codeBegin = codeBegin ~= "" and (codeBegin .. "\n" .. extras) or extras
				end
				if codeBegin ~= "" then
					Source.events[#Source.events + 1] = { Frame = frame, String = codeBegin }
				end
				local codeEnd = eclipseText(event, "CodeEnd")
				if codeEnd ~= "" then
					Source.events[#Source.events + 1] = { Frame = frame + duration, String = codeEnd }
				end
			end
		end

		if isCamera then
			-- Eclipse's camera is a rig (RootPart + CamPart), animated like a Moon CameraRig
			if object then
				Source.rigs[#Source.rigs + 1] = { instance = object }
			else
				warn(">> [Generate] The Eclipse camera of", label, "doesn't exist yet - open the project in Eclipse once so it builds the camera rig.")
			end
			local fovKeys = eclipseCameraFov(entry, sequence, object)
			if #fovKeys > 0 then
				Source.items[#Source.items + 1] = {
					label = label,
					isCamera = true,
					instance = workspace.CurrentCamera,
					properties = { { name = "FieldOfView", keyframes = fovKeys } },
				}
			end
			continue
		end

		if not object then
			warn(">> [Generate] Could not find:", label)
			continue
		end

		if isRigModel(object) then
			Source.rigs[#Source.rigs + 1] = { instance = object }
			continue
		end

		local item = { label = label, isCamera = false, instance = object, properties = {} }
		local properties = sequence:FindFirstChild("EclipseProperties")
		if properties then
			local ok, data = pcall(function()
				return eclipseDocDecode(HttpService:JSONDecode(eclipseReadChunks(properties)))
			end)
			if ok and type(data) == "table" and type(data.tracks) == "table" then
				for _, row in pairs(data.tracks) do
					if type(row) ~= "table" or row.enabled == false or row.disabled == true or type(row.keys) ~= "table" then
						continue
					end
					local frames = {}
					for frame in pairs(row.keys) do
						frames[#frames + 1] = frame
					end
					table.sort(frames)
					local keyframes = {}
					for _, frame in ipairs(frames) do
						local key = row.keys[frame]
						if type(key) ~= "table" or key.Disabled then
							continue
						end
						local value = eclipsePropertyValue(object, row.id, key)
						if value ~= nil then
							local style, direction = eclipseEase(key)
							keyframes[#keyframes + 1] = { Frame = frame, Value = value, Style = style, Direction = direction }
						end
					end
					item.properties[#item.properties + 1] = { name = row.id, keyframes = keyframes }
				end
			else
				warn(">> [Generate] Couldn't read the property tracks of", label)
			end
		end
		Source.items[#Source.items + 1] = item
	end

	return Source
end

-- Anything inside an Eclipse project folder, or a Moon save (StringValue)
local function readAnimationSource(object)
	local project = findEclipseProject(object)
	if project then
		return readEclipseProject(project)
	end
	if object:IsA("StringValue") then
		return readMoonSave(object)
	end
	return nil, "Invalid file (select a MoonAnimator2 save or an Eclipse Animator project)"
end

local function runGeneration(includeCutscene)
	local SelectedList = Selection:Get()
	if #SelectedList == 0 then
		warn(">> Please select MoonAnimator2 save file(s) or Eclipse Animator project(s) to generate.")
		return
	end

	local ForcedSelection = {}
	local userWantsRigs = false
	local prompted = false

	local handledSources = {}
	for _, SaveOBJ in pairs(SelectedList) do
		local Source, SourceError = readAnimationSource(SaveOBJ)
		if not Source then
			warn(">> " .. SourceError, SaveOBJ)
			continue
		end

		-- Selecting several parts of one Eclipse project generates it once
		if handledSources[Source.object] then
			continue
		end
		handledSources[Source.object] = true

		local FPS = Source.fps

		-- Create output model
		local OutputModel = Instance.new("Model")
		OutputModel.Name = Source.name .. "_VFX"

		-- Helper: ensure folder path exists inside OutputModel
		local function ensureFolderPath(parts)
			local current = OutputModel
			for _, name in ipairs(parts) do
				local child = current:FindFirstChild(name)
				if not child then
					child = Instance.new("Folder")
					child.Name = name
					child.Parent = current
				end
				current = child
			end
			return current
		end

		-- ========== PASS 1: Find BaseRoot & Detect Rigs ==========
		local BaseRoot = nil
		local detectedRigs = {} -- { {name=string, instance=Instance, isCameraRig=bool, hasAnimator=bool} }
		local hasCutscene = false

		for _, RigSource in ipairs(Source.rigs) do
			local actual = RigSource.instance
			if actual then
				local rigName = actual.Name
				local camRig = isCameraRig(actual)
				local hasAnim = hasAnimator(actual)

				if camRig and includeCutscene then
					hasCutscene = true
					detectedRigs[#detectedRigs + 1] = {
						name = rigName,
						instance = actual,
						isCameraRig = true,
						hasAnimator = hasAnim,
					}
					print(">> [Generate] Detected CameraRig:", rigName)
				elseif camRig then
					print(">> [Generate] Skipping CameraRig (no-cutscene mode):", rigName)
				elseif hasAnim then
					-- Character rig with Humanoid/AnimationController
					detectedRigs[#detectedRigs + 1] = {
						name = rigName,
						instance = actual,
						isCameraRig = false,
						hasAnimator = true,
					}
					print(">> [Generate] Detected animated rig:", rigName)
				end

				-- Set BaseRoot from the first non-camera rig
				if not BaseRoot and not camRig then
					local hrp = actual:FindFirstChild("HumanoidRootPart")
					if hrp then
						BaseRoot = hrp
					elseif actual:IsA("BasePart") then
						BaseRoot = actual
					elseif actual:IsA("Model") and actual.PrimaryPart then
						BaseRoot = actual.PrimaryPart
					end
				end
			end
		end

		-- Create RootPart in output
		if BaseRoot then
			local rp = Instance.new("Part")
			rp.Name = "RootPart"
			rp.Size = BaseRoot.Size
			rp.CFrame = BaseRoot.CFrame
			rp.Transparency = 1
			rp.CanTouch = false
			rp.CanCollide = false
			rp.CanQuery = false
			rp.Massless = true
			rp.Anchored = true
			rp:SetAttribute("IsRootPart", true)
			rp.Parent = OutputModel
			OutputModel.PrimaryPart = rp
		end

		-- Prompt user if there are standard character rigs detected
		local hasStandardRig = false
		for _, rig in ipairs(detectedRigs) do
			if not rig.isCameraRig then
				hasStandardRig = true
				break
			end
		end

		if hasStandardRig and not prompted then
			prompted = true
			userWantsRigs = promptCloneRigsSync()
		end

		-- Clone CameraRigs (always) AND standard Rigs (if user said Yes)
		for _, rig in ipairs(detectedRigs) do
			if rig.isCameraRig or userWantsRigs then
				local clone = rig.instance:Clone()
				clone:SetAttribute("GroupType", rig.isCameraRig and "CameraRig" or "CharacterRig")

				-- Eclipse poses rigs through Motor6D.C0 while it's open and keeps the rest pose in an attribute
				for _, motor in ipairs(clone:GetDescendants()) do
					if motor:IsA("Motor6D") then
						local rest = motor:GetAttribute("EclipseAnimatorDefaultC0")
						if typeof(rest) == "CFrame" then
							motor.C0 = rest
						end
					end
				end

				-- Find the root part of the rig
				local rigRoot = clone:FindFirstChild("HumanoidRootPart") or (clone:IsA("Model") and clone.PrimaryPart)

				-- Make all parts non-physical but keep unanchored so Motor6D works
				for _, part in ipairs(clone:GetDescendants()) do
					if part:IsA("BasePart") then
						part.CanTouch = false
						part.CanCollide = false
						part.CanQuery = false
						part.Massless = true
						-- Only anchor the root part; others stay unanchored for Motor6D
						if part == rigRoot then
							part.Anchored = true
						end
					end
				end

				-- Prevent Humanoid from auto-killing the cloned rig
				local hum = clone:FindFirstChildWhichIsA("Humanoid")
				if hum then
					hum.RequiresNeck = false
					hum.BreakJointsOnDeath = false
					hum.Health = hum.MaxHealth
				end

				clone.Parent = OutputModel
				print(">> [Generate] Cloned Rig into output:", rig.name)
			end
		end

		-- ========== PASS 2: Clone instances & compile animation code ==========
		local clonedBPs = {} -- actualBasePart → clonedBasePart (tracks what we've already cloned)
		local clonedOthers = {} -- key → true
		local moduleRefLines = {} -- "local varName = model.X.Y.Z"
		local moduleAnimBuffer = {} -- { {var=string, code=string} } grouped by instance
		local cameraFOVKeyframes = {} -- { {time, value, style, direction} } for physical FOV folder
		local cameraOtherAnims = {} -- {code} for non-FOV camera anims
		local usedVarNames = {}
		local varCounter = 0

		for _, ItemSource in ipairs(Source.items) do
			local actual = ItemSource.instance

			if not actual then
				warn(">> [Generate] Could not find:", ItemSource.label)
				continue
			end

			-- Determine category
			local isCamera = ItemSource.isCamera
			local isWorkspaceDesc = (not isCamera) and actual:IsDescendantOf(workspace)
			local isLightingChild = false
			pcall(function()
				isLightingChild = (actual.Parent == game:GetService("Lighting"))
					or (actual == game:GetService("Lighting"))
			end)
			local isCoreGuiChild = false
			pcall(function()
				isCoreGuiChild = actual:IsDescendantOf(game:GetService("CoreGui"))
			end)
			local isScreenCover = (actual.Name == "Screen Cover")

			-- No-cutscene mode: skip camera, lighting, and screen-space items entirely
			if not includeCutscene and (isCamera or isLightingChild or isCoreGuiChild or isScreenCover) then
				continue
			end

			local varName = ""
			local instanceAccessor = ""

			if isCamera then
				instanceAccessor = "workspace.CurrentCamera"
				varName = "ref_Camera"
				-- Prevent cloning the camera object
				clonedOthers[actual] = true

				-- ---- Workspace descendants (BasePart, Beam, ParticleEmitter, Light, etc.) ----
			elseif isWorkspaceDesc and not isScreenCover then
				local cloneTarget = nil
				if actual:IsA("BasePart") then
					cloneTarget = actual
				else
					cloneTarget = findBasePartAncestor(actual)
				end

				if cloneTarget then
					if not clonedBPs[cloneTarget] then
						local pathToTarget = getRelativePath(cloneTarget, workspace)
						local parentParts = {}
						for i = 1, #pathToTarget - 1 do
							parentParts[i] = pathToTarget[i]
						end
						local container = ensureFolderPath(parentParts)

						local clone = cloneTarget:Clone()
						clone.CanTouch = false
						clone.CanCollide = false
						clone.CanQuery = false
						clone.Massless = true
						clone.Anchored = true
						clone.Parent = container
						clonedBPs[cloneTarget] = clone
					end
				else
					-- No BasePart ancestor; clone the instance directly
					if not clonedOthers[actual] then
						local pathParts = getRelativePath(actual, workspace)
						local parentParts = {}
						for i = 1, #pathParts - 1 do
							parentParts[i] = pathParts[i]
						end
						local container = ensureFolderPath(parentParts)
						local clone = actual:Clone()
						clone.Parent = container
						clonedOthers[actual] = true
					end
				end

				local fullPath = getRelativePath(actual, workspace)
				instanceAccessor = pathToLuaAccessor(fullPath)
				varName = "ref_" .. sanitizeVarName(table.concat(fullPath, "_"))

				-- ---- Lighting children (ColorCorrection, Atmosphere, etc.) ----
			elseif isLightingChild then
				if actual == game:GetService("Lighting") then
					instanceAccessor = "game:GetService('Lighting')"
					varName = "ref_Lighting"
				else
					if not clonedOthers[actual] then
						local clone = actual:Clone()
						clone:SetAttribute("GroupType", "CameraEffect")
						clone.Parent = OutputModel
						clonedOthers[actual] = true
					end
					instanceAccessor = pathToLuaAccessor({ actual.Name })
					varName = "ref_" .. sanitizeVarName(actual.Name)
				end

				-- ---- CoreGui / Vignette ----
			elseif isCoreGuiChild then
				if not clonedOthers["Vignette"] then
					local vigUI = script:FindFirstChild("VignetteUI")
					if vigUI then
						local clone = vigUI:Clone()
						clone:SetAttribute("GroupType", "Vignette")
						clone.Parent = OutputModel
						clonedOthers["Vignette"] = true
					end
				end
				instanceAccessor = "model.VignetteUI.L"
				varName = "ref_Vignette_L"
				-- Also register R
				if not usedVarNames["ref_Vignette_R"] then
					usedVarNames["ref_Vignette_R"] = true
					moduleRefLines[#moduleRefLines + 1] = "local ref_Vignette_R = model.VignetteUI.R"
				end

				-- ---- Screen Cover ----
			elseif isScreenCover then
				if not clonedOthers["ScreenCover"] then
					local scUI = script:FindFirstChild("ScreenCoverUI")
					if scUI then
						local clone = scUI:Clone()
						clone:SetAttribute("GroupType", "ScreenCover")
						clone.Parent = OutputModel
						clonedOthers["ScreenCover"] = true
					end
				end
				instanceAccessor = 'model.ScreenCoverUI["Screen Cover"]'
				varName = "ref_ScreenCover"
			end

			-- Skip if we couldn't determine a path
			if varName == "" then
				warn(">> [Generate] Skipping unhandled item:", ItemSource.label)
				continue
			end

			-- Ensure unique variable name
			if usedVarNames[varName] then
				varCounter += 1
				varName = varName .. "_" .. varCounter
			end
			usedVarNames[varName] = true

			-- Add variable declaration (skip camera - handled in setupCamera)
			if not isCamera then
				moduleRefLines[#moduleRefLines + 1] = "local " .. varName .. " = " .. instanceAccessor
			end

			-- ========== Compile property keyframes → animation code ==========
			for _, PropertySource in ipairs(ItemSource.properties) do
				local Property = PropertySource.name

				-- Build keyframe list
				local keyframes = {}
				for _, raw in ipairs(PropertySource.keyframes) do
					local val = raw.Value

					-- Make CFrame relative to BaseRoot
					if Property == "CFrame" and BaseRoot and typeof(val) == "CFrame" then
						val = BaseRoot.CFrame:ToObjectSpace(val)
					end

					keyframes[#keyframes + 1] = {
						Time = frameToTime(raw.Frame, FPS),
						Style = fixEaseStyle(raw.Style),
						Direction = fixEaseDirection(raw.Direction),
						Value = val,
						ValueClass = raw.ValueClass,
					}
				end

				if #keyframes == 0 then
					continue
				end

				-- Determine the property type on the actual instance
				local propType = nil
				pcall(function()
					propType = typeof(actual[Property])
				end)

				-- Generate animation data
				local isRelCF = (Property == "CFrame" and BaseRoot ~= nil)
				local didCamera = false

				-- Camera properties: handled per-keyframe
				for i = 1, #keyframes do
					local kf = keyframes[i]
					local nextKf = keyframes[i + 1]
					local time = kf.Time
					local timeStr = string.format("%.4g", time)

					if isCamera and Property == "FieldOfView" then
						cameraFOVKeyframes[#cameraFOVKeyframes + 1] = {
							time = time, value = kf.Value,
							style = kf.Style, direction = kf.Direction,
						}
						didCamera = true
					elseif isCamera then
						if kf.Style == "Constant" or not nextKf then
							local valCode = valueToLuaCode(kf.Value, kf.ValueClass)
							cameraOtherAnims[#cameraOtherAnims + 1] = string.format("setProperty(camera, '%s', %s, %s)", Property, valCode, timeStr)
						else
							local dur = nextKf.Time - time
							if dur <= 0 then dur = 0.001 end
							local fromVal = valueToLuaCode(kf.Value, kf.ValueClass)
							local toVal = valueToLuaCode(nextKf.Value, nextKf.ValueClass)
							cameraOtherAnims[#cameraOtherAnims + 1] = string.format("tweenProperty(camera, '%s', %s, %s, %s, %.4g, '%s', '%s')", Property, fromVal, toVal, timeStr, dur, nextKf.Style, nextKf.Direction)
						end
						didCamera = true
					end
				end

				-- Non-camera: generate animation code
				if not didCamera then
					-- Boolean/non-tweenable: generate direct setProperty calls
					if propType == "boolean" or propType == "string" or propType == "EnumItem" then
						for i = 1, #keyframes do
							local kf = keyframes[i]
							local timeStr = string.format("%.4g", kf.Time)
							local valCode = valueToLuaCode(kf.Value, kf.ValueClass)
							moduleAnimBuffer[#moduleAnimBuffer + 1] = {var = varName, code = string.format("setProperty(%s, '%s', %s, %s)", varName, Property, valCode, timeStr)}
						end
					else
						-- Tweenable: generate playKeyframes call
						local kfArray = {}
						for i = 1, #keyframes do
							local kf = keyframes[i]
							local timeStr = string.format("%.4g", kf.Time)
							local valCode = valueToLuaCode(kf.Value, kf.ValueClass)

							if propType == "NumberSequence" then
								valCode = "NumberSequence.new({NumberSequenceKeypoint.new(0, " .. valCode .. "), NumberSequenceKeypoint.new(1, " .. valCode .. ")})"
							elseif propType == "ColorSequence" then
								valCode = "ColorSequence.new(" .. valCode .. ")"
							end

							local style = kf.Style or "Linear"
							if style == "Constant" then style = "Linear" end
							local dir = kf.Direction or "In"
							kfArray[#kfArray + 1] = string.format("{%s, %s, '%s', '%s'}", timeStr, valCode, style, dir)
						end

						local targetType = isRelCF and "RelCFrame" or propType
						local code = string.format("playKeyframes(%s, '%s', '%s', {\n\t\t%s\n\t}%s)",
							varName, Property, targetType, table.concat(kfArray, ",\n\t\t"), isRelCF and ", baseRoot" or ""
						)

						moduleAnimBuffer[#moduleAnimBuffer + 1] = {var = varName, code = code}
					end
				end
			end

			-- For Vignette: duplicate animations for R side
			if isCoreGuiChild and varName:find("Vignette_L") then
				local rEntries = {}
				for _, entry in ipairs(moduleAnimBuffer) do
					if entry.code:find(varName) then
						rEntries[#rEntries + 1] =
							{ var = "ref_Vignette_R", code = entry.code:gsub(varName, "ref_Vignette_R") }
					end
				end
				for _, entry in ipairs(rEntries) do
					moduleAnimBuffer[#moduleAnimBuffer + 1] = entry
				end
			end
		end

		-- ========== PASS 3: Collect & remap event code ==========
		local eventLines = {}
		local eventContainer = {}
		for _, EventSource in ipairs(Source.events) do
			eventContainer[#eventContainer + 1] = {
				Time = frameToTime(EventSource.Frame, FPS),
				String = EventSource.String,
			}
		end
		table.sort(eventContainer, function(a, b)
			return a.Time < b.Time
		end)

		for _, ev in ipairs(eventContainer) do
			local code = ev.String
			code = code:gsub("workspace%.", "model.")
			code = code:gsub('workspace%["', 'model["')
			code = code:gsub('([%w_%.%[%]"]+):Emit%((%d+)%)', "safeEmit(%1, %2)")
			code = code:gsub("[^\n]*%.AttachToPart[^\n]*", "")
			code = code:gsub(
				"v:IsA%('ParticleEmitter'%)%s+or%s+v:IsA%('Beam'%)%s+or%s+v:IsA%('Trail'%)",
				"v:IsA('ParticleEmitter')"
			)
			code = code:gsub(
				'v:IsA%("ParticleEmitter"%)[%s]+or[%s]+v:IsA%("Beam"%)[%s]+or[%s]+v:IsA%("Trail"%)',
				'v:IsA("ParticleEmitter")'
			)
			-- Remap shared.vfx calls to ForgeVFX module
			code = code:gsub("shared%.vfx%.", "ForgeVFX.")
			local timeStr = string.format("%.6g", ev.Time)

			if ev.Time == 0 then
				eventLines[#eventLines + 1] = "task.spawn(function()"
				for line in code:gmatch("[^\n]+") do
					eventLines[#eventLines + 1] = "\t" .. line
				end
				eventLines[#eventLines + 1] = "end)"
			else
				eventLines[#eventLines + 1] = "task.delay(" .. timeStr .. ", function()"
				for line in code:gmatch("[^\n]+") do
					eventLines[#eventLines + 1] = "\t" .. line
				end
				eventLines[#eventLines + 1] = "end)"
			end
		end
		-- ========== PASS 3.5: Clone event-referenced instances ==========
		-- Scan event code for workspace.X.Y.Z references and clone them into OutputModel
		local eventReferencedPaths = {} -- set of path strings we've already handled

		local function mergeClone(srcInst, destParent)
			local destInst = destParent:FindFirstChild(srcInst.Name)
			if not destInst then
				local clone = srcInst:Clone()
				for _, desc in ipairs(clone:GetDescendants()) do
					if desc:IsA("BasePart") then
						desc.CanTouch = false
						desc.CanCollide = false
						desc.CanQuery = false
						desc.Massless = true
						desc.Anchored = true
					end
				end
				if clone:IsA("BasePart") then
					clone.CanTouch = false
					clone.CanCollide = false
					clone.CanQuery = false
					clone.Massless = true
					clone.Anchored = true
				end
				clone.Parent = destParent
				print(">> [Generate] Cloned event dependency:", srcInst.Name)
			elseif srcInst:IsA("Folder") or srcInst:IsA("Model") then
				for _, child in ipairs(srcInst:GetChildren()) do
					mergeClone(child, destInst)
				end
			end
		end

		for _, ev in ipairs(eventContainer) do
			local rawCode = ev.String

			-- Match workspace.Fx.SlashFx, workspace.Fx.SlashFx.ParticleEmitter, etc.
			for pathStr in rawCode:gmatch("workspace%.([%w_]+[%w_%.]+)") do
				if not eventReferencedPaths[pathStr] then
					eventReferencedPaths[pathStr] = true

					local pathParts = string.split(pathStr, ".")

					-- Walk workspace to find the deepest existing ancestor
					local current = workspace
					local topLevelName = nil
					local topLevelInstance = nil

					for i, part in ipairs(pathParts) do
						local child = current:FindFirstChild(part)
						if not child then
							break
						end
						if i == 1 then
							topLevelName = part
							topLevelInstance = child
						end
						current = child
					end

					if topLevelInstance then
						mergeClone(topLevelInstance, OutputModel)
					end
				end
			end

			-- Also match workspace["Name"].X.Y pattern
			for bracketName in rawCode:gmatch('workspace%[%"([^%"]+)%"%]') do
				if not eventReferencedPaths["bracket_" .. bracketName] then
					eventReferencedPaths["bracket_" .. bracketName] = true

					local topLevelInstance = workspace:FindFirstChild(bracketName)
					if topLevelInstance then
						mergeClone(topLevelInstance, OutputModel)
					end
				end
			end
		end

		-- ========== ASSEMBLE MODULE SOURCE ==========
		local src = {}

		-- Header
		src[#src + 1] = "-- Auto-generated VFX Module by VFXComplier Plugin"
		src[#src + 1] = "-- Source: " .. Source.name
		src[#src + 1] = ""
		src[#src + 1] = "local TweenService = game:GetService('TweenService')"
		src[#src + 1] = "local RunService = game:GetService('RunService')"
		src[#src + 1] = "local Debris = game:GetService('Debris')"
		src[#src + 1] = "local Players = game:GetService('Players')"

		-- Requires: ForgeVFX + Payload library (always emitted, path from Settings)
		local pathSegments = parseForgeVFXPath(getForgeVFXPath()) or string.split(DEFAULT_FORGEVFX_PATH, ".")
		local forgeExpr = segmentsToRequireExpr(pathSegments)
		local payloadParentExpr = segmentsToRequireExpr(pathSegments, #pathSegments - 1)
		src[#src + 1] = "local ForgeVFX = require(" .. forgeExpr .. ")"
		src[#src + 1] = "local Payload = require(" .. payloadParentExpr .. ':WaitForChild("Payload"):WaitForChild("VFXPayload"))'
		src[#src + 1] = "local setProperty, tweenProperty, playKeyframes, safeEmit = Payload.setProperty, Payload.tweenProperty, Payload.playKeyframes, Payload.safeEmit"

		src[#src + 1] = ""
		src[#src + 1] = "local module = {}"
		src[#src + 1] = ""

		-- === Animation dictionary ===
		if #detectedRigs > 0 then
			src[#src + 1] = "-- === Animation IDs ==="
			src[#src + 1] = "module.Animations = {"
			for _, rig in ipairs(detectedRigs) do
				local label = rig.isCameraRig and (rig.name .. " (CameraRig)") or rig.name
				src[#src + 1] = '\t["' .. label .. '"] = "", -- Insert rbxassetid:// here'
			end
			src[#src + 1] = "}"
			src[#src + 1] = ""
		end

		-- === Cutscene flag ===
		if hasCutscene then
			src[#src + 1] = "module.HasCutscene = true"
		else
			src[#src + 1] = "module.HasCutscene = false"
		end
		src[#src + 1] = ""

		-- Play function
		src[#src + 1] = "function module.Play(rootPart, offset, lifeTime, config)"
		src[#src + 1] = "\tconfig = config or {}"
		src[#src + 1] = "\toffset = offset or CFrame.new()"
		src[#src + 1] = "\tlifeTime = lifeTime or 10"
		src[#src + 1] = "\tlocal sizeMulti = config.SizeMulti or 1"
		src[#src + 1] = "\tlocal autoPlayAnimations = (config.AutoPlayAnimations ~= false) -- defaults to true"
		if includeCutscene then
			src[#src + 1] = "\tlocal playCutscene = (config.PlayCutscene ~= false) -- defaults to true"
		end
		src[#src + 1] = ""
		src[#src + 1] = "\tlocal model = script.Parent:Clone()"
		src[#src + 1] = "\tlocal selfModule = model:FindFirstChild('VFXPlayer')"
		src[#src + 1] = "\tif selfModule then selfModule:Destroy() end"
		src[#src + 1] = ""
		src[#src + 1] = "\tlocal baseRoot = model:FindFirstChild('RootPart')"
		src[#src + 1] = "\tlocal animationTracks = {}"
		src[#src + 1] = ""
		if includeCutscene then
			src[#src + 1] = "\t-- === Save original state for restoration ==="
			src[#src + 1] = "\tlocal _Lighting = game:GetService('Lighting')"
			src[#src + 1] = "\tlocal _savedLighting = {}"
			src[#src + 1] =
				"\tfor _, prop in ipairs({'Ambient','OutdoorAmbient','Brightness','ColorShift_Bottom','ColorShift_Top','FogColor','FogEnd','FogStart','EnvironmentDiffuseScale','EnvironmentSpecularScale','ExposureCompensation'}) do"
			src[#src + 1] = "\t\tpcall(function() _savedLighting[prop] = _Lighting[prop] end)"
			src[#src + 1] = "\tend"
			src[#src + 1] = "\tlocal _savedCameraFOV = workspace.CurrentCamera.FieldOfView"
			src[#src + 1] = "\tlocal _savedAtmospheres = {}"
			src[#src + 1] = "\tfor _, child in ipairs(_Lighting:GetChildren()) do"
			src[#src + 1] = "\t\tif child:IsA('Atmosphere') then"
			src[#src + 1] =
				"\t\t\t_savedAtmospheres[child] = {Density=child.Density, Offset=child.Offset, Color=child.Color, Decay=child.Decay, Glare=child.Glare, Haze=child.Haze}"
			src[#src + 1] = "\t\tend"
			src[#src + 1] = "\tend"
			src[#src + 1] = ""
			src[#src + 1] = "\tlocal function _restoreState()"
			src[#src + 1] = "\t\tfor prop, val in pairs(_savedLighting) do"
			src[#src + 1] = "\t\t\tpcall(function() _Lighting[prop] = val end)"
			src[#src + 1] = "\t\tend"
			src[#src + 1] = "\t\tworkspace.CurrentCamera.FieldOfView = _savedCameraFOV"
			src[#src + 1] = "\t\tfor atm, props in pairs(_savedAtmospheres) do"
			src[#src + 1] = "\t\t\tif atm and atm.Parent then"
			src[#src + 1] = "\t\t\t\tfor p, v in pairs(props) do pcall(function() atm[p] = v end) end"
			src[#src + 1] = "\t\t\tend"
			src[#src + 1] = "\t\tend"
			src[#src + 1] = "\tend"
		else
			src[#src + 1] = "\tlocal function _restoreState() end"
		end
		src[#src + 1] = ""
		src[#src + 1] = "\tif rootPart and typeof(rootPart) == 'Instance' and rootPart:IsA('BasePart') then"
		src[#src + 1] = "\t\tlocal endTime = os.clock() + lifeTime"
		src[#src + 1] = "\t\ttask.spawn(function()"
		src[#src + 1] = "\t\t\twhile true do"
		src[#src + 1] = "\t\t\t\tif os.clock() >= endTime or not rootPart:IsDescendantOf(game) then"
		src[#src + 1] = "\t\t\t\t\t_restoreState()"
		src[#src + 1] = "\t\t\t\t\tDebris:AddItem(model, 0)"
		src[#src + 1] = "\t\t\t\t\tbreak"
		src[#src + 1] = "\t\t\t\tend"
		src[#src + 1] = "\t\t\t\tmodel:PivotTo(rootPart.CFrame * offset)"
		src[#src + 1] = "\t\t\t\tRunService.RenderStepped:Wait()"
		src[#src + 1] = "\t\t\tend"
		src[#src + 1] = "\t\tend)"
		src[#src + 1] = "\telse"
		src[#src + 1] = "\t\ttask.delay(lifeTime, function()"
		src[#src + 1] = "\t\t\t_restoreState()"
		src[#src + 1] = "\t\t\tDebris:AddItem(model, 0)"
		src[#src + 1] = "\t\tend)"
		src[#src + 1] = "\tend"
		src[#src + 1] = ""
		src[#src + 1] = "\tfor _, item in pairs(model:GetChildren()) do"
		src[#src + 1] = "\t\tif item:GetAttribute('GroupType') == 'CharacterRig' then"
		src[#src + 1] = "\t\t\tlocal hum = item:FindFirstChildWhichIsA('Humanoid')"
		src[#src + 1] = "\t\t\tif hum then"
		src[#src + 1] = "\t\t\t\thum.RequiresNeck = false"
		src[#src + 1] = "\t\t\t\thum.BreakJointsOnDeath = false"
		src[#src + 1] = "\t\t\t\thum.Health = hum.MaxHealth"
		src[#src + 1] = "\t\t\tend"
		src[#src + 1] = "\t\tend"
		src[#src + 1] = "\tend"
		src[#src + 1] = ""
		src[#src + 1] = "\tmodel.Parent = workspace"
		src[#src + 1] = "\ttask.wait()"
		src[#src + 1] = ""
		src[#src + 1] = "\t-- === EmitDuration: auto enable/disable ParticleEmitters ==="
		src[#src + 1] = "\tfor _, desc in ipairs(model:GetDescendants()) do"
		src[#src + 1] = "\t\tif desc:IsA('ParticleEmitter') then"
		src[#src + 1] = "\t\t\tlocal emitDur = desc:GetAttribute('EmitDuration')"
		src[#src + 1] = "\t\t\tif emitDur and emitDur > 0 then"
		src[#src + 1] = "\t\t\t\tdesc.Enabled = true"
		src[#src + 1] = "\t\t\t\ttask.delay(emitDur, function()"
		src[#src + 1] = "\t\t\t\t\tif desc and desc.Parent then desc.Enabled = false end"
		src[#src + 1] = "\t\t\t\tend)"
		src[#src + 1] = "\t\t\tend"
		src[#src + 1] = "\t\tend"
		src[#src + 1] = "\tend"
		src[#src + 1] = ""

		-- Instance references
		src[#src + 1] = "\t-- === Instance References ==="
		for _, line in ipairs(moduleRefLines) do
			src[#src + 1] = "\t" .. line
		end
		src[#src + 1] = ""

		-- Group type handling (CameraEffect → Camera, Vignette → PlayerGui)
		if includeCutscene then
			src[#src + 1] = "\t-- === Special Instance Handling (Camera Effects, UI) ==="
			src[#src + 1] = "\tfor _, item in pairs(model:GetChildren()) do"
			src[#src + 1] = "\t\tlocal groupType = item:GetAttribute('GroupType')"
			src[#src + 1] = "\t\tif groupType == 'CameraEffect' then"
			src[#src + 1] = "\t\t\titem.Parent = workspace.CurrentCamera"
			src[#src + 1] = "\t\t\tmodel.AncestryChanged:Once(function()"
			src[#src + 1] = "\t\t\t\tDebris:AddItem(item, 0)"
			src[#src + 1] = "\t\t\tend)"
			src[#src + 1] = "\t\telseif groupType == 'Vignette' or groupType == 'ScreenCover' then"
			src[#src + 1] = "\t\t\tif Players.LocalPlayer then"
			src[#src + 1] = "\t\t\t\tlocal pg = Players.LocalPlayer:FindFirstChild('PlayerGui')"
			src[#src + 1] = "\t\t\t\tif pg then item.Parent = pg end"
			src[#src + 1] = "\t\t\t\tmodel.AncestryChanged:Once(function()"
			src[#src + 1] = "\t\t\t\t\tDebris:AddItem(item, 0)"
			src[#src + 1] = "\t\t\t\tend)"
			src[#src + 1] = "\t\t\tend"
			src[#src + 1] = "\t\tend"
			src[#src + 1] = "\tend"
			src[#src + 1] = ""
		end

		-- === Animation auto-play ===
		if #detectedRigs > 0 then
			src[#src + 1] = "\t-- === Animation Playback ==="
			src[#src + 1] = "\tif autoPlayAnimations then"

			for _, rig in ipairs(detectedRigs) do
				local label = rig.isCameraRig and (rig.name .. " (CameraRig)") or rig.name

				if rig.isCameraRig then
					-- CameraRig: load animation on its AnimationController inside the cloned model
					src[#src + 1] = '\t\t-- CameraRig: "' .. rig.name .. '"'
					src[#src + 1] = "\t\tdo"
					src[#src + 1] = '\t\t\tlocal camRigModel = model:FindFirstChild("' .. rig.name .. '")'
					src[#src + 1] = "\t\t\tif camRigModel then"
					src[#src + 1] =
						"\t\t\t\tlocal animController = camRigModel:FindFirstChildWhichIsA('AnimationController')"
					src[#src + 1] = "\t\t\t\t\tor camRigModel:FindFirstChildWhichIsA('Humanoid')"
					src[#src + 1] = "\t\t\t\tif animController then"
					src[#src + 1] = "\t\t\t\t\tlocal animator = animController:FindFirstChildWhichIsA('Animator')"
					src[#src + 1] = "\t\t\t\t\tif not animator then"
					src[#src + 1] = "\t\t\t\t\t\tanimator = Instance.new('Animator')"
					src[#src + 1] = "\t\t\t\t\t\tanimator.Parent = animController"
					src[#src + 1] = "\t\t\t\t\tend"
					src[#src + 1] = '\t\t\t\t\tlocal animId = module.Animations["' .. label .. '"]'
					src[#src + 1] = '\t\t\t\t\tif animId and animId ~= "" then'
					src[#src + 1] = "\t\t\t\t\t\tlocal matchId = animId:match('%d+')"
					src[#src + 1] = "\t\t\t\t\t\tif matchId then animId = 'rbxassetid://' .. matchId end"
					src[#src + 1] = "\t\t\t\t\t\tlocal animObj = Instance.new('Animation')"
					src[#src + 1] = "\t\t\t\t\t\tanimObj.AnimationId = animId"
					src[#src + 1] = "\t\t\t\t\t\tlocal track = animator:LoadAnimation(animObj)"
					src[#src + 1] = "\t\t\t\t\t\ttrack:Play()"
					src[#src + 1] = '\t\t\t\t\t\tanimationTracks["' .. label .. '"] = track'
					src[#src + 1] = "\t\t\t\t\tend"
					src[#src + 1] = "\t\t\t\tend"
					src[#src + 1] = "\t\t\tend"
					src[#src + 1] = "\t\tend"
					src[#src + 1] = ""
				elseif userWantsRigs then
					-- Cloned display rig: use AnimationController (not Humanoid) for reliable playback
					src[#src + 1] = '\t\t-- Cloned Character Rig: "' .. rig.name .. '"'
					src[#src + 1] = "\t\tdo"
					src[#src + 1] = '\t\t\tlocal charModel = model:FindFirstChild("' .. rig.name .. '")'
					src[#src + 1] = "\t\t\tif charModel then"
					src[#src + 1] =
						"\t\t\t\tlocal animController = charModel:FindFirstChildWhichIsA('AnimationController')"
					src[#src + 1] = "\t\t\t\tif not animController then"
					src[#src + 1] = "\t\t\t\t\tanimController = Instance.new('AnimationController')"
					src[#src + 1] = "\t\t\t\t\tanimController.Parent = charModel"
					src[#src + 1] = "\t\t\t\tend"
					src[#src + 1] = "\t\t\t\tlocal animator = animController:FindFirstChildWhichIsA('Animator')"
					src[#src + 1] = "\t\t\t\tif not animator then"
					src[#src + 1] = "\t\t\t\t\tanimator = Instance.new('Animator')"
					src[#src + 1] = "\t\t\t\t\tanimator.Parent = animController"
					src[#src + 1] = "\t\t\t\tend"
					src[#src + 1] = '\t\t\t\tlocal animId = module.Animations["' .. label .. '"]'
					src[#src + 1] = '\t\t\t\tif animId and animId ~= "" then'
					src[#src + 1] = "\t\t\t\t\tlocal matchId = animId:match('%d+')"
					src[#src + 1] = "\t\t\t\t\tif matchId then animId = 'rbxassetid://' .. matchId end"
					src[#src + 1] = "\t\t\t\t\tlocal animObj = Instance.new('Animation')"
					src[#src + 1] = "\t\t\t\t\tanimObj.AnimationId = animId"
					src[#src + 1] = "\t\t\t\t\tlocal track = animator:LoadAnimation(animObj)"
					src[#src + 1] = "\t\t\t\t\ttrack:Play()"
					src[#src + 1] = '\t\t\t\t\tanimationTracks["' .. label .. '"] = track'
					src[#src + 1] = "\t\t\t\tend"
					src[#src + 1] = "\t\t\tend"
					src[#src + 1] = "\t\tend"
					src[#src + 1] = ""
				else
					-- External rig: load animation on the rootPart's parent Humanoid
					src[#src + 1] = '\t\t-- External Character Rig: "' .. rig.name .. '"'
					src[#src + 1] = "\t\tdo"
					src[#src + 1] = "\t\t\tif rootPart and rootPart.Parent then"
					src[#src + 1] = "\t\t\t\tlocal humanoid = rootPart.Parent:FindFirstChildWhichIsA('Humanoid')"
					src[#src + 1] = "\t\t\t\t\tor rootPart.Parent:FindFirstChildWhichIsA('AnimationController')"
					src[#src + 1] = "\t\t\t\tif humanoid then"
					src[#src + 1] = "\t\t\t\t\tlocal animator = humanoid:FindFirstChildWhichIsA('Animator')"
					src[#src + 1] = "\t\t\t\t\tif not animator then"
					src[#src + 1] = "\t\t\t\t\t\tanimator = Instance.new('Animator')"
					src[#src + 1] = "\t\t\t\t\t\tanimator.Parent = humanoid"
					src[#src + 1] = "\t\t\t\t\tend"
					src[#src + 1] = '\t\t\t\t\tlocal animId = module.Animations["' .. label .. '"]'
					src[#src + 1] = '\t\t\t\t\tif animId and animId ~= "" then'
					src[#src + 1] = "\t\t\t\t\t\tlocal matchId = animId:match('%d+')"
					src[#src + 1] = "\t\t\t\t\t\tif matchId then animId = 'rbxassetid://' .. matchId end"
					src[#src + 1] = "\t\t\t\t\t\tlocal animObj = Instance.new('Animation')"
					src[#src + 1] = "\t\t\t\t\t\tanimObj.AnimationId = animId"
					src[#src + 1] = "\t\t\t\t\t\tlocal track = animator:LoadAnimation(animObj)"
					src[#src + 1] = "\t\t\t\t\t\ttrack:Play()"
					src[#src + 1] = '\t\t\t\t\t\tanimationTracks["' .. label .. '"] = track'
					src[#src + 1] = "\t\t\t\t\tend"
					src[#src + 1] = "\t\t\t\tend"
					src[#src + 1] = "\t\t\tend"
					src[#src + 1] = "\t\tend"
					src[#src + 1] = ""
				end
			end

			src[#src + 1] = "\tend"
			src[#src + 1] = ""
		end

		-- === Create physical FOV folder ===
		if #cameraFOVKeyframes > 0 then
			local fovFolder = Instance.new("Folder")
			fovFolder.Name = "FOV"
			for _, kf in ipairs(cameraFOVKeyframes) do
				local nv = Instance.new("NumberValue")
				nv.Name = string.format("%.4g", kf.time)
				nv.Value = kf.value
				nv:SetAttribute("EasingStyle", kf.style or "Linear")
				nv:SetAttribute("EasingDirection", kf.direction or "In")
				nv.Parent = fovFolder
			end
			fovFolder.Parent = OutputModel
		end

		-- === setupCamera function ===
		local camRigName = nil
		for _, rig in ipairs(detectedRigs) do
			if rig.isCameraRig then
				camRigName = rig.name
				break
			end
		end

		if includeCutscene and (#cameraFOVKeyframes > 0 or #cameraOtherAnims > 0 or hasCutscene) then
			src[#src + 1] = "\tlocal function setupCamera()"
			src[#src + 1] = "\t\tlocal camera = workspace.CurrentCamera"
			src[#src + 1] = ""

			-- FOV from physical folder
			if #cameraFOVKeyframes > 0 then
				src[#src + 1] = "\t\tlocal fovFolder = model:FindFirstChild('FOV')"
				src[#src + 1] = "\t\tif fovFolder then"
				src[#src + 1] = "\t\t\tlocal keys = fovFolder:GetChildren()"
				src[#src + 1] = "\t\t\ttable.sort(keys, function(a, b) return tonumber(a.Name) < tonumber(b.Name) end)"
				src[#src + 1] = "\t\t\tfor i, key in ipairs(keys) do"
				src[#src + 1] = "\t\t\t\tlocal nextKey = keys[i + 1]"
				src[#src + 1] = "\t\t\t\tlocal t = tonumber(key.Name) or 0"
				src[#src + 1] = "\t\t\t\tif nextKey then"
				src[#src + 1] = "\t\t\t\t\tlocal nt = tonumber(nextKey.Name) or 0"
				src[#src + 1] = "\t\t\t\t\tlocal dur = nt - t"
				src[#src + 1] = "\t\t\t\t\tlocal style = key:GetAttribute('EasingStyle') or 'Linear'"
				src[#src + 1] = "\t\t\t\t\tlocal dir = key:GetAttribute('EasingDirection') or 'In'"
				src[#src + 1] =
					"\t\t\t\t\ttweenProperty(camera, 'FieldOfView', key.Value, nextKey.Value, t, dur, style, dir)"
				src[#src + 1] = "\t\t\t\telse"
				src[#src + 1] = "\t\t\t\t\tsetProperty(camera, 'FieldOfView', key.Value, t)"
				src[#src + 1] = "\t\t\t\tend"
				src[#src + 1] = "\t\t\tend"
				src[#src + 1] = "\t\tend"
				src[#src + 1] = ""
			end

			-- Other camera property animations
			if #cameraOtherAnims > 0 then
				for _, line in ipairs(cameraOtherAnims) do
					src[#src + 1] = "\t\t" .. line
				end
				src[#src + 1] = ""
			end

			-- Cutscene (CamPart follow + camera type)
			if hasCutscene and camRigName then
				src[#src + 1] = "\t\tif playCutscene then"
				src[#src + 1] = '\t\t\tlocal cameraRig = model:FindFirstChild("' .. camRigName .. '")'
				src[#src + 1] = "\t\t\tif cameraRig then"
				src[#src + 1] = "\t\t\t\tlocal camPart = cameraRig:FindFirstChild('CamPart')"
				src[#src + 1] = "\t\t\t\tif camPart then"
				src[#src + 1] = "\t\t\t\t\tlocal originalCamType = camera.CameraType"
				src[#src + 1] = "\t\t\t\t\tcamera.CameraType = Enum.CameraType.Scriptable"
				src[#src + 1] = "\t\t\t\t\tlocal conn = RunService.RenderStepped:Connect(function()"
				src[#src + 1] = "\t\t\t\t\t\tcamera.CFrame = camPart.CFrame"
				src[#src + 1] = "\t\t\t\t\tend)"
				src[#src + 1] = "\t\t\t\t\ttask.delay(lifeTime, function()"
				src[#src + 1] = "\t\t\t\t\t\tconn:Disconnect()"
				src[#src + 1] = "\t\t\t\t\t\tcamera.CameraType = originalCamType"
				src[#src + 1] = "\t\t\t\t\tend)"
				src[#src + 1] = "\t\t\t\tend"
				src[#src + 1] = "\t\t\tend"
				src[#src + 1] = "\t\tend"
			end

			src[#src + 1] = "\tend"
			src[#src + 1] = ""
			src[#src + 1] = "\tsetupCamera()"
			src[#src + 1] = ""
		end

		-- Output animations grouped by instance variable with spacing
		src[#src + 1] = "\t-- === Property Animations ==="
		local lastVar = nil
		for _, entry in ipairs(moduleAnimBuffer) do
			if entry.var ~= lastVar then
				if lastVar ~= nil then
					src[#src + 1] = ""
				end
				lastVar = entry.var
			end
			src[#src + 1] = "\t" .. entry.code
		end
		src[#src + 1] = ""

		-- Event code
		if #eventLines > 0 then
			src[#src + 1] = "\t-- === Animation Event Code ==="
			for _, line in ipairs(eventLines) do
				src[#src + 1] = "\t" .. line
			end
			src[#src + 1] = ""
		end

		src[#src + 1] = "\treturn model, animationTracks"
		src[#src + 1] = "end"
		src[#src + 1] = ""
		src[#src + 1] = "return module"

		-- Create ModuleScript
		local moduleScript = Instance.new("ModuleScript")
		moduleScript.Name = "VFXPlayer"
		moduleScript.Source = table.concat(src, "\n")
		moduleScript.Parent = OutputModel

		OutputModel.Parent = workspace
		table.insert(ForcedSelection, OutputModel)

		local rigCount = #detectedRigs
		local camCount = 0
		for _, r in ipairs(detectedRigs) do
			if r.isCameraRig then
				camCount += 1
			end
		end
		print(
			">> Generated VFX Module for:",
			Source.name,
			"("
				.. #moduleAnimBuffer
				.. " anim lines, "
				.. #eventLines
				.. " event lines, "
				.. rigCount
				.. " rigs, "
				.. camCount
				.. " camera rigs)"
		)
	end

	Selection:Set(ForcedSelection)
	warn(">> VFX Module generation complete!")
end

generateBtn.Click:Connect(function()
	runGeneration(true)
end)

generateNoCutsceneBtn.Click:Connect(function()
	runGeneration(false)
end)
