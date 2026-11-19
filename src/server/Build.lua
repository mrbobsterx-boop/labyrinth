-- Постройки игроков: детали дома (по сетке), кровать, сундук.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Parts = require(script.Parent.Parts)
local Building = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Building"))
local Deployables = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Deployables"))

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

-- украшения детали под уровень: рамка из брусьев, доски, раскосы, кладка, заклёпки
local function decorate(model, tier)
	local old = model:FindFirstChild("Deco")
	if old then
		old:Destroy()
	end
	local t = Building.Tiers[tier]
	local deco = Instance.new("Model")
	deco.Name = "Deco"
	local kind = model:GetAttribute("BKind")
	local function bit(cf, size, color, mat, shape)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = mat
		if shape then
			p.Shape = shape
		end
		p.Parent = deco
		return p
	end
	for _, core in ipairs(model:GetChildren()) do
		if core:IsA("Part") and core.Name ~= "Door" and core.Name ~= "Handle" and core.Name ~= "Bar" then
			-- плоскость детали: две длинные оси, третья — толщина
			local sz = core.Size
			local cf = core.CFrame
			local thinY = sz.Y < sz.X and sz.Y < sz.Z
			-- переводим в «стеновые» координаты: u — ширина, v — высота, w — толщина
			local base, u, v, w
			if thinY then
				base = cf * CFrame.Angles(math.pi / 2, 0, 0)
				u, v, w = sz.X, sz.Z, sz.Y
			else
				base = cf
				u, v, w = sz.X, sz.Y, sz.Z
			end
			local b = tier == 0 and 0.35 or (tier == 3 and 0.55 or 0.6)
			local depth = w + (tier == 0 and 0.15 or 0.3)
			local fc, fm = t.Frame, t.FrameMat
			-- рамка по краю
			bit(base * CFrame.new(0, v / 2 - b / 2, 0), V(u, b, depth), fc, fm)
			bit(base * CFrame.new(0, -v / 2 + b / 2, 0), V(u, b, depth), fc, fm)
			bit(base * CFrame.new(-u / 2 + b / 2, 0, 0), V(b, v - b * 2, depth), fc, fm)
			bit(base * CFrame.new(u / 2 - b / 2, 0, 0), V(b, v - b * 2, depth), fc, fm)
			local big = u >= 6 and v >= 6
			if tier <= 1 then
				-- доски: тонкие щели между досками на обеих сторонах
				local n = math.floor(v / 1.6)
				for k = 1, n - 1 do
					local y = -v / 2 + k * (v / n)
					bit(base * CFrame.new(0, y, 0), V(u - b * 2, 0.08, w + 0.06), fc, fm)
				end
				-- раскос крест-накрест на стенах
				if tier == 1 and big and not thinY then
					local diag = math.sqrt((u - b * 2) ^ 2 + (v - b * 2) ^ 2)
					local ang = math.atan2(v - b * 2, u - b * 2)
					bit(base * CFrame.Angles(0, 0, ang), V(diag, 0.5, depth), fc, fm)
					bit(base * CFrame.Angles(0, 0, -ang), V(diag, 0.5, depth), fc, fm)
				end
				if tier == 0 then
					-- чертёж: голубые «линии разметки»
					bit(base * CFrame.new(0, 0, 0), V(u - 0.4, 0.06, w + 0.08), RGB(150, 120, 80), Enum.Material.Wood)
				end
			elseif tier == 2 then
				-- каменная кладка: швы рядами, со сдвигом через ряд
				local rows = math.max(1, math.floor(v / 1.4))
				for r = 1, rows - 1 do
					bit(base * CFrame.new(0, -v / 2 + r * (v / rows), 0), V(u - b * 2, 0.1, w + 0.06), RGB(80, 78, 74), Enum.Material.Concrete)
				end
				for r = 0, rows - 1 do
					local y = -v / 2 + (r + 0.5) * (v / rows)
					local off = (r % 2 == 0) and 0 or 1
					for x = -u / 2 + 2 + off, u / 2 - 1.5, 2.6 do
						bit(base * CFrame.new(x, y, 0), V(0.1, v / rows, w + 0.06), RGB(80, 78, 74), Enum.Material.Concrete)
					end
				end
			else
				-- металл: заклёпки по углам и центральная полоса
				for _, sx in ipairs({ -1, 1 }) do
					for _, sy in ipairs({ -1, 1 }) do
						for _, sw in ipairs({ -1, 1 }) do
							bit(base * CFrame.new(sx * (u / 2 - b / 2), sy * (v / 2 - b / 2), sw * depth / 2), V(0.3, 0.3, 0.3), RGB(170, 175, 182), Enum.Material.Metal, Enum.PartType.Ball)
						end
					end
				end
				if big then
					bit(base, V(u - b * 2, 0.8, w + 0.12), RGB(80, 84, 90), Enum.Material.Metal)
				end
			end
		end
	end
	-- у фундамента — массивные угловые столбы
	if kind == "foundation" then
		local core = model:FindFirstChild("Slab")
		if core then
			for _, sx in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					bit(core.CFrame * CFrame.new(sx * 3.6, -0.2, sz * 3.6), V(1.2, core.Size.Y + 0.6, 1.2), t.Frame, t.FrameMat)
				end
			end
		end
	end
	deco.Parent = model
end

local TIER_FX = { [1] = RGB(150, 110, 70), [2] = RGB(170, 170, 165), [3] = RGB(200, 210, 225) }

-- перекрасить деталь под уровень (animate — с анимацией улучшения)
function Build.setTier(model, tier, animate)
	local t = Building.Tiers[tier]
	model:SetAttribute("Tier", tier)
	model:SetAttribute("HP", t.HP)
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") and d.Name ~= "Handle" then
			d.Color = t.Color
			d.Material = t.Material
			d.Transparency = tier == 0 and 0.25 or 0
			if animate then
				-- «толчок»: деталь чуть раздувается и встаёт на место, летит пыль
				local size = d.Size
				d.Size = size * 1.06
				TweenService:Create(d, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = size }):Play()
			end
		end
	end
	if model:GetAttribute("BKind") ~= "door" and model:GetAttribute("BKind") ~= "stairs" then
		decorate(model, tier)
		if animate then
			-- новая отделка «нарастает» поверх старой
			for k, d in ipairs(model:FindFirstChild("Deco"):GetChildren()) do
				local tr = d.Transparency
				d.Transparency = 1
				task.delay(k * 0.015, function()
					TweenService:Create(d, TweenInfo.new(0.25), { Transparency = tr }):Play()
				end)
			end
		end
	end
	if animate then
		local main = model:FindFirstChildWhichIsA("BasePart")
		if main then
			local fx = Instance.new("ParticleEmitter")
			fx.Color = ColorSequence.new(TIER_FX[tier] or RGB(200, 200, 200))
			fx.Size = NumberSequence.new(1.2, 0)
			fx.Lifetime = NumberRange.new(0.5, 0.9)
			fx.Speed = NumberRange.new(6, 12)
			fx.SpreadAngle = Vector2.new(180, 180)
			fx.Rate = 0
			fx.Parent = main
			fx:Emit(30)
			task.delay(1.5, function()
				fx:Destroy()
			end)
		end
	end
end

-- деталь «собирается»: части поднимаются из земли, доски слетаются к центру
local function buildAnimation(model)
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	for k, d in ipairs(parts) do
		local final, tr = d.CFrame, d.Transparency
		d.CFrame = final - V(0, 2.5, 0)
		d.Transparency = 1
		task.delay(math.min(0.6, (k - 1) * 0.025), function()
			TweenService:Create(d, TweenInfo.new(0.45, Enum.EasingStyle.Back), { CFrame = final, Transparency = tr }):Play()
		end)
	end
	local cf = model:GetBoundingBox()
	for k = 1, 5 do
		local plank = Instance.new("Part")
		plank.Anchored = true
		plank.CanCollide = false
		plank.CanQuery = false
		plank.Size = V(3, 0.3, 0.8)
		plank.Color = RGB(205, 180, 125)
		plank.Material = M.WoodPlanks
		local a = k / 5 * math.pi * 2
		plank.CFrame = cf * CFrame.new(math.cos(a) * 6, 4, math.sin(a) * 6) * CFrame.Angles(a, a * 2, 0)
		plank.Parent = model
		TweenService:Create(plank, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = cf, Transparency = 1 }):Play()
		task.delay(0.45, function()
			plank:Destroy()
		end)
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
	if def.Edge or def.Door then
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
	elseif id == "door" then
		-- дверь на петлях (левый край), E — открыть/закрыть
		local hinge = cf * CFrame.new(-1.8, 0, 0)
		local door = part("Door", CFrame.new(), def.Size)
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
	buildAnimation(m)
	return m
end

-- кровать: лечь и проспать ночь
function Build.bed(parent, cf)
	local m = Deployables.build("bed", cf)
	m.Name = "Bed"
	local pr = prompt(m:FindFirstChild("Mattress"), "Лечь спать", "Кровать", 0.4, 8)
	m:SetAttribute("SleepCF", cf * CFrame.new(0, 2.6, 0.4))
	m.Parent = parent
	return m, pr
end

-- сундук-хранилище
function Build.chest(parent, cf)
	local m = Deployables.build("chest", cf)
	m.Name = "StorageChest"
	local body = m:FindFirstChild("Body")
	local put = prompt(body, "Положить всё", "Сундук (пусто)", 0.3, 9)
	local take = prompt(body, "Забрать всё", "Сундук", 0.3, 9)
	take.KeyboardKeyCode = Enum.KeyCode.F
	take.UIOffset = Vector2.new(0, 70)
	m.Parent = parent
	return m, put, take
end

return Build
