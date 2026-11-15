-- Руки от первого лица: держат кирку, топор, меч, копьё или факел.
-- Покачивание при ходьбе, инерция при повороте камеры, анимация удара и доставания.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemModels = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemModels"))
local Items = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Items"))

local player = Players.LocalPlayer

local Viewmodel = {}

local V = Vector3.new
local RGB = Color3.fromRGB

local folder
local rightArm, rightHand, leftArm, leftHand
local itemModel, itemId
local swingT -- 0..1 во время удара
local equipT = 1
local sway = CFrame.new()
local lastCam
local bobT = 0
Viewmodel.visible = false

local SLEEVE = RGB(62, 70, 52)
local function skinColor()
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	return head and head.Color or RGB(230, 190, 150)
end

local function mk(name, size, color, mat)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = mat or Enum.Material.Fabric
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = folder
	return p
end

local function ensure()
	if folder and folder.Parent == workspace.CurrentCamera then
		return
	end
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Model")
	folder.Name = "Viewmodel"
	folder.Parent = workspace.CurrentCamera
	rightArm = mk("RightArm", V(0.5, 0.5, 2.2), SLEEVE)
	rightHand = mk("RightHand", V(0.55, 0.55, 0.6), skinColor(), Enum.Material.SmoothPlastic)
	leftArm = mk("LeftArm", V(0.5, 0.5, 2.2), SLEEVE)
	leftHand = mk("LeftHand", V(0.55, 0.55, 0.6), skinColor(), Enum.Material.SmoothPlastic)
	if itemId then
		Viewmodel.setItem(itemId, true)
	end
end

function Viewmodel.setItem(id, silent)
	ensure()
	if itemModel then
		itemModel:Destroy()
		itemModel = nil
	end
	itemId = id
	if id and id ~= "fists" then
		itemModel = ItemModels.build(id)
		itemModel.Parent = folder
	end
	if not silent then
		equipT = 0
	end
end

function Viewmodel.swing()
	if not swingT then
		swingT = 0
	end
end

function Viewmodel.isSwinging()
	return swingT ~= nil
end

local function hide(h)
	if folder then
		for _, d in ipairs(folder:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = h and 1 or 0
				if d:GetAttribute("T0") == nil then
					d:SetAttribute("T0", d.Transparency)
				end
				d.Transparency = h and 1 or d:GetAttribute("T0")
			elseif d:IsA("Light") or d:IsA("Fire") then
				d.Enabled = not h
			end
		end
	end
end

-- вызывать каждый кадр ПОСЛЕ обновления камеры
function Viewmodel.update(dt, visible, moving, sprinting)
	ensure()
	Viewmodel.visible = visible
	hide(not visible)
	if not visible then
		return
	end
	local cam = workspace.CurrentCamera
	local camCF = cam.CFrame

	-- инерция при повороте
	if lastCam then
		local delta = camCF:ToObjectSpace(lastCam)
		local x, y = delta:ToEulerAnglesXYZ()
		sway = sway:Lerp(CFrame.Angles(math.clamp(x, -0.15, 0.15) * 0.6, math.clamp(y, -0.15, 0.15) * 0.6, 0), 0.25)
	end
	lastCam = camCF
	sway = sway:Lerp(CFrame.new(), math.min(1, dt * 6))

	-- покачивание при ходьбе
	if moving then
		bobT += dt * (sprinting and 13 or 8.5)
	else
		bobT += dt * 1.5
	end
	local amp = moving and (sprinting and 0.12 or 0.07) or 0.015
	local bob = CFrame.new(math.cos(bobT) * amp, math.abs(math.sin(bobT)) * amp * 1.2, 0)

	-- доставание
	equipT = math.min(1, equipT + dt * 4)
	local eq = 1 - (1 - equipT) ^ 3
	local equipOff = CFrame.new(0, -(1 - eq) * 1.6, 0) * CFrame.Angles(-(1 - eq) * 0.6, 0, 0)

	-- удар: замах назад, резкий удар вперёд-вниз
	local swingAng, punch = 0, 0
	if swingT then
		swingT += dt / 0.38
		local t = swingT
		if t < 0.35 then
			swingAng = -0.9 * (t / 0.35)
		elseif t < 0.6 then
			swingAng = -0.9 + 2.3 * ((t - 0.35) / 0.25)
		else
			swingAng = 1.4 * (1 - (t - 0.6) / 0.4)
		end
		punch = math.sin(math.min(t, 1) * math.pi) * 0.9
		if swingT >= 1 then
			swingT = nil
		end
	end

	local base = camCF * sway * bob * equipOff
	local kind = itemId and Items.Tools[itemId] and Items.Tools[itemId].Kind or "fists"

	-- правая рука
	local shoulder = base * CFrame.new(1.25, -1.5, -0.4)
	local rArmCF
	if kind == "fists" then
		rArmCF = shoulder * CFrame.new(0, 0, -punch * 1.2) * CFrame.Angles(0.15, 0.25, 0) * CFrame.new(0, 0, -1.1)
	else
		rArmCF = shoulder * CFrame.Angles(swingAng, 0, 0) * CFrame.Angles(0.35, 0.3, 0) * CFrame.new(0, 0, -1.1)
	end
	rightArm.CFrame = rArmCF
	local handCF = rArmCF * CFrame.new(0, 0, -1.3)
	rightHand.CFrame = handCF

	-- левая рука (для кулаков бьёт левой по очереди — просто стоит в защите)
	local lShoulder = base * CFrame.new(-1.25, -1.55, -0.4)
	local lArmCF = lShoulder * CFrame.Angles(0.3, -0.3, 0) * CFrame.new(0, 0, -1.05)
	if kind == "spear" then
		lArmCF = lShoulder * CFrame.Angles(swingAng * 0.5, 0, 0) * CFrame.Angles(0.25, -0.5, 0) * CFrame.new(0, 0, -1.2)
	end
	leftArm.CFrame = lArmCF
	leftHand.CFrame = lArmCF * CFrame.new(0, 0, -1.3)

	-- предмет в правой руке
	if itemModel then
		local tilt
		if kind == "spear" then
			tilt = CFrame.Angles(-math.pi / 2 + 0.15, 0, 0)
		elseif kind == "torch" then
			tilt = CFrame.Angles(-0.25, 0, 0.15)
		else
			tilt = CFrame.Angles(-0.35, 0.1, 0.12)
		end
		itemModel:PivotTo(handCF * CFrame.new(0, -0.1, 0) * tilt)
	end
end

function Viewmodel.destroy()
	if folder then
		folder:Destroy()
		folder = nil
	end
end

return Viewmodel
