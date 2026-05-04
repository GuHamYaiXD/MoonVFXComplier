-- Auto-generated VFX Module by MeshEmitter Plugin
-- Source: Bykaya cutt2

local TweenService = game:GetService('TweenService')
local RunService = game:GetService('RunService')
local Debris = game:GetService('Debris')
local Players = game:GetService('Players')
local ForgeVFX = require(game:GetService('ReplicatedStorage'):WaitForChild('ForgeVFX'))

local module = {}

-- === Animation IDs ===
module.Animations = {
	["Bykaya"] = "", -- Insert rbxassetid:// here
	["Blade-2"] = "", -- Insert rbxassetid:// here
	["cam (CameraRig)"] = "", -- Insert rbxassetid:// here
}

module.HasCutscene = true

local function setProperty(obj, prop, val, delayTime)
	if delayTime > 0 then
		task.delay(delayTime, function() if obj then obj[prop] = val end end)
	else
		if obj then obj[prop] = val end
	end
end

local function tweenProperty(obj, prop, fromVal, toVal, delayTime, dur, style, dir)
	local function go()
		if not obj then return end
		obj[prop] = fromVal
		TweenService:Create(obj, TweenInfo.new(dur, Enum.EasingStyle[style], Enum.EasingDirection[dir]), {[prop] = toVal}):Play()
	end
	if delayTime > 0 then task.delay(delayTime, go) else go() end
end

local function playKeyframes(obj, prop, propType, keyframes, baseRoot)
	for i = 1, #keyframes do
		local kf = keyframes[i]
		local nextKf = keyframes[i + 1]
		local t, v, style, dir = kf[1], kf[2], kf[3], kf[4]
		if not nextKf then
			setProperty(obj, prop, v, t)
			break
		end
		local t2, v2 = nextKf[1], nextKf[2]
		local dur = math.max(0.001, t2 - t)
		local info = TweenInfo.new(dur, Enum.EasingStyle[style], Enum.EasingDirection[dir])
		local function go()
			if not obj then return end
			if propType == 'boolean' then
				obj[prop] = v
			elseif propType == 'NumberSequence' then
				local nv = Instance.new('NumberValue'); nv.Value = v
				nv.Changed:Connect(function(val) if obj then obj[prop] = NumberSequence.new({NumberSequenceKeypoint.new(0, val), NumberSequenceKeypoint.new(1, val)}) end end)
				local tw = TweenService:Create(nv, info, {Value = v2})
				tw.Completed:Once(function() nv:Destroy() end); tw:Play()
			elseif propType == 'ColorSequence' then
				local cv = Instance.new('Color3Value'); cv.Value = v
				cv.Changed:Connect(function(val) if obj then obj[prop] = ColorSequence.new(val) end end)
				local tw = TweenService:Create(cv, info, {Value = v2})
				tw.Completed:Once(function() cv:Destroy() end); tw:Play()
			elseif propType == 'RelCFrame' then
				if baseRoot then
					local nv = Instance.new('NumberValue'); nv.Value = 0; local conn
					conn = nv.Changed:Connect(function(a) if obj and baseRoot then obj.CFrame = baseRoot.CFrame * v:Lerp(v2, a) end end)
					local tw = TweenService:Create(nv, info, {Value = 1})
					tw.Completed:Once(function() conn:Disconnect() nv:Destroy() end); tw:Play()
				end
			else
				obj[prop] = v
				TweenService:Create(obj, info, {[prop] = v2}):Play()
			end
		end
		if t > 0 then task.delay(t, go) else go() end
	end
end

local function safeEmit(instance, count)
	if instance and instance:IsA('ParticleEmitter') then instance:Emit(count) end
end

function module.Play(rootPart, offset, lifeTime, config)
	config = config or {}
	offset = offset or CFrame.new()
	lifeTime = lifeTime or 10
	local sizeMulti = config.SizeMulti or 1
	local autoPlayAnimations = (config.AutoPlayAnimations ~= false) -- defaults to true
	local playCutscene = (config.PlayCutscene ~= false) -- defaults to true

	local model = script.Parent:Clone()
	local selfModule = model:FindFirstChild('VFXPlayer')
	if selfModule then selfModule:Destroy() end

	local baseRoot = model:FindFirstChild('RootPart')
	local animationTracks = {}

	-- === Save original state for restoration ===
	local _Lighting = game:GetService('Lighting')
	local _savedLighting = {}
	for _, prop in ipairs({'Ambient','OutdoorAmbient','Brightness','ColorShift_Bottom','ColorShift_Top','FogColor','FogEnd','FogStart','EnvironmentDiffuseScale','EnvironmentSpecularScale','ExposureCompensation'}) do
		pcall(function() _savedLighting[prop] = _Lighting[prop] end)
	end
	local _savedCameraFOV = workspace.CurrentCamera.FieldOfView
	local _savedAtmospheres = {}
	for _, child in ipairs(_Lighting:GetChildren()) do
		if child:IsA('Atmosphere') then
			_savedAtmospheres[child] = {Density=child.Density, Offset=child.Offset, Color=child.Color, Decay=child.Decay, Glare=child.Glare, Haze=child.Haze}
		end
	end

	local function _restoreState()
		for prop, val in pairs(_savedLighting) do
			pcall(function() _Lighting[prop] = val end)
		end
		workspace.CurrentCamera.FieldOfView = _savedCameraFOV
		for atm, props in pairs(_savedAtmospheres) do
			if atm and atm.Parent then
				for p, v in pairs(props) do pcall(function() atm[p] = v end) end
			end
		end
	end

	if rootPart and typeof(rootPart) == 'Instance' and rootPart:IsA('BasePart') then
		local endTime = os.clock() + lifeTime
		task.spawn(function()
			while true do
				if os.clock() >= endTime or not rootPart:IsDescendantOf(game) then
					_restoreState()
					Debris:AddItem(model, 0)
					break
				end
				model:PivotTo(rootPart.CFrame * offset)
				RunService.RenderStepped:Wait()
			end
		end)
	else
		task.delay(lifeTime, function()
			_restoreState()
			Debris:AddItem(model, 0)
		end)
	end

	for _, item in pairs(model:GetChildren()) do
		if item:GetAttribute('GroupType') == 'CharacterRig' then
			local hum = item:FindFirstChildWhichIsA('Humanoid')
			if hum then
				hum.RequiresNeck = false
				hum.BreakJointsOnDeath = false
				hum.Health = hum.MaxHealth
			end
		end
	end

	model.Parent = workspace
	task.wait()

	-- === EmitDuration: auto enable/disable ParticleEmitters ===
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA('ParticleEmitter') then
			local emitDur = desc:GetAttribute('EmitDuration')
			if emitDur and emitDur > 0 then
				desc.Enabled = true
				task.delay(emitDur, function()
					if desc and desc.Parent then desc.Enabled = false end
				end)
			end
		end
	end

	-- === Instance References ===
	local ref_Atmosphere = model.Atmosphere
	local ref_Lighting = game:GetService('Lighting')
	local ref_Box1 = model.Box1
	local ref_Bykaya_Asset_BykayaBlade_Highlight1 = model.Bykaya.Asset.BykayaBlade.Highlight1
	local ref_Ground_prob = model["Ground prob"]
	local ref_Bykaya_Asset_Blade_2_Big = model.Bykaya.Asset["Blade-2"].Big

	-- === Special Instance Handling (Camera Effects, UI) ===
	for _, item in pairs(model:GetChildren()) do
		local groupType = item:GetAttribute('GroupType')
		if groupType == 'CameraEffect' then
			item.Parent = workspace.CurrentCamera
			model.AncestryChanged:Once(function()
				Debris:AddItem(item, 0)
			end)
		elseif groupType == 'Vignette' or groupType == 'ScreenCover' then
			if Players.LocalPlayer then
				local pg = Players.LocalPlayer:FindFirstChild('PlayerGui')
				if pg then item.Parent = pg end
				model.AncestryChanged:Once(function()
					Debris:AddItem(item, 0)
				end)
			end
		end
	end

	-- === Animation Playback ===
	if autoPlayAnimations then
		-- Cloned Character Rig: "Bykaya"
		do
			local charModel = model:FindFirstChild("Bykaya")
			if charModel then
				local animController = charModel:FindFirstChildWhichIsA('AnimationController')
				if not animController then
					animController = Instance.new('AnimationController')
					animController.Parent = charModel
				end
				local animator = animController:FindFirstChildWhichIsA('Animator')
				if not animator then
					animator = Instance.new('Animator')
					animator.Parent = animController
				end
				local animId = module.Animations["Bykaya"]
				if animId and animId ~= "" then
					local matchId = animId:match('%d+')
					if matchId then animId = 'rbxassetid://' .. matchId end
					local animObj = Instance.new('Animation')
					animObj.AnimationId = animId
					local track = animator:LoadAnimation(animObj)
					track:Play()
					animationTracks["Bykaya"] = track
				end
			end
		end

		-- Cloned Character Rig: "Blade-2"
		do
			local charModel = model:FindFirstChild("Blade-2")
			if charModel then
				local animController = charModel:FindFirstChildWhichIsA('AnimationController')
				if not animController then
					animController = Instance.new('AnimationController')
					animController.Parent = charModel
				end
				local animator = animController:FindFirstChildWhichIsA('Animator')
				if not animator then
					animator = Instance.new('Animator')
					animator.Parent = animController
				end
				local animId = module.Animations["Blade-2"]
				if animId and animId ~= "" then
					local matchId = animId:match('%d+')
					if matchId then animId = 'rbxassetid://' .. matchId end
					local animObj = Instance.new('Animation')
					animObj.AnimationId = animId
					local track = animator:LoadAnimation(animObj)
					track:Play()
					animationTracks["Blade-2"] = track
				end
			end
		end

		-- CameraRig: "cam"
		do
			local camRigModel = model:FindFirstChild("cam")
			if camRigModel then
				local animController = camRigModel:FindFirstChildWhichIsA('AnimationController')
					or camRigModel:FindFirstChildWhichIsA('Humanoid')
				if animController then
					local animator = animController:FindFirstChildWhichIsA('Animator')
					if not animator then
						animator = Instance.new('Animator')
						animator.Parent = animController
					end
					local animId = module.Animations["cam (CameraRig)"]
					if animId and animId ~= "" then
						local matchId = animId:match('%d+')
						if matchId then animId = 'rbxassetid://' .. matchId end
						local animObj = Instance.new('Animation')
						animObj.AnimationId = animId
						local track = animator:LoadAnimation(animObj)
						track:Play()
						animationTracks["cam (CameraRig)"] = track
					end
				end
			end
		end

	end

	local function setupCamera()
		local camera = workspace.CurrentCamera

		local fovFolder = model:FindFirstChild('FOV')
		if fovFolder then
			local keys = fovFolder:GetChildren()
			table.sort(keys, function(a, b) return tonumber(a.Name) < tonumber(b.Name) end)
			for i, key in ipairs(keys) do
				local nextKey = keys[i + 1]
				local t = tonumber(key.Name) or 0
				if nextKey then
					local nt = tonumber(nextKey.Name) or 0
					local dur = nt - t
					local style = key:GetAttribute('EasingStyle') or 'Linear'
					local dir = key:GetAttribute('EasingDirection') or 'In'
					tweenProperty(camera, 'FieldOfView', key.Value, nextKey.Value, t, dur, style, dir)
				else
					setProperty(camera, 'FieldOfView', key.Value, t)
				end
			end
		end

		if playCutscene then
			local cameraRig = model:FindFirstChild("cam")
			if cameraRig then
				local camPart = cameraRig:FindFirstChild('CamPart')
				if camPart then
					local originalCamType = camera.CameraType
					camera.CameraType = Enum.CameraType.Scriptable
					local conn = RunService.RenderStepped:Connect(function()
						camera.CFrame = camPart.CFrame
					end)
					task.delay(lifeTime, function()
						conn:Disconnect()
						camera.CameraType = originalCamType
					end)
				end
			end
		end
	end

	setupCamera()

	-- === Property Animations ===
	playKeyframes(ref_Atmosphere, 'Density', 'number', {
		{0, 0.3, 'Linear', 'In'},
		{0.2833, 0.574, 'Linear', 'In'},
		{4.233, 0.574, 'Linear', 'In'},
		{4.833, 0.495, 'Linear', 'In'},
		{5.517, 0.277, 'Linear', 'In'}
	})
	playKeyframes(ref_Atmosphere, 'Offset', 'number', {
		{0, 0.25, 'Linear', 'In'},
		{0.2833, 0.25, 'Linear', 'In'},
		{4.233, 0.25, 'Linear', 'In'},
		{4.833, 0.335, 'Linear', 'In'},
		{5.517, 0.335, 'Linear', 'In'}
	})
	playKeyframes(ref_Atmosphere, 'Color', 'Color3', {
		{0, Color3.new(0.7804, 0.7804, 0.7804), 'Linear', 'In'},
		{0.2833, Color3.new(0.2314, 0.2314, 0.2314), 'Linear', 'In'},
		{4.233, Color3.new(0.2314, 0.2314, 0.2314), 'Linear', 'In'},
		{4.833, Color3.new(0.1059, 0.1059, 0.1059), 'Linear', 'In'},
		{5.517, Color3.new(0.1059, 0.1059, 0.1059), 'Linear', 'In'}
	})
	playKeyframes(ref_Atmosphere, 'Decay', 'Color3', {
		{0, Color3.new(0.4157, 0.4392, 0.4902), 'Linear', 'In'},
		{0.2833, Color3.new(0.2353, 0.251, 0.2784), 'Linear', 'In'},
		{4.233, Color3.new(0.2353, 0.251, 0.2784), 'Linear', 'In'},
		{4.833, Color3.new(0.1922, 0.2039, 0.2275), 'Linear', 'In'},
		{5.517, Color3.new(0.1922, 0.2039, 0.2275), 'Linear', 'In'}
	})
	playKeyframes(ref_Atmosphere, 'Haze', 'number', {
		{0, 0, 'Linear', 'In'},
		{0.2833, 1.54, 'Linear', 'In'},
		{4.233, 1.54, 'Linear', 'In'},
		{4.833, 1.12, 'Linear', 'In'},
		{5.517, 1.12, 'Linear', 'In'}
	})
	playKeyframes(ref_Atmosphere, 'Glare', 'number', {
		{0, 0, 'Linear', 'In'},
		{0.2833, 1.22, 'Linear', 'In'},
		{4.233, 1.22, 'Linear', 'In'},
		{4.833, 2.98, 'Linear', 'In'},
		{5.517, 2.98, 'Linear', 'In'}
	})

	playKeyframes(ref_Lighting, 'ClockTime', 'number', {
		{0, 5.3, 'Linear', 'In'},
		{0.65, 5.3, 'Linear', 'In'},
		{2.517, 5.3, 'Linear', 'In'},
		{3.867, 4.8, 'Linear', 'In'}
	})

	playKeyframes(ref_Box1, 'Color', 'Color3', {
		{0, Color3.new(0, 0, 0), 'Linear', 'In'},
		{0.3, Color3.new(0, 0, 0), 'Linear', 'In'},
		{1.267, Color3.new(0.185, 0.172, 0.2078), 'Linear', 'In'},
		{2.783, Color3.new(0, 0, 0), 'Linear', 'In'},
		{5.483, Color3.new(0, 0, 0), 'Linear', 'In'},
		{5.967, Color3.new(0.192, 0.1484, 0.1961), 'Linear', 'In'},
		{6.683, Color3.new(0.1882, 0.1451, 0.1961), 'Linear', 'In'},
		{7.167, Color3.new(0.1176, 0.1176, 0.1176), 'Linear', 'In'}
	})

	setProperty(ref_Bykaya_Asset_BykayaBlade_Highlight1, 'Enabled', true, 0)
	setProperty(ref_Bykaya_Asset_BykayaBlade_Highlight1, 'Enabled', true, 2.567)
	setProperty(ref_Bykaya_Asset_BykayaBlade_Highlight1, 'Enabled', true, 2.767)
	playKeyframes(ref_Bykaya_Asset_BykayaBlade_Highlight1, 'OutlineTransparency', 'number', {
		{0, 1, 'Linear', 'In'},
		{2.567, 1, 'Linear', 'In'},
		{2.767, 1, 'Linear', 'In'}
	})
	playKeyframes(ref_Bykaya_Asset_BykayaBlade_Highlight1, 'OutlineColor', 'Color3', {
		{0, Color3.new(1, 1, 1), 'Linear', 'In'},
		{2.567, Color3.new(1, 1, 1), 'Linear', 'In'},
		{2.767, Color3.new(1, 1, 1), 'Linear', 'In'}
	})
	playKeyframes(ref_Bykaya_Asset_BykayaBlade_Highlight1, 'FillTransparency', 'number', {
		{0, 1, 'Linear', 'In'},
		{2.567, 1, 'Linear', 'In'},
		{2.767, -2, 'Linear', 'In'}
	})
	playKeyframes(ref_Bykaya_Asset_BykayaBlade_Highlight1, 'FillColor', 'Color3', {
		{0, Color3.new(0.6667, 0.2863, 1), 'Linear', 'In'},
		{2.567, Color3.new(0.6667, 0.2863, 1), 'Linear', 'In'},
		{2.767, Color3.new(1, 0.3882, 0.7137), 'Linear', 'In'}
	})

	playKeyframes(ref_Ground_prob, 'Transparency', 'number', {
		{0, 1, 'Linear', 'In'},
		{1.2, 1, 'Linear', 'In'},
		{2.483, 0, 'Linear', 'In'},
		{3.567, 0, 'Linear', 'In'},
		{3.617, 1, 'Linear', 'In'}
	})

	setProperty(ref_Bykaya_Asset_Blade_2_Big, 'Enabled', true, 0)
	setProperty(ref_Bykaya_Asset_Blade_2_Big, 'Enabled', true, 6.483)
	setProperty(ref_Bykaya_Asset_Blade_2_Big, 'Enabled', true, 6.65)
	setProperty(ref_Bykaya_Asset_Blade_2_Big, 'Enabled', true, 6.817)
	playKeyframes(ref_Bykaya_Asset_Blade_2_Big, 'OutlineTransparency', 'number', {
		{0, 1, 'Linear', 'In'},
		{6.483, 1, 'Linear', 'In'},
		{6.65, 1, 'Linear', 'In'},
		{6.817, 1, 'Linear', 'In'}
	})
	playKeyframes(ref_Bykaya_Asset_Blade_2_Big, 'OutlineColor', 'Color3', {
		{0, Color3.new(1, 1, 1), 'Linear', 'In'},
		{6.483, Color3.new(1, 1, 1), 'Linear', 'In'},
		{6.65, Color3.new(1, 1, 1), 'Linear', 'In'},
		{6.817, Color3.new(1, 1, 1), 'Linear', 'In'}
	})
	playKeyframes(ref_Bykaya_Asset_Blade_2_Big, 'FillTransparency', 'number', {
		{0, 1, 'Linear', 'In'},
		{6.483, 1, 'Linear', 'In'},
		{6.65, -0.6, 'Linear', 'In'},
		{6.817, -0.6, 'Linear', 'In'}
	})
	playKeyframes(ref_Bykaya_Asset_Blade_2_Big, 'FillColor', 'Color3', {
		{0, Color3.new(1, 1, 1), 'Linear', 'In'},
		{6.483, Color3.new(1, 1, 1), 'Linear', 'In'},
		{6.65, Color3.new(0.6745, 0.3882, 1), 'Linear', 'In'},
		{6.817, Color3.new(0.6745, 0.3882, 1), 'Linear', 'In'}
	})

	-- === Animation Event Code ===
	task.spawn(function()
		ForgeVFX.emit(model.IdkWHatthis.Vfx.ScVfx)
	end)
	task.delay(1.56667, function()
		ForgeVFX.emit(model.IdkWHatthis.Vfx.LiverPool)
	end)
	task.delay(1.98333, function()
		ForgeVFX.emit(model.IdkWHatthis.Vfx.LiverPool)
	end)
	task.delay(2.25, function()
		ForgeVFX.emit(model.IdkWHatthis.Mesh.cx)
	end)
	task.delay(3.98333, function()
		ForgeVFX.emit(model.IdkWHatthis.Vfx.Patapim)
	end)
	task.delay(5.98333, function()
		local TweenService = game:GetService("TweenService")
		for i,v in ipairs(model.IdkWHatthis.Vfx.BoomVFX.PL:GetDescendants()) do
			if v:IsA('PointLight') then
				TweenService:Create(v, TweenInfo.new(0.8), {
					Brightness = 4.74
				}):Play()
			end
		end
	end)
	task.delay(6.63333, function()
		ForgeVFX.emit(model.IdkWHatthis.Vfx.SwordEmitEnd)
		ForgeVFX.emit(model.IdkWHatthis.Vfx.SakuraFly)
		ForgeVFX.emit(model.IdkWHatthis.Vfx.BoomVFX)
	end)
	task.delay(6.8, function()
		local Lighting = game:GetService("Lighting")
		local TweenService = game:GetService("TweenService")
		local CC = Instance.new("ColorCorrectionEffect")
		CC.TintColor = Color3.fromRGB(255, 98, 255)
		game.Debris:AddItem(CC,1)
		CC.Parent = Lighting
		TweenService:Create(CC, TweenInfo.new(0.5), {Brightness = 1},{Contrast = 1},{Saturation = 0.6},{TintColor = Color3.fromRGB(255, 98, 255)}):Play()
		local TweenService = game:GetService("TweenService")
		for i,v in ipairs(model.IdkWHatthis.Vfx.BoomVFX.PL:GetDescendants()) do
			if v:IsA('PointLight') then
				TweenService:Create(v, TweenInfo.new(0.8), {
					Brightness = 0
				}):Play()
			end
		end
		task.wait(0.5)
		TweenService:Create(CC, TweenInfo.new(0.5), {Brightness = -1},{Contrast = 1},{Saturation = 1},{TintColor = Color3.fromRGB(255, 98, 255)}):Play()
	end)

	return model, animationTracks
end

return module
