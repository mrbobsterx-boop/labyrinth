-- Постройки игроков: детали дома (по сетке), кровать, сундук.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Parts = require(script.Parent.Parts)
local Building = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Building"))

local Build = {}

local V = Vector3.new
local RGB = Color3.fromRGB
local M = Enum.Material

local function prompt(part, action, object, hold, dist)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object or ""
	p.HoldDuration = hold or 0
	p.MaxActivationDistance = dist or 10
	p.RequiresLineOfSight = false
	p.Parent = part
	return p
end

-- перекрасить деталь под уровень
function Build.setTier(model, tier)
	local t = Building.Tiers[tier]
	model:SetAttribute("Tier", tier)
	model:SetAttribute("HP", t.HP)
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") and d.Name ~= "Door" and d.Name ~= "Handle" then
			d.Color = t.Color
			d.Material = t.Material
			d.Transparency = tier == 0 and 0.15 or 0
		end
	end
end

-- деталь по сетке. a — параметры привязки (см. Building.cframe)
function Build.piece(parent, id, O, a)
	local def = Building.ById[id]
	local cf = Building.cframe(id, O, a)
	local m = Instance.new("Model")
	m.Name = def.Name
	m:SetAttribute("BKind", id)
	m:SetAttribute("Key", Building.key(id, a))
	m:SetAttribute("Base", a.y)
	m:SetAttribute("Top", Building.top(id, a))
	if def.Edge then
		m:SetAttribute("EX", a.ex)
		m:SetAttribute("EZ", a.ez)
		m:SetAttribute("Axis", a.axis)
	else
		m:SetAttribute("CX", a.cx)
		m:SetAttribute("CZ", a.cz)
	end
	local c = RGB(200, 180, 120)
	local function part(name, rel, size)
		return Parts.box(m, name, cf * rel, size, c, M.WoodPlanks)
	end
	if id == "foundation" or id == "floor" then
		part("Slab", CFrame.new(), def.Size)
	elseif id == "wall" then
		part("Wall", CFrame.new(), def.Size)
	elseif id == "window" then
		part("Wall", CFrame.new(0, -2.5, 0), V(8, 3, 0.8))
		part("Wall", CFrame.new(0, 3, 0), V(8, 2, 0.8))
		part("Wall", CFrame.new(-2.75, 0.5, 0), V(2.5, 3, 0.8))
		part("Wall", CFrame.new(2.75, 0.5, 0), V(2.5, 3, 0.8))
		Parts.box(m, "Bar", cf * CFrame.new(0, 0.5, 0), V(0.25, 3, 0.25), RGB(60, 50, 40), M.Wood)
	elseif id == "doorway" then
		part("Wall", CFrame.new(-2.9, 0, 0), V(2.2, 8, 0.8))
		part("Wall", CFrame.new(2.9, 0, 0), V(2.2, 8, 0.8))
		part("Wall", CFrame.new(0, 3.1, 0), V(3.6, 1.8, 0.8))
		-- дверь на петлях (левый край)
		local hinge = cf * CFrame.new(-1.8, -0.9, 0)
		local door = Parts.box(m, "Door", hinge * CFrame.new(1.8, 0, 0), V(3.6, 6.2, 0.4), RGB(96, 64, 40), M.Wood)
		local handle = Parts.box(m, "Handle", hinge * CFrame.new(3.1, 0, -0.35), V(0.25, 0.6, 0.25), RGB(40, 40, 40), M.Metal, { CanCollide = false })
		local open = false
		local pr = prompt(door, "Открыть", "Дверь", 0, 8)
		local dRel, hRel = hinge:ToObjectSpace(door.CFrame), hinge:ToObjectSpace(handle.CFrame)
		pr.Triggered:Connect(function()
			open = not open
			pr.ActionText = open and "Закрыть" or "Открыть"
			local h = hinge * CFrame.Angles(0, open and math.rad(100) or 0, 0)
			TweenService:Create(door, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { CFrame = h * dRel }):Play()
			TweenService:Create(handle, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { CFrame = h * hRel }):Play()
		end)
	elseif id == "stairs" then
		local w = Instance.new("WedgePart")
		w.Name = "Steps"
		w.Anchored = true
		w.Size = def.Size
		w.CFrame = cf
		w.Parent = m
	end
	CollectionService:AddTag(m, "BuildPiece")
	Build.setTier(m, 0)
	m.Parent = parent
	return m
end

-- кровать: лечь и проспать ночь
function Build.bed(parent, cf)
	local m = Instance.new("Model")
	m.Name = "Bed"
	local wood = RGB(100, 70, 44)
	Parts.box(m, "Frame", cf * CFrame.new(0, 0.6, 0), V(4, 1.2, 7.5), wood, M.Wood)
	Parts.box(m, "Mattress", cf * CFrame.new(0, 1.45, 0.2), V(3.6, 0.6, 7), RGB(200, 190, 170), M.Fabric)
	Parts.box(m, "Blanket", cf * CFrame.new(0, 1.8, 1.3), V(3.7, 0.25, 4.6), RGB(120, 50, 45), M.Fabric)
	Parts.box(m, "Pillow", cf * CFrame.new(0, 1.9, -2.6), V(2.6, 0.5, 1.2), RGB(235, 230, 220), M.Fabric)
	Parts.box(m, "Headboard", cf * CFrame.new(0, 2, -3.6), V(4, 2.8, 0.4), wood, M.Wood)
	local pr = prompt(m:FindFirstChild("Mattress"), "Лечь спать", "Кровать", 0.4, 8)
	m:SetAttribute("SleepCF", cf * CFrame.new(0, 2.6, 0.4))
	m.Parent = parent
	return m, pr
end

-- сундук-хранилище
function Build.chest(parent, cf)
	local m = Instance.new("Model")
	m.Name = "StorageChest"
	local wood = RGB(110, 76, 46)
	local body = Parts.box(m, "Body", cf * CFrame.new(0, 1, 0), V(4.4, 2, 2.6), wood, M.WoodPlanks)
	Parts.box(m, "Lid", cf * CFrame.new(0, 2.3, 0), V(4.6, 0.6, 2.8), RGB(90, 60, 36), M.WoodPlanks)
	Parts.box(m, "Lock", cf * CFrame.new(0, 1.9, -1.45), V(0.6, 0.7, 0.2), RGB(200, 170, 60), M.Metal)
	local put = prompt(body, "Положить всё", "Сундук (пусто)", 0.3, 9)
	local take = prompt(body, "Забрать всё", "Сундук", 0.3, 9)
	take.KeyboardKeyCode = Enum.KeyCode.F
	take.UIOffset = Vector2.new(0, 70)
	m.Parent = parent
	return m, put, take
end

return Build
