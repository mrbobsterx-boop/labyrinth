-- Руки от первого лица — это копии рук твоего персонажа (с футболкой и цветом кожи).
-- Анимации: кирка бьёт сверху вниз, топор рубит наискось, меч рубит вбок, копьё колет вперёд,
-- кулаки бьют по очереди, факел просто держится. Покачивание при ходьбе и инерция поворота.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemModels = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemModels"))
local Items = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Items"))

local player = Players.LocalPlayer

local Viewmodel = {}

local V = Vector3.new
local RGB = Color3.fromRGB

local vm -- модель с руками
local arms = { right = {}, left = {} } -- списки {part, len}
local armLen = { right = 2.4, left = 2.4 }
local itemModel, itemId
local swingT, swingKind, punchLeft
local equipT = 1
local sway = CFrame.new()
local lastCam
local bobT = 0

local R15 = { right = { "RightUpperArm", "RightLowerArm", "RightHand" }, left = { "LeftUpperArm", "LeftLowerArm", "LeftHand" } }
local R6 = { right = { "Right Arm" }, left = { "Left Arm" } }

local function prep(p)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	for _, d in ipairs(p:GetChildren()) do
		if d:IsA("Motor6D") or d:IsA("Attachment") or d:IsA("Weld") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
end

function Viewmodel.rebuild()
	if vm then
		vm:Destroy()
	end
	vm = Instance.new("Model")
	vm.Name = "Viewmodel"
	arms = { right = {}, left = {} }
	local char = player.Character
	local names = char and (char:FindFirstChild("RightUpperArm") and R15 or R6)
	local ok = false
	if char and names then
		ok = pcall(function()
			for _, side in ipairs({ "right", "left" }) do
				local total = 0
				for _, n in ipairs(names[side]) do
					local src = char:FindFirstChild(n)
					if not src then
						error("нет части " .. n)
					end
					src.Archivable = true
					local c = src:Clone()
					prep(c)
					c.Parent = vm
					table.insert(arms[side], { part = c, len = c.Size.Y })
					total += c.Size.Y
				end
				armLen[side] = total
			end
			-- одежда и цвет кожи применяются через Humanoid
			local hum = Instance.new("Humanoid")
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			hum.Parent = vm
			for _, cls in ipairs({ "Shirt", "BodyColors" }) do
				local src = char:FindFirstChildOfClass(cls)
				if src then
					src.Archivable = true
					src:Clone().Parent = vm
				end
			end
		end)
	end
	if not ok then
		-- запасные квадратные руки
		for _, d in ipairs(vm:GetChildren()) do
			d:Destroy()
		end
		arms = { right = {}, left = {} }
		for _, side in ipairs({ "right", "left" }) do
			local p = Instance.new("Part")
			p.Size = V(1, 2.2, 1)
			p.Color = RGB(230, 190, 150)
			p.Material = Enum.Material.SmoothPlastic
			prep(p)
			p.Parent = vm
			arms[side] = { { part = p, len = 2.2 } }
			armLen[side] = 2.2
		end
	end
	vm.Parent = workspace.CurrentCamera
	if itemId then
		Viewmodel.setItem(itemId, true)
	end
end

function Viewmodel.setItem(id, silent)
	if itemModel then
		itemModel:Destroy()
		itemModel = nil
	end
	itemId = id
	if id and id ~= "fists" and vm then
		itemModel = ItemModels.build(id)
		itemModel.Parent = vm
	end
	if not silent then
		equipT = 0
	end
end

local function kindOf()
	local d = itemId and Items.Tools[itemId]
	return d and d.Kind or "fists"
end

-- удар; kind можно передать для добычи на E (инструмент выбирается автоматически)
function Viewmodel.swing(kind)
	if swingT then
		return false
	end
	kind = kind or kindOf()
	if kind == "torch" or kind == "blueprint" then
		return false
	end
	if kind == "hammer" then
		kind = "axe"
	end
	swingT, swingKind = 0, kind
	punchLeft = not punchLeft
	return true
end

local function setVisible(on)
	if not vm then
		return
	end
	for _, d in ipairs(vm:GetDescendants()) do
		if d:IsA("BasePart") then
			if d:GetAttribute("T0") == nil then
				d:SetAttribute("T0", d.Transparency)
			end
			d.Transparency = on and d:GetAttribute("T0") or 1
			d.LocalTransparencyModifier = 0
		elseif d:IsA("Light") or d:IsA("Fire") then
			d.Enabled = on
		end
	end
end

local function ease(a)
	return a * a * (3 - 2 * a)
end

-- поза удара: rot — поворот плеча, push — сдвиг (для копья/кулаков)
local function pose(kind, t)
	if not t then
		return CFrame.new(), CFrame.new()
	end
	if kind == "pickaxe" or kind == "axe" then
		local a
		if t < 0.35 then
			a = 1.0 * ease(t / 0.35) -- замах вверх
		elseif t < 0.55 then
			a = 1.0 - 1.9 * ease((t - 0.35) / 0.2) -- удар вниз
		else
			a = -0.9 * (1 - ease((t - 0.55) / 0.45))
		end
		local roll = kind == "axe" and a * 0.45 or 0
		return CFrame.Angles(a, kind == "axe" and -a * 0.25 or 0, roll), CFrame.new()
	elseif kind == "sword" then
		local y
		if t < 0.3 then
			y = -1.1 * ease(t / 0.3) -- отвести вправо
		elseif t < 0.55 then
			y = -1.1 + 2.4 * ease((t - 0.3) / 0.25) -- рубануть влево
		else
			y = 1.3 * (1 - ease((t - 0.55) / 0.45))
		end
		return CFrame.Angles(0.25, y, -y * 0.35), CFrame.new()
	elseif kind == "spear" then
		local z
		if t < 0.3 then
			z = 0.6 * ease(t / 0.3) -- отвести назад
		elseif t < 0.5 then
			z = 0.6 - 3.2 * ease((t - 0.3) / 0.2) -- выпад вперёд
		else
			z = -2.6 * (1 - ease((t - 0.5) / 0.5))
		end
		return CFrame.new(), CFrame.new(0, 0, z)
	else -- кулаки
		local z = -1.6 * math.sin(math.min(t, 1) * math.pi)
		return CFrame.Angles(0.1, 0, 0), CFrame.new(0, 0.2, z)
	end
end

-- как предмет лежит в ладони (рукоять снизу, рабочая часть вверх-вперёд в кадре)
local function hold(kind)
	if kind == "pickaxe" then
		return CFrame.Angles(math.rad(-125), 0, 0) * CFrame.new(0, -0.9, 0)
	elseif kind == "axe" then
		return CFrame.Angles(math.rad(-125), 0, 0) * CFrame.new(0, -0.8, 0)
	elseif kind == "sword" then
		return CFrame.Angles(math.rad(-105), 0, 0) * CFrame.new(0, -0.15, 0)
	elseif kind == "spear" then
		return CFrame.Angles(math.pi, 0, 0) * CFrame.new(0, -2.6, 0)
	elseif kind == "torch" or kind == "blueprint" then
		return CFrame.Angles(math.rad(-100), 0, 0) * CFrame.new(0, -0.3, 0)
	elseif kind == "hammer" then
		return CFrame.Angles(math.rad(-125), 0, 0) * CFrame.new(0, -0.6, 0)
	end
	return CFrame.new()
end

local function placeArm(side, shoulder)
	local y = 0
	for _, seg in ipairs(arms[side]) do
		seg.part.CFrame = shoulder * CFrame.new(0, -(y + seg.len / 2), 0)
		y += seg.len
	end
	return shoulder * CFrame.new(0, -armLen[side] + 0.3, 0)
end

-- вызывать каждый кадр ПОСЛЕ камеры
function Viewmodel.update(dt, visible, moving, sprinting)
	if not vm or vm.Parent ~= workspace.CurrentCamera then
		Viewmodel.rebuild()
	end
	setVisible(visible)
	if not visible then
		return
	end
	local camCF = workspace.CurrentCamera.CFrame

	if lastCam then
		local x, y = camCF:ToObjectSpace(lastCam):ToEulerAnglesXYZ()
		sway = sway:Lerp(CFrame.Angles(math.clamp(x, -0.12, 0.12) * 0.5, math.clamp(y, -0.12, 0.12) * 0.5, 0), 0.25)
	end
	lastCam = camCF
	sway = sway:Lerp(CFrame.new(), math.min(1, dt * 6))

	bobT += dt * (moving and (sprinting and 12 or 8) or 1.4)
	local amp = moving and (sprinting and 0.11 or 0.06) or 0.012
	local bob = CFrame.new(math.cos(bobT) * amp, math.abs(math.sin(bobT)) * amp * 1.2, 0) * CFrame.Angles(0, 0, sprinting and math.cos(bobT) * 0.04 or 0)

	equipT = math.min(1, equipT + dt * 4)
	local eq = 1 - (1 - equipT) ^ 3
	local equipOff = CFrame.new(0, -(1 - eq) * 1.8, 0) * CFrame.Angles(-(1 - eq) * 0.7, 0, 0)

	if swingT then
		swingT += dt / 0.42
		if swingT >= 1 then
			swingT = nil
		end
	end
	local kind = swingT and swingKind or kindOf()
	local rot, push = pose(kind, swingT)
	local base = camCF * sway * bob * equipOff

	-- руки: ось -Y части направлена от плеча к кисти; поворот на ~78° вокруг X направляет руку вперёд
	local rAim, lAim
	-- руки подняты так, чтобы кисти всегда были в кадре
	if kind == "spear" then
		rAim = CFrame.Angles(math.rad(92), math.rad(-6), 0)
		lAim = CFrame.Angles(math.rad(94), math.rad(18), 0)
	elseif kind == "fists" then
		rAim = CFrame.Angles(math.rad(96), math.rad(-14), 0)
		lAim = CFrame.Angles(math.rad(96), math.rad(14), 0)
	else
		rAim = CFrame.Angles(math.rad(92), math.rad(-14), 0)
		lAim = CFrame.Angles(math.rad(86), math.rad(22), 0)
	end
	local rPush, lPush = push, CFrame.new()
	if kind == "fists" and swingT and punchLeft then
		rPush, lPush = CFrame.new(), push
	end
	local rShoulder = base * CFrame.new(1.0, -1.15, 0.35) * rPush * (kind == "fists" and CFrame.new() or rot) * rAim
	local lShoulder = base * CFrame.new(-1.0, -1.2, 0.35) * lPush * (kind == "spear" and push or CFrame.new()) * lAim
	local grip = placeArm("right", rShoulder)
	placeArm("left", lShoulder)

	if itemModel then
		itemModel:PivotTo(grip * hold(kindOf()))
	end
end

return Viewmodel
