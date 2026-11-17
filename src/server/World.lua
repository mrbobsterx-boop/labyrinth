-- Постройка мира: лобби (3 лифта сложности, торговец классами), поляна (лес, река, лифт),
-- стены с воротами и лабиринт (шахты, сундуки, щели, выход с вертолётной площадкой).
-- Каждая группа игроков получает свой лабиринт со своим смещением O.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Parts = require(script.Parent.Parts)
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Items = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Items"))
local Deployables = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Deployables"))

local World = {}

local V = Vector3.new
local RGB = Color3.fromRGB
local M = Enum.Material

local MZ = Config.Maze
local N, C = MZ.Cells, MZ.CellSize
local MID = (N - 1) // 2
local HALF = N * C / 2
local CLEAR_LO, CLEAR_HI = MID - (MZ.ClearingCells - 1) // 2, MID + (MZ.ClearingCells - 1) // 2
local CLEAR_HALF = MZ.ClearingCells * C / 2

World.LOBBY = V(0, 50, 0)
World.CLEARING_HALF = CLEAR_HALF
World.HALF = HALF

local WALL = RGB(84, 86, 82)
local WALL_DARK = RGB(60, 62, 60)
local IVY = RGB(52, 82, 44)
local WOOD = RGB(92, 64, 40)
local METAL = RGB(70, 72, 76)
local NOCOLLIDE = { CanCollide = false }

local function inClearing(i, j)
	return i >= CLEAR_LO and i <= CLEAR_HI and j >= CLEAR_LO and j <= CLEAR_HI
end

local function tag(inst, name)
	CollectionService:AddTag(inst, name)
end

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

------------------------------------------------------------------
-- Ресурсные узлы (деревья, камни, руда) — добываются ударом или зажатой E
------------------------------------------------------------------
local function node(parent, kind, pos, rng)
	local def = Items.Nodes[kind]
	local m = Instance.new("Model")
	m.Name = def.Name
	m:SetAttribute("Node", kind)
	m:SetAttribute("HP", def.Health)
	local main
	if kind == "tree" then
		local h = rng:NextNumber(20, 30)
		main = Parts.box(m, "Trunk", CFrame.new(pos + V(0, h / 2, 0)), V(2.2, h, 2.2), RGB(84, 60, 40), M.Wood)
		local leaf = RGB(rng:NextInteger(38, 58), rng:NextInteger(86, 112), rng:NextInteger(38, 52))
		for k = 1, 5 do
			local s = rng:NextNumber(9, 13) * (1 - k * 0.11)
			Parts.box(m, "Leaves", CFrame.new(pos + V(rng:NextNumber(-2, 2), h * 0.55 + k * 2.8, rng:NextNumber(-2, 2))), V(s, s * 0.8, s), leaf, M.LeafyGrass, {
				Shape = Enum.PartType.Ball,
				CanCollide = false,
			})
		end
	else
		local rock = RGB(100, 100, 104)
		for _ = 1, 3 do
			local s = rng:NextNumber(2.6, 4.4)
			local cf = CFrame.new(pos + V(rng:NextNumber(-1.6, 1.6), s * 0.4, rng:NextNumber(-1.6, 1.6)))
				* CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), rng:NextNumber(0, 3))
			local r = Parts.box(m, "Rock", cf, V(s, s * 0.8, s), rock, M.Slate)
			main = main or r
		end
		if kind ~= "stone" then
			local c = kind == "iron" and RGB(170, 100, 60) or RGB(170, 90, 255)
			local mat = kind == "iron" and M.CorrodedMetal or M.Neon
			for _ = 1, 5 do
				local cf = CFrame.new(pos + V(rng:NextNumber(-2, 2), rng:NextNumber(0.8, 3), rng:NextNumber(-2, 2)))
					* CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), rng:NextNumber(0, 3))
				Parts.box(m, "Ore", cf, kind == "crystal" and V(0.5, 1.8, 0.5) or V(0.9, 0.9, 0.9), c, mat, NOCOLLIDE)
			end
			if kind == "crystal" then
				Parts.light(m:FindFirstChild("Ore"), 12, 1, c, false)
			end
		end
	end
	local p = prompt(main, def.Action, def.Name, 0.7, 11)
	tag(p, "NodePrompt")
	m.Parent = parent
	tag(m, "Node")
	return m
end
World.node = node

------------------------------------------------------------------
-- Верстак (крафтится игроком и ставится перед собой)
------------------------------------------------------------------
function World.BuildWorkbench(parent, cf)
	local wb = Deployables.build("workbench", cf)
	wb.Name = "Workbench"
	local top = wb:FindFirstChild("Top")
	local p = prompt(top, "Крафт", "Верстак", 0, 10)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 200, 0, 36)
	bb.StudsOffset = V(0, 3, 0)
	bb.MaxDistance = 60
	bb.Parent = top
	local bl = Instance.new("TextLabel")
	bl.Size = UDim2.fromScale(1, 1)
	bl.BackgroundTransparency = 1
	bl.TextColor3 = RGB(255, 230, 180)
	bl.TextStrokeTransparency = 0.3
	bl.Font = Enum.Font.GothamBold
	bl.TextScaled = true
	bl.Text = "Верстак · ур. 1"
	bl.Parent = bb
	wb:SetAttribute("Level", 1)
	wb.Parent = parent
	tag(wb, "Workbench")
	return { model = wb, prompt = p, label = bl, top = top }
end

------------------------------------------------------------------
-- Классический Roblox-человечек (торговец)
------------------------------------------------------------------
local function classicNPC(parent, cf, name)
	local m = Instance.new("Model")
	m.Name = name
	-- торговец-путешественник: шляпа-сафари, рубашка цвета хаки, жилет, ремень, рюкзак
	local skin, khaki, vest, pants = RGB(245, 205, 48), RGB(196, 170, 112), RGB(120, 92, 58), RGB(92, 74, 52)
	local torso = Parts.box(m, "Torso", cf * CFrame.new(0, 3, 0), V(2, 2, 1), khaki, M.Fabric)
	local head = Parts.box(m, "Head", cf * CFrame.new(0, 4.5, 0), V(2, 1, 1), skin, M.SmoothPlastic)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = V(1.25, 1.25, 1.25)
	mesh.Parent = head
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head
	Parts.box(m, "Left Arm", cf * CFrame.new(-1.5, 3, 0), V(1, 2, 1), khaki, M.Fabric)
	Parts.box(m, "Right Arm", cf * CFrame.new(1.5, 3, 0), V(1, 2, 1), khaki, M.Fabric)
	Parts.box(m, "LeftHand", cf * CFrame.new(-1.5, 2.2, 0), V(1.02, 0.5, 1.02), skin, M.SmoothPlastic, NOCOLLIDE)
	Parts.box(m, "RightHand", cf * CFrame.new(1.5, 2.2, 0), V(1.02, 0.5, 1.02), skin, M.SmoothPlastic, NOCOLLIDE)
	Parts.box(m, "Left Leg", cf * CFrame.new(-0.5, 1, 0), V(1, 2, 1), pants, M.Fabric)
	Parts.box(m, "Right Leg", cf * CFrame.new(0.5, 1, 0), V(1, 2, 1), pants, M.Fabric)
	for _, x in ipairs({ -0.5, 0.5 }) do
		Parts.box(m, "Boot", cf * CFrame.new(x, 0.35, -0.05), V(1.05, 0.7, 1.15), RGB(60, 40, 28), M.Leather, NOCOLLIDE)
	end
	-- жилет с карманами, ремень с пряжкой
	Parts.box(m, "Vest", cf * CFrame.new(0, 3.1, 0), V(2.06, 1.8, 1.06), vest, M.Leather, NOCOLLIDE)
	Parts.box(m, "VestOpen", cf * CFrame.new(0, 3.1, -0.54), V(0.6, 1.8, 0.04), khaki, M.Fabric, NOCOLLIDE)
	for _, x in ipairs({ -0.65, 0.65 }) do
		Parts.box(m, "Pocket", cf * CFrame.new(x, 3.2, -0.55), V(0.5, 0.45, 0.05), RGB(100, 76, 46), M.Leather, NOCOLLIDE)
	end
	Parts.box(m, "Belt", cf * CFrame.new(0, 2.1, 0), V(2.08, 0.3, 1.08), RGB(50, 34, 22), M.Leather, NOCOLLIDE)
	Parts.box(m, "Buckle", cf * CFrame.new(0, 2.1, -0.56), V(0.4, 0.3, 0.06), RGB(230, 190, 70), M.Metal, NOCOLLIDE)
	-- шляпа-сафари
	Parts.box(m, "HatBrim", cf * CFrame.new(0, 5.15, 0) * CFrame.Angles(0, 0, math.pi / 2), V(0.15, 3, 3), RGB(214, 190, 130), M.Fabric, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	Parts.box(m, "HatTop", cf * CFrame.new(0, 5.55, 0), V(1.7, 0.9, 1.7), RGB(214, 190, 130), M.Fabric, { Shape = Enum.PartType.Ball, CanCollide = false })
	Parts.box(m, "HatBand", cf * CFrame.new(0, 5.3, 0) * CFrame.Angles(0, 0, math.pi / 2), V(0.25, 1.75, 1.75), RGB(80, 56, 34), M.Fabric, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	-- рюкзак со скатанным спальником
	Parts.box(m, "Backpack", cf * CFrame.new(0, 3.1, 0.85), V(1.6, 1.8, 0.7), RGB(70, 90, 60), M.Fabric, NOCOLLIDE)
	Parts.box(m, "Bedroll", cf * CFrame.new(0, 4.1, 0.85) * CFrame.Angles(0, 0, math.pi / 2), V(0.6, 1.9, 0.6), RGB(160, 60, 50), M.Fabric, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	local hum = Instance.new("Humanoid")
	hum.DisplayName = name
	hum.Parent = m
	m.PrimaryPart = torso
	m.Parent = parent
	return m, torso
end

------------------------------------------------------------------
-- Лобби: три лифта (легко / обычно / тяжело), торговец классами, декор
------------------------------------------------------------------
function World.BuildLobby()
	local m = Instance.new("Model")
	m.Name = "Lobby"
	local o = World.LOBBY
	local concrete = RGB(74, 76, 78)
	Parts.span(m, "Floor", o, V(-62, -1, -27), V(62, 0, 27), RGB(56, 58, 60), M.Concrete)
	Parts.span(m, "Ceiling", o, V(-62, 20, -45), V(62, 21, 27), concrete, M.Concrete)
	Parts.wall(m, o, "X", 27, -62, 62, 0, 20, nil, concrete, M.Concrete, 1)
	Parts.wall(m, o, "Z", -62, -27, 27, 0, 20, nil, concrete, M.Concrete, 1)
	Parts.wall(m, o, "Z", 62, -27, 27, 0, 20, nil, concrete, M.Concrete, 1)
	-- северная стена с тремя проёмами лифтов
	local lifts = { { id = "easy", x = -36 }, { id = "normal", x = 0 }, { id = "hard", x = 36 } }
	local ops = {}
	for _, l in ipairs(lifts) do
		table.insert(ops, { c = l.x, w = 14, b = 0, h = 13 })
	end
	Parts.wall(m, o, "X", -27, -62, 62, 0, 20, ops, concrete, M.Concrete, 1)

	local elevators = {}
	for _, l in ipairs(lifts) do
		local col = RGB(230, 220, 190)
		local x = l.x
		Parts.span(m, "LiftFloor", o, V(x - 9, -1, -45), V(x + 9, 0, -27), RGB(40, 40, 42), M.DiamondPlate)
		Parts.span(m, "LiftWall", o, V(x - 9.5, 0, -45), V(x - 9, 20, -27), METAL, M.DiamondPlate)
		Parts.span(m, "LiftWall", o, V(x + 9, 0, -45), V(x + 9.5, 20, -27), METAL, M.DiamondPlate)
		Parts.span(m, "LiftWall", o, V(x - 9.5, 0, -45.5), V(x + 9.5, 20, -45), METAL, M.DiamondPlate)
		local lamp = Parts.span(m, "LiftLight", o, V(x - 6, 19.2, -42), V(x + 6, 19.5, -30), RGB(255, 235, 200), M.Neon)
		Parts.light(lamp, 24, 1.1, RGB(255, 225, 190), false)
		-- цветная полоса и табличка над входом
		Parts.span(m, "LiftStripe", o, V(x - 7, 13, -26.6), V(x + 7, 13.6, -26.2), col, M.Neon)
		local sign = Parts.span(m, "LiftSign", o, V(x - 7, 14, -26.6), V(x + 7, 18, -26.2), RGB(20, 20, 22), M.SmoothPlastic)
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Back
		sg.PixelsPerStud = 25
		sg.Parent = sign
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.GothamBlack
		t.TextScaled = true
		t.TextColor3 = col
		t.Text = "ЛИФТ"
		t.Parent = sg
		for k = -3, 3 do
			Parts.span(m, "Hazard", o, V(x + k * 2 - 0.5, 0, -27), V(x + k * 2 + 0.5, 0.05, -25), (k % 2 == 0) and RGB(220, 180, 30) or RGB(20, 20, 20), M.SmoothPlastic)
		end
		local zone = Parts.span(m, "LiftZone", o, V(x - 8.5, 0, -44.5), V(x + 8.5, 12, -27.5), nil, nil, { Transparency = 1, CanCollide = false, CanQuery = false })
		elevators[l.id] = { zone = zone, door = o + V(x, 0, -27), outside = CFrame.lookAt(o + V(x, 3, -20), o + V(x, 3, 0)), label = t }
	end

	-- лампы
	for x = -48, 48, 24 do
		for _, z in ipairs({ -10, 12 }) do
			local lamp = Parts.span(m, "Lamp", o, V(x - 2.5, 19.4, z - 1), V(x + 2.5, 19.9, z + 1), RGB(255, 235, 200), M.Neon)
			Parts.light(lamp, 30, 0.9, RGB(255, 225, 190), (x + z) % 3 == 0)
		end
	end

	-- правила
	local board = Parts.span(m, "Rules", o, V(61.4, 4, -12), V(61.6, 15, 12), RGB(28, 30, 34), M.SmoothPlastic)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Left
	sg.PixelsPerStud = 25
	sg.Parent = board
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.TextColor3 = RGB(230, 225, 210)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextWrapped = true
	t.Text = "ПРАВИЛА ПОЛЯНЫ\n\n1. Днём врата открыты — исследуй лабиринт.\n2. На закате врата закрываются. Вернись!\n3. Ночью в лабиринте Скрежетники.\n4. Раненого друга подними бинтом.\n5. Найди Ключ в золотом сундуке и выход.\n6. Ctrl — пригнуться и пролезть в щель."
	t.Parent = sg

	-- ларёк торговца классами: деревянный навес, гирлянда ламп, вывеска, клетка, ящики
	local base = CFrame.lookAt(o + V(-52, 0, 4), o + V(0, 0, 4)) -- -Z смотрит в зал
	local LOG, PLANK, TRIM = RGB(120, 78, 44), RGB(98, 62, 36), RGB(240, 200, 70)
	local function bp(name, rel, size, color, mat, props)
		return Parts.box(m, name, base * rel, size, color, mat, props)
	end
	bp("BoothFloor", CFrame.new(0, 0.2, 0), V(22, 0.4, 12), RGB(80, 60, 44), M.WoodPlanks)
	bp("BoothGlow", CFrame.new(0, 0.05, -6.6), V(24, 0.1, 1.2), RGB(60, 255, 230), M.Neon, NOCOLLIDE)
	for _, x in ipairs({ -10, -6, 6, 10 }) do
		bp("BoothPost", CFrame.new(x, 7, -5), V(1.4, 14, 1.4), LOG, M.Wood, { Shape = Enum.PartType.Cylinder, Orientation = V(0, 0, 90) })
		bp("BoothPost", CFrame.new(x, 7, 5), V(1.4, 14, 1.4), LOG, M.Wood, { Shape = Enum.PartType.Cylinder, Orientation = V(0, 0, 90) })
	end
	bp("BoothBack", CFrame.new(0, 7, 5.6), V(22, 14, 0.6), PLANK, M.WoodPlanks)
	bp("BoothRoof", CFrame.new(0, 14.4, 0) * CFrame.Angles(math.rad(-8), 0, 0), V(25, 0.8, 14), RGB(110, 70, 40), M.WoodPlanks)
	-- зубчатая жёлтая кромка крыши
	for k = -6, 6 do
		bp("RoofTrim", CFrame.new(k * 1.9, 13.5, -7.3) * CFrame.Angles(0, 0, math.rad(45)), V(1.3, 1.3, 0.3), TRIM, M.SmoothPlastic, NOCOLLIDE)
	end
	bp("RoofBeam", CFrame.new(0, 13.9, -7.1), V(25, 0.6, 0.6), TRIM, M.SmoothPlastic, NOCOLLIDE)
	-- прилавок из бревна
	local counter = bp("Counter", CFrame.new(0, 1.8, -3.8), V(18, 3.6, 2.2), PLANK, M.WoodPlanks)
	bp("CounterLog", CFrame.new(0, 3.9, -3.8) * CFrame.Angles(0, math.pi / 2, 0), V(19, 1.6, 1.6), LOG, M.Wood, { Shape = Enum.PartType.Cylinder })
	for _, x in ipairs({ -9.6, 9.6 }) do
		bp("LogEnd", CFrame.new(x, 3.9, -3.8) * CFrame.Angles(0, math.pi / 2, 0), V(0.3, 1.7, 1.7), TRIM, M.Wood, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	end
	-- лампы-шары под крышей
	for _, x in ipairs({ -9, -5, 5, 9 }) do
		local bulb = bp("BoothBulb", CFrame.new(x, 12.6, -5.6), V(1.8, 1.8, 1.8), RGB(255, 245, 220), M.Neon, { Shape = Enum.PartType.Ball, CanCollide = false })
		Parts.light(bulb, 16, 1.2, RGB(255, 235, 200), false)
	end
	-- вывеска
	local signBoard = bp("BoothSign", CFrame.new(0, 17.2, -6.2) * CFrame.Angles(math.rad(-6), 0, 0), V(18, 5, 0.6), RGB(90, 56, 32), M.WoodPlanks)
	local ss = Instance.new("SurfaceGui")
	ss.Face = Enum.NormalId.Front
	ss.PixelsPerStud = 30
	ss.Parent = signBoard
	local st1 = Instance.new("TextLabel")
	st1.Size = UDim2.fromScale(1, 0.62)
	st1.BackgroundTransparency = 1
	st1.Font = Enum.Font.FredokaOne
	st1.TextScaled = true
	st1.TextColor3 = RGB(255, 70, 120)
	st1.TextStrokeTransparency = 0
	st1.TextStrokeColor3 = RGB(60, 20, 20)
	st1.Text = "КЛАССЫ"
	st1.Parent = ss
	local st2 = Instance.new("TextLabel")
	st2.Position = UDim2.fromScale(0.05, 0.62)
	st2.Size = UDim2.fromScale(0.9, 0.32)
	st2.BackgroundTransparency = 1
	st2.Font = Enum.Font.GothamBold
	st2.TextScaled = true
	st2.TextColor3 = RGB(255, 245, 225)
	st2.Text = "Стань сильнее с новым классом"
	st2.Parent = ss
	-- декор: птичья клетка, ящики, бумаги, красный флаг
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		bp("CageBar", CFrame.new(5 + math.cos(a) * 1.5, 6.4, 2 + math.sin(a) * 1.5), V(0.15, 4.4, 0.15), RGB(150, 110, 60), M.Wood, NOCOLLIDE)
	end
	bp("CageTop", CFrame.new(5, 8.8, 2), V(3.4, 0.5, 3.4), RGB(150, 110, 60), M.Wood, { Shape = Enum.PartType.Ball, CanCollide = false })
	bp("CageBase", CFrame.new(5, 4.2, 2), V(3.6, 0.3, 3.6), RGB(120, 84, 48), M.Wood)
	bp("CageStand", CFrame.new(5, 2.1, 2), V(0.4, 4.2, 0.4), RGB(90, 60, 36), M.Wood)
	bp("Crate", CFrame.new(-7, 1.2, 3), V(2.4, 2.4, 2.4), RGB(180, 150, 100), M.WoodPlanks)
	bp("Crate", CFrame.new(-7.2, 3.3, 3.1) * CFrame.Angles(0, 0.4, 0), V(1.8, 1.8, 1.8), RGB(190, 160, 110), M.WoodPlanks)
	bp("Paper", CFrame.new(-3, 4.75, -3.6) * CFrame.Angles(0, 0.3, 0), V(1.2, 0.05, 1.5), RGB(240, 230, 200), M.SmoothPlastic, NOCOLLIDE)
	bp("Paper", CFrame.new(3.4, 4.75, -3.7) * CFrame.Angles(0, -0.5, 0), V(1.2, 0.05, 1.5), RGB(240, 230, 200), M.SmoothPlastic, NOCOLLIDE)
	bp("BannerPole", CFrame.new(13.5, 8, -4), V(0.5, 16, 0.5), RGB(70, 50, 30), M.Wood)
	bp("Banner", CFrame.new(13.5, 11, -2.2), V(0.2, 7, 3.4), RGB(200, 50, 45), M.Fabric, NOCOLLIDE)
	local _, npcTorso = classicNPC(m, base * CFrame.new(0, 0.4, 1), "Торговец классами")
	local mp = prompt(counter, "Классы", "Торговец", 0, 14)
	local _ = npcTorso

	-- декор: ящики, бочки, растения, скамейки
	local rng = Random.new(42)
	for _, p in ipairs({ V(50, 0, 20), V(54, 0, 22), V(52, 4, 21), V(-20, 0, 22), V(20, 0, 23) }) do
		Parts.span(m, "Crate", o, p + V(-2, 0, -2), p + V(2, 4, 2), RGB(110, 85, 55), M.WoodPlanks)
	end
	for _, x in ipairs({ -30, -10, 10, 30 }) do
		Parts.span(m, "Bench", o, V(x - 5, 1.6, 20), V(x + 5, 2.1, 23), WOOD, M.WoodPlanks)
		Parts.span(m, "BenchLeg", o, V(x - 4.5, 0, 20.5), V(x - 4, 1.6, 22.5), METAL, M.Metal)
		Parts.span(m, "BenchLeg", o, V(x + 4, 0, 20.5), V(x + 4.5, 1.6, 22.5), METAL, M.Metal)
	end
	for _, p in ipairs({ V(-56, 0, -22), V(56, 0, -22), V(-56, 0, 24), V(42, 0, 24) }) do
		Parts.span(m, "Pot", o, p + V(-1.5, 0, -1.5), p + V(1.5, 2, 1.5), RGB(80, 60, 50), M.Slate)
		Parts.box(m, "Plant", CFrame.new(o + p + V(0, 4, 0)), V(4, 4.5, 4), RGB(50, 110, 55), M.LeafyGrass, { Shape = Enum.PartType.Ball })
	end
	local _ = rng

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = V(12, 1, 6)
	spawn.CFrame = CFrame.new(o + V(0, -0.4, 14))
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = m
	m.Parent = workspace
	return { model = m, spawn = spawn, elevators = elevators, merchantPrompt = mp }
end

------------------------------------------------------------------
-- Рельеф
------------------------------------------------------------------
local RAD = MZ.OuterRadius * C -- радиус круглого лабиринта в studs
World.RADIUS = RAD
local LAKE_R, SAND_R = 62, 76

local function safe(fn)
	local ok, err = pcall(fn)
	if not ok then
		warn("[Labyrinth] рельеф:", err)
	end
end

-- огромная земля вокруг (одинаковая для этого места, строится один раз)
local terrainBuilt = {}
function World.BuildTerrain(O)
	if terrainBuilt[O.X] then
		return
	end
	terrainBuilt[O.X] = true
	local terrain = workspace.Terrain
	local size = Config.SlotSpacing - 160
	safe(function()
		terrain:FillBlock(CFrame.new(O + V(0, -4, 0)), V(size, 8, size), M.Grass)
	end)
	-- внутри круглого лабиринта — утоптанная земля
	safe(function()
		terrain:FillCylinder(CFrame.new(O + V(0, -2, 0)), 4, RAD + 24, M.Ground)
	end)
	-- холмы и горы до самого горизонта
	local rng = Random.new(O.X + 11)
	for k = 1, 46 do
		local a = k / 46 * math.pi * 2 + rng:NextNumber(-0.06, 0.06)
		local dist = rng:NextNumber(RAD + 520, size / 2 - 220)
		local r = rng:NextNumber(120, 240)
		local c = O + V(math.cos(a) * dist, -r * 0.5, math.sin(a) * dist)
		safe(function()
			terrain:FillBall(c, r, M.Grass)
		end)
		if k % 3 == 0 then
			safe(function()
				terrain:FillBall(c + V(0, r * 0.3, 0), r * 0.6, M.Rock)
			end)
		end
	end
	safe(function()
		if not terrain:FindFirstChildOfClass("Clouds") then
			local clouds = Instance.new("Clouds")
			clouds.Cover = 0.55
			clouds.Density = 0.6
			clouds.Parent = terrain
		end
		terrain.WaterColor = RGB(40, 100, 115)
		terrain.WaterTransparency = 0.45
		terrain.WaterWaveSize = 0.12
		terrain.WaterReflectance = 0.7
	end)
end

-- трава поляны и озеро (озеро каждый раз в своей четверти поляны)
function World.BuildClearingTerrain(O, lake)
	local terrain = workspace.Terrain
	local E = CLEAR_HALF
	safe(function()
		terrain:FillBlock(CFrame.new(O + V(0, -6, 0)), V(E * 2, 12, E * 2), M.Grass)
	end)
	safe(function()
		terrain:FillBlock(CFrame.new(O + V(0, 4, 0)), V(E * 2, 8, E * 2), M.Air)
	end)
	if lake then
		safe(function()
			terrain:FillCylinder(CFrame.new(lake + V(0, -2, 0)), 4, SAND_R, M.Sand)
		end)
		safe(function()
			terrain:FillCylinder(CFrame.new(lake + V(0, 1, 0)), 6, LAKE_R, M.Air)
		end)
		safe(function()
			terrain:FillCylinder(CFrame.new(lake + V(0, -6, 0)), 10, LAKE_R, M.Water)
		end)
	end
end

-- после игры пропасть у выхода снова засыпаем
function World.ClearTerrain(O, pit)
	local _ = O
	if pit then
		safe(function()
			workspace.Terrain:FillBlock(pit.cf * CFrame.new(0, -2, 0), pit.size - V(0, 4, 0), M.Grass)
		end)
	end
end

-- лес вокруг всего лабиринта, до самых холмов
function World.BuildOuterForest(parent, O, seed, avoid)
	local m = Instance.new("Model")
	m.Name = "OuterForest"
	local rng = Random.new(seed + 5)
	local far = RAD + 1100
	local placed, tries = 0, 0
	while placed < 1100 and tries < 9000 do
		tries += 1
		local r = RAD + 30 + (rng:NextNumber() ^ 1.5) * (far - RAD - 30)
		local a = rng:NextNumber(0, math.pi * 2)
		local p = O + V(math.cos(a) * r, 0, math.sin(a) * r)
		local blocked = false
		for _, z in ipairs(avoid or {}) do
			local lp = z.cf:PointToObjectSpace(p)
			if math.abs(lp.X) < z.size.X / 2 and math.abs(lp.Z) < z.size.Z / 2 then
				blocked = true
			end
		end
		if not blocked then
			placed += 1
			local h = rng:NextNumber(30, 56)
			local s1 = rng:NextNumber(16, 24)
			Parts.box(m, "Trunk", CFrame.new(p + V(0, h / 2, 0)), V(3, h, 3), RGB(78, 56, 38), M.Wood)
			if rng:NextNumber() < 0.4 then
				Parts.box(m, "Crown", CFrame.new(p + V(0, h * 0.62, 0)), V(s1 * 1.1, h * 0.75, s1 * 1.1), RGB(28, 66, 40), M.LeafyGrass, { Shape = Enum.PartType.Ball, CanCollide = false })
			else
				local leaf = RGB(rng:NextInteger(30, 52), rng:NextInteger(74, 108), rng:NextInteger(34, 50))
				Parts.box(m, "Crown", CFrame.new(p + V(0, h * 0.75, 0)), V(s1, s1 * 0.85, s1), leaf, M.LeafyGrass, { Shape = Enum.PartType.Ball, CanCollide = false })
				if r < RAD + 300 then
					Parts.box(m, "Crown", CFrame.new(p + V(rng:NextNumber(-3, 3), h * 0.95, rng:NextNumber(-3, 3))), V(s1 * 0.7, s1 * 0.6, s1 * 0.7), leaf, M.LeafyGrass, { Shape = Enum.PartType.Ball, CanCollide = false })
				end
			end
		end
	end
	m.Parent = parent
end

------------------------------------------------------------------
-- Записки прошлых выживших и заброшенные лагеря
------------------------------------------------------------------
local NOTES = {
	{ "Дневник, день 3", "Стены не двигаются. Я проверил: зарубки на камне те же. Это мы теряем рассудок, а не лабиринт меняется." },
	{ "Нацарапано углём", "НЕ БЕГИТЕ НОЧЬЮ. Они слышат шаги. Идите тихо — и, может быть, доживёте до утра." },
	{ "Обрывок карты", "Выход есть! Огромные ворота у самой внешней стены. Но без ключ-карты они не откроются." },
	{ "Записка шахтёра", "Камень — деревянной киркой. Железо — только каменной. Кристаллы светятся в самых дальних шахтах, нужна железная." },
	{ "Медицинская памятка", "Если друг упал — не бросай его. Три пучка высокой травы — и у тебя бинт. Подними его, пока не поздно." },
	{ "Подпись: М.", "Скрежетники огромные. В узкие щели в стенах они не пролезают. Пригнись (Ctrl) — и ты спасён." },
	{ "Дрожащий почерк", "Вчера ночью я слышал вертолёт за стеной. Значит, снаружи кто-то есть. Значит, отсюда можно выбраться." },
	{ "Список", "Нас было пятеро. Осталось двое. Мы больше не ходим в лабиринт после того, как солнце касается стен." },
	{ "Правило поляны", "Пока врата закрыты — поляна безопасна. Опоздал хоть на секунду — ночуешь с ними." },
	{ "Чья-то догадка", "Каждый раз, когда приезжает лифт, коридоры другие. Карты бесполезны. Запоминай приметы: мох, кости, шахты." },
	{ "Рецепт", "Верстак — двенадцать брёвен и четыре камня. Без него не будет ни мечей, ни нормальной кирки." },
	{ "Последняя запись", "Золотой сундук. Самый дальний тупик. Над ним светится ключ. Я почти дошёл, но стемнело..." },
}

local function note(parent, cf, rng, index)
	local n = NOTES[(index - 1) % #NOTES + 1]
	local paper = Parts.box(parent, "Note", cf, V(1.2, 0.05, 1.6), RGB(230, 220, 190), M.SmoothPlastic, NOCOLLIDE)
	paper.CanQuery = true
	local p = prompt(paper, "Прочитать", "Записка", 0, 8)
	p:SetAttribute("Title", n[1])
	p:SetAttribute("Text", n[2])
	tag(p, "NotePrompt")
	local _ = rng
	return paper
end

local function lootCrate(parent, pos, rng, name)
	local crate = Parts.box(parent, name or "SupplyBox", CFrame.new(pos + V(0, 1.1, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), V(2.6, 2.2, 2.2), RGB(115, 90, 58), M.WoodPlanks)
	local p = prompt(crate, "Обыскать", name == "Backpack" and "Рюкзак" or "Ящик", 0.8, 9)
	tag(p, "LootPrompt")
	return crate
end

-- заброшенный лагерь: палатка, потухший костёр, рюкзак, записка
local function camp(parent, center, rng, noteIndex)
	local base = CFrame.new(center) * CFrame.Angles(0, rng:NextNumber(0, 6), 0)
	local cloth = RGB(rng:NextInteger(90, 140), rng:NextInteger(70, 100), 50)
	for _, side in ipairs({ -1, 1 }) do
		Parts.box(parent, "Tent", base * CFrame.new(side * 2.2, 2.3, -4) * CFrame.Angles(0, 0, side * math.rad(-40)), V(0.2, 6, 7), cloth, M.Fabric)
	end
	Parts.box(parent, "AshPit", base * CFrame.new(3, 0.15, 3), V(3, 0.3, 3), RGB(40, 36, 34), M.Slate, NOCOLLIDE)
	for k = 0, 3 do
		Parts.box(parent, "BurntLog", base * CFrame.new(3, 0.4, 3) * CFrame.Angles(0, k * math.pi / 4, math.pi / 2), V(0.6, 2.6, 0.6), RGB(30, 26, 24), M.Wood, NOCOLLIDE)
	end
	lootCrate(parent, (base * CFrame.new(-3, 0, 2)).Position, rng, "Backpack")
	note(parent, base * CFrame.new(0.5, 0.1, 1) * CFrame.Angles(0, 0.4, 0), rng, noteIndex)
end

-- заросли лиан: занавес из свисающих стеблей и шапка листвы сверху
local function vineHide(parent, pos, rng)
	local m = Instance.new("Model")
	m.Name = "VineHide"
	local center = Parts.box(m, "HideCenter", CFrame.new(pos + V(0, 3, 0)), V(4, 6, 4), IVY, M.LeafyGrass, NOCOLLIDE)
	center.Transparency = 1
	Parts.box(m, "Canopy", CFrame.new(pos + V(0, 10, 0)), V(10, 5, 10), IVY, M.LeafyGrass, { Shape = Enum.PartType.Ball, CanCollide = false })
	for k = 1, 30 do
		local a = k / 30 * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local r = rng:NextNumber(2.6, 3.8)
		local len = rng:NextNumber(7, 10)
		local top = 10
		local c = RGB(rng:NextInteger(40, 66), rng:NextInteger(78, 110), rng:NextInteger(36, 52))
		Parts.box(m, "Vine", CFrame.new(pos + V(math.cos(a) * r, top - len / 2, math.sin(a) * r)) * CFrame.Angles(rng:NextNumber(-0.06, 0.06), a, rng:NextNumber(-0.06, 0.06)), V(rng:NextNumber(0.25, 0.5), len, rng:NextNumber(0.6, 1.4)), c, M.LeafyGrass, NOCOLLIDE)
	end
	for _ = 1, 8 do
		local a = rng:NextNumber(0, math.pi * 2)
		Parts.box(m, "Leaves", CFrame.new(pos + V(math.cos(a) * 3.4, rng:NextNumber(1, 7), math.sin(a) * 3.4)), V(2.2, 1.6, 2.2), IVY, M.LeafyGrass, { Shape = Enum.PartType.Ball, CanCollide = false })
	end
	local p = prompt(center, "Спрятаться", "Заросли лиан", 0.3, 9)
	tag(p, "HidePrompt")
	m.Parent = parent
	return m
end

------------------------------------------------------------------
-- Поляна
------------------------------------------------------------------
local function mine(parent, center, facing, kinds, rng, nodes)
	local b = CFrame.lookAt(center, center + facing)
	local beam = RGB(80, 58, 36)
	for _, x in ipairs({ -10, 10 }) do
		Parts.box(parent, "MineSupport", b * CFrame.new(x, 7, -11), V(1.4, 14, 1.4), beam, M.Wood)
	end
	Parts.box(parent, "MineBeam", b * CFrame.new(0, 14.5, -11), V(21.5, 1.4, 1.4), beam, M.Wood)
	local lantern = Parts.box(parent, "MineLantern", b * CFrame.new(0, 13, -11), V(0.9, 1.3, 0.9), RGB(255, 170, 80), M.Neon)
	Parts.light(lantern, 30, 1.3, RGB(255, 170, 90), true)
	Parts.box(parent, "MineCart", b * CFrame.new(8, 1.2, 5), V(3.4, 2.2, 5), RGB(80, 70, 60), M.CorrodedMetal)
	for k, kind in ipairs(kinds) do
		local off = ({ V(-7, 0, 2), V(5, 0, -3), V(-3, 0, 8), V(7, 0, 9) })[k]
		table.insert(nodes, node(parent, kind, (b * CFrame.new(off)).Position, rng))
	end
end

function World.BuildClearing(parent, seed, O)
	local m = Instance.new("Model")
	m.Name = "Clearing"
	local rng = Random.new(seed)
	local refs = { model = m, nodes = {} }
	local E = CLEAR_HALF

	-- тропинки от лифта к четырём воротам
	Parts.span(m, "Path", O, V(-3.5, 0, -E + 2), V(3.5, 0.06, E - 2), RGB(120, 100, 70), M.Ground)
	Parts.span(m, "Path", O, V(-E + 2, 0, -3.5), V(E - 2, 0.06, 3.5), RGB(120, 100, 70), M.Ground)

	-- лифт в центре поляны
	local e = O
	Parts.span(m, "LiftFloor", e, V(-9, 0, -9), V(9, 0.6, 9), RGB(40, 40, 42), M.DiamondPlate)
	Parts.span(m, "LiftRoof", e, V(-9.5, 16, -9.5), V(9.5, 17, 9.5), METAL, M.DiamondPlate)
	for _, x in ipairs({ -9, 9 }) do
		Parts.span(m, "LiftWall", e, V(x - 0.3, 0.6, -9), V(x + 0.3, 16, 9), METAL, M.DiamondPlate)
	end
	Parts.span(m, "LiftWall", e, V(-9, 0.6, 8.7), V(9, 16, 9.3), METAL, M.DiamondPlate)
	local liftLight = Parts.span(m, "LiftLight", e, V(-6, 15.6, -6), V(6, 15.9, 6), RGB(255, 230, 190), M.Neon)
	Parts.light(liftLight, 22, 1, nil, false)
	local grate = Instance.new("Model")
	grate.Name = "LiftGrate"
	for x = -8, 8, 1.6 do
		Parts.box(grate, "Bar", CFrame.new(e + V(x, 8.3, -9)), V(0.25, 15.4, 0.25), RGB(50, 50, 54), M.Metal)
	end
	for y = 2, 15, 4 do
		Parts.box(grate, "Bar", CFrame.new(e + V(0, y, -9)), V(17.4, 0.25, 0.25), RGB(50, 50, 54), M.Metal)
	end
	grate.Parent = m
	refs.grate = grate
	refs.grateClosed = grate:GetPivot()
	refs.liftSpawn = CFrame.lookAt(e + V(0, 3.5, 0), e + V(0, 3.5, -30))
	refs.liftPos = e

	-- припасы прямо в лифте: ящик, бочка, мешки
	local crate = Parts.span(m, "SupplyCrate", O, V(-8.6, 0.6, 3.6), V(-5.6, 4, 8.4), RGB(120, 95, 60), M.WoodPlanks)
	for _, y in ipairs({ 1.2, 3.4 }) do
		Parts.span(m, "CrateBand", O, V(-8.7, y, 3.5), V(-5.5, y + 0.3, 8.5), RGB(60, 60, 64), M.Metal, NOCOLLIDE)
	end
	refs.supplyPrompt = prompt(crate, "Взять припасы", "Припасы в лифте", 0, 10)
	note(m, CFrame.new(O + V(-7, 4.1, 6)), rng, 9)
	Parts.box(m, "Barrel", CFrame.new(O + V(6.5, 2.4, 6.5)), V(3.6, 3.6, 3.6), RGB(90, 70, 50), M.Wood, { Shape = Enum.PartType.Cylinder, Orientation = V(0, 0, 90) })
	Parts.box(m, "Sack", CFrame.new(O + V(6.8, 1.3, 2.5)) * CFrame.Angles(0, 0.4, 0), V(2.4, 1.4, 1.8), RGB(170, 150, 110), M.Fabric)
	Parts.box(m, "Sack", CFrame.new(O + V(7.2, 1.3, -2.5)) * CFrame.Angles(0, -0.3, 0), V(2.4, 1.4, 1.8), RGB(160, 140, 105), M.Fabric)

	-- поляна делится на 4 четверти, в каждой своё (порядок случайный)
	local kinds = { "lake", "forest", "mine", "meadow" }
	for k = #kinds, 2, -1 do
		local j = rng:NextInteger(1, k)
		kinds[k], kinds[j] = kinds[j], kinds[k]
	end
	local quads = { V(-1, 0, -1), V(1, 0, -1), V(-1, 0, 1), V(1, 0, 1) }
	local QC = E / 2
	local lakeC
	refs.quadrants = {}
	-- случайная точка внутри четверти (не на тропинках, не у лифта)
	local function spotIn(q, margin, avoid)
		for _ = 1, 80 do
			local p = V(q.X * rng:NextNumber(14, E - margin), 0, q.Z * rng:NextNumber(14, E - margin))
			local ok = true
			if lakeC and (O + p - lakeC).Magnitude < SAND_R + 6 then
				ok = false
			end
			for _, a in ipairs(avoid or {}) do
				if (p - a.p).Magnitude < a.r then
					ok = false
				end
			end
			if ok then
				return O + p
			end
		end
		return O + V(q.X * QC, 0, q.Z * QC)
	end
	for k, kind in ipairs(kinds) do
		local q = quads[k]
		local qc = O + q * QC
		refs.quadrants[kind] = qc
		if kind == "lake" then
			lakeC = qc + V(-q.X * 4, 0, -q.Z * 4)
			refs.lakeCenter = lakeC
			-- причал к центру озера
			local dock = lakeC - q * 50
			Parts.box(m, "Dock", CFrame.lookAt(dock + V(0, 0.6, 0), lakeC + V(0, 0.6, 0)) * CFrame.new(0, 0, -6), V(6, 0.6, 24), WOOD, M.WoodPlanks)
			for _, x in ipairs({ -2.6, 2.6 }) do
				for _, z in ipairs({ -2, -10, -17 }) do
					Parts.box(m, "DockPost", CFrame.lookAt(dock, lakeC) * CFrame.new(x, -1, z), V(0.8, 4, 0.8), RGB(70, 50, 34), M.Wood)
				end
			end
			-- камыш и трава по берегу (из неё — бинты)
			for _ = 1, 14 do
				local a = rng:NextNumber(0, math.pi * 2)
				local p = lakeC + V(math.cos(a), 0, math.sin(a)) * rng:NextNumber(LAKE_R + 3, SAND_R + 6)
				if math.abs(p.X - O.X) < E - 6 and math.abs(p.Z - O.Z) < E - 6 then
					local base = Parts.box(m, "TallGrass", CFrame.new(p + V(0, 1.4, 0)), V(2.6, 2.8, 2.6), RGB(110, 140, 70), M.Grass, NOCOLLIDE)
					base.Transparency = 0.2
					tag(prompt(base, "Сорвать траву", "Высокая трава", 0.4, 9), "FiberPrompt")
				end
			end
		elseif kind == "forest" then
			-- густая роща: деревья отрастают после вырубки
			local placedT = {}
			for _ = 1, 700 do
				if #placedT >= 95 then
					break
				end
				local p = spotIn(q, 8)
				local ok = true
				for _, t in ipairs(placedT) do
					if (t - p).Magnitude < 8.5 then
						ok = false
						break
					end
				end
				if ok then
					table.insert(placedT, p)
					table.insert(refs.nodes, node(m, "tree", p, rng))
				end
			end
		elseif kind == "mine" then
			-- скалы, вход в шахту и много камня с железом
			for _ = 1, 14 do
				local p = spotIn(q, 16)
				local sz = rng:NextNumber(8, 20)
				Parts.box(m, "Cliff", CFrame.new(p + V(0, sz * 0.3, 0)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6), rng:NextNumber(-0.3, 0.3)), V(sz, sz * 0.8, sz * 0.9), RGB(98, 96, 92), M.Slate)
			end
			mine(m, qc, ((O - qc) * V(1, 0, 1)).Unit, { "stone", "stone", "iron", "iron" }, rng, refs.nodes)
			for k2 = 1, 16 do
				table.insert(refs.nodes, node(m, k2 % 4 == 0 and "iron" or "stone", spotIn(q, 10, { { p = qc - O, r = 18 } }), rng))
			end
		else
			-- луг: костёр с брёвнами, ягоды, высокая трава, цветы
			local fc = qc
			local fireBase = Parts.box(m, "Campfire", CFrame.new(fc + V(0, 0.3, 0)), V(4, 0.6, 4), RGB(50, 34, 26), M.Slate)
			local fire = Instance.new("Fire")
			fire.Size = 6
			fire.Heat = 9
			fire.Parent = fireBase
			Parts.light(fireBase, 40, 1.5, RGB(255, 150, 70), true)
			for k2 = 0, 5 do
				local a = k2 / 6 * math.pi * 2
				Parts.box(m, "Log", CFrame.new(fc + V(math.cos(a) * 6, 0.8, math.sin(a) * 6)) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, math.pi / 2), V(1.6, 4.5, 1.6), WOOD, M.Wood, { Shape = Enum.PartType.Cylinder })
			end
			local avoidFire = { { p = fc - O, r = 12 } }
			for _ = 1, 22 do
				local p = spotIn(q, 10, avoidFire)
				local bush = Parts.box(m, "BerryBush", CFrame.new(p + V(0, 1.8, 0)), V(5, 3.8, 5), RGB(46, 84, 40), M.LeafyGrass, { Shape = Enum.PartType.Ball })
				for _ = 1, 7 do
					Parts.box(m, "Berry", CFrame.new(p + V(rng:NextNumber(-2, 2), rng:NextNumber(1.2, 3.4), rng:NextNumber(-2, 2))), V(0.55, 0.55, 0.55), RGB(200, 30, 50), M.SmoothPlastic, {
						Shape = Enum.PartType.Ball,
						CanCollide = false,
					})
				end
				tag(prompt(bush, "Собрать ягоды", "Куст", 0.5, 10), "BerryPrompt")
			end
			for _ = 1, 20 do
				local p = spotIn(q, 8, avoidFire)
				local base = Parts.box(m, "TallGrass", CFrame.new(p + V(0, 1.4, 0)), V(2.6, 2.8, 2.6), RGB(110, 140, 70), M.Grass, NOCOLLIDE)
				base.Transparency = 0.2
				for _ = 1, 5 do
					Parts.box(m, "Blade", CFrame.new(p + V(rng:NextNumber(-1.2, 1.2), 1.8, rng:NextNumber(-1.2, 1.2))) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), 0, rng:NextNumber(-0.2, 0.2)), V(0.2, 3.6, 0.2), RGB(120, 150, 70), M.Grass, NOCOLLIDE)
				end
				tag(prompt(base, "Сорвать траву", "Высокая трава", 0.4, 9), "FiberPrompt")
			end
			for _ = 1, 120 do
				local p = spotIn(q, 4)
				local c = ({ RGB(230, 210, 80), RGB(200, 80, 120), RGB(240, 240, 240), RGB(150, 120, 230) })[rng:NextInteger(1, 4)]
				Parts.box(m, "Flower", CFrame.new(p + V(0, 0.4, 0)), V(0.7, 0.3, 0.7), c, M.SmoothPlastic, NOCOLLIDE)
			end
		end
	end
	-- немного деревьев и камней у стен по всей поляне
	for _ = 1, 10 do
		local q = quads[rng:NextInteger(1, 4)]
		if refs.quadrants.lake ~= O + q * QC then
			table.insert(refs.nodes, node(m, "stone", spotIn(q, 8), rng))
		end
	end

	m.Parent = parent
	return refs
end

------------------------------------------------------------------
-- Стены поляны с воротами
------------------------------------------------------------------
function World.BuildClearingWalls(parent, O)
	local m = Instance.new("Model")
	m.Name = "ClearingWalls"
	local h = MZ.WallHeight + 12
	local t = 8
	local GW = Config.GateWidth
	local GH = h - 14
	local gates = {}
	local E = CLEAR_HALF
	local op = { { c = 0, w = GW, b = 0, h = GH } }
	Parts.wall(m, O, "X", -E, -E - t / 2, E + t / 2, 0, h, op, WALL_DARK, M.Slate, t)
	Parts.wall(m, O, "X", E, -E - t / 2, E + t / 2, 0, h, op, WALL_DARK, M.Slate, t)
	Parts.wall(m, O, "Z", -E, -E, E, 0, h, op, WALL_DARK, M.Slate, t)
	Parts.wall(m, O, "Z", E, -E, E, 0, h, op, WALL_DARK, M.Slate, t)
	-- плющ на стенах поляны
	local rng = Random.new(O.X + 3)
	for _ = 1, 30 do
		local side = rng:NextInteger(1, 4)
		local a = rng:NextNumber(-E + 20, E - 20)
		local len, hh = rng:NextNumber(10, 26), rng:NextNumber(14, 40)
		local inset = E - t / 2 - 0.2
		local p, size
		if side == 1 then
			p, size = V(a, h - hh / 2, -inset), V(len, hh, 0.4)
		elseif side == 2 then
			p, size = V(a, h - hh / 2, inset), V(len, hh, 0.4)
		elseif side == 3 then
			p, size = V(-inset, h - hh / 2, a), V(0.4, hh, len)
		else
			p, size = V(inset, h - hh / 2, a), V(0.4, hh, len)
		end
		if math.abs(a) > GW / 2 + 6 then
			Parts.box(m, "Ivy", CFrame.new(O + p), size, IVY, M.LeafyGrass, NOCOLLIDE)
		end
	end

	for _, g in ipairs({
		{ name = "Север", pos = V(0, 0, -E), axis = "X" },
		{ name = "Юг", pos = V(0, 0, E), axis = "X" },
		{ name = "Запад", pos = V(-E, 0, 0), axis = "Z" },
		{ name = "Восток", pos = V(E, 0, 0), axis = "Z" },
	}) do
		local along = g.axis == "X" and V(1, 0, 0) or V(0, 0, 1)
		local leaves = {}
		for _, side in ipairs({ -1, 1 }) do
			local size = g.axis == "X" and V(GW / 2, GH, 6) or V(6, GH, GW / 2)
			local closed = CFrame.new(O + g.pos + along * side * (GW / 4) + V(0, GH / 2, 0))
			local leaf = Parts.box(m, "GateLeaf", closed, size, RGB(66, 62, 58), M.Slate)
			for y = -GH / 2 + 5, GH / 2 - 5, 9 do
				Parts.box(leaf, "Band", closed * CFrame.new(0, y, 0), g.axis == "X" and V(GW / 2, 1.2, 6.4) or V(6.4, 1.2, GW / 2), METAL, M.Metal, NOCOLLIDE)
			end
			table.insert(leaves, { part = leaf, closed = closed, open = closed + along * side * (GW / 2 + 1) })
		end
		for _, side in ipairs({ -1, 1 }) do
			local inward = -g.pos.Unit
			local tp = O + g.pos + along * side * (GW / 2 + 4) + inward * 5 + V(0, 14, 0)
			local torch = Parts.box(m, "GateTorch", CFrame.new(tp), V(1, 1.5, 1), RGB(255, 140, 50), M.Neon)
			Parts.light(torch, 34, 1.4, RGB(255, 150, 70), true)
			local f = Instance.new("Fire")
			f.Size = 3
			f.Parent = torch
		end
		table.insert(gates, { name = g.name, leaves = leaves })
	end
	m.Parent = parent
	return gates
end

------------------------------------------------------------------
-- Лабиринт
------------------------------------------------------------------
------------------------------------------------------------------
-- Геометрия лабиринта: внутренний круг (клетки 32) и внешнее кольцо
-- (клетки 64 — «увеличенный» лабиринт: коридоры шире, стены выше).
-- Внешние клетки — это блоки 2x2 мелких клеток, поэтому стены сходятся ровно.
------------------------------------------------------------------
local R1, R2 = MZ.Radius, MZ.OuterRadius
local C2 = C * 2
local NC = math.ceil(N / 2)
local H1, H2 = MZ.WallHeight, MZ.OuterWallHeight

local function blockDist(I, J)
	local x, y = 2 * I + 0.5 - MID, 2 * J + 0.5 - MID
	return math.sqrt(x * x + y * y)
end

-- "inner" / "outer" / "out" для большого блока
local function regionC(I, J)
	if I < 0 or J < 0 or I >= NC or J >= NC then
		return "out"
	end
	local d = blockDist(I, J)
	if d <= R1 then
		return "inner"
	elseif d <= R2 then
		return "outer"
	end
	return "out"
end

-- "in" / "outer" / "clear" / "out" для мелкой клетки
local function regionF(i, j)
	if i < 0 or j < 0 or i >= N or j >= N then
		return "out"
	end
	if inClearing(i, j) then
		return "clear"
	end
	local r = regionC(i // 2, j // 2)
	if r == "inner" then
		return "in"
	end
	return r
end

local function fineKey(i, j)
	return "f" .. i .. "," .. j
end
local function coarseKey(I, J)
	return "c" .. I .. "," .. J
end
local function finePos(i, j)
	return V((i - MID) * C, 0, (j - MID) * C)
end
local function coarsePos(I, J)
	return V((2 * I + 0.5 - MID) * C, 0, (2 * J + 0.5 - MID) * C)
end

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- лабиринт как граф: узлы — клетки обеих зон, рёбра — проходы
local function generate(rng)
	local open = {} -- ключ ребра -> true
	local function ekey(a, b)
		return a < b and (a .. "|" .. b) or (b .. "|" .. a)
	end
	local function dfs(cells, start, nbrs)
		local visited = { [start] = true }
		local stack = { start }
		while #stack > 0 do
			local cur = stack[#stack]
			local cand = {}
			for _, nb in ipairs(nbrs(cur)) do
				if not visited[nb] then
					table.insert(cand, nb)
				end
			end
			if #cand == 0 then
				table.remove(stack)
			else
				local nb = cand[rng:NextInteger(1, #cand)]
				open[ekey(cur, nb)] = true
				visited[nb] = true
				table.insert(stack, nb)
			end
		end
		-- немного лишних проходов, чтобы были петли
		for _, c in ipairs(cells) do
			for _, nb in ipairs(nbrs(c)) do
				if rng:NextNumber() < MZ.ExtraOpenings * 0.5 then
					open[ekey(c, nb)] = true
				end
			end
		end
	end
	local nodes = {}
	-- внутренняя зона
	local fineCells, fineIJ = {}, {}
	for i = 0, N - 1 do
		for j = 0, N - 1 do
			if regionF(i, j) == "in" then
				local k = fineKey(i, j)
				table.insert(fineCells, k)
				fineIJ[k] = { i, j }
				nodes[k] = { key = k, pos = finePos(i, j), size = C, zone = "in", i = i, j = j }
			end
		end
	end
	dfs(fineCells, fineKey(MID, CLEAR_LO - 1), function(k)
		local ij = fineIJ[k]
		local list = {}
		for _, d in ipairs(DIRS) do
			if regionF(ij[1] + d[1], ij[2] + d[2]) == "in" then
				table.insert(list, fineKey(ij[1] + d[1], ij[2] + d[2]))
			end
		end
		return list
	end)
	-- внешнее кольцо
	local coarseCells, coarseIJ = {}, {}
	for I = 0, NC - 1 do
		for J = 0, NC - 1 do
			if regionC(I, J) == "outer" then
				local k = coarseKey(I, J)
				table.insert(coarseCells, k)
				coarseIJ[k] = { I, J }
				nodes[k] = { key = k, pos = coarsePos(I, J), size = C2, zone = "outer", I = I, J = J }
			end
		end
	end
	dfs(coarseCells, coarseCells[1], function(k)
		local ij = coarseIJ[k]
		local list = {}
		for _, d in ipairs(DIRS) do
			if regionC(ij[1] + d[1], ij[2] + d[2]) == "outer" then
				table.insert(list, coarseKey(ij[1] + d[1], ij[2] + d[2]))
			end
		end
		return list
	end)
	-- проходы между кругом и кольцом: по одному в каждом из 10 секторов
	local bins = {}
	for _, k in ipairs(fineCells) do
		local ij = fineIJ[k]
		for _, d in ipairs(DIRS) do
			local ni, nj = ij[1] + d[1], ij[2] + d[2]
			if regionF(ni, nj) == "outer" then
				local a = math.atan2(nj - MID, ni - MID)
				local bin = math.floor((a + math.pi) / (math.pi * 2) * 10) % 10
				bins[bin] = bins[bin] or {}
				table.insert(bins[bin], { k, coarseKey(ni // 2, nj // 2), ni, nj, ij[1], ij[2] })
			end
		end
	end
	local gates = {}
	for b = 0, 9 do
		local list = bins[b]
		if list and #list > 0 then
			local g = list[rng:NextInteger(1, #list)]
			open[ekey(g[1], g[2])] = true
			gates[g[5] .. "," .. g[6] .. ">" .. g[3] .. "," .. g[4]] = true
		end
	end
	-- соседи для поиска путей
	local adj = {}
	for k, n in pairs(nodes) do
		adj[k] = {}
		if n.zone == "in" then
			for _, d in ipairs(DIRS) do
				local ni, nj = n.i + d[1], n.j + d[2]
				local r = regionF(ni, nj)
				local nk = (r == "in" and fineKey(ni, nj)) or (r == "outer" and coarseKey(ni // 2, nj // 2)) or nil
				if nk and open[ekey(k, nk)] and (r == "in" or gates[n.i .. "," .. n.j .. ">" .. ni .. "," .. nj]) then
					table.insert(adj[k], nk)
				end
			end
		end
	end
	for k, n in pairs(nodes) do
		if n.zone == "outer" then
			for _, d in ipairs(DIRS) do
				local nk = coarseKey(n.I + d[1], n.J + d[2])
				if regionC(n.I + d[1], n.J + d[2]) == "outer" and open[ekey(k, nk)] then
					table.insert(adj[k], nk)
				end
			end
		end
	end
	for k, list in pairs(adj) do
		for _, nk in ipairs(list) do
			if nodes[nk].zone ~= nodes[k].zone and not table.find(adj[nk], k) then
				table.insert(adj[nk], k)
			end
		end
	end
	return {
		nodes = nodes,
		adj = adj,
		open = open,
		gates = gates,
		ekey = ekey,
	}
end

-- выход: большая клетка на краю кольца, наружу — свободное место
local function exitCandidates()
	local list = {}
	for I = 0, NC - 1 do
		for J = 0, NC - 1 do
			if regionC(I, J) == "outer" then
				for _, d in ipairs(DIRS) do
					local clear = regionC(I + d[1], J + d[2]) == "out"
					for k = 1, 6 do
						for l = -2, 2 do
							local ci = I + d[1] * k + (d[1] == 0 and l or 0)
							local cj = J + d[2] * k + (d[2] == 0 and l or 0)
							if regionC(ci, cj) ~= "out" then
								clear = false
							end
						end
					end
					if clear then
						table.insert(list, { I = I, J = J, di = d[1], dj = d[2] })
					end
				end
			end
		end
	end
	return list
end

local function chest(parent, pos, facing, golden)
	local m = Instance.new("Model")
	m.Name = golden and "GoldenChest" or "Chest"
	pos = pos + V(0, 0.4, 0)
	local b = CFrame.lookAt(pos, pos + facing)
	local wood = golden and RGB(90, 60, 30) or RGB(100, 70, 40)
	local trim = golden and RGB(230, 180, 60) or RGB(70, 70, 74)
	local body = Parts.box(m, "Body", b * CFrame.new(0, 1.1, 0), V(4, 2.2, 2.6), wood, M.WoodPlanks)
	local lid = Parts.box(m, "Lid", b * CFrame.new(0, 2.5, 0), V(4.1, 0.7, 2.7), wood, M.WoodPlanks)
	for _, x in ipairs({ -1.4, 1.4 }) do
		Parts.box(m, "Band", b * CFrame.new(x, 1.5, 0), V(0.3, 3, 2.8), trim, M.Metal, NOCOLLIDE)
	end
	Parts.box(m, "Lock", b * CFrame.new(0, 2.1, -1.4), V(0.6, 0.7, 0.2), trim, M.Metal, NOCOLLIDE)
	if golden then
		Parts.light(body, 20, 1.4, RGB(255, 200, 90), true)
		-- над золотым сундуком висит ключ
		local key = Parts.box(m, "KeyGlow", b * CFrame.new(0, 5, 0), V(0.4, 1.6, 0.8), RGB(255, 210, 90), M.Neon, NOCOLLIDE)
		Parts.light(key, 14, 1, RGB(255, 210, 90), false)
	end
	local p = prompt(body, "Открыть", golden and "Золотой сундук" or "Сундук", 0.8, 10)
	m:SetAttribute("Golden", golden == true)
	m.Parent = parent
	tag(m, "Chest")
	return { model = m, lid = lid, prompt = p, base = b }
end

-- Стены лабиринта и всё внутри. Каждую ночь строится заново, выход остаётся на месте.
-- fixed: { exit = {I,J,di,dj}, keyTaken, mapFound }
function World.BuildMazeLayout(parent, seed, O, fixed)
	fixed = fixed or {}
	local rng = Random.new(seed)
	local m = Instance.new("Model")
	m.Name = "Maze"
	local g = generate(rng)
	local nodes, adj, open, gates, ekey = g.nodes, g.adj, g.open, g.gates, g.ekey
	local refs = { model = m, nodes = {}, chests = {}, cells = {}, mapWalls = {} }
	local T = MZ.WallThickness

	local list = {}
	for k, n in pairs(nodes) do
		table.insert(list, k)
		table.insert(refs.cells, O + n.pos)
	end
	table.sort(list)

	-- расстояния от ворот поляны
	local dist = {}
	local queue = {}
	for _, st in ipairs({ { MID, CLEAR_LO - 1 }, { MID, CLEAR_HI + 1 }, { CLEAR_LO - 1, MID }, { CLEAR_HI + 1, MID } }) do
		local k = fineKey(st[1], st[2])
		if nodes[k] then
			dist[k] = 0
			table.insert(queue, k)
		end
	end
	local head = 1
	while head <= #queue do
		local cur = queue[head]
		head += 1
		for _, nb in ipairs(adj[cur]) do
			if dist[nb] == nil then
				dist[nb] = dist[cur] + 1
				table.insert(queue, nb)
			end
		end
	end

	-- выход выбирается один раз — самый дальний подходящий
	local ex = fixed.exit
	if not ex then
		local best = -1
		for _, c in ipairs(exitCandidates()) do
			local d = dist[coarseKey(c.I, c.J)] or 0
			if d > best then
				ex, best = c, d
			end
		end
	end
	refs.exit = ex

	-- все отрезки стен: потом соседние склеиваются в длинные
	local segs = {}
	local function addSeg(axis, fixedC, a, b, h, crack)
		table.insert(segs, { axis = axis, fixed = fixedC, a = a, b = b, h = h, crack = crack })
	end
	-- мелкая сетка: стены внутреннего круга и граница с кольцом
	for i = -1, N - 1 do
		for j = -1, N - 1 do
			for _, d in ipairs({ { 1, 0 }, { 0, 1 } }) do
				local ai, aj, bi, bj = i, j, i + d[1], j + d[2]
				local ra, rb = regionF(ai, aj), regionF(bi, bj)
				local wall, h, crack = false, H1, false
				if ra ~= "clear" and rb ~= "clear" then
					if ra == "in" and rb == "in" then
						wall = not open[ekey(fineKey(ai, aj), fineKey(bi, bj))]
						crack = wall and rng:NextNumber() < 0.045
					elseif (ra == "in" and rb == "outer") or (ra == "outer" and rb == "in") then
						local fi, fj, oi, oj = ai, aj, bi, bj
						if ra == "outer" then
							fi, fj, oi, oj = bi, bj, ai, aj
						end
						wall = not gates[fi .. "," .. fj .. ">" .. oi .. "," .. oj]
						h = H2
					elseif (ra == "in" and rb == "out") or (ra == "out" and rb == "in") then
						wall, h = true, H2
					end
				end
				if wall then
					if d[1] == 1 then -- стена между клетками по X: идёт вдоль Z
						local x = (ai - MID) * C + C / 2
						addSeg("Z", x, (aj - MID) * C - C / 2, (aj - MID) * C + C / 2, h, crack)
					else
						local z = (aj - MID) * C + C / 2
						addSeg("X", z, (ai - MID) * C - C / 2, (ai - MID) * C + C / 2, h, crack)
					end
				end
			end
		end
	end
	-- крупная сетка: стены внешнего кольца
	local function isExit(I, J, di, dj)
		return ex and ex.I == I and ex.J == J and ex.di == di and ex.dj == dj
	end
	for I = -1, NC - 1 do
		for J = -1, NC - 1 do
			for _, d in ipairs({ { 1, 0 }, { 0, 1 } }) do
				local bI, bJ = I + d[1], J + d[2]
				local ra, rb = regionC(I, J), regionC(bI, bJ)
				local wall = false
				if ra == "outer" and rb == "outer" then
					wall = not open[ekey(coarseKey(I, J), coarseKey(bI, bJ))]
				elseif ra == "outer" and rb == "out" then
					wall = not isExit(I, J, d[1], d[2])
				elseif ra == "out" and rb == "outer" then
					wall = not isExit(bI, bJ, -d[1], -d[2])
				end
				if wall then
					if d[1] == 1 then
						local x = (2 * I + 1.5 - MID) * C
						addSeg("Z", x, (2 * J - MID) * C - C / 2, (2 * J + 1 - MID) * C + C / 2, H2, false)
					else
						local z = (2 * J + 1.5 - MID) * C
						addSeg("X", z, (2 * I - MID) * C - C / 2, (2 * I + 1 - MID) * C + C / 2, H2, false)
					end
				end
			end
		end
	end

	local function ivy(axis, fixedC, a, b, h)
		if rng:NextNumber() < 0.5 then
			local len = math.min(b - a, rng:NextNumber(8, 22))
			local cpos = rng:NextNumber(a + len / 2, b - len / 2)
			local hgt = rng:NextNumber(12, h * 0.7)
			local side = rng:NextNumber() < 0.5 and -1 or 1
			if axis == "X" then
				Parts.span(m, "Ivy", O, V(cpos - len / 2, h - hgt, fixedC + side * (T / 2) - 0.2), V(cpos + len / 2, h, fixedC + side * (T / 2) + 0.2), IVY, M.LeafyGrass, NOCOLLIDE)
			else
				Parts.span(m, "Ivy", O, V(fixedC + side * (T / 2) - 0.2, h - hgt, cpos - len / 2), V(fixedC + side * (T / 2) + 0.2, h, cpos + len / 2), IVY, M.LeafyGrass, NOCOLLIDE)
			end
		end
	end
	local function wallPart(name, axis, fixedC, a, b, y0, y1, th)
		if axis == "X" then
			return Parts.span(m, name, O, V(a, y0, fixedC - th / 2), V(b, y1, fixedC + th / 2), WALL, M.Slate)
		end
		return Parts.span(m, name, O, V(fixedC - th / 2, y0, a), V(fixedC + th / 2, y1, b), WALL, M.Slate)
	end
	-- стена со щелью (пролезть только пригнувшись)
	local function crackWall(axis, fixedC, from, to, h)
		local mid = (from + to) / 2
		wallPart("MazeWall", axis, fixedC, from - T / 2, mid - 3, 0, h, T)
		wallPart("MazeWall", axis, fixedC, mid + 3, to + T / 2, 0, h, T)
		wallPart("MazeWall", axis, fixedC, mid - 3, mid + 3, 9, h, T)
		wallPart("CrawlCover", axis, fixedC, mid - 3, mid + 3, 4, 9, T).CollisionGroup = "CrawlCover"
		for _, side in ipairs({ -1, 1 }) do
			for k = 0, 6 do
				local a = k / 6 * math.pi
				local along = -math.cos(a) * 3.6
				local up = math.sin(a) * 5.2
				local face = fixedC + side * (T / 2 + 0.25)
				local p = axis == "X" and V(mid + along, up, face) or V(face, up, mid + along)
				Parts.box(m, "CrackStone", CFrame.new(O + p) * CFrame.Angles(0, 0, rng:NextNumber(-0.6, 0.6)), axis == "X" and V(rng:NextNumber(0.8, 1.2), rng:NextNumber(0.6, 0.9), 0.5) or V(0.5, rng:NextNumber(0.6, 0.9), rng:NextNumber(0.8, 1.2)), WALL, M.Slate, NOCOLLIDE)
			end
			local mp = axis == "X" and V(mid, 0.1, fixedC + side * (T / 2 + 1.5)) or V(fixedC + side * (T / 2 + 1.5), 0.1, mid)
			Parts.box(m, "CrackMoss", CFrame.new(O + mp), axis == "X" and V(7, 0.2, 2.5) or V(2.5, 0.2, 7), IVY, M.LeafyGrass, NOCOLLIDE)
		end
	end
	-- склеиваем отрезки на одной линии одной высоты
	table.sort(segs, function(p, q)
		if p.axis ~= q.axis then
			return p.axis < q.axis
		elseif p.fixed ~= q.fixed then
			return p.fixed < q.fixed
		elseif p.h ~= q.h then
			return p.h < q.h
		end
		return p.a < q.a
	end)
	local run
	local function flush()
		if run then
			local th = run.h > H1 and T * 2 or T
			wallPart("MazeWall", run.axis, run.fixed, run.a - T / 2, run.b + T / 2, 0, run.h, th)
			-- карниз сверху, тёмный цоколь со мхом снизу, у высоких стен — пояс посередине
			local cap = wallPart("WallCap", run.axis, run.fixed, run.a - T / 2 - 0.6, run.b + T / 2 + 0.6, run.h - 0.2, run.h + 1.6, th + 1.2)
			cap.Color, cap.Material = WALL_DARK, M.Slate
			local foot = wallPart("WallFoot", run.axis, run.fixed, run.a - T / 2, run.b + T / 2, 0, 3.2, th + 0.8)
			foot.Color, foot.Material = RGB(58, 66, 52), M.Slate
			if run.h > H1 then
				local band = wallPart("WallBand", run.axis, run.fixed, run.a - T / 2, run.b + T / 2, run.h * 0.55, run.h * 0.55 + 2, th + 0.6)
				band.Color, band.Material = WALL_DARK, M.Slate
			end
			table.insert(refs.mapWalls, { run.axis, run.fixed, run.a - T / 2, run.b + T / 2, 0 })
			ivy(run.axis, run.fixed, run.a, run.b, run.h)
			run = nil
		end
	end
	for _, sg in ipairs(segs) do
		if sg.crack then
			flush()
			crackWall(sg.axis, sg.fixed, sg.a, sg.b, sg.h)
			table.insert(refs.mapWalls, { sg.axis, sg.fixed, sg.a - T / 2, sg.b + T / 2, 1 })
		elseif run and run.axis == sg.axis and run.fixed == sg.fixed and run.h == sg.h and math.abs(run.b - sg.a) < 0.01 then
			run.b = sg.b
		else
			flush()
			run = { axis = sg.axis, fixed = sg.fixed, a = sg.a, b = sg.b, h = sg.h }
		end
	end
	flush()

	-- тупики
	local deadEnds = {}
	for _, k in ipairs(list) do
		local n = nodes[k]
		local isEx = ex and n.zone == "outer" and n.I == ex.I and n.J == ex.J
		if dist[k] and dist[k] > 2 and #adj[k] == 1 and not isEx then
			table.insert(deadEnds, { k = k, d = dist[k], pos = O + n.pos, to = O + nodes[adj[k][1]].pos })
		end
	end
	table.sort(deadEnds, function(a, b)
		return a.d > b.d
	end)
	if deadEnds[1] and not fixed.keyTaken then
		local de = table.remove(deadEnds, 1)
		table.insert(refs.chests, chest(m, de.pos, (de.to - de.pos).Unit, true))
	end
	-- карта лабиринта лежит на столе в тупике средней глубины
	if not fixed.mapFound and #deadEnds > 4 then
		local de = table.remove(deadEnds, math.floor(#deadEnds / 2))
		local b = CFrame.lookAt(de.pos, de.pos + (de.to - de.pos).Unit)
		Parts.box(m, "MapTable", b * CFrame.new(0, 1.6, 0), V(5, 0.4, 3), RGB(100, 72, 46), M.WoodPlanks)
		for _, x in ipairs({ -2.1, 2.1 }) do
			for _, z in ipairs({ -1.1, 1.1 }) do
				Parts.box(m, "TableLeg", b * CFrame.new(x, 0.7, z), V(0.4, 1.4, 0.4), RGB(80, 58, 38), M.Wood)
			end
		end
		local sheet = Parts.box(m, "MazeMap", b * CFrame.new(0, 1.85, 0) * CFrame.Angles(0, 0.2, 0), V(2.6, 0.06, 1.8), RGB(225, 210, 170), M.SmoothPlastic, NOCOLLIDE)
		sheet.CanQuery = true
		Parts.light(sheet, 12, 0.8, RGB(255, 230, 170), false)
		tag(prompt(sheet, "Взять карту", "Карта лабиринта", 0.6, 9), "MapPrompt")
	end
	local far, near = {}, {}
	for k, de in ipairs(deadEnds) do
		table.insert(k <= #deadEnds / 2 and far or near, de)
	end
	local function takeMine(lst, kinds)
		if #lst == 0 then
			return
		end
		local de = table.remove(lst, rng:NextInteger(1, #lst))
		mine(m, de.pos, (de.to - de.pos).Unit, kinds, rng, refs.nodes)
	end
	for k = 1, MZ.Mines do
		if k % 2 == 1 then
			takeMine(near, { "stone", "stone", "iron", "iron" })
		else
			takeMine(far, { "iron", "crystal", "crystal", "stone" })
		end
	end
	local rest = {}
	for _, de in ipairs(near) do
		table.insert(rest, de)
	end
	for _, de in ipairs(far) do
		table.insert(rest, de)
	end
	for _ = 1, math.min(MZ.Chests, #rest) do
		local de = table.remove(rest, rng:NextInteger(1, #rest))
		local c = chest(m, de.pos, (de.to - de.pos).Unit, false)
		c.model:SetAttribute("Depth", de.d)
		table.insert(refs.chests, c)
	end

	-- атмосфера: светящийся мох, кости, обломки, высокая трава
	local cells = refs.cells
	for _ = 1, 110 do
		local p = cells[rng:NextInteger(1, #cells)]
		local glow = Parts.box(m, "GlowMoss", CFrame.new(p + V(rng:NextNumber(-12, 12), 0.2, rng:NextNumber(-12, 12))), V(rng:NextNumber(1, 3), 0.3, rng:NextNumber(1, 3)), RGB(90, 255, 170), M.Neon, NOCOLLIDE)
		if rng:NextNumber() < 0.3 then
			Parts.light(glow, 12, 0.5, RGB(90, 255, 170), false)
		end
	end
	for _ = 1, 50 do
		local p = cells[rng:NextInteger(1, #cells)] + V(rng:NextNumber(-10, 10), 0, rng:NextNumber(-10, 10))
		if rng:NextNumber() < 0.5 then
			Parts.box(m, "Bone", CFrame.new(p + V(0, 0.2, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), V(0.35, 0.35, 2.4), RGB(220, 215, 195), M.SmoothPlastic, NOCOLLIDE)
		else
			Parts.box(m, "Debris", CFrame.new(p + V(0, 0.8, 0)) * CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0), V(rng:NextNumber(1.5, 3), rng:NextNumber(1, 2), rng:NextNumber(1.5, 3)), WALL_DARK, M.Slate)
		end
	end
	for _ = 1, 28 do
		local p = cells[rng:NextInteger(1, #cells)] + V(rng:NextNumber(-9, 9), 0, rng:NextNumber(-9, 9))
		local base = Parts.box(m, "TallGrass", CFrame.new(p + V(0, 1.4, 0)), V(2.6, 2.8, 2.6), RGB(100, 130, 65), M.Grass, NOCOLLIDE)
		base.Transparency = 0.2
		tag(prompt(base, "Сорвать траву", "Высокая трава", 0.4, 9), "FiberPrompt")
	end
	for k = 1, 10 do
		local p = cells[rng:NextInteger(1, #cells)]
		if (p - O).Magnitude > CLEAR_HALF + 60 then
			camp(m, p, rng, k)
		end
	end
	for _ = 1, 34 do
		local p = cells[rng:NextInteger(1, #cells)] + V(rng:NextNumber(-9, 9), 0, rng:NextNumber(-9, 9))
		lootCrate(m, p, rng)
	end
	for k = 10, 16 do
		local p = cells[rng:NextInteger(1, #cells)] + V(rng:NextNumber(-8, 8), 0.1, rng:NextNumber(-8, 8))
		note(m, CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), rng, k)
	end
	for _ = 1, 30 do
		local c = cells[rng:NextInteger(1, #cells)]
		if (c - O).Magnitude > CLEAR_HALF + 40 then
			local dir = ({ V(1, 0, 0), V(-1, 0, 0), V(0, 0, 1), V(0, 0, -1) })[rng:NextInteger(1, 4)]
			vineHide(m, c + dir * 9.5, rng)
		end
	end

	m.Parent = parent
	return refs
end

------------------------------------------------------------------
-- Выход: широкий проём во всю клетку кольца → сразу пропасть с мостом →
-- металлическая лаборатория → вертолётная площадка.
-- Строится один раз за игру (лабиринт меняется, а выход — нет).
------------------------------------------------------------------
function World.BuildExit(parent, O, ex)
	local m = Instance.new("Model")
	m.Name = "Exit"
	local T = MZ.WallThickness
	local inner = O + coarsePos(ex.I, ex.J)
	local out = V(ex.di, 0, ex.dj)
	local W = C2
	local mouth = inner + out * (W / 2)
	local b = CFrame.lookAt(mouth, mouth + out) -- -Z смотрит наружу
	local refs = { model = m, exitOut = b }
	local STEEL = RGB(96, 102, 110)
	local STEEL_D = RGB(60, 64, 70)

	-- 1. короткий широкий проход: стены кольца продолжаются до самой пропасти
	local pitStart, pitEnd = 10, 44
	for _, sx in ipairs({ -1, 1 }) do
		Parts.box(m, "ExitWall", b * CFrame.new(sx * (W / 2 + T), H2 / 2, -(pitEnd + 4) / 2), V(T * 2, H2, pitEnd + 4), WALL_DARK, M.Slate)
		for d = 6, pitEnd, 12 do
			local lamp = Parts.box(m, "ExitLamp", b * CFrame.new(sx * (W / 2 - 0.6), 14, -d), V(0.8, 1.8, 1.4), RGB(255, 200, 120), M.Neon)
			Parts.light(lamp, 34, 1.3, RGB(255, 190, 120), d > 20)
			Parts.box(m, "Ivy", b * CFrame.new(sx * (W / 2 - 0.3), H2 - 16, -d - 4), V(0.4, 32, 8), IVY, M.LeafyGrass, NOCOLLIDE)
		end
	end
	Parts.box(m, "ExitFloor", b * CFrame.new(0, 0.15, -pitStart / 2), V(W, 0.3, pitStart), RGB(70, 68, 64), M.Concrete)
	refs.trigger = Parts.box(m, "ExitTrigger", b * CFrame.new(0, 6, -4), V(W, 12, 5), RGB(0, 0, 0), M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })

	-- 2. пропасть во всю ширину, вниз — темнота и красный отсвет; широкий мост
	local plen = pitEnd - pitStart
	local pmid = -(pitStart + pitEnd) / 2
	refs.pit = { cf = b * CFrame.new(0, -10, pmid), size = V(W + 8, 28, plen + 2) }
	safe(function()
		workspace.Terrain:FillBlock(refs.pit.cf, refs.pit.size, M.Air)
	end)
	for _, d in ipairs({ -pitStart, -pitEnd }) do
		Parts.box(m, "PitFace", b * CFrame.new(0, -45, d + (d == -pitStart and -0.5 or 0.5)), V(W + 8, 90, 1), RGB(40, 38, 36), M.Slate)
	end
	for _, sx in ipairs({ -1, 1 }) do
		Parts.box(m, "PitSide", b * CFrame.new(sx * (W / 2 + 0.5), -45, pmid), V(1, 90, plen), RGB(40, 38, 36), M.Slate)
	end
	Parts.box(m, "PitBottom", b * CFrame.new(0, -92, pmid), V(W + 8, 2, plen), RGB(10, 8, 8), M.Slate)
	for _, x in ipairs({ -18, 18 }) do
		local glow = Parts.box(m, "PitGlow", b * CFrame.new(x, -88, pmid), V(2, 1, 2), RGB(120, 20, 20), M.Neon, NOCOLLIDE)
		Parts.light(glow, 60, 2, RGB(255, 40, 30), true)
	end
	Parts.box(m, "Bridge", b * CFrame.new(0, 0.3, pmid), V(10, 0.6, plen + 4), RGB(84, 88, 94), M.DiamondPlate)
	for _, sx in ipairs({ -1, 1 }) do
		Parts.box(m, "BridgeRail", b * CFrame.new(sx * 5, 3.4, pmid), V(0.3, 0.3, plen + 4), STEEL_D, M.Metal, NOCOLLIDE)
		for d = pitStart, pitEnd, 6 do
			Parts.box(m, "BridgePost", b * CFrame.new(sx * 5, 1.8, -d), V(0.4, 3.4, 0.4), STEEL_D, M.Metal)
		end
	end

	-- 3. фасад лаборатории закрывает весь проход
	local face = -(pitEnd + 2)
	local FW, FH = W + 40, 60
	local doorW, doorH = 20, 18
	Parts.box(m, "LabFacade", b * CFrame.new(-(doorW / 2 + (FW - doorW) / 4), FH / 2, face), V((FW - doorW) / 2, FH, 4), STEEL, M.DiamondPlate)
	Parts.box(m, "LabFacade", b * CFrame.new(doorW / 2 + (FW - doorW) / 4, FH / 2, face), V((FW - doorW) / 2, FH, 4), STEEL, M.DiamondPlate)
	Parts.box(m, "LabFacade", b * CFrame.new(0, doorH + (FH - doorH) / 2, face), V(doorW, FH - doorH, 4), STEEL, M.DiamondPlate)
	for y = 8, FH - 4, 10 do
		Parts.box(m, "FacadeRib", b * CFrame.new(0, y, face + 2.2), V(FW, 0.8, 0.4), STEEL_D, M.Metal, NOCOLLIDE)
	end
	local door = Parts.box(m, "ExitDoor", b * CFrame.new(0, doorH / 2, face + 0.6), V(doorW, doorH, 1.6), RGB(90, 95, 100), M.DiamondPlate)
	for _, x in ipairs({ -doorW / 2 - 1, doorW / 2 + 1 }) do
		Parts.box(m, "HazardStripe", b * CFrame.new(x, doorH / 2, face + 2.2), V(1.2, doorH, 0.2), RGB(230, 180, 40), M.SmoothPlastic, NOCOLLIDE)
	end
	for _, x in ipairs({ -14, 14 }) do
		local lamp = Parts.box(m, "ExitLamp", b * CFrame.new(x, doorH + 3, face + 2.6), V(1.8, 1.8, 1.8), RGB(120, 255, 160), M.Neon)
		Parts.light(lamp, 40, 1.8, RGB(140, 255, 170), true)
	end
	local sign = Parts.box(m, "ExitSign", b * CFrame.new(0, doorH + 8, face + 2.3), V(30, 6, 0.3), RGB(20, 40, 25), M.SmoothPlastic)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.PixelsPerStud = 25
	sg.Parent = sign
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Text = "СЕКТОР 7 · ВЫХОД"
	tl.Font = Enum.Font.GothamBlack
	tl.TextScaled = true
	tl.TextColor3 = RGB(140, 255, 170)
	tl.Parent = sg
	local reader = Parts.box(m, "CardReader", b * CFrame.new(doorW / 2 + 3, 4.6, face + 2.4), V(1.6, 2.4, 0.5), RGB(30, 32, 36), M.Metal)
	refs.readerLight = Parts.box(m, "ReaderLight", reader.CFrame * CFrame.new(0, 0.8, 0.3), V(0.5, 0.3, 0.1), RGB(255, 40, 40), M.Neon, NOCOLLIDE)
	Parts.box(m, "ReaderSlot", reader.CFrame * CFrame.new(0, -0.2, 0.3), V(1, 0.12, 0.1), RGB(10, 10, 10), M.SmoothPlastic, NOCOLLIDE)
	refs.reader = reader
	refs.exitDoor = door
	refs.exitPrompt = prompt(reader, "Приложить ключ-карту", "Считыватель", 0.3, 9)
	refs.doorFront = b * CFrame.new(doorW / 2 - 1, 3, face + 7)
	refs.introPts = { (b * CFrame.new(0, 5, 2)).Position, (b * CFrame.new(0, 5, -pitStart + 1)).Position, (b * CFrame.new(0, 5.3, face + 6)).Position }
	refs.doorEye = (b * CFrame.new(0, 5.3, face + 6)).Position

	-- 4. лаборатория: металлический пол, стены из панелей, мигающий свет
	local L0, L1 = face - 2, face - 64
	local LW, LH = 48, 16
	local len = L0 - L1
	local mid = (L0 + L1) / 2
	Parts.box(m, "LabFloor", b * CFrame.new(0, 0.3, mid), V(LW, 0.6, len), RGB(110, 114, 120), M.DiamondPlate)
	for x = -LW / 2 + 6, LW / 2 - 6, 12 do
		Parts.box(m, "FloorGrate", b * CFrame.new(x, 0.62, mid), V(3, 0.05, len - 4), RGB(50, 54, 60), M.Metal, NOCOLLIDE)
	end
	Parts.box(m, "LabCeiling", b * CFrame.new(0, LH, mid), V(LW, 0.8, len), STEEL_D, M.Metal)
	for _, sx in ipairs({ -1, 1 }) do
		Parts.box(m, "LabWall", b * CFrame.new(sx * (LW / 2 + 0.5), LH / 2, mid), V(1, LH, len), RGB(150, 156, 164), M.Metal)
		for d = L0 - 4, L1 + 4, -8 do
			Parts.box(m, "WallPanel", b * CFrame.new(sx * (LW / 2 - 0.1), LH / 2, d), V(0.3, LH - 2, 0.5), STEEL_D, M.Metal, NOCOLLIDE)
		end
		Parts.box(m, "Pipe", b * CFrame.new(sx * (LW / 2 - 0.8), LH - 2, mid) * CFrame.Angles(0, math.pi / 2, 0), V(len, 1, 1), RGB(120, 90, 60), M.Metal, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	end
	local backW = 14
	Parts.box(m, "LabWall", b * CFrame.new(-(backW / 2 + (LW - backW) / 4), LH / 2, L1), V((LW - backW) / 2, LH, 1), RGB(150, 156, 164), M.Metal)
	Parts.box(m, "LabWall", b * CFrame.new(backW / 2 + (LW - backW) / 4, LH / 2, L1), V((LW - backW) / 2, LH, 1), RGB(150, 156, 164), M.Metal)
	Parts.box(m, "LabWall", b * CFrame.new(0, 12 + (LH - 12) / 2, L1), V(backW, LH - 12, 1), RGB(150, 156, 164), M.Metal)
	refs.labBackDoor = Parts.box(m, "LabBackDoor", b * CFrame.new(0, 6, L1), V(backW, 12, 0.8), RGB(90, 95, 100), M.DiamondPlate)
	for d = L0 - 6, L1 + 6, -10 do
		local lamp = Parts.box(m, "LabLamp", b * CFrame.new(0, LH - 0.6, d), V(10, 0.3, 1.2), RGB(230, 245, 255), M.Neon)
		Parts.light(lamp, 26, 1, RGB(220, 235, 255), (d // 10) % 2 == 0)
	end
	local rng = Random.new(ex.I * 31 + ex.J)
	for k = 0, 4 do
		for _, sx in ipairs({ -1, 1 }) do
			local d = L0 - 8 - k * 11
			local dcf = b * CFrame.new(sx * 17, 0.6, d) * CFrame.Angles(0, sx * math.pi / 2, 0)
			Parts.box(m, "Desk", dcf * CFrame.new(0, 2.6, 0), V(8, 0.3, 3.4), RGB(70, 72, 78), M.Metal)
			Parts.box(m, "DeskLeg", dcf * CFrame.new(0, 1.25, 0), V(7.6, 2.5, 0.3), RGB(60, 62, 66), M.Metal)
			Parts.box(m, "Monitor", dcf * CFrame.new(-1.5, 4, 1) * CFrame.Angles(0, math.pi, 0), V(2.6, 1.7, 0.2), rng:NextNumber() < 0.5 and RGB(60, 200, 120) or RGB(70, 140, 230), M.Neon, NOCOLLIDE)
			Parts.box(m, "Paper", dcf * CFrame.new(rng:NextNumber(-2, 2), 2.8, rng:NextNumber(-1, 1)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), V(1, 0.05, 1.3), RGB(240, 240, 235), M.SmoothPlastic, NOCOLLIDE)
			Parts.box(m, "Chair", dcf * CFrame.new(0, 1.2, -2.6) * CFrame.Angles(0, rng:NextNumber(-0.6, 0.6), rng:NextNumber() < 0.2 and 1.4 or 0), V(1.8, 2.4, 1.8), RGB(40, 40, 46), M.Fabric)
		end
	end
	Parts.box(m, "TankBase", b * CFrame.new(0, 1.2, mid), V(7, 1.2, 7), RGB(60, 62, 66), M.Metal, { Shape = Enum.PartType.Cylinder, Orientation = V(0, 0, 90) })
	Parts.box(m, "TankGlass", b * CFrame.new(0, 5.4, mid), V(7, 6, 6), RGB(150, 220, 200), M.Glass, { Transparency = 0.6, CanCollide = false })
	for _ = 1, 10 do
		Parts.box(m, "Shard", b * CFrame.new(rng:NextNumber(-8, 8), 0.65, mid + rng:NextNumber(-8, 8)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), V(0.8, 0.05, 0.5), RGB(170, 230, 210), M.Glass, NOCOLLIDE)
	end
	refs.labStart = b * CFrame.new(0, 5.3, face - 4)
	refs.labEnd = b * CFrame.new(0, 5.3, L1 + 4)

	-- 5. снаружи: вертолётная площадка в лесу
	local pad = b * CFrame.new(0, 0, L1 - 70)
	Parts.box(m, "Helipad", pad * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.pi / 2), V(0.4, 56, 56), RGB(80, 80, 82), M.Concrete, { Shape = Enum.PartType.Cylinder })
	Parts.box(m, "PadH", pad * CFrame.new(-6, 0.45, 0), V(2, 0.1, 16), RGB(240, 240, 240), M.SmoothPlastic, NOCOLLIDE)
	Parts.box(m, "PadH", pad * CFrame.new(6, 0.45, 0), V(2, 0.1, 16), RGB(240, 240, 240), M.SmoothPlastic, NOCOLLIDE)
	Parts.box(m, "PadH", pad * CFrame.new(0, 0.45, 0), V(10, 0.1, 2), RGB(240, 240, 240), M.SmoothPlastic, NOCOLLIDE)
	Parts.box(m, "Path", b * CFrame.new(0, 0.1, L1 - 35), V(8, 0.2, 70), RGB(120, 100, 70), M.Ground, NOCOLLIDE)
	refs.helipad = pad
	-- зона выхода: здесь нет Скрежетников, и лес не растёт
	refs.zone = { cf = b * CFrame.new(0, 0, (L1 - 100) / 2), size = V(W + 50, 300, -(L1 - 100) + 10) }
	m.Parent = parent
	return refs
end

return World
