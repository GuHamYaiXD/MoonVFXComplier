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
	"One-click: generate a complete VFX ModuleScript from MoonAnimator2 save files. Supports Beam, ParticleEmitter, Lights, Animations, CameraRig cutscenes.",
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

generateBtn.Click:Connect(function()
	local SelectedList = Selection:Get()
	if #SelectedList == 0 then
		warn(">> Please select MoonAnimator2 save file(s) to generate.")
		return
	end

	local ForcedSelection = {}
	local userWantsRigs = false
	local prompted = false

	for _, SaveOBJ in pairs(SelectedList) do
		if SaveOBJ.ClassName ~= "StringValue" then
			warn(">> Invalid file", SaveOBJ)
			continue
		end

		local ok, Decoded = pcall(function()
			return HttpService:JSONDecode(SaveOBJ.Value)
		end)
		if not ok or not Decoded or Decoded == "" then
			warn(">> Failed to decode", SaveOBJ)
			continue
		end

		local Items = Decoded.Items
		local Information = Decoded.Information
		if not Items or not Information then
			warn(">> Invalid save file", SaveOBJ)
			continue
		end

		local FPS = 60

		-- Create output model
		local OutputModel = Instance.new("Model")
		OutputModel.Name = SaveOBJ.Name .. "_VFX"

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

		for idx, Item in ipairs(Items) do
			if Item.Path.ItemType == "Rig" then
				local DataInstance = SaveOBJ:FindFirstChild(tostring(idx))
				if DataInstance and DataInstance:FindFirstChild("Rig") then
					local actual = SearchInstance(Item.Path.InstanceNames)
					if actual then
						local rigName = actual.Name
						local camRig = isCameraRig(actual)
						local hasAnim = hasAnimator(actual)

						if camRig then
							hasCutscene = true
							detectedRigs[#detectedRigs + 1] = {
								name = rigName,
								instance = actual,
								isCameraRig = true,
								hasAnimator = hasAnim,
							}
							print(">> [Generate] Detected CameraRig:", rigName)
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

		for idx, Item in ipairs(Items) do
			local ItemType = Item.Path.ItemType
			local InstanceNames = Item.Path.InstanceNames
			local DataInstance = SaveOBJ:FindFirstChild(tostring(idx))
			if not DataInstance then
				continue
			end
			if ItemType == "Rig" then
				continue
			end

			local actual = nil
			if ItemType == "Camera" then
				actual = workspace.CurrentCamera
			else
				actual = SearchInstance(InstanceNames)
			end

			if not actual then
				warn(">> [Generate] Could not find:", table.concat(InstanceNames, "."))
				continue
			end

			-- Determine category
			local isCamera = (ItemType == "Camera")
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
				warn(">> [Generate] Skipping unhandled item:", table.concat(InstanceNames, "."))
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
			for _, propertyOBJ in pairs(DataInstance:GetChildren()) do
				local Property = propertyOBJ.Name
				if Property == "Rig" or Property == "AttachToPart" then
					continue
				end

				-- Gather sorted frame folders
				local frameFolders = {}
				for _, v in pairs(propertyOBJ:GetChildren()) do
					if v:IsA("Folder") and v.Name ~= "default" and tonumber(v.Name) ~= nil then
						frameFolders[#frameFolders + 1] = v
					end
				end
				table.sort(frameFolders, function(a, b)
					return tonumber(a.Name) < tonumber(b.Name)
				end)

				-- Build keyframe list
				local keyframes = {}
				for _, framedata in ipairs(frameFolders) do
					local Frame = tonumber(framedata.Name)
					local Values = framedata:FindFirstChild("Values")
					if not Values then
						continue
					end
					local Value = Values:FindFirstChild("0")
					if not Value then
						continue
					end

					local EaseStyle = "Linear"
					local EaseDirection = "In"
					local Eases = framedata:FindFirstChild("Eases")
					if Eases then
						local FirstEase = Eases:FindFirstChild("0")
						if FirstEase then
							local TypeInst = FirstEase:FindFirstChild("Type")
							if TypeInst then
								EaseStyle = TypeInst.Value
							end
							local Params = FirstEase:FindFirstChild("Params")
							if Params then
								local DirInst = Params:FindFirstChild("Direction")
								if DirInst then
									EaseDirection = DirInst.Value
								end
							end
						end
					end

					local val = Value.Value
					local valClass = Value.ClassName

					-- Make CFrame relative to BaseRoot
					if Property == "CFrame" and BaseRoot then
						val = BaseRoot.CFrame:ToObjectSpace(val)
					end

					keyframes[#keyframes + 1] = {
						Time = frameToTime(Frame, FPS),
						Style = fixEaseStyle(EaseStyle),
						Direction = EaseDirection,
						Value = val,
						ValueClass = valClass,
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
					if propType == "boolean" then
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
		for _, OBJ in pairs(SaveOBJ:GetDescendants()) do
			if OBJ.Name == "codeBegin" or OBJ.Name == "codeEnd" then
				local Frame = tonumber(OBJ.Parent.Name)
				if Frame then
					eventContainer[#eventContainer + 1] = {
						Time = frameToTime(Frame, FPS),
						String = OBJ.Value,
					}
				end
			end
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
		src[#src + 1] = "-- Source: " .. SaveOBJ.Name
		src[#src + 1] = ""
		src[#src + 1] = "local TweenService = game:GetService('TweenService')"
		src[#src + 1] = "local RunService = game:GetService('RunService')"
		src[#src + 1] = "local Debris = game:GetService('Debris')"
		src[#src + 1] = "local Players = game:GetService('Players')"

		-- Check if any event code uses ForgeVFX
		local needsForgeVFX = false
		for _, line in ipairs(eventLines) do
			if line:find("ForgeVFX%.") then
				needsForgeVFX = true
				break
			end
		end
		if needsForgeVFX then
			src[#src + 1] = "local ForgeVFX = require(game:GetService('ReplicatedStorage'):WaitForChild('ForgeVFX'))"
		end

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

		-- setProperty utility (still needed for camera/events)
		src[#src + 1] = "local function setProperty(obj, prop, val, delayTime)"
		src[#src + 1] = "\tif delayTime > 0 then"
		src[#src + 1] = "\t\ttask.delay(delayTime, function() if obj then obj[prop] = val end end)"
		src[#src + 1] = "\telse"
		src[#src + 1] = "\t\tif obj then obj[prop] = val end"
		src[#src + 1] = "\tend"
		src[#src + 1] = "end"
		src[#src + 1] = ""

		-- tweenProperty utility (still needed for camera FOV folder)
		src[#src + 1] = "local function tweenProperty(obj, prop, fromVal, toVal, delayTime, dur, style, dir)"
		src[#src + 1] = "\tlocal function go()"
		src[#src + 1] = "\t\tif not obj then return end"
		src[#src + 1] = "\t\tobj[prop] = fromVal"
		src[#src + 1] = "\t\tTweenService:Create(obj, TweenInfo.new(dur, Enum.EasingStyle[style], Enum.EasingDirection[dir]), {[prop] = toVal}):Play()"
		src[#src + 1] = "\tend"
		src[#src + 1] = "\tif delayTime > 0 then task.delay(delayTime, go) else go() end"
		src[#src + 1] = "end"
		src[#src + 1] = ""

		-- playKeyframes engine
		src[#src + 1] = "local function playKeyframes(obj, prop, propType, keyframes, baseRoot)"
		src[#src + 1] = "\tfor i = 1, #keyframes do"
		src[#src + 1] = "\t\tlocal kf = keyframes[i]"
		src[#src + 1] = "\t\tlocal nextKf = keyframes[i + 1]"
		src[#src + 1] = "\t\tlocal t, v, style, dir = kf[1], kf[2], kf[3], kf[4]"
		src[#src + 1] = "\t\tif not nextKf then"
		src[#src + 1] = "\t\t\tsetProperty(obj, prop, v, t)"
		src[#src + 1] = "\t\t\tbreak"
		src[#src + 1] = "\t\tend"
		src[#src + 1] = "\t\tlocal t2, v2 = nextKf[1], nextKf[2]"
		src[#src + 1] = "\t\tlocal dur = math.max(0.001, t2 - t)"
		src[#src + 1] = "\t\tlocal info = TweenInfo.new(dur, Enum.EasingStyle[style], Enum.EasingDirection[dir])"
		src[#src + 1] = "\t\tlocal function go()"
		src[#src + 1] = "\t\t\tif not obj then return end"
		src[#src + 1] = "\t\t\tif propType == 'boolean' then"
		src[#src + 1] = "\t\t\t\tobj[prop] = v"
		src[#src + 1] = "\t\t\telseif propType == 'NumberSequence' then"
		src[#src + 1] = "\t\t\t\tlocal nv = Instance.new('NumberValue'); nv.Value = v"
		src[#src + 1] = "\t\t\t\tnv.Changed:Connect(function(val) if obj then obj[prop] = NumberSequence.new({NumberSequenceKeypoint.new(0, val), NumberSequenceKeypoint.new(1, val)}) end end)"
		src[#src + 1] = "\t\t\t\tlocal tw = TweenService:Create(nv, info, {Value = v2})"
		src[#src + 1] = "\t\t\t\ttw.Completed:Once(function() nv:Destroy() end); tw:Play()"
		src[#src + 1] = "\t\t\telseif propType == 'ColorSequence' then"
		src[#src + 1] = "\t\t\t\tlocal cv = Instance.new('Color3Value'); cv.Value = v"
		src[#src + 1] = "\t\t\t\tcv.Changed:Connect(function(val) if obj then obj[prop] = ColorSequence.new(val) end end)"
		src[#src + 1] = "\t\t\t\tlocal tw = TweenService:Create(cv, info, {Value = v2})"
		src[#src + 1] = "\t\t\t\ttw.Completed:Once(function() cv:Destroy() end); tw:Play()"
		src[#src + 1] = "\t\t\telseif propType == 'RelCFrame' then"
		src[#src + 1] = "\t\t\t\tif baseRoot then"
		src[#src + 1] = "\t\t\t\t\tlocal nv = Instance.new('NumberValue'); nv.Value = 0; local conn"
		src[#src + 1] = "\t\t\t\t\tconn = nv.Changed:Connect(function(a) if obj and baseRoot then obj.CFrame = baseRoot.CFrame * v:Lerp(v2, a) end end)"
		src[#src + 1] = "\t\t\t\t\tlocal tw = TweenService:Create(nv, info, {Value = 1})"
		src[#src + 1] = "\t\t\t\t\ttw.Completed:Once(function() conn:Disconnect() nv:Destroy() end); tw:Play()"
		src[#src + 1] = "\t\t\t\tend"
		src[#src + 1] = "\t\t\telse"
		src[#src + 1] = "\t\t\t\tobj[prop] = v"
		src[#src + 1] = "\t\t\t\tTweenService:Create(obj, info, {[prop] = v2}):Play()"
		src[#src + 1] = "\t\t\tend"
		src[#src + 1] = "\t\tend"
		src[#src + 1] = "\t\tif t > 0 then task.delay(t, go) else go() end"
		src[#src + 1] = "\tend"
		src[#src + 1] = "end"
		src[#src + 1] = ""

		-- safeEmit utility
		src[#src + 1] = "local function safeEmit(instance, count)"
		src[#src + 1] = "\tif instance and instance:IsA('ParticleEmitter') then instance:Emit(count) end"
		src[#src + 1] = "end"
		src[#src + 1] = ""

		-- Play function
		src[#src + 1] = "function module.Play(rootPart, offset, lifeTime, config)"
		src[#src + 1] = "\tconfig = config or {}"
		src[#src + 1] = "\toffset = offset or CFrame.new()"
		src[#src + 1] = "\tlifeTime = lifeTime or 10"
		src[#src + 1] = "\tlocal sizeMulti = config.SizeMulti or 1"
		src[#src + 1] = "\tlocal autoPlayAnimations = (config.AutoPlayAnimations ~= false) -- defaults to true"
		src[#src + 1] = "\tlocal playCutscene = (config.PlayCutscene ~= false) -- defaults to true"
		src[#src + 1] = ""
		src[#src + 1] = "\tlocal model = script.Parent:Clone()"
		src[#src + 1] = "\tlocal selfModule = model:FindFirstChild('VFXPlayer')"
		src[#src + 1] = "\tif selfModule then selfModule:Destroy() end"
		src[#src + 1] = ""
		src[#src + 1] = "\tlocal baseRoot = model:FindFirstChild('RootPart')"
		src[#src + 1] = "\tlocal animationTracks = {}"
		src[#src + 1] = ""
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

		if #cameraFOVKeyframes > 0 or #cameraOtherAnims > 0 or hasCutscene then
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
			SaveOBJ.Name,
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
end)
