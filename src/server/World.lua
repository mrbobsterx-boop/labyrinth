-- Постройка мира: лобби с лифтом, поляна (лес, река, верстак), стены с воротами
-- и лабиринт, который генерируется заново каждую игру (шахты, сундуки, выход).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Parts = require(script.Parent.Parts)
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Items = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Items"))

local World = {}

local V = Vector3.new
local RGB = Color3.fromRGB
local M = Enum.Material
local O = Vector3.zero

local MZ = Config.Maze
local N, C = MZ.Cells, MZ.CellSize
local MID = (N - 1) / 2
local HALF = N * C / 2
local CLEAR_LO, CLEAR_HI = MID - (MZ.ClearingCells - 1) / 2, MID + (MZ.ClearingCells - 1) / 2
local CLEAR_HALF = MZ.ClearingCells * C / 2

World.LOBBY = V(2000, 50, 0)
World.CLEARING_HALF = CLEAR_HALF

local WALL = RGB(78, 82, 80)
local WALL_DARK = RGB(58, 62, 60)
local IVY = RGB(52, 82, 44)
local WOOD = RGB(92, 64, 40)
local METAL = RGB(70, 72, 76)
local NOCOLLIDE = { CanCollide = false }

local function cellPos(i, j)
	return V((i - MID) * C, 0, (j - MID) * C)
end

local function inClearing(i, j)
	return i >= CLEAR_LO and i <= CLEAR_HI and j >= CLEAR_LO and j <= CLEAR_HI
end

local function tag(inst, name)
	CollectionService:AddTag(inst, name)
end

------------------------------------------------------------------
-- Ресурсные узлы (деревья, камни, руда)
------------------------------------------------------------------
local function node(parent, kind, pos, rng)
	local def = Items.Nodes[kind]
	local m = Instance.new("Model")
	m.Name = def.Name
	m:SetAttribute("Node", kind)
	m:SetAttribute("HP", def.Health)
	if kind == "tree" then
		local h = rng:NextNumber(16, 24)
		Parts.box(m, "Trunk", CFrame.new(pos + V(0, h / 2, 0)), V(1.8, h, 1.8), RGB(84, 60, 40), M.Wood)
		local leaf = RGB(rng:NextInteger(40, 60), rng:NextInteger(90, 115), rng:NextInteger(40, 55))
		for k = 1, 4 do
			local s = rng:NextNumber(7, 11) * (1 - k * 0.12)
			Parts.box(m, "Leaves", CFrame.new(pos + V(rng:NextNumber(-1.5, 1.5), h * 0.6 + k * 2.4, rng:NextNumber(-1.5, 1.5))), V(s, s * 0.8, s), leaf, M.LeafyGrass, {
				Shape = Enum.PartType.Ball,
				CanCollide = false,
			})
		end
	else
		local rock = RGB(96, 96, 100)
		for _ = 1, 3 do
			local s = rng:NextNumber(2.4, 4.2)
			local cf = CFrame.new(pos + V(rng:NextNumber(-1.6, 1.6), s * 0.4, rng:NextNumber(-1.6, 1.6)))
				* CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), rng:NextNumber(0, 3))
			Parts.box(m, "Rock", cf, V(s, s * 0.8, s), rock, M.Slate)
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
	m.Parent = parent
	tag(m, "Node")
	return m
end
World.node = node

------------------------------------------------------------------
-- Лобби с лифтом
------------------------------------------------------------------
function World.BuildLobby()
	local m = Instance.new("Model")
	m.Name = "Lobby"
	local o = World.LOBBY
	local concrete = RGB(70, 72, 74)
	Parts.span(m, "Floor", o, V(-40, -1, -20), V(40, 0, 20), RGB(54, 56, 58), M.Concrete)
	Parts.span(m, "Ceiling", o, V(-40, 16, -20), V(40, 17, 20), concrete, M.Concrete)
	Parts.wall(m, o, "X", -20, -40, 40, 0, 16, nil, concrete, M.Concrete, 1)
	Parts.wall(m, o, "X", 20, -40, 40, 0, 16, nil, concrete, M.Concrete, 1)
	Parts.wall(m, o, "Z", -40, -20, 20, 0, 16, nil, concrete, M.Concrete, 1)
	-- справа шахта лифта с открытым проёмом
	Parts.wall(m, o, "Z", 24, -20, 20, 0, 16, { { c = 0, w = 14, b = 0, h = 12 } }, METAL, M.DiamondPlate, 1)
	Parts.span(m, "ElevatorFloor", o, V(24, -1, -8), V(40, 0, 8), RGB(40, 40, 42), M.DiamondPlate)
	Parts.wall(m, o, "X", -8, 24, 40, 0, 16, nil, METAL, M.DiamondPlate, 0.6)
	Parts.wall(m, o, "X", 8, 24, 40, 0, 16, nil, METAL, M.DiamondPlate, 0.6)
	Parts.wall(m, o, "Z", 40, -8, 8, 0, 16, nil, METAL, M.DiamondPlate, 0.6)
	local stripe = Parts.span(m, "ElevatorLight", o, V(26, 15.2, -6), V(38, 15.5, 6), RGB(255, 230, 190), M.Neon)
	Parts.light(stripe, 24, 1.2, RGB(255, 220, 180), false)
	local zone = Parts.span(m, "ElevatorZone", o, V(25, 0, -7.5), V(39.5, 10, 7.5), nil, nil, { Transparency = 1, CanCollide = false, CanQuery = false })
	-- жёлто-чёрная разметка у входа
	for k = -3, 3 do
		Parts.span(m, "Hazard", o, V(22, 0, k * 2 - 0.5), V(24, 0.05, k * 2 + 0.5), (k % 2 == 0) and RGB(220, 180, 30) or RGB(20, 20, 20), M.SmoothPlastic)
	end
	-- лампы
	for x = -30, 15, 15 do
		local lamp = Parts.span(m, "Lamp", o, V(x - 2, 15.4, -1), V(x + 2, 15.9, 1), RGB(255, 235, 200), M.Neon)
		Parts.light(lamp, 26, 0.8, RGB(255, 225, 190), x == 0)
	end
	-- табличка с правилами
	local board = Parts.span(m, "Rules", o, V(-39.4, 4, -8), V(-39.2, 12, 8), RGB(30, 30, 34), M.SmoothPlastic)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Right
	sg.PixelsPerStud = 30
	sg.Parent = board
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.TextColor3 = RGB(230, 225, 210)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextWrapped = true
	t.Text = "ПРАВИЛА ПОЛЯНЫ\n\n1. Днём врата открыты. Исследуй лабиринт.\n2. На закате врата закрываются. Вернись до заката.\n3. Ночью в лабиринте — Скрежетники.\n4. Добывай, строй, выживай.\n5. Найди Ключ и выход."
	t.Parent = sg
	-- скамейки
	for x = -30, 0, 15 do
		Parts.span(m, "Bench", o, V(x - 4, 1.5, -18), V(x + 4, 2, -15.5), WOOD, M.WoodPlanks)
		Parts.span(m, "BenchLeg", o, V(x - 3.5, 0, -17.5), V(x - 3, 1.5, -16), METAL, M.Metal)
		Parts.span(m, "BenchLeg", o, V(x + 3, 0, -17.5), V(x + 3.5, 1.5, -16), METAL, M.Metal)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = V(10, 1, 10)
	spawn.CFrame = CFrame.new(o + V(-25, -0.4, 0)) * CFrame.Angles(0, -math.pi / 2, 0)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = m
	m.Parent = workspace
	return { model = m, zone = zone, spawn = spawn }
end

------------------------------------------------------------------
-- Поляна (безопасная зона): трава, река, мост, лес, кусты, камни,
-- лифт, верстак, костёр и стены с четырьмя воротами
------------------------------------------------------------------
local RIVER = { V(-64, 0, -22), V(-24, 0, -12), V(18, 0, 4), V(64, 0, 12) }

local function distToRiver(p)
	local best = math.huge
	for k = 1, #RIVER - 1 do
		local a, b = RIVER[k], RIVER[k + 1]
		local ab = b - a
		local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
		local q = a + ab * t
		best = math.min(best, (V(p.X, 0, p.Z) - V(q.X, 0, q.Z)).Magnitude)
	end
	return best
end

function World.BuildTerrain()
	local terrain = workspace.Terrain
	terrain:Clear()
	local size = HALF * 2 + 200
	terrain:FillBlock(CFrame.new(0, -8, 0), V(size, 16, size), M.Ground)
	terrain:FillBlock(CFrame.new(0, -1, 0), V(CLEAR_HALF * 2, 2, CLEAR_HALF * 2), M.Grass)
	-- река
	for k = 1, #RIVER - 1 do
		local a, b = RIVER[k], RIVER[k + 1]
		local mid = (a + b) / 2
		local len = (b - a).Magnitude + 6
		local cf = CFrame.lookAt(mid, mid + (b - a))
		terrain:FillBlock(cf * CFrame.new(0, -3.5, 0), V(12, 6, len), M.Water)
		terrain:FillBlock(cf * CFrame.new(0, 1.5, 0), V(12, 3, len), M.Air)
		terrain:FillBlock(cf * CFrame.new(0, -1, 0), V(16, 2, len), M.Sand)
		terrain:FillBlock(cf * CFrame.new(0, -3, 0), V(10, 5, len), M.Water)
	end
	if not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.55
		clouds.Density = 0.6
		clouds.Parent = terrain
	end
	terrain.WaterColor = RGB(40, 90, 100)
	terrain.WaterTransparency = 0.6
	terrain.WaterWaveSize = 0.08
	terrain.WaterReflectance = 0.6
end

function World.BuildClearing(parent, seed)
	local m = Instance.new("Model")
	m.Name = "Clearing"
	local rng = Random.new(seed)
	local refs = { model = m, nodes = {} }

	-- мост через реку
	local bridgeZ = -2
	Parts.span(m, "Bridge", O, V(-4, 0.4, bridgeZ - 9), V(4, 1, bridgeZ + 9), WOOD, M.WoodPlanks)
	for _, x in ipairs({ -4, 4 }) do
		Parts.span(m, "BridgeRail", O, V(x - 0.3, 1, bridgeZ - 9), V(x + 0.3, 3.5, bridgeZ + 9), RGB(70, 48, 30), M.Wood)
	end
	-- тропинки к воротам
	for _, seg in ipairs({ { V(-3, 0, -58), V(3, 0.06, 58) }, { V(-58, 0, 22), V(58, 0.06, 26) } }) do
		Parts.span(m, "Path", O, seg[1], seg[2], RGB(120, 100, 70), M.Ground)
	end

	-- лифт на поляне
	local e = V(0, 0, 42)
	Parts.span(m, "LiftFloor", e, V(-8, 0, -8), V(8, 0.6, 8), RGB(40, 40, 42), M.DiamondPlate)
	Parts.span(m, "LiftRoof", e, V(-8.5, 14, -8.5), V(8.5, 15, 8.5), METAL, M.DiamondPlate)
	for _, x in ipairs({ -8, 8 }) do
		Parts.span(m, "LiftWall", e, V(x - 0.3, 0.6, -8), V(x + 0.3, 14, 8), METAL, M.DiamondPlate)
	end
	Parts.span(m, "LiftWall", e, V(-8, 0.6, 7.7), V(8, 14, 8.3), METAL, M.DiamondPlate)
	local liftLight = Parts.span(m, "LiftLight", e, V(-5, 13.6, -5), V(5, 13.9, 5), RGB(255, 230, 190), M.Neon)
	Parts.light(liftLight, 20, 1, nil, false)
	local grate = Instance.new("Model")
	grate.Name = "LiftGrate"
	for x = -7, 7, 1.4 do
		Parts.box(grate, "Bar", CFrame.new(e + V(x, 7.3, -8)), V(0.25, 13.4, 0.25), RGB(50, 50, 54), M.Metal)
	end
	for y = 2, 13, 3.6 do
		Parts.box(grate, "Bar", CFrame.new(e + V(0, y, -8)), V(15.4, 0.25, 0.25), RGB(50, 50, 54), M.Metal)
	end
	grate.Parent = m
	refs.grate = grate
	refs.grateClosed = grate:GetPivot()
	refs.liftSpawn = CFrame.lookAt(e + V(0, 3.5, 2), e + V(0, 3.5, -20))

	-- верстак
	local wb = Instance.new("Model")
	wb.Name = "Workbench"
	local wp = V(16, 0, 30)
	local top = Parts.span(wb, "Top", wp, V(-4, 3.2, -2), V(4, 3.7, 2), RGB(110, 80, 50), M.WoodPlanks)
	for _, x in ipairs({ -3.5, 3.5 }) do
		for _, z in ipairs({ -1.5, 1.5 }) do
			Parts.span(wb, "Leg", wp, V(x - 0.3, 0, z - 0.3), V(x + 0.3, 3.2, z + 0.3), WOOD, M.Wood)
		end
	end
	Parts.span(wb, "Vise", wp, V(2.5, 3.7, -1), V(3.6, 4.6, 0), METAL, M.Metal)
	Parts.span(wb, "Saw", wp, V(-3, 3.7, 0.5), V(-0.5, 3.8, 1.3), RGB(170, 170, 175), M.Metal)
	Parts.span(wb, "Hammer", wp, V(0, 3.7, -1.2), V(1.6, 3.95, -0.9), WOOD, M.Wood)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Крафт"
	prompt.ObjectText = "Верстак"
	prompt.MaxActivationDistance = 10
	prompt.Parent = top
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 200, 0, 40)
	bb.StudsOffset = V(0, 3, 0)
	bb.AlwaysOnTop = false
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
	wb.Parent = m
	refs.workbenchPrompt = prompt
	refs.workbenchLabel = bl

	-- ящик с припасами
	local crate = Parts.span(m, "SupplyCrate", O, V(-15, 0, 29), V(-10, 3, 33), RGB(120, 95, 60), M.WoodPlanks)
	local cp = Instance.new("ProximityPrompt")
	cp.ActionText = "Взять припасы"
	cp.ObjectText = "Начальные ресурсы"
	cp.MaxActivationDistance = 9
	cp.Parent = crate
	refs.supplyPrompt = cp

	-- костёр
	local fireBase = Parts.span(m, "Campfire", O, V(-16, 0, 12), V(-12, 0.6, 16), RGB(60, 40, 30), M.Wood)
	local fire = Instance.new("Fire")
	fire.Size = 5
	fire.Heat = 8
	fire.Parent = fireBase
	Parts.light(fireBase, 34, 1.4, RGB(255, 150, 70), true)
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		Parts.box(m, "Log", CFrame.new(V(-14, 0.9, 14) + V(math.cos(a) * 5, 0, math.sin(a) * 5)) * CFrame.Angles(0, -a, 0), V(1.4, 1.4, 4), WOOD, M.Wood)
	end

	-- деревья, кусты с ягодами, камни
	local function freeSpot(minRiver)
		for _ = 1, 50 do
			local p = V(rng:NextNumber(-52, 52), 0, rng:NextNumber(-52, 52))
			local ok = distToRiver(p) > (minRiver or 10)
				and math.abs(p.X) > 6
				and (p - V(0, 0, 42)).Magnitude > 16
				and (p - V(16, 0, 30)).Magnitude > 10
				and (p - V(-14, 0, 14)).Magnitude > 10
				and not (math.abs(p.Z - 24) < 5)
			if ok then
				return p
			end
		end
		return V(rng:NextNumber(-50, 50), 0, -45)
	end
	for _ = 1, 22 do
		table.insert(refs.nodes, node(m, "tree", freeSpot(12), rng))
	end
	for _ = 1, 6 do
		table.insert(refs.nodes, node(m, "stone", freeSpot(8), rng))
	end
	for _ = 1, 7 do
		local p = freeSpot(8)
		local bush = Parts.box(m, "BerryBush", CFrame.new(p + V(0, 1.6, 0)), V(4.4, 3.4, 4.4), RGB(46, 84, 40), M.LeafyGrass, { Shape = Enum.PartType.Ball })
		for _ = 1, 6 do
			Parts.box(m, "Berry", CFrame.new(p + V(rng:NextNumber(-1.8, 1.8), rng:NextNumber(1.2, 3), rng:NextNumber(-1.8, 1.8))), V(0.5, 0.5, 0.5), RGB(200, 30, 50), M.SmoothPlastic, {
				Shape = Enum.PartType.Ball,
				CanCollide = false,
			})
		end
		local bp = Instance.new("ProximityPrompt")
		bp.ActionText = "Собрать ягоды"
		bp.ObjectText = "Куст"
		bp.HoldDuration = 0.6
		bp.MaxActivationDistance = 9
		bp.Parent = bush
		tag(bp, "BerryPrompt")
	end
	-- камыши и цветы у реки
	for _ = 1, 40 do
		local p = V(rng:NextNumber(-55, 55), 0, rng:NextNumber(-55, 55))
		local d = distToRiver(p)
		if d > 6 and d < 11 then
			Parts.box(m, "Reed", CFrame.new(p + V(0, 1.2, 0)), V(0.2, 2.4, 0.2), RGB(90, 120, 60), M.Grass, NOCOLLIDE)
		elseif d > 14 and rng:NextNumber() < 0.5 then
			local c = ({ RGB(230, 210, 80), RGB(200, 80, 120), RGB(240, 240, 240) })[rng:NextInteger(1, 3)]
			Parts.box(m, "Flower", CFrame.new(p + V(0, 0.4, 0)), V(0.6, 0.3, 0.6), c, M.SmoothPlastic, NOCOLLIDE)
		end
	end

	m.Parent = parent
	return refs
end

------------------------------------------------------------------
-- Стены поляны с воротами (закрываются ночью)
------------------------------------------------------------------
local GATE_W = 20

function World.BuildClearingWalls(parent)
	local m = Instance.new("Model")
	m.Name = "ClearingWalls"
	local h = MZ.WallHeight + 8
	local t = 6
	local gates = {}
	local E = CLEAR_HALF
	local op = { { c = 0, w = GATE_W, b = 0, h = h - 6 } }
	Parts.wall(m, O, "X", -E, -E - t / 2, E + t / 2, 0, h, op, WALL_DARK, M.Slate, t)
	Parts.wall(m, O, "X", E, -E - t / 2, E + t / 2, 0, h, op, WALL_DARK, M.Slate, t)
	Parts.wall(m, O, "Z", -E, -E, E, 0, h, op, WALL_DARK, M.Slate, t)
	Parts.wall(m, O, "Z", E, -E, E, 0, h, op, WALL_DARK, M.Slate, t)

	-- ворота: две створки въезжают в стену
	for _, g in ipairs({
		{ name = "Север", pos = V(0, 0, -E), axis = "X" },
		{ name = "Юг", pos = V(0, 0, E), axis = "X" },
		{ name = "Запад", pos = V(-E, 0, 0), axis = "Z" },
		{ name = "Восток", pos = V(E, 0, 0), axis = "Z" },
	}) do
		local along = g.axis == "X" and V(1, 0, 0) or V(0, 0, 1)
		local leaves = {}
		for _, side in ipairs({ -1, 1 }) do
			local size = g.axis == "X" and V(GATE_W / 2, h - 6, 4) or V(4, h - 6, GATE_W / 2)
			local closed = CFrame.new(g.pos + along * side * (GATE_W / 4) + V(0, (h - 6) / 2, 0))
			local leaf = Parts.box(m, "GateLeaf", closed, size, RGB(64, 60, 56), M.Slate)
			-- металлические полосы на створке
			for y = -12, 12, 8 do
				Parts.box(leaf, "Band", closed * CFrame.new(0, y, 0), g.axis == "X" and V(GATE_W / 2, 0.8, 4.3) or V(4.3, 0.8, GATE_W / 2), METAL, M.Metal, NOCOLLIDE)
			end
			table.insert(leaves, { part = leaf, closed = closed, open = closed + along * side * (GATE_W / 2 + 0.5) })
		end
		-- факелы у ворот
		for _, side in ipairs({ -1, 1 }) do
			local inward = -g.pos.Unit
			local tp = g.pos + along * side * (GATE_W / 2 + 3) + inward * 3.5 + V(0, 10, 0)
			local torch = Parts.box(m, "GateTorch", CFrame.new(tp), V(0.8, 1.2, 0.8), RGB(255, 140, 50), M.Neon)
			Parts.light(torch, 28, 1.3, RGB(255, 150, 70), true)
			local f = Instance.new("Fire")
			f.Size = 2.5
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
	-- поиск в глубину
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
	-- дополнительные проходы
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
		Parts.light(body, 16, 1.2, RGB(255, 200, 90), true)
	end
	local p = Instance.new("ProximityPrompt")
	p.ActionText = "Открыть"
	p.ObjectText = golden and "Золотой сундук" or "Сундук"
	p.HoldDuration = 0.8
	p.MaxActivationDistance = 9
	p.Parent = body
	m:SetAttribute("Golden", golden == true)
	m.Parent = parent
	tag(m, "Chest")
	return { model = m, lid = lid, prompt = p, base = b }
end

local function mine(parent, center, facing, kinds, rng, nodes)
	-- рудная пещерка в тупике: деревянные крепи, фонарь, руда
	local b = CFrame.lookAt(center, center + facing)
	local beam = RGB(80, 58, 36)
	for _, x in ipairs({ -8, 8 }) do
		Parts.box(parent, "MineSupport", b * CFrame.new(x, 6, -8), V(1.2, 12, 1.2), beam, M.Wood)
	end
	Parts.box(parent, "MineBeam", b * CFrame.new(0, 12.4, -8), V(17.5, 1.2, 1.2), beam, M.Wood)
	local lantern = Parts.box(parent, "MineLantern", b * CFrame.new(0, 11, -8), V(0.8, 1.2, 0.8), RGB(255, 170, 80), M.Neon)
	Parts.light(lantern, 26, 1.3, RGB(255, 170, 90), true)
	Parts.box(parent, "MineCart", b * CFrame.new(6, 1.2, 4), V(3, 2, 4.5), RGB(80, 70, 60), M.CorrodedMetal)
	for k, kind in ipairs(kinds) do
		local off = ({ V(-5, 0, 2), V(4, 0, -2), V(-2, 0, 6), V(5, 0, 7) })[k]
		table.insert(nodes, node(parent, kind, (b * CFrame.new(off)).Position, rng))
	end
end

function World.BuildMaze(parent, seed)
	local rng = Random.new(seed)
	local m = Instance.new("Model")
	m.Name = "Maze"
	local openE, openS, valid = generate(rng)
	local refs = { model = m, nodes = {}, chests = {}, cells = {} }
	local H, T = MZ.WallHeight, MZ.WallThickness

	-- сохраняем список клеток для монстров
	for i = 0, N - 1 do
		for j = 0, N - 1 do
			if valid(i, j) then
				table.insert(refs.cells, cellPos(i, j))
			end
		end
	end

	-- расстояния от ворот (поиск в ширину)
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

	-- выход: самая дальняя клетка на внешнем краю
	local exitCell, exitD = nil, -1
	for i = 0, N - 1 do
		for j = 0, N - 1 do
			if (i == 0 or j == 0 or i == N - 1 or j == N - 1) and dist[i][j] and dist[i][j] > exitD then
				exitCell, exitD = { i, j }, dist[i][j]
			end
		end
	end

	-- стены: объединяем соседние куски в один длинный
	local function wallRun(axis, fixed, from, to)
		local a, b = from - T / 2, to + T / 2
		local p
		if axis == "X" then
			p = Parts.span(m, "MazeWall", O, V(a, 0, fixed - T / 2), V(b, H, fixed + T / 2), WALL, M.Slate)
		else
			p = Parts.span(m, "MazeWall", O, V(fixed - T / 2, 0, a), V(fixed + T / 2, H, b), WALL, M.Slate)
		end
		-- плющ
		if rng:NextNumber() < 0.45 then
			local len = math.min(b - a, rng:NextNumber(6, 16))
			local cpos = rng:NextNumber(a + len / 2, b - len / 2)
			local hgt = rng:NextNumber(8, 22)
			local side = rng:NextNumber() < 0.5 and -1 or 1
			if axis == "X" then
				Parts.span(m, "Ivy", O, V(cpos - len / 2, H - hgt, fixed + side * (T / 2) - 0.15), V(cpos + len / 2, H, fixed + side * (T / 2) + 0.15), IVY, M.LeafyGrass, NOCOLLIDE)
			else
				Parts.span(m, "Ivy", O, V(fixed + side * (T / 2) - 0.15, H - hgt, cpos - len / 2), V(fixed + side * (T / 2) + 0.15, H, cpos + len / 2), IVY, M.LeafyGrass, NOCOLLIDE)
			end
		end
		return p
	end

	local isExitWall = function(axis, line, k)
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

	-- горизонтальные линии (вдоль X), line от -1 до N-1: стена между рядами line и line+1
	for line = -1, N - 1 do
		local z = (line - MID) * C + C / 2
		local runStart
		for i = 0, N do
			local present = false
			if i < N then
				local up, down = line, line + 1
				if line == -1 or line == N - 1 then
					present = not isExitWall("X", line, i)
				else
					local cA, cB = inClearing(i, up), inClearing(i, down)
					present = not cA and not cB and not openS[i][up]
				end
			end
			if present and not runStart then
				runStart = i
			elseif not present and runStart then
				wallRun("X", z, (runStart - MID) * C - C / 2, (i - 1 - MID) * C + C / 2)
				runStart = nil
			end
		end
	end
	-- вертикальные линии (вдоль Z)
	for line = -1, N - 1 do
		local x = (line - MID) * C + C / 2
		local runStart
		for j = 0, N do
			local present = false
			if j < N then
				if line == -1 or line == N - 1 then
					present = not isExitWall("Z", line, j)
				else
					local cA, cB = inClearing(line, j), inClearing(line + 1, j)
					present = not cA and not cB and not openE[line][j]
				end
			end
			if present and not runStart then
				runStart = j
			elseif not present and runStart then
				wallRun("Z", x, (runStart - MID) * C - C / 2, (j - 1 - MID) * C + C / 2)
				runStart = nil
			end
		end
	end

	-- тупики: шахты, сундуки, золотой сундук с ключом
	local deadEnds = {}
	for i = 0, N - 1 do
		for j = 0, N - 1 do
			if valid(i, j) and dist[i][j] and dist[i][j] > 2 and not (exitCell and exitCell[1] == i and exitCell[2] == j) then
				local nb = neighbors(i, j, openE, openS, valid)
				if #nb == 1 then
					table.insert(deadEnds, { i = i, j = j, d = dist[i][j], to = cellPos(nb[1][1], nb[1][2]) })
				end
			end
		end
	end
	table.sort(deadEnds, function(a, b)
		return a.d > b.d
	end)
	-- золотой сундук — в самом дальнем тупике
	if deadEnds[1] then
		local de = table.remove(deadEnds, 1)
		local pos = cellPos(de.i, de.j)
		table.insert(refs.chests, chest(m, pos, (de.to - pos).Unit, true))
	end
	-- шахты: половина ближних (камень+железо), половина дальних (железо+кристаллы)
	local usedMines = 0
	local far = {}
	local near = {}
	for k, de in ipairs(deadEnds) do
		if k <= #deadEnds / 2 then
			table.insert(far, de)
		else
			table.insert(near, de)
		end
	end
	local function takeMine(list, kinds)
		if #list == 0 then
			return
		end
		local de = table.remove(list, rng:NextInteger(1, #list))
		local pos = cellPos(de.i, de.j)
		mine(m, pos, (de.to - pos).Unit, kinds, rng, refs.nodes)
		usedMines += 1
		de.used = true
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
		local pos = cellPos(de.i, de.j)
		local c = chest(m, pos, (de.to - pos).Unit, false)
		c.model:SetAttribute("Depth", de.d)
		table.insert(refs.chests, c)
	end

	-- светящийся мох на стенах для атмосферы
	for _ = 1, 50 do
		local p = refs.cells[rng:NextInteger(1, #refs.cells)]
		local glow = Parts.box(m, "GlowMoss", CFrame.new(p + V(rng:NextNumber(-9, 9), rng:NextNumber(0.3, 1), rng:NextNumber(-9, 9))), V(rng:NextNumber(1, 2.5), 0.3, rng:NextNumber(1, 2.5)), RGB(90, 255, 170), M.Neon, NOCOLLIDE)
		if rng:NextNumber() < 0.3 then
			Parts.light(glow, 10, 0.5, RGB(90, 255, 170), false)
		end
	end

	-- выход за внешней стеной
	if exitCell then
		local i, j = exitCell[1], exitCell[2]
		local inner = cellPos(i, j)
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
			Parts.box(m, "ExitWall", b * CFrame.new(x, H / 2, -20), V(T, H, 40), WALL_DARK, M.Slate)
		end
		Parts.box(m, "ExitFloor", b * CFrame.new(0, 0.2, -20), V(C, 0.4, 40), RGB(60, 60, 64), M.Concrete)
		local door = Parts.box(m, "ExitDoor", b * CFrame.new(0, 13, -40), V(C, 26, 2), RGB(90, 95, 100), M.DiamondPlate)
		for _, x in ipairs({ -8, 8 }) do
			local lamp = Parts.box(m, "ExitLamp", b * CFrame.new(x, 24, -38), V(1.5, 1.5, 1.5), RGB(120, 255, 160), M.Neon)
			Parts.light(lamp, 30, 1.6, RGB(140, 255, 170), true)
		end
		local sign = Parts.box(m, "ExitSign", b * CFrame.new(0, 28, -38.8), V(14, 3, 0.3), RGB(20, 40, 25), M.SmoothPlastic)
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
		local p = Instance.new("ProximityPrompt")
		p.ActionText = "Открыть выход"
		p.ObjectText = "Нужен Ключ Лабиринта"
		p.HoldDuration = 2
		p.MaxActivationDistance = 12
		p.Parent = door
		refs.exitDoor = door
		refs.exitPrompt = p
		refs.exitOut = b
	end

	m.Parent = parent
	return refs
end

return World
