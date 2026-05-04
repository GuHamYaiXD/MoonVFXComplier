--[[ EXAMPLE
local MeshEmitter = require(game.ReplicatedStorage.MeshEmitter)
local Character = workspace.Character
local Root = Character.HumanoidRootPart

MeshEmitter.StartMeshEmitter(Root, ReplicatedStorage.MeshEmitter,3)
]]

-- || Services || --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerService = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

-- || Imports || --
local VisualFolder = workspace

local VFXModule = {}
function PropertyConvert(BaseRoot,PropertyType, val)
	local Result = nil

	if PropertyType == "CFrame" then
		Result = BaseRoot.CFrame * CFrame.new(unpack(string.split(val,", ")))
	elseif PropertyType == "boolean" then
		Result = val == "true"
	elseif PropertyType == "Color3" then
		Result = Color3.new(unpack(string.split(val,", ")))
	elseif PropertyType == "Vector3" then
		Result = Vector3.new(unpack(string.split(val,", ")))
	elseif PropertyType == "number" then
		Result = tonumber(val)
	elseif PropertyType == "ColorSequence" then
		Result = ColorSequence.new(Color3.new(unpack(string.split(val,", "))))
	elseif PropertyType == "NumberSequence" then
		Result = NumberSequence.new(val)
	end

	return Result
end

function VFXModule.StartMeshEmitter(Root : BasePart, Pack : Model,Offset : CFrame, LifeTime : number, Config : {SizeMulti : number}, PlayOnSelectedGroup : boolean)
	Config = Config or {}
	PlayOnSelectedGroup = PlayOnSelectedGroup or false
	local SizeMulti = Config.SizeMulti or 1
	if not Root or not Root:IsA("BasePart") then
		return warn(">> Invalid Root for MeshEmitter. must be a BasePart.")
	end

	Offset = Offset or CFrame.new(0,0,0)
	LifeTime = LifeTime or 10

	local MeshPack = PlayOnSelectedGroup and Pack or Pack:Clone()
	local EndTime = os.clock() + LifeTime

	task.spawn(function()
		while true do
			if os.clock() >= EndTime or not Root:IsDescendantOf(game) then
				Debris:AddItem(MeshPack, 0)
				break
			end
			MeshPack:PivotTo(Root.CFrame * Offset)
			RunService.RenderStepped:Wait()
		end
	end)

	local BaseRoot = MeshPack.PrimaryPart
	MeshPack.Parent = VisualFolder

	for i,instance in pairs(MeshPack:GetDescendants()) do
		local RawData = instance:GetAttribute("MeshEmitter")
		if RawData then
			local DataPack = HttpService:JSONDecode(RawData)

			for initProperty, data in pairs(DataPack) do
				for num,info in pairs(data) do
					local Direction = info.Direction
					local Style = info.Style
					local Property = info.Property
					local Time = info.Time
					local Value = info.Value

					local GoalData = data[num + 1]

					if GoalData == nil then
						continue
					end

					local GoalDirection = GoalData.Direction
					local GoalStyle = GoalData.Style
					local GoalProperty = GoalData.Property
					local GoalTime = GoalData.Time
					local GoalValue = GoalData.Value

					local function Getval(val)
						local PropertyType = typeof(instance[Property])
						local Result = PropertyConvert(BaseRoot,PropertyType, val)

						if Property == "Size" or Property == "Scale" then
							if PropertyType == "Vector3" then
								Result = Vector3.new(Result.X * SizeMulti, Result.Y * SizeMulti, Result.Z * SizeMulti)
							end
						end

						return Result
					end

					if Style == "Circ" then
						Style = "Circular"
					elseif Style == "Expo" or Style == "Sextic" then
						Style = "Exponential"
					end

					if Style == "Constant" then
						if Time > 0 then
							task.delay(Time, function()
								instance[Property] = Getval(Value)
							end)
						else
							instance[Property] = Getval(Value)
						end
						task.delay(GoalTime, function()
							instance[Property] = Getval(GoalValue)
						end)
					else
						local FindEasingStyle = Enum.EasingStyle:FromName(Style)

						if FindEasingStyle == nil then
							FindEasingStyle = Enum.EasingStyle.Linear
							warn("MeshEmitter does not support",Style,"yet. has been redirected to Linear")
						end

						local tweenInfo = TweenInfo.new(GoalTime - Time, FindEasingStyle, Enum.EasingDirection[Direction])

						local function StartTweening()
							if typeof(instance[Property]) == "ColorSequence" then
								local ValueHolder = Instance.new("Color3Value")
								ValueHolder.Value = Getval(Value).Keypoints[1].Value
								ValueHolder.Parent = MeshPack
								local Tween = TweenService:Create(ValueHolder, tweenInfo, {Value = Getval(GoalValue).Keypoints[1].Value})
								Tween:Play()
								
								local Connection = nil
								Connection = RunService.RenderStepped:Connect(function()
									instance[Property] = ColorSequence.new(ValueHolder.Value)
								end)
								Tween.Completed:Once(function()
									Connection:Disconnect()
									Connection = nil
									Debris:AddItem(ValueHolder, 0)
									Debris:AddItem(Tween, 0)
								end)
							elseif typeof(instance[Property]) == "NumberSequence" then
								local ValueHolder = Instance.new("NumberValue")
								ValueHolder.Value = Getval(Value).Keypoints[1].Value
								ValueHolder.Parent = MeshPack
								local Tween = TweenService:Create(ValueHolder, tweenInfo, {Value = Getval(GoalValue).Keypoints[1].Value})
								Tween:Play()

								local Connection = nil
								Connection = RunService.RenderStepped:Connect(function()
									instance[Property] = ColorSequence.new(ValueHolder.Value)
								end)
								Tween.Completed:Once(function()
									Connection:Disconnect()
									Connection = nil
									Debris:AddItem(ValueHolder, 0)
									Debris:AddItem(Tween, 0)
								end)
							else
								local Tween = TweenService:Create(instance, tweenInfo, {[Property] = Getval(GoalValue)})
								Tween:Play()
							end
						end

						if Time > 0 then
							task.delay(Time, function()
								instance[Property] = Getval(Value)
								StartTweening()
							end)
						else
							instance[Property] = Getval(Value)
							StartTweening()
						end
					end
				end
			end
		end
	end

	for _,Item in pairs(MeshPack:GetChildren()) do
		local GroupType = Item:GetAttribute("GroupType")

		if GroupType == "CameraEffect" then
			Item.Parent = workspace.CurrentCamera

			MeshPack.AncestryChanged:Once(function()
				Debris:AddItem(Item, 0)
			end)
		elseif GroupType == "Vignette" or GroupType == "ScreenCover" then
			if PlayerService.LocalPlayer then
				Item.Parent = ((PlayerService.LocalPlayer and PlayerService.LocalPlayer:FindFirstChild("PlayerGui")) and PlayerService.LocalPlayer.PlayerGui or game:GetService("StarterGui"))
				MeshPack.AncestryChanged:Once(function()
					Debris:AddItem(Item, 0)
				end)
			end
		end
	end
	return MeshPack
end

return VFXModule