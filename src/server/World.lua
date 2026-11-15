-- Постройка мира: лобби (3 лифта сложности, торговец классами), поляна (лес, река, лифт),
-- стены с воротами и лабиринт (шахты, сундуки, щели, выход с вертолётной площадкой).
-- Каждая группа игроков получает свой лабиринт со своим смещением O.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Parts = require(script.Parent.Parts)
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Items = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Items"))

local World = {}

local V = Vector3.new
local RGB = Color3.fromRGB
local M = Enum.Material

local MZ = Config.Maze
local N, C = MZ.Cells, MZ.CellSize
local MID = (N - 1) / 2
local HALF = N * C / 2
local CLEAR_LO, CLEAR_HI = MID - (MZ.ClearingCells - 1) / 2, MID + (MZ.ClearingCells - 1) / 2
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

local function cellPos(O, i, j)
	return O + V((i - MID) * C, 0, (j - MID) * C)
end

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
	local wb = Instance.new("Model")
	wb.Name = "Workbench"
	local top = Parts.box(wb, "Top", cf * CFrame.new(0, 3.45, 0), V(8, 0.5, 4), RGB(110, 80, 50), M.WoodPlanks)
	for _, x in ipairs({ -3.5, 3.5 }) do
		for _, z in ipairs({ -1.5, 1.5 }) do
			Parts.box(wb, "Leg", cf * CFrame.new(x, 1.6, z), V(0.6, 3.2, 0.6), WOOD, M.Wood)
		end
	end
	Parts.box(wb, "Shelf", cf * CFrame.new(0, 1, 0), V(7.4, 0.3, 3.4), WOOD, M.WoodPlanks)
	Parts.box(wb, "Vise", cf * CFrame.new(3, 4.1, -1), V(1.1, 0.9, 1), METAL, M.Metal)
	Parts.box(wb, "Saw", cf * CFrame.new(-1.7, 3.75, 0.9), V(2.5, 0.1, 0.8), RGB(170, 170, 175), M.Metal)
	Parts.box(wb, "Hammer", cf * CFrame.new(0.8, 3.8, -1.05), V(1.6, 0.25, 0.3), WOOD, M.Wood)
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
	local yellow, blue, green = RGB(245, 205, 48), RGB(13, 105, 172), RGB(40, 127, 71)
	local torso = Parts.box(m, "Torso", cf * CFrame.new(0, 3, 0), V(2, 2, 1), blue, M.SmoothPlastic)
	local head = Parts.box(m, "Head", cf * CFrame.new(0, 4.5, 0), V(2, 1, 1), yellow, M.SmoothPlastic)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = V(1.25, 1.25, 1.25)
	mesh.Parent = head
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head
	Parts.box(m, "Left Arm", cf * CFrame.new(-1.5, 3, 0), V(1, 2, 1), yellow, M.SmoothPlastic)
	Parts.box(m, "Right Arm", cf * CFrame.new(1.5, 3, 0), V(1, 2, 1), yellow, M.SmoothPlastic)
	Parts.box(m, "Left Leg", cf * CFrame.new(-0.5, 1, 0), V(1, 2, 1), green, M.SmoothPlastic)
	Parts.box(m, "Right Leg", cf * CFrame.new(0.5, 1, 0), V(1, 2, 1), green, M.SmoothPlastic)
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
		local d = Config.Difficulty[l.id]
		local col = RGB(d.Color[1], d.Color[2], d.Color[3])
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
		t.Text = d.Name
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

	-- торговец классами
	local counter = Parts.span(m, "Counter", o, V(-58, 0, 2), V(-50, 3.5, 18), RGB(90, 64, 40), M.WoodPlanks)
	Parts.span(m, "CounterTop", o, V(-58.3, 3.5, 1.7), V(-49.7, 3.9, 18.3), RGB(120, 90, 60), M.Wood)
	local _, npcTorso = classicNPC(m, CFrame.lookAt(o + V(-59.5, 0, 10), o + V(-40, 0, 10)), "Торговец классами")
	local mp = prompt(counter, "Классы", "Торговец", 0, 12)
	local msign = Parts.span(m, "ShopSign", o, V(-61.4, 9, 2), V(-61.2, 13, 18), RGB(40, 24, 16), M.Wood)
	local ms = Instance.new("SurfaceGui")
	ms.Face = Enum.NormalId.Right
	ms.PixelsPerStud = 25
	ms.Parent = msign
	local mt = Instance.new("TextLabel")
	mt.Size = UDim2.fromScale(1, 1)
	mt.BackgroundTransparency = 1
	mt.Font = Enum.Font.GothamBlack
	mt.TextScaled = true
	mt.TextColor3 = RGB(255, 210, 90)
	mt.Text = "КЛАССЫ · за монеты"
	mt.Parent = ms
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
-- Рельеф: земля лабиринта, трава поляны, река
------------------------------------------------------------------
-- озеро сверху слева (северо-запад), из него на восток течёт река
local LAKE = V(-112, 0, -112)
local LAKE_R, SAND_R = 74, 92
local RIVER = { V(-50, 0, -96), V(40, 0, -74), V(120, 0, -40), V(196, 0, -26) }

local function distToWater(p)
	local best = (V(p.X, 0, p.Z) - LAKE).Magnitude - LAKE_R
	for k = 1, #RIVER - 1 do
		local a, b = RIVER[k], RIVER[k + 1]
		local ab = b - a
		local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
		local q = a + ab * t
		best = math.min(best, (V(p.X, 0, p.Z) - V(q.X, 0, q.Z)).Magnitude)
	end
	return best
end

function World.BuildTerrain(O)
	local terrain = workspace.Terrain
	local size = HALF * 2 + 300
	terrain:FillBlock(CFrame.new(O + V(0, -8, 0)), V(size, 16, size), M.Ground)
	terrain:FillBlock(CFrame.new(O + V(0, -2, 0)), V(CLEAR_HALF * 2, 4, CLEAR_HALF * 2), M.Grass)
	-- большое озеро с песчаным пляжем
	terrain:FillCylinder(CFrame.new(O + LAKE + V(0, -2, 0)), 4, SAND_R, M.Sand)
	terrain:FillCylinder(CFrame.new(O + LAKE + V(0, -8, 0)), 16, LAKE_R, M.Water)
	-- река: сначала песчаный берег, потом вода до уровня земли
	for k = 1, #RIVER - 1 do
		local a, b = O + RIVER[k], O + RIVER[k + 1]
		local mid = (a + b) / 2
		local len = (b - a).Magnitude + 8
		local cf = CFrame.lookAt(mid, mid + (b - a))
		terrain:FillBlock(cf * CFrame.new(0, -2, 0), V(26, 4, len), M.Sand)
		terrain:FillBlock(cf * CFrame.new(0, -5, 0), V(16, 10, len), M.Water)
	end
	if not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.55
		clouds.Density = 0.6
		clouds.Parent = terrain
	end
	terrain.WaterColor = RGB(40, 90, 100)
	terrain.WaterTransparency = 0.6
	terrain.WaterWaveSize = 0.1
	terrain.WaterReflectance = 0.6
end

function World.ClearTerrain(O)
	local size = HALF * 2 + 320
	workspace.Terrain:FillBlock(CFrame.new(O + V(0, -6, 0)), V(size, 20, size), M.Air)
end

------------------------------------------------------------------
-- Поляна
------------------------------------------------------------------
function World.BuildClearing(parent, seed, O)
	local m = Instance.new("Model")
	m.Name = "Clearing"
	local rng = Random.new(seed)
	local refs = { model = m, nodes = {} }
	local E = CLEAR_HALF

	-- мост через реку на тропе к северным воротам
	local bz = -82
	Parts.span(m, "Bridge", O, V(-5, 0.3, bz - 18), V(5, 1, bz + 18), WOOD, M.WoodPlanks)
	for _, x in ipairs({ -5, 5 }) do
		Parts.span(m, "BridgeRail", O, V(x - 0.3, 1, bz - 18), V(x + 0.3, 3.8, bz + 18), RGB(70, 48, 30), M.Wood)
		for z = bz - 17, bz + 17, 5 do
			Parts.span(m, "BridgePost", O, V(x - 0.4, 0, z - 0.4), V(x + 0.4, 4.2, z + 0.4), RGB(70, 48, 30), M.Wood)
		end
	end
	-- тропинки от лифта к четырём воротам
	Parts.span(m, "Path", O, V(-3.5, 0, -E + 2), V(3.5, 0.06, E - 2), RGB(120, 100, 70), M.Ground)
	Parts.span(m, "Path", O, V(-E + 2, 0, -3.5), V(E - 2, 0.06, 3.5), RGB(120, 100, 70), M.Ground)
	-- деревянный причал на озере
	local dock = O + LAKE + V(52, 0, 40)
	Parts.box(m, "Dock", CFrame.lookAt(dock + V(0, 0.6, 0), O + LAKE + V(0, 0.6, 0)) * CFrame.new(0, 0, -8), V(6, 0.6, 26), WOOD, M.WoodPlanks)

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
	refs.liftSpawn = CFrame.lookAt(e + V(0, 3.5, 2), e + V(0, 3.5, -30))
	refs.liftPos = e

	-- ящик с припасами у лифта
	local crate = Parts.span(m, "SupplyCrate", O, V(-20, 0, -16), V(-14, 3.5, -11), RGB(120, 95, 60), M.WoodPlanks)
	refs.supplyPrompt = prompt(crate, "Взять припасы", "Начальные ресурсы", 0, 10)

	-- костёр с брёвнами вокруг
	local fc = O + V(34, 0, 34)
	local fireBase = Parts.box(m, "Campfire", CFrame.new(fc + V(0, 0.3, 0)), V(4, 0.6, 4), RGB(50, 34, 26), M.Slate)
	local fire = Instance.new("Fire")
	fire.Size = 6
	fire.Heat = 9
	fire.Parent = fireBase
	Parts.light(fireBase, 40, 1.5, RGB(255, 150, 70), true)
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		Parts.box(m, "Log", CFrame.new(fc + V(math.cos(a) * 6, 0.8, math.sin(a) * 6)) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, math.pi / 2), V(1.6, 4.5, 1.6), WOOD, M.Wood, { Shape = Enum.PartType.Cylinder })
	end

	local function freeSpot(minRiver)
		for _ = 1, 60 do
			local p = V(rng:NextNumber(-E + 10, E - 10), 0, rng:NextNumber(-E + 10, E - 10))
			local ok = distToWater(p) > (minRiver or 14)
				and math.abs(p.X) > 8
				and math.abs(p.Z) > 8
				and p.Magnitude > 30
				and (p - V(34, 0, 34)).Magnitude > 14
			if ok then
				return O + p
			end
		end
		return O + V(rng:NextNumber(-E + 10, E - 10), 0, -E + 14)
	end
	for _ = 1, 95 do
		table.insert(refs.nodes, node(m, "tree", freeSpot(18), rng))
	end
	for _ = 1, 16 do
		table.insert(refs.nodes, node(m, "stone", freeSpot(10), rng))
	end
	for _ = 1, 20 do
		local p = freeSpot(10)
		local bush = Parts.box(m, "BerryBush", CFrame.new(p + V(0, 1.8, 0)), V(5, 3.8, 5), RGB(46, 84, 40), M.LeafyGrass, { Shape = Enum.PartType.Ball })
		for _ = 1, 7 do
			Parts.box(m, "Berry", CFrame.new(p + V(rng:NextNumber(-2, 2), rng:NextNumber(1.2, 3.4), rng:NextNumber(-2, 2))), V(0.55, 0.55, 0.55), RGB(200, 30, 50), M.SmoothPlastic, {
				Shape = Enum.PartType.Ball,
				CanCollide = false,
			})
		end
		tag(prompt(bush, "Собрать ягоды", "Куст", 0.5, 10), "BerryPrompt")
	end
	-- высокая трава у реки (из неё делаются бинты и верёвки)
	for _ = 1, 26 do
		local p
		for _ = 1, 40 do
			local cand = V(rng:NextNumber(-E + 8, E - 8), 0, rng:NextNumber(-E + 8, E - 8))
			local d = distToWater(cand)
			if d > 18 and d < 30 and math.abs(cand.X) > 7 then
				p = O + cand
				break
			end
		end
		if p then
			local base = Parts.box(m, "TallGrass", CFrame.new(p + V(0, 1.4, 0)), V(2.6, 2.8, 2.6), RGB(110, 140, 70), M.Grass, NOCOLLIDE)
			base.Transparency = 0.2
			for _ = 1, 6 do
				Parts.box(m, "Blade", CFrame.new(p + V(rng:NextNumber(-1.2, 1.2), 1.8, rng:NextNumber(-1.2, 1.2))) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), 0, rng:NextNumber(-0.2, 0.2)), V(0.2, 3.6, 0.2), RGB(120, 150, 70), M.Grass, NOCOLLIDE)
			end
			tag(prompt(base, "Сорвать траву", "Высокая трава", 0.4, 9), "FiberPrompt")
		end
	end
	-- цветы
	for _ = 1, 160 do
		local p = V(rng:NextNumber(-E + 4, E - 4), 0, rng:NextNumber(-E + 4, E - 4))
		if distToWater(p) > 20 then
			local c = ({ RGB(230, 210, 80), RGB(200, 80, 120), RGB(240, 240, 240), RGB(150, 120, 230) })[rng:NextInteger(1, 4)]
			Parts.box(m, "Flower", CFrame.new(O + p + V(0, 0.4, 0)), V(0.7, 0.3, 0.7), c, M.SmoothPlastic, NOCOLLIDE)
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
local function generate(rng)
	local openE, openS, visited = {}, {}, {}
	for i = 0, N - 1 do
		openE[i], openS[i], visited[i] = {}, {}, {}
	end
	local function valid(i, j)
		return i >= 0 and j >= 0 and i < N and j < N and not inClearing(i, j)
	end
	local function link(a, b, c, d)
		if a == c then
			openS[a][math.min(b, d)] = true
		else
			openE[math.min(a, c)][b] = true
		end
	end
	local stack = { { MID, CLEAR_LO - 1 } }
	visited[MID][CLEAR_LO - 1] = true
	while #stack > 0 do
		local cur = stack[#stack]
		local i, j = cur[1], cur[2]
		local nbrs = {}
		for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local ni, nj = i + d[1], j + d[2]
			if valid(ni, nj) and not visited[ni][nj] then
				table.insert(nbrs, { ni, nj })
			end
		end
		if #nbrs == 0 then
			table.remove(stack)
		else
			local nb = nbrs[rng:NextInteger(1, #nbrs)]
			link(i, j, nb[1], nb[2])
			visited[nb[1]][nb[2]] = true
			table.insert(stack, nb)
		end
	end
	for i = 0, N - 2 do
		for j = 0, N - 1 do
			if valid(i, j) and valid(i + 1, j) and rng:NextNumber() < MZ.ExtraOpenings then
				openE[i][j] = true
			end
		end
	end
	for i = 0, N - 1 do
		for j = 0, N - 2 do
			if valid(i, j) and valid(i, j + 1) and rng:NextNumber() < MZ.ExtraOpenings then
				openS[i][j] = true
			end
		end
	end
	return openE, openS, valid
end

local function neighbors(i, j, openE, openS, valid)
	local list = {}
	if i < N - 1 and openE[i][j] and valid(i + 1, j) then
		table.insert(list, { i + 1, j })
	end
	if i > 0 and openE[i - 1][j] and valid(i - 1, j) then
		table.insert(list, { i - 1, j })
	end
	if j < N - 1 and openS[i][j] and valid(i, j + 1) then
		table.insert(list, { i, j + 1 })
	end
	if j > 0 and openS[i][j - 1] and valid(i, j - 1) then
		table.insert(list, { i, j - 1 })
	end
	return list
end

local function chest(parent, pos, facing, golden)
	local m = Instance.new("Model")
	m.Name = golden and "GoldenChest" or "Chest"
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

function World.BuildMaze(parent, seed, O)
	local rng = Random.new(seed)
	local m = Instance.new("Model")
	m.Name = "Maze"
	local openE, openS, valid = generate(rng)
	local refs = { model = m, nodes = {}, chests = {}, cells = {}, reeds = {} }
	local H, T = MZ.WallHeight, MZ.WallThickness

	for i = 0, N - 1 do
		for j = 0, N - 1 do
			if valid(i, j) then
				table.insert(refs.cells, cellPos(O, i, j))
			end
		end
	end

	-- расстояния от ворот
	local dist = {}
	for i = 0, N - 1 do
		dist[i] = {}
	end
	local queue = {}
	for _, s in ipairs({ { MID, CLEAR_LO - 1 }, { MID, CLEAR_HI + 1 }, { CLEAR_LO - 1, MID }, { CLEAR_HI + 1, MID } }) do
		dist[s[1]][s[2]] = 0
		table.insert(queue, s)
	end
	local head = 1
	while head <= #queue do
		local cur = queue[head]
		head += 1
		for _, nb in ipairs(neighbors(cur[1], cur[2], openE, openS, valid)) do
			if dist[nb[1]][nb[2]] == nil then
				dist[nb[1]][nb[2]] = dist[cur[1]][cur[2]] + 1
				table.insert(queue, nb)
			end
		end
	end

	local exitCell, exitD = nil, -1
	for i = 0, N - 1 do
		for j = 0, N - 1 do
			if (i == 0 or j == 0 or i == N - 1 or j == N - 1) and dist[i][j] and dist[i][j] > exitD then
				exitCell, exitD = { i, j }, dist[i][j]
			end
		end
	end

	-- щели: случайные внутренние стены между двумя клетками лабиринта
	local crackS, crackE = {}, {}
	for i = 0, N - 1 do
		crackS[i], crackE[i] = {}, {}
	end
	local placed, tries = 0, 0
	while placed < MZ.Cracks and tries < 2000 do
		tries += 1
		local i, j = rng:NextInteger(1, N - 3), rng:NextInteger(1, N - 3)
		if rng:NextNumber() < 0.5 then
			if valid(i, j) and valid(i, j + 1) and not openS[i][j] and not crackS[i][j] then
				crackS[i][j] = true
				placed += 1
			end
		elseif valid(i, j) and valid(i + 1, j) and not openE[i][j] and not crackE[i][j] then
			crackE[i][j] = true
			placed += 1
		end
	end

	local function ivy(axis, fixed, a, b)
		if rng:NextNumber() < 0.5 then
			local len = math.min(b - a, rng:NextNumber(8, 22))
			local cpos = rng:NextNumber(a + len / 2, b - len / 2)
			local hgt = rng:NextNumber(12, 40)
			local side = rng:NextNumber() < 0.5 and -1 or 1
			if axis == "X" then
				Parts.span(m, "Ivy", O, V(cpos - len / 2, H - hgt, fixed + side * (T / 2) - 0.2), V(cpos + len / 2, H, fixed + side * (T / 2) + 0.2), IVY, M.LeafyGrass, NOCOLLIDE)
			else
				Parts.span(m, "Ivy", O, V(fixed + side * (T / 2) - 0.2, H - hgt, cpos - len / 2), V(fixed + side * (T / 2) + 0.2, H, cpos + len / 2), IVY, M.LeafyGrass, NOCOLLIDE)
			end
		end
	end

	local function wallRun(axis, fixed, from, to)
		local a, b = from - T / 2, to + T / 2
		if axis == "X" then
			Parts.span(m, "MazeWall", O, V(a, 0, fixed - T / 2), V(b, H, fixed + T / 2), WALL, M.Slate)
		else
			Parts.span(m, "MazeWall", O, V(fixed - T / 2, 0, a), V(fixed + T / 2, H, b), WALL, M.Slate)
		end
		ivy(axis, fixed, a, b)
	end

	-- стена со щелью: узкий проём 6 шириной, снизу 4 высотой; выше 4..9 — «крышка»,
	-- сквозь которую проходит только пригнувшийся игрок (группа столкновений CrawlCover)
	local function crackWall(axis, fixed, from, to)
		local mid = (from + to) / 2
		local function seg(a, b, y0, y1, name, group)
			local p
			if axis == "X" then
				p = Parts.span(m, name, O, V(a, y0, fixed - T / 2), V(b, y1, fixed + T / 2), WALL, M.Slate)
			else
				p = Parts.span(m, name, O, V(fixed - T / 2, y0, a), V(fixed + T / 2, y1, b), WALL, M.Slate)
			end
			if group then
				p.CollisionGroup = group
			end
			return p
		end
		seg(from - T / 2, mid - 3, 0, H, "MazeWall")
		seg(mid + 3, to + T / 2, 0, H, "MazeWall")
		seg(mid - 3, mid + 3, 9, H, "MazeWall")
		seg(mid - 3, mid + 3, 4, 9, "CrawlCover", "CrawlCover")
		-- пролом: неровные камни по краю дыры с обеих сторон стены, мох и обломки на полу
		for _, side in ipairs({ -1, 1 }) do
			for k = 0, 6 do
				local a = k / 6 * math.pi
				local along = -math.cos(a) * 3.6
				local up = math.sin(a) * 5.2
				local face = fixed + side * (T / 2 + 0.25)
				local p = axis == "X" and V(mid + along, up, face) or V(face, up, mid + along)
				Parts.box(m, "CrackStone", CFrame.new(O + p) * CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), rng:NextNumber(0, 3)), V(rng:NextNumber(1.2, 2), rng:NextNumber(1, 1.6), rng:NextNumber(0.8, 1.2)), WALL_DARK, M.Slate, NOCOLLIDE)
			end
			local mp = axis == "X" and V(mid, 0.1, fixed + side * (T / 2 + 1.5)) or V(fixed + side * (T / 2 + 1.5), 0.1, mid)
			Parts.box(m, "CrackMoss", CFrame.new(O + mp), axis == "X" and V(7, 0.2, 2.5) or V(2.5, 0.2, 7), IVY, M.LeafyGrass, NOCOLLIDE)
			for _ = 1, 3 do
				local off = rng:NextNumber(-6, 6)
				local rp = axis == "X" and V(mid + off, 0.4, fixed + side * rng:NextNumber(3, 6)) or V(fixed + side * rng:NextNumber(3, 6), 0.4, mid + off)
				Parts.box(m, "Rubble", CFrame.new(O + rp) * CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0), V(1.2, 0.8, 1), WALL_DARK, M.Slate, NOCOLLIDE)
			end
		end
	end

	local function isExitWall(axis, line, k)
		if not exitCell then
			return false
		end
		local i, j = exitCell[1], exitCell[2]
		if axis == "X" then
			return k == i and ((line == -1 and j == 0) or (line == N - 1 and j == N - 1))
		else
			return k == j and ((line == -1 and i == 0) or (line == N - 1 and i == N - 1))
		end
	end

	for line = -1, N - 1 do
		local z = (line - MID) * C + C / 2
		local runStart
		for i = 0, N do
			local present, crack = false, false
			if i < N then
				if line == -1 or line == N - 1 then
					present = not isExitWall("X", line, i)
				else
					local cA, cB = inClearing(i, line), inClearing(i, line + 1)
					present = not cA and not cB and not openS[i][line]
					crack = present and crackS[i][line] == true
					present = present and not crack
				end
			end
			if present and not runStart then
				runStart = i
			elseif not present and runStart then
				wallRun("X", z, (runStart - MID) * C - C / 2, (i - 1 - MID) * C + C / 2)
				runStart = nil
			end
			if crack then
				crackWall("X", z, (i - MID) * C - C / 2, (i - MID) * C + C / 2)
			end
		end
	end
	for line = -1, N - 1 do
		local x = (line - MID) * C + C / 2
		local runStart
		for j = 0, N do
			local present, crack = false, false
			if j < N then
				if line == -1 or line == N - 1 then
					present = not isExitWall("Z", line, j)
				else
					local cA, cB = inClearing(line, j), inClearing(line + 1, j)
					present = not cA and not cB and not openE[line][j]
					crack = present and crackE[line][j] == true
					present = present and not crack
				end
			end
			if present and not runStart then
				runStart = j
			elseif not present and runStart then
				wallRun("Z", x, (runStart - MID) * C - C / 2, (j - 1 - MID) * C + C / 2)
				runStart = nil
			end
			if crack then
				crackWall("Z", x, (j - MID) * C - C / 2, (j - MID) * C + C / 2)
			end
		end
	end

	-- тупики
	local deadEnds = {}
	for i = 0, N - 1 do
		for j = 0, N - 1 do
			if valid(i, j) and dist[i][j] and dist[i][j] > 2 and not (exitCell and exitCell[1] == i and exitCell[2] == j) then
				local nb = neighbors(i, j, openE, openS, valid)
				if #nb == 1 then
					table.insert(deadEnds, { i = i, j = j, d = dist[i][j], to = cellPos(O, nb[1][1], nb[1][2]) })
				end
			end
		end
	end
	table.sort(deadEnds, function(a, b)
		return a.d > b.d
	end)
	if deadEnds[1] then
		local de = table.remove(deadEnds, 1)
		local pos = cellPos(O, de.i, de.j)
		table.insert(refs.chests, chest(m, pos, (de.to - pos).Unit, true))
	end
	local far, near = {}, {}
	for k, de in ipairs(deadEnds) do
		table.insert(k <= #deadEnds / 2 and far or near, de)
	end
	local function takeMine(list, kinds)
		if #list == 0 then
			return
		end
		local de = table.remove(list, rng:NextInteger(1, #list))
		local pos = cellPos(O, de.i, de.j)
		mine(m, pos, (de.to - pos).Unit, kinds, rng, refs.nodes)
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
		local pos = cellPos(O, de.i, de.j)
		local c = chest(m, pos, (de.to - pos).Unit, false)
		c.model:SetAttribute("Depth", de.d)
		table.insert(refs.chests, c)
	end

	-- атмосфера: светящийся мох, кости, обломки, высокая трава в коридорах
	for _ = 1, 90 do
		local p = refs.cells[rng:NextInteger(1, #refs.cells)]
		local glow = Parts.box(m, "GlowMoss", CFrame.new(p + V(rng:NextNumber(-12, 12), 0.2, rng:NextNumber(-12, 12))), V(rng:NextNumber(1, 3), 0.3, rng:NextNumber(1, 3)), RGB(90, 255, 170), M.Neon, NOCOLLIDE)
		if rng:NextNumber() < 0.3 then
			Parts.light(glow, 12, 0.5, RGB(90, 255, 170), false)
		end
	end
	for _ = 1, 40 do
		local p = refs.cells[rng:NextInteger(1, #refs.cells)] + V(rng:NextNumber(-10, 10), 0, rng:NextNumber(-10, 10))
		if rng:NextNumber() < 0.5 then
			Parts.box(m, "Bone", CFrame.new(p + V(0, 0.2, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), V(0.35, 0.35, 2.4), RGB(220, 215, 195), M.SmoothPlastic, NOCOLLIDE)
		else
			Parts.box(m, "Debris", CFrame.new(p + V(0, 0.8, 0)) * CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0), V(rng:NextNumber(1.5, 3), rng:NextNumber(1, 2), rng:NextNumber(1.5, 3)), WALL_DARK, M.Slate)
		end
	end
	for _ = 1, 24 do
		local p = refs.cells[rng:NextInteger(1, #refs.cells)] + V(rng:NextNumber(-9, 9), 0, rng:NextNumber(-9, 9))
		local base = Parts.box(m, "TallGrass", CFrame.new(p + V(0, 1.4, 0)), V(2.6, 2.8, 2.6), RGB(100, 130, 65), M.Grass, NOCOLLIDE)
		base.Transparency = 0.2
		tag(prompt(base, "Сорвать траву", "Высокая трава", 0.4, 9), "FiberPrompt")
	end

	-- выход и вертолётная площадка за ним
	if exitCell then
		local i, j = exitCell[1], exitCell[2]
		local inner = cellPos(O, i, j)
		local out
		if i == 0 then
			out = V(-1, 0, 0)
		elseif i == N - 1 then
			out = V(1, 0, 0)
		elseif j == 0 then
			out = V(0, 0, -1)
		else
			out = V(0, 0, 1)
		end
		local mouth = inner + out * (C / 2)
		local b = CFrame.lookAt(mouth, mouth + out)
		for _, x in ipairs({ -C / 2, C / 2 }) do
			Parts.box(m, "ExitWall", b * CFrame.new(x, H / 2, -25), V(T, H, 50), WALL_DARK, M.Slate)
		end
		Parts.box(m, "ExitFloor", b * CFrame.new(0, 0.2, -25), V(C, 0.4, 50), RGB(60, 60, 64), M.Concrete)
		local door = Parts.box(m, "ExitDoor", b * CFrame.new(0, H / 2 - 4, -50), V(C, H - 8, 2), RGB(90, 95, 100), M.DiamondPlate)
		for _, x in ipairs({ -10, 10 }) do
			local lamp = Parts.box(m, "ExitLamp", b * CFrame.new(x, H - 10, -48), V(1.8, 1.8, 1.8), RGB(120, 255, 160), M.Neon)
			Parts.light(lamp, 40, 1.8, RGB(140, 255, 170), true)
		end
		local sign = Parts.box(m, "ExitSign", b * CFrame.new(0, H - 4, -48.8), V(18, 4, 0.3), RGB(20, 40, 25), M.SmoothPlastic)
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Back
		sg.PixelsPerStud = 25
		sg.Parent = sign
		local tl = Instance.new("TextLabel")
		tl.Size = UDim2.fromScale(1, 1)
		tl.BackgroundTransparency = 1
		tl.Text = "ВЫХОД"
		tl.Font = Enum.Font.GothamBlack
		tl.TextScaled = true
		tl.TextColor3 = RGB(140, 255, 170)
		tl.Parent = sg
		-- считыватель ключ-карты на стене у ворот (на уровне груди)
		local reader = Parts.box(m, "CardReader", b * CFrame.new(C / 2 - T / 2 - 0.4, 4.8, -46) * CFrame.Angles(0, -math.pi / 2, 0), V(1.6, 2.4, 0.5), RGB(30, 32, 36), M.Metal)
		local readerLight = Parts.box(m, "ReaderLight", reader.CFrame * CFrame.new(0, 0.8, -0.3), V(0.5, 0.3, 0.1), RGB(255, 40, 40), M.Neon, NOCOLLIDE)
		Parts.box(m, "ReaderSlot", reader.CFrame * CFrame.new(0, -0.2, -0.3), V(1, 0.12, 0.1), RGB(10, 10, 10), M.SmoothPlastic, NOCOLLIDE)
		refs.readerLight = readerLight

		-- снаружи: лесная поляна, где ждёт вертолёт
		local pad = b * CFrame.new(0, 0, -95)
		local padGround = Parts.box(m, "ForestClearing", pad * CFrame.new(0, 0.05, 0), V(60, 0.1, 60), RGB(70, 105, 55), M.Grass, NOCOLLIDE)
		local _ = padGround
		local frng = Random.new(seed + 99)
		for _ = 1, 70 do
			local a = frng:NextNumber(0, math.pi * 2)
			local r = frng:NextNumber(34, 120)
			local local2 = V(math.cos(a) * r, 0, math.sin(a) * r)
			-- не ставим деревья на дорогу от ворот к поляне
			local rel = pad * CFrame.new(local2)
			local toMouth = (b:PointToObjectSpace(rel.Position))
			if not (math.abs(toMouth.X) < 14 and toMouth.Z > -100 and toMouth.Z < 0) then
				local h = frng:NextNumber(26, 40)
				local tp = rel.Position
				Parts.box(m, "ForestTrunk", CFrame.new(tp + V(0, h / 2, 0)), V(2.4, h, 2.4), RGB(80, 58, 40), M.Wood)
				for k = 1, 4 do
					local sz = frng:NextNumber(10, 15) * (1 - k * 0.12)
					Parts.box(m, "ForestLeaves", CFrame.new(tp + V(frng:NextNumber(-2, 2), h * 0.6 + k * 3, frng:NextNumber(-2, 2))), V(sz, sz * 0.8, sz), RGB(40, frng:NextInteger(85, 110), 45), M.LeafyGrass, {
						Shape = Enum.PartType.Ball,
						CanCollide = false,
					})
				end
			end
		end
		refs.exitDoor = door
		refs.exitPrompt = prompt(reader, "Вставить ключ-карту", "Считыватель", 1.2, 9)
		refs.exitOut = b
		refs.helipad = pad
	end

	m.Parent = parent
	return refs
end

return World
