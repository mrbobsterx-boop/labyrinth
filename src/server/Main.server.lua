-- Главный серверный скрипт «ЛАБИРИНТ».
-- Лобби -> лифт -> поляна. День: врата открыты, исследуй лабиринт, добывай, крафти.
-- Ночь: врата закрыты, в лабиринте Скрежетники. Найди Ключ и выход.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local ItemModels = require(Shared:WaitForChild("ItemModels"))
local World = require(script.Parent.World)
local Monster = require(script.Parent.Monster)

local V = Vector3.new
local RGB = Color3.fromRGB

------------------------------------------------------------------
-- Remotes
------------------------------------------------------------------
local remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage
local R = {}
for _, name in ipairs({ "Swing", "Equip", "Craft", "Eat", "OpenCraft", "Notify", "PlayElevator", "Hurt", "HitMarker", "Win", "Dev" }) do
	local r = remotes:FindFirstChild(name) or Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	R[name] = r
end

------------------------------------------------------------------
-- Освещение: красивое небо, лучи солнца, дымка, ночью — холодная тьма
------------------------------------------------------------------
for _, c in ipairs(Lighting:GetChildren()) do
	if c:IsA("PostEffect") or c:IsA("Atmosphere") or c:IsA("Sky") then
		c:Destroy()
	end
end
Lighting.GlobalShadows = true
Lighting.EnvironmentDiffuseScale = 0.6
Lighting.EnvironmentSpecularScale = 0.6
local atmo = Instance.new("Atmosphere")
atmo.Parent = Lighting
local sky = Instance.new("Sky")
sky.StarCount = 4000
sky.MoonAngularSize = 14
sky.SunAngularSize = 16
sky.Parent = Lighting
local bloom = Instance.new("BloomEffect")
bloom.Intensity = 0.5
bloom.Size = 30
bloom.Threshold = 1.1
bloom.Parent = Lighting
local rays = Instance.new("SunRaysEffect")
rays.Intensity = 0.12
rays.Spread = 0.7
rays.Parent = Lighting
local cc = Instance.new("ColorCorrectionEffect")
cc.Parent = Lighting
local dof = Instance.new("DepthOfFieldEffect")
dof.FarIntensity = 0.12
dof.FocusDistance = 60
dof.InFocusRadius = 80
dof.NearIntensity = 0
dof.Parent = Lighting

-- night: 0 (день) .. 1 (глубокая ночь)
local function applyLight(night)
	local function mix(a, b)
		return a:Lerp(b, night)
	end
	Lighting.Brightness = 3 - night * 2.2
	Lighting.Ambient = mix(RGB(70, 66, 60), RGB(14, 16, 26))
	Lighting.OutdoorAmbient = mix(RGB(140, 135, 125), RGB(30, 36, 60))
	atmo.Density = 0.3 + night * 0.15
	atmo.Haze = 1.2 + night * 1.2
	atmo.Color = mix(RGB(200, 190, 170), RGB(60, 70, 100))
	atmo.Decay = mix(RGB(110, 100, 90), RGB(20, 22, 40))
	atmo.Glare = 0.3 * (1 - night)
	cc.TintColor = mix(RGB(255, 245, 230), RGB(190, 205, 255))
	cc.Saturation = 0.1 - night * 0.35
	cc.Contrast = 0.12
	rays.Intensity = 0.12 * (1 - night)
end

------------------------------------------------------------------
-- Мир
------------------------------------------------------------------
local lobby = World.BuildLobby()
World.BuildTerrain()
local worldFolder
local clearing, maze, gates

local GameState = ReplicatedStorage
local workbenchLevel = 1

local function buildWorld()
	if worldFolder then
		worldFolder:Destroy()
	end
	worldFolder = Instance.new("Folder")
	worldFolder.Name = "World"
	worldFolder.Parent = workspace
	local seed = math.random(1, 1e6)
	clearing = World.BuildClearing(worldFolder, seed)
	gates = World.BuildClearingWalls(worldFolder)
	maze = World.BuildMaze(worldFolder, seed + 7)
	workbenchLevel = 1
	GameState:SetAttribute("WorkbenchLevel", 1)
end

------------------------------------------------------------------
-- Игроки и инвентарь
------------------------------------------------------------------
local state = {} -- [player] = {inMatch, res, tools, equipped, ...}

local function notify(p, text)
	R.Notify:FireClient(p, text)
end
local function notifyAll(text)
	R.Notify:FireAllClients(text)
end

local function inMatchPlayers()
	local list = {}
	for p, st in pairs(state) do
		if st.inMatch and p.Parent then
			table.insert(list, p)
		end
	end
	return list
end

local function sync(p)
	local st = state[p]
	for k in pairs(Items.Resources) do
		p:SetAttribute("Res_" .. k, st.res[k] or 0)
	end
	p:SetAttribute("Tools", HttpService:JSONEncode(st.tools))
	p:SetAttribute("Equipped", st.equipped)
end

local function addRes(p, k, n)
	local st = state[p]
	st.res[k] = math.max(0, (st.res[k] or 0) + n)
	p:SetAttribute("Res_" .. k, st.res[k])
end

local function newState()
	return { inMatch = false, res = {}, tools = { "wood_pickaxe", "wood_axe" }, equipped = nil, lastSwing = 0 }
end

local function hrpOf(p)
	local c = p.Character
	return c and c:FindFirstChild("HumanoidRootPart"), c
end

local function place(p, cf, anchored)
	local hrp, char = hrpOf(p)
	if hrp then
		hrp.Anchored = anchored == true
		char:PivotTo(cf)
		hrp.AssemblyLinearVelocity = Vector3.zero
	end
end

local function inSafeZone(pos)
	local h = World.CLEARING_HALF - 2
	return math.abs(pos.X) < h and math.abs(pos.Z) < h and pos.Y > -20 and pos.Y < 200
end

-- предмет в руке (виден другим игрокам)
local function updateHeld(p)
	local st = state[p]
	local char = p.Character
	if not char then
		return
	end
	local old = char:FindFirstChild("HeldItem")
	if old then
		old:Destroy()
	end
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	if not st.equipped or not hand then
		return
	end
	local m = ItemModels.build(st.equipped)
	m.Name = "HeldItem"
	m:PivotTo(hand.CFrame * CFrame.new(0, -hand.Size.Y / 2, -0.1) * CFrame.Angles(-math.pi / 2, 0, 0))
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			local w = Instance.new("WeldConstraint")
			w.Part0 = hand
			w.Part1 = d
			w.Parent = d
		end
	end
	m.Parent = char
end

R.Equip.OnServerEvent:Connect(function(p, id)
	local st = state[p]
	if not st then
		return
	end
	if id ~= nil and (typeof(id) ~= "string" or not table.find(st.tools, id)) then
		return
	end
	st.equipped = id
	p:SetAttribute("Equipped", id)
	updateHeld(p)
end)

------------------------------------------------------------------
-- Ресурсные узлы
------------------------------------------------------------------
local function setNodeVisible(model, visible)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d:GetAttribute("BaseT") == nil then
				d:SetAttribute("BaseT", d.Transparency)
				d:SetAttribute("BaseC", d.CanCollide)
			end
			d.Transparency = visible and d:GetAttribute("BaseT") or 1
			d.CanCollide = visible and d:GetAttribute("BaseC") or false
			d.CanQuery = visible
		elseif d:IsA("Light") then
			d.Enabled = visible
		end
	end
end

local function hitNode(p, model, def)
	local kind = model:GetAttribute("Node")
	local nd = Items.Nodes[kind]
	if not nd or model:GetAttribute("Depleted") then
		return
	end
	if def.Kind ~= nd.Tool then
		notify(p, nd.Tool == "axe" and "Нужен топор" or "Нужна кирка")
		return
	end
	if def.Tier < nd.Tier then
		notify(p, "Слишком твёрдо! Нужна кирка уровня " .. nd.Tier .. " (крафт на верстаке)")
		return
	end
	local hp = (model:GetAttribute("HP") or nd.Health) - def.Damage
	model:SetAttribute("HP", hp)
	addRes(p, nd.Drop, 1)
	R.HitMarker:FireClient(p, "node")
	if hp <= 0 then
		addRes(p, nd.Drop, nd.Amount)
		model:SetAttribute("Depleted", true)
		setNodeVisible(model, false)
		task.delay(Config.NodeRespawn, function()
			if model.Parent then
				model:SetAttribute("Depleted", false)
				model:SetAttribute("HP", nd.Health)
				setNodeVisible(model, true)
			end
		end)
	end
end

------------------------------------------------------------------
-- Монстры
------------------------------------------------------------------
local monsters = {} -- [model] = Monster

local function spawnMonsters()
	local players = inMatchPlayers()
	if #players == 0 then
		return
	end
	local count = Config.Monster.BaseCount + Config.Monster.PerPlayer * #players
	local far = {}
	for _, c in ipairs(maze.cells) do
		if c.Magnitude > World.CLEARING_HALF + 50 then
			table.insert(far, c)
		end
	end
	for _ = 1, count do
		local pos = far[math.random(1, #far)]
		local mon = Monster.new({
			parent = worldFolder,
			spawn = CFrame.new(pos + V(0, 8, 0)),
			patrol = maze.cells,
			getPlayers = inMatchPlayers,
			inSafeZone = inSafeZone,
			onHit = function(player)
				R.Hurt:FireClient(player)
			end,
		})
		monsters[mon.model] = mon
	end
end

local function clearMonsters(retreat)
	for model, mon in pairs(monsters) do
		mon:Die(retreat)
		monsters[model] = nil
	end
end

------------------------------------------------------------------
-- Бой и добыча
------------------------------------------------------------------
R.Swing.OnServerEvent:Connect(function(p, hit, hitPos)
	local st = state[p]
	if not st or not st.inMatch then
		return
	end
	local def = Items.Tools[st.equipped or "fists"] or Items.Tools.fists
	local now = os.clock()
	if now - st.lastSwing < 0.4 then
		return
	end
	st.lastSwing = now
	if typeof(hit) ~= "Instance" or typeof(hitPos) ~= "Vector3" then
		return
	end
	local char = p.Character
	local head = char and char:FindFirstChild("Head")
	if not head or (head.Position - hitPos).Magnitude > def.Range + 4 then
		return
	end
	-- монстр?
	local model = hit:FindFirstAncestorOfClass("Model")
	while model and not monsters[model] and model.Parent and model.Parent:IsA("Model") do
		model = model.Parent
	end
	local mon = model and monsters[model]
	if mon then
		local died = mon:TakeDamage(def.Damage, head.Position)
		R.HitMarker:FireClient(p, died and "kill" or "monster")
		if died then
			monsters[model] = nil
			addRes(p, "fang", 2)
			notifyAll(p.DisplayName .. " победил Скрежетника!")
		end
		return
	end
	-- ресурс?
	local nodeModel = hit:FindFirstAncestorWhichIsA("Model")
	while nodeModel and nodeModel:GetAttribute("Node") == nil and nodeModel.Parent and nodeModel.Parent:IsA("Model") do
		nodeModel = nodeModel.Parent
	end
	if nodeModel and nodeModel:GetAttribute("Node") then
		hitNode(p, nodeModel, def)
	end
end)

R.Eat.OnServerEvent:Connect(function(p)
	local st = state[p]
	local _, char = hrpOf(p)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not st or not hum or (st.res.berry or 0) < 1 or hum.Health >= hum.MaxHealth then
		return
	end
	addRes(p, "berry", -1)
	hum.Health = math.min(hum.MaxHealth, hum.Health + Config.BerryHeal)
end)

------------------------------------------------------------------
-- Верстак
------------------------------------------------------------------
local function recipeById(id)
	for _, r in ipairs(Items.Recipes) do
		if r.Id == id then
			return r
		end
	end
end

R.Craft.OnServerEvent:Connect(function(p, id)
	local st = state[p]
	local r = typeof(id) == "string" and recipeById(id)
	local hrp = hrpOf(p)
	if not st or not r or not hrp then
		return
	end
	local wb = clearing.workbenchPrompt.Parent
	if (hrp.Position - wb.Position).Magnitude > 16 then
		notify(p, "Подойди к верстаку")
		return
	end
	if r.Level > workbenchLevel then
		notify(p, "Нужен верстак " .. r.Level .. " уровня")
		return
	end
	if r.Id ~= "upgrade2" and table.find(st.tools, r.Id) then
		notify(p, "У тебя уже есть: " .. Items.toolName(r.Id))
		return
	end
	if r.Id == "upgrade2" and workbenchLevel >= 2 then
		notify(p, "Верстак уже 2 уровня")
		return
	end
	for k, n in pairs(r.Cost) do
		if (st.res[k] or 0) < n then
			notify(p, "Не хватает: " .. Items.Resources[k].Name)
			return
		end
	end
	for k, n in pairs(r.Cost) do
		addRes(p, k, -n)
	end
	if r.Id == "upgrade2" then
		workbenchLevel = 2
		GameState:SetAttribute("WorkbenchLevel", 2)
		clearing.workbenchLabel.Text = "Верстак · ур. 2"
		notifyAll(p.DisplayName .. " улучшил верстак до 2 уровня! Открыты железо и кристаллы.")
	else
		table.insert(st.tools, r.Id)
		p:SetAttribute("Tools", HttpService:JSONEncode(st.tools))
		notify(p, "Создано: " .. Items.toolName(r.Id) .. " (выбери цифрой)")
	end
end)

------------------------------------------------------------------
-- Подсказки (ProximityPrompt): верстак, припасы, ягоды, сундуки, выход
------------------------------------------------------------------
local function connectWorldPrompts()
	clearing.workbenchPrompt.Triggered:Connect(function(p)
		R.OpenCraft:FireClient(p)
	end)
	clearing.supplyPrompt.Triggered:Connect(function(p)
		local st = state[p]
		if not st or st.gotSupply then
			notify(p, "Ты уже забрал свои припасы")
			return
		end
		st.gotSupply = true
		addRes(p, "wood", 10)
		addRes(p, "stone", 6)
		addRes(p, "berry", 3)
		notify(p, "Начальные ресурсы: +10 дерева, +6 камня, +3 ягоды")
	end)
	for _, bp in ipairs(CollectionService:GetTagged("BerryPrompt")) do
		if bp:IsDescendantOf(worldFolder) then
			bp.Triggered:Connect(function(p)
				local now = os.clock()
				if (bp:GetAttribute("Next") or 0) > now then
					notify(p, "Ягоды ещё не выросли")
					return
				end
				bp:SetAttribute("Next", now + 40)
				addRes(p, "berry", 3)
				notify(p, "+3 ягоды (H — съесть, лечит)")
			end)
		end
	end
	for _, c in ipairs(maze.chests) do
		c.prompt.Triggered:Connect(function(p)
			if c.model:GetAttribute("Opened") then
				notify(p, "Сундук пуст")
				return
			end
			c.model:SetAttribute("Opened", true)
			c.prompt.Enabled = false
			c.lid.CFrame = c.lid.CFrame * CFrame.new(0, 0.6, 1.2) * CFrame.Angles(math.rad(70), 0, 0)
			local got = {}
			local function gain(k, n)
				addRes(p, k, n)
				table.insert(got, "+" .. n .. " " .. Items.Resources[k].Name)
			end
			if c.model:GetAttribute("Golden") then
				gain("key", 1)
				gain("crystal", 3)
				gain("iron", 5)
				notifyAll(p.DisplayName .. " нашёл КЛЮЧ ЛАБИРИНТА! Теперь найдите выход!")
			else
				local depth = c.model:GetAttribute("Depth") or 5
				local pool = { { "wood", 4, 8 }, { "stone", 4, 8 }, { "berry", 2, 4 } }
				if depth > 5 then
					table.insert(pool, { "iron", 2, 5 })
				end
				if depth > 11 then
					table.insert(pool, { "crystal", 1, 3 })
				end
				for _ = 1, 2 do
					local e = pool[math.random(1, #pool)]
					gain(e[1], math.random(e[2], e[3]))
				end
				if math.random() < 0.2 then
					local tool = ({ "spear", "stone_sword", "torch" })[math.random(1, 3)]
					local st = state[p]
					if not table.find(st.tools, tool) then
						table.insert(st.tools, tool)
						p:SetAttribute("Tools", HttpService:JSONEncode(st.tools))
						table.insert(got, Items.toolName(tool))
					end
				end
			end
			notify(p, "Сундук: " .. table.concat(got, ", "))
		end)
	end
	if maze.exitPrompt then
		maze.exitPrompt.Triggered:Connect(function(p)
			local st = state[p]
			if not st or (st.res.key or 0) < 1 then
				notify(p, "Заперто. Нужен Ключ Лабиринта — он в золотом сундуке в самом дальнем тупике.")
				return
			end
			if GameState:GetAttribute("Won") then
				return
			end
			GameState:SetAttribute("Won", true)
			TweenService:Create(maze.exitDoor, TweenInfo.new(3), { CFrame = maze.exitDoor.CFrame + V(0, 26, 0) }):Play()
			R.Win:FireAllClients(p.DisplayName, GameState:GetAttribute("Day") or 1)
		end)
	end
end

------------------------------------------------------------------
-- Врата
------------------------------------------------------------------
local gatesClosed = false
local function moveGates(close, duration)
	gatesClosed = close
	for _, g in ipairs(gates) do
		for _, leaf in ipairs(g.leaves) do
			local from = leaf.part.CFrame
			local to = close and leaf.closed or leaf.open
			local children = {}
			for _, ch in ipairs(leaf.part:GetChildren()) do
				if ch:IsA("BasePart") then
					children[ch] = from:ToObjectSpace(ch.CFrame)
				end
			end
			task.spawn(function()
				local t0 = os.clock()
				while true do
					local a = math.clamp((os.clock() - t0) / duration, 0, 1)
					local e = a * a * (3 - 2 * a)
					local cf = from:Lerp(to, e)
					leaf.part.CFrame = cf
					for ch, rel in pairs(children) do
						ch.CFrame = cf * rel
					end
					if a >= 1 then
						break
					end
					RunService.Heartbeat:Wait()
				end
			end)
		end
		-- грохот
		local s = Instance.new("Sound")
		s.SoundId = Config.Sounds.Rumble
		s.Volume = 3
		s.PlaybackSpeed = 0.25
		s.RollOffMaxDistance = 400
		s.Parent = g.leaves[1].part
		s:Play()
		task.delay(duration + 1, function()
			s:Destroy()
		end)
	end
end

------------------------------------------------------------------
-- Лифт
------------------------------------------------------------------
local function openLiftGrate()
	local grate = clearing.grate
	local closed = clearing.grateClosed
	task.spawn(function()
		for i = 1, 30 do
			grate:PivotTo(closed + V(0, 13 * i / 30, 0))
			task.wait(0.03)
		end
		task.wait(6)
		for i = 1, 30 do
			grate:PivotTo(closed + V(0, 13 * (1 - i / 30), 0))
			task.wait(0.03)
		end
	end)
end

local function arrive(p, index)
	local st = state[p]
	if not st or not p.Parent then
		return
	end
	local off = V(((index - 1) % 3 - 1) * 3.5, 0, math.floor((index - 1) / 3) * 3)
	place(p, clearing.liftSpawn + off, false)
	p:SetAttribute("InMatch", true)
end

local riding = false
local function ride(riders)
	riding = true
	for _, p in ipairs(riders) do
		local st = state[p]
		st.inMatch = true
		local hrp = hrpOf(p)
		if hrp then
			hrp.Anchored = true
		end
		R.PlayElevator:FireClient(p, riders, Config.Elevator.RideTime)
	end
	task.wait(Config.Elevator.RideTime)
	for i, p in ipairs(riders) do
		arrive(p, i)
	end
	openLiftGrate()
	riding = false
end

local function playersInLift()
	local list = {}
	local zone = lobby.zone
	for _, p in ipairs(Players:GetPlayers()) do
		local st = state[p]
		local hrp = hrpOf(p)
		if st and not st.inMatch and hrp then
			local rel = zone.CFrame:PointToObjectSpace(hrp.Position)
			local h = zone.Size / 2
			if math.abs(rel.X) < h.X and math.abs(rel.Y) < h.Y + 3 and math.abs(rel.Z) < h.Z then
				table.insert(list, p)
			end
		end
	end
	return list
end

task.spawn(function()
	local countdownEnd
	while true do
		task.wait(0.5)
		if not riding and not GameState:GetAttribute("Won") then
			local inside = playersInLift()
			if #inside > 0 then
				if not countdownEnd then
					countdownEnd = os.clock() + Config.Elevator.Countdown
				end
				local left = math.ceil(countdownEnd - os.clock())
				GameState:SetAttribute("LiftCountdown", math.max(0, left))
				if left <= 0 then
					countdownEnd = nil
					GameState:SetAttribute("LiftCountdown", -1)
					local riders = {}
					for i = 1, math.min(#inside, Config.Elevator.MaxPlayers) do
						riders[i] = inside[i]
					end
					task.spawn(ride, riders)
				end
			else
				countdownEnd = nil
				GameState:SetAttribute("LiftCountdown", -1)
			end
		end
	end
end)

------------------------------------------------------------------
-- День и ночь
------------------------------------------------------------------
local phaseStart, phaseLen = os.clock(), Config.DayLength
local phase = "day"
local skipPhase = false

local function setPhase(ph, len)
	phase, phaseStart, phaseLen = ph, os.clock(), len
	GameState:SetAttribute("Phase", ph)
	GameState:SetAttribute("PhaseEnd", workspace:GetServerTimeNow() + len)
end

RunService.Heartbeat:Connect(function()
	local a = math.clamp((os.clock() - phaseStart) / phaseLen, 0, 1)
	local clock, night
	if phase == "day" then
		clock = 6.5 + a * 11.5 -- 6:30 .. 18:00
		night = math.clamp((clock - 16.5) / 2, 0, 1) * 0.5 + math.clamp((7.5 - clock) / 1, 0, 1) * 0.5
	else
		clock = (18.2 + a * 12.1) % 24 -- 18:12 .. 6:18
		-- полная ночь в середине, мягкие сумерки по краям
		night = 0.5 + 0.5 * math.clamp(math.min(a, 1 - a) / 0.08, 0, 1)
	end
	Lighting.ClockTime = clock
	applyLight(night)
end)

local function waitPhase(seconds, warnAt)
	local t0 = os.clock()
	local warned = false
	while os.clock() - t0 < seconds do
		if skipPhase then
			skipPhase = false
			return
		end
		if warnAt and not warned and seconds - (os.clock() - t0) <= warnAt then
			warned = true
			notifyAll("Скоро закат! Врата закроются через " .. warnAt .. " секунд — возвращайтесь на поляну!")
		end
		task.wait(0.25)
	end
end

buildWorld()
connectWorldPrompts()

task.spawn(function()
	local day = 1
	while true do
		GameState:SetAttribute("Day", day)
		setPhase("day", Config.DayLength)
		if gatesClosed then
			moveGates(false, 6)
			notifyAll("Рассвет. Врата открываются. День " .. day .. ".")
		end
		clearMonsters(true)
		waitPhase(Config.DayLength, Config.WarningTime)
		setPhase("night", Config.NightLength)
		moveGates(true, 8)
		notifyAll("Ночь. Врата закрылись. В лабиринте — Скрежетники...")
		task.delay(6, spawnMonsters)
		waitPhase(Config.NightLength)
		day += 1
	end
end)
moveGates(false, 0.1)

------------------------------------------------------------------
-- Победа и новый лабиринт
------------------------------------------------------------------
GameState:GetAttributeChangedSignal("Won"):Connect(function()
	if not GameState:GetAttribute("Won") then
		return
	end
	task.wait(10)
	clearMonsters(false)
	for p, st in pairs(state) do
		if st.inMatch and p.Parent then
			state[p] = newState()
			sync(p)
			p:SetAttribute("InMatch", false)
			p:LoadCharacter()
		end
	end
	buildWorld()
	connectWorldPrompts()
	skipPhase = true
	GameState:SetAttribute("Won", false)
end)

------------------------------------------------------------------
-- Игроки
------------------------------------------------------------------
local function onCharacter(p, char)
	local st = state[p]
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	local hum = char:WaitForChild("Humanoid", 5)
	if not hrp or not hum or not st then
		return
	end
	hum.WalkSpeed = Config.WalkSpeed
	task.wait()
	if st.inMatch then
		place(p, clearing.liftSpawn, false)
	else
		char:PivotTo(lobby.spawn.CFrame + V(math.random(-3, 3), 4, math.random(-3, 3)))
	end
	updateHeld(p)
end

local function onPlayer(p)
	state[p] = newState()
	sync(p)
	p:SetAttribute("InMatch", false)
	p.CharacterAdded:Connect(function(char)
		onCharacter(p, char)
	end)
	if p.Character then
		task.spawn(onCharacter, p, p.Character)
	end
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	onPlayer(p)
end
Players.PlayerRemoving:Connect(function(p)
	state[p] = nil
end)

------------------------------------------------------------------
-- Тестовые кнопки
------------------------------------------------------------------
R.Dev.OnServerEvent:Connect(function(p, action, value)
	if not Config.DevTools then
		return
	end
	if action == "ghost" and typeof(value) == "boolean" then
		p:SetAttribute("DevGhost", value)
	elseif action == "phase" then
		skipPhase = true
	elseif action == "res" then
		for k in pairs(Items.Resources) do
			addRes(p, k, k == "key" and 1 or 30)
		end
		notify(p, "[Тест] +30 всех ресурсов и Ключ")
	elseif action == "toexit" and maze.exitOut then
		place(p, maze.exitOut * CFrame.new(0, 4, -30), false)
	end
end)
