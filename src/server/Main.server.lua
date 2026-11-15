-- Главный серверный скрипт «ЛАБИРИНТ».
-- Лобби (3 лифта сложности, торговец классами) -> лифт -> своя поляна и свой лабиринт для группы.
-- День: врата открыты, добывай и исследуй. Ночь: врата закрыты, Скрежетники.
-- Раненого поднимает друг бинтом. Найди Ключ и выход — улетай на вертолёте.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local PhysicsService = game:GetService("PhysicsService")
local DataStoreService = game:GetService("DataStoreService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local ItemModels = require(Shared:WaitForChild("ItemModels"))
local World = require(script.Parent.World)
local Monster = require(script.Parent.Monster)

local V = Vector3.new

------------------------------------------------------------------
-- Remotes
------------------------------------------------------------------
local remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage
local R = {}
for _, name in ipairs({
	"Swing", "Equip", "Craft", "Eat", "OpenCraft", "Notify", "PlayElevator", "Arrive", "Hurt", "HitMarker",
	"Outro", "Dev", "Crouch", "LiftSettings", "ShopOpen", "ShopBuy", "ShopSelect",
}) do
	local r = remotes:FindFirstChild(name) or Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	R[name] = r
end

------------------------------------------------------------------
-- Группы столкновений: пригнувшийся игрок проходит сквозь «крышку» щели
------------------------------------------------------------------
pcall(function()
	PhysicsService:RegisterCollisionGroup("CrawlCover")
	PhysicsService:RegisterCollisionGroup("Crawler")
	PhysicsService:CollisionGroupSetCollidable("CrawlCover", "Crawler", false)
end)

------------------------------------------------------------------
-- Освещение (время суток каждый игрок видит своё — его рисует клиент)
------------------------------------------------------------------
for _, c in ipairs(Lighting:GetChildren()) do
	if c:IsA("PostEffect") or c:IsA("Atmosphere") then
		c:Destroy()
	end
end
-- Небо НЕ удаляем: если вставить красивое небо из Toolbox в Lighting, оно останется
if not Lighting:FindFirstChildOfClass("Sky") then
	local sky = Instance.new("Sky")
	sky.StarCount = 4000
	sky.MoonAngularSize = 14
	sky.SunAngularSize = 16
	sky.Parent = Lighting
end
Lighting.GlobalShadows = true
Lighting.EnvironmentDiffuseScale = 0.6
Lighting.EnvironmentSpecularScale = 0.6
Lighting.ClockTime = 14
local atmo = Instance.new("Atmosphere")
atmo.Density = 0.3
atmo.Haze = 1.2
atmo.Parent = Lighting
for _, cls in ipairs({ "BloomEffect", "SunRaysEffect", "ColorCorrectionEffect", "DepthOfFieldEffect" }) do
	local e = Instance.new(cls)
	if cls == "BloomEffect" then
		e.Intensity, e.Size, e.Threshold = 0.5, 30, 1.1
	elseif cls == "SunRaysEffect" then
		e.Intensity, e.Spread = 0.12, 0.7
	elseif cls == "DepthOfFieldEffect" then
		e.FarIntensity, e.FocusDistance, e.InFocusRadius, e.NearIntensity = 0.12, 70, 100, 0
	end
	e.Parent = Lighting
end

------------------------------------------------------------------
-- Профиль: монеты и классы (сохраняются в опубликованной игре)
------------------------------------------------------------------
local profileStore
pcall(function()
	profileStore = DataStoreService:GetDataStore("LabyrinthProfile")
end)
local profiles = {}

local function syncProfile(p)
	local pr = profiles[p]
	p:SetAttribute("Coins", pr.coins)
	p:SetAttribute("Class", pr.class)
	p:SetAttribute("OwnedClasses", HttpService:JSONEncode(pr.owned))
end

local function saveProfile(p)
	local pr = profiles[p]
	if pr and profileStore then
		task.spawn(function()
			pcall(function()
				profileStore:SetAsync("u" .. p.UserId, HttpService:JSONEncode(pr))
			end)
		end)
	end
end

local function loadProfile(p)
	local pr = { coins = 0, owned = { "none" }, class = "none" }
	if profileStore then
		local ok, json = pcall(function()
			return profileStore:GetAsync("u" .. p.UserId)
		end)
		if ok and typeof(json) == "string" then
			local ok2, data = pcall(function()
				return HttpService:JSONDecode(json)
			end)
			if ok2 and typeof(data) == "table" then
				pr.coins = tonumber(data.coins) or 0
				pr.owned = typeof(data.owned) == "table" and data.owned or { "none" }
				pr.class = typeof(data.class) == "string" and data.class or "none"
			end
		end
	end
	profiles[p] = pr
	syncProfile(p)
end

local function addCoins(p, n)
	local pr = profiles[p]
	if pr then
		pr.coins += n
		syncProfile(p)
		saveProfile(p)
	end
end

------------------------------------------------------------------
-- Игроки и инвентарь
------------------------------------------------------------------
local lobby = World.BuildLobby()
local state = {} -- [player] = {...}
local sessions = {}
local usedSlots = {}

local function notify(p, text)
	R.Notify:FireClient(p, text)
end

local function sessionOf(p)
	local st = state[p]
	return st and st.session
end

local function notifySession(s, text)
	for _, p in ipairs(s.players) do
		notify(p, text)
	end
end

local function addRes(p, k, n)
	local st = state[p]
	st.res[k] = math.max(0, (st.res[k] or 0) + n)
	p:SetAttribute("Res_" .. k, st.res[k])
end

local function syncInventory(p)
	local st = state[p]
	for k in pairs(Items.Resources) do
		p:SetAttribute("Res_" .. k, st.res[k] or 0)
	end
	p:SetAttribute("Tools", HttpService:JSONEncode(st.tools))
	p:SetAttribute("Equipped", st.equipped)
end

local function freshInventory(p)
	local st = state[p]
	st.res, st.tools, st.equipped, st.gotSupply = {}, { "wood_pickaxe", "wood_axe" }, nil, false
	local cls = profiles[p] and profiles[p].class or "none"
	if cls == "lumber" then
		table.insert(st.tools, "stone_axe")
	elseif cls == "miner" then
		table.insert(st.tools, "stone_pickaxe")
	elseif cls == "warrior" then
		table.insert(st.tools, "spear")
	end
	syncInventory(p)
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

local function inSafeZone(s, pos)
	local h = World.CLEARING_HALF - 3
	local rel = pos - s.O
	return math.abs(rel.X) < h and math.abs(rel.Z) < h and rel.Y > -20 and rel.Y < 300
end

local function classOf(p)
	return profiles[p] and profiles[p].class or "none"
end

-- предмет в руке (виден другим игрокам)
local function updateHeld(p)
	local st = state[p]
	local char = p.Character
	if not char or not st then
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
	if not st or (id ~= nil and (typeof(id) ~= "string" or not table.find(st.tools, id))) then
		return
	end
	st.equipped = id
	p:SetAttribute("Equipped", id)
	updateHeld(p)
end)

------------------------------------------------------------------
-- Ранение и подъём
------------------------------------------------------------------
local respawnAtClearing

local function setDownedVisual(p, on)
	local _, char = hrpOf(p)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.PlatformStand = on
		hum.WalkSpeed = on and 0 or Config.WalkSpeed
		hum.JumpPower = on and 0 or 50
	end
end

local function revive(p, by)
	local st = state[p]
	if not st or not st.downed then
		return
	end
	st.downed = false
	p:SetAttribute("Downed", false)
	if st.revivePrompt then
		st.revivePrompt:Destroy()
		st.revivePrompt = nil
	end
	setDownedVisual(p, false)
	local _, char = hrpOf(p)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Health = Config.ReviveHealth
	end
	notify(p, by and (by.DisplayName .. " поднял тебя!") or "Ты пришёл в себя")
end

local function checkAllDowned(s)
	for _, p in ipairs(s.players) do
		local st = state[p]
		if st and not st.downed then
			return
		end
	end
	notifySession(s, "Все ранены... Вы очнулись у лифта на поляне.")
	for _, p in ipairs(s.players) do
		respawnAtClearing(p)
	end
end

local function down(p)
	local st = state[p]
	local s = st and st.session
	if not s or st.downed then
		return
	end
	st.downed = true
	st.downedAt = os.clock()
	p:SetAttribute("Downed", true)
	p:SetAttribute("DownedEnd", workspace:GetServerTimeNow() + Config.DownedTime)
	setDownedVisual(p, true)
	local hrp = hrpOf(p)
	if hrp then
		local pr = Instance.new("ProximityPrompt")
		pr.ActionText = "Поднять (нужен бинт)"
		pr.ObjectText = p.DisplayName .. " ранен"
		pr.HoldDuration = 2.5
		pr.MaxActivationDistance = 9
		pr.RequiresLineOfSight = false
		pr.Parent = hrp
		st.revivePrompt = pr
		pr.Triggered:Connect(function(by)
			local bst = state[by]
			if by == p or not bst or bst.session ~= s or bst.downed then
				return
			end
			if (bst.res.bandage or 0) < 1 then
				notify(by, "Нужен бинт! Сделай его из травы (C → Бинт).")
				return
			end
			addRes(by, "bandage", -1)
			revive(p, by)
		end)
	end
	for _, other in ipairs(s.players) do
		if other ~= p then
			notify(other, p.DisplayName .. " ранен! Подойди и подними его бинтом (зажми E).")
		end
	end
	local token = st.downedAt
	task.delay(Config.DownedTime, function()
		if st.downed and st.downedAt == token and st.session == s then
			notify(p, "Ты очнулся у лифта на поляне.")
			respawnAtClearing(p)
		end
	end)
	checkAllDowned(s)
end

local function damage(p, amount)
	local st = state[p]
	local _, char = hrpOf(p)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not st or not hum or st.downed then
		return
	end
	hum.Health = math.max(1, hum.Health - amount)
	R.Hurt:FireClient(p)
	if hum.Health <= 1 then
		down(p)
	end
end

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
		elseif d:IsA("Light") or d:IsA("ProximityPrompt") then
			d.Enabled = visible
		end
	end
end

local function hitNode(p, model, def)
	local kind = model:GetAttribute("Node")
	local nd = Items.Nodes[kind]
	if not nd or model:GetAttribute("Depleted") then
		return false
	end
	if def.Kind ~= nd.Tool then
		notify(p, nd.Tool == "axe" and "Нужен топор" or "Нужна кирка")
		return false
	end
	if def.Tier < nd.Tier then
		notify(p, "Слишком твёрдо! Нужна кирка " .. nd.Tier .. " уровня (крафт на верстаке)")
		return false
	end
	local dmg = def.Damage
	local gain = 1
	local cls = classOf(p)
	if cls == "miner" and nd.Tool == "pickaxe" then
		dmg *= 1.5
	end
	if cls == "lumber" and nd.Tool == "axe" then
		gain = 2
	end
	local hp = (model:GetAttribute("HP") or nd.Health) - dmg
	model:SetAttribute("HP", hp)
	addRes(p, nd.Drop, gain)
	R.HitMarker:FireClient(p, "node", nd.Tool)
	if hp <= 0 then
		addRes(p, nd.Drop, nd.Amount * gain)
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
	return true
end

-- лучший свой инструмент нужного вида (для добычи на E)
local function bestTool(p, kind)
	local st = state[p]
	local best
	for _, id in ipairs(st.tools) do
		local t = Items.Tools[id]
		if t and t.Kind == kind and (not best or t.Tier > best.Tier) then
			best = t
		end
	end
	return best
end

------------------------------------------------------------------
-- Монстры
------------------------------------------------------------------
local function alivePlayers(s)
	local list = {}
	for _, p in ipairs(s.players) do
		local st = state[p]
		if st and not st.downed and p.Parent then
			table.insert(list, p)
		end
	end
	return list
end

local function spawnMonsters(s)
	if s.ended or #s.players == 0 then
		return
	end
	local d = s.diff
	local count = math.floor(d.Monsters + d.PerPlayer * #s.players + 0.5)
	local far = {}
	for _, c in ipairs(s.maze.cells) do
		if (c - s.O).Magnitude > World.CLEARING_HALF + 70 then
			table.insert(far, c)
		end
	end
	for _ = 1, count do
		local pos = far[math.random(1, #far)]
		local mon = Monster.new({
			parent = s.folder,
			spawn = CFrame.new(pos + V(0, 10, 0)),
			patrol = s.maze.cells,
			getPlayers = function()
				return alivePlayers(s)
			end,
			inSafeZone = function(pos2)
				return inSafeZone(s, pos2)
			end,
			damage = damage,
			health = d.Health,
			speed = d.Speed,
			dmg = d.Damage,
		})
		s.monsters[mon.model] = mon
	end
end

local function clearMonsters(s, retreat)
	for model, mon in pairs(s.monsters) do
		mon:Die(retreat)
		s.monsters[model] = nil
	end
end

------------------------------------------------------------------
-- Удар (ЛКМ)
------------------------------------------------------------------
R.Swing.OnServerEvent:Connect(function(p, hit, hitPos)
	local st = state[p]
	local s = st and st.session
	if not s or st.downed then
		return
	end
	local def = Items.Tools[st.equipped or "fists"] or Items.Tools.fists
	if def.Kind == "torch" then
		return -- факел только светит
	end
	local now = os.clock()
	if now - (st.lastSwing or 0) < 0.4 then
		return
	end
	st.lastSwing = now
	if typeof(hit) ~= "Instance" or typeof(hitPos) ~= "Vector3" then
		return
	end
	local _, char = hrpOf(p)
	local head = char and char:FindFirstChild("Head")
	if not head or (head.Position - hitPos).Magnitude > def.Range + 4 then
		return
	end
	local model = hit:FindFirstAncestorOfClass("Model")
	while model and not s.monsters[model] and model.Parent and model.Parent:IsA("Model") do
		model = model.Parent
	end
	local mon = model and s.monsters[model]
	if mon then
		local died = mon:TakeDamage(def.Damage, head.Position)
		R.HitMarker:FireClient(p, died and "kill" or "monster")
		if died then
			s.monsters[model] = nil
			addRes(p, "fang", 2)
			notifySession(s, p.DisplayName .. " победил Скрежетника!")
		end
		return
	end
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
	if not st or st.downed or not hum or (st.res.berry or 0) < 1 or hum.Health >= hum.MaxHealth then
		return
	end
	addRes(p, "berry", -1)
	hum.Health = math.min(hum.MaxHealth, hum.Health + Config.BerryHeal)
end)

------------------------------------------------------------------
-- Крафт: из инвентаря (C) и на верстаке
------------------------------------------------------------------
local function recipeById(id)
	for _, r in ipairs(Items.Recipes) do
		if r.Id == id then
			return r
		end
	end
end

local function nearestBench(s, pos)
	local best, bd
	for _, b in ipairs(s.benches) do
		if b.model.Parent then
			local d = (b.top.Position - pos).Magnitude
			if d < 16 and (not bd or d < bd) then
				best, bd = b, d
			end
		end
	end
	return best
end

local function connectBench(s, bench)
	bench.prompt.Triggered:Connect(function(p)
		if sessionOf(p) == s then
			R.OpenCraft:FireClient(p, bench.model:GetAttribute("Level") or 1)
		end
	end)
end

R.Craft.OnServerEvent:Connect(function(p, id)
	local st = state[p]
	local s = st and st.session
	local r = typeof(id) == "string" and recipeById(id)
	local hrp = hrpOf(p)
	if not s or not r or not hrp or st.downed then
		return
	end
	local bench
	if r.Station == "bench" then
		bench = nearestBench(s, hrp.Position)
		if not bench then
			notify(p, "Нужен верстак рядом. Сделай его: C → Верстак.")
			return
		end
		if r.Level > (bench.model:GetAttribute("Level") or 1) then
			notify(p, "Нужен верстак " .. r.Level .. " уровня")
			return
		end
	end
	if r.Id == "upgrade2" and (bench.model:GetAttribute("Level") or 1) >= 2 then
		notify(p, "Этот верстак уже 2 уровня")
		return
	end
	if Items.Tools[r.Id] and table.find(st.tools, r.Id) then
		notify(p, "У тебя уже есть: " .. Items.toolName(r.Id))
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
	if r.Id == "workbench" then
		local look = hrp.CFrame.LookVector * V(1, 0, 1)
		local pos = hrp.Position + look.Unit * 7
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { p.Character }
		local hit = workspace:Raycast(pos + V(0, 6, 0), V(0, -30, 0), params)
		local ground = hit and hit.Position or (pos - V(0, 3, 0))
		local b = World.BuildWorkbench(s.folder, CFrame.lookAt(ground, ground - look))
		table.insert(s.benches, b)
		connectBench(s, b)
		notifySession(s, p.DisplayName .. " поставил верстак")
	elseif r.Id == "upgrade2" then
		bench.model:SetAttribute("Level", 2)
		bench.label.Text = "Верстак · ур. 2"
		notifySession(s, p.DisplayName .. " улучшил верстак до 2 уровня!")
	elseif r.Res then
		addRes(p, r.Res, 1)
		notify(p, "Создано: " .. Items.Resources[r.Res].Name)
	else
		table.insert(st.tools, r.Id)
		p:SetAttribute("Tools", HttpService:JSONEncode(st.tools))
		notify(p, "Создано: " .. Items.toolName(r.Id) .. " (выбери цифрой)")
	end
end)

------------------------------------------------------------------
-- Врата
------------------------------------------------------------------
local function moveGates(s, close, duration)
	s.gatesClosed = close
	for _, g in ipairs(s.gates) do
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
				while leaf.part.Parent do
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
		local snd = Instance.new("Sound")
		snd.SoundId = Config.Sounds.Rumble
		snd.Volume = 3
		snd.PlaybackSpeed = 0.25
		snd.RollOffMaxDistance = 500
		snd.Parent = g.leaves[1].part
		snd:Play()
		task.delay(duration + 1, function()
			snd:Destroy()
		end)
	end
end

------------------------------------------------------------------
-- Сессии (одна группа = один лабиринт)
------------------------------------------------------------------
local function setPhase(s, phase, len)
	s.phase, s.phaseStart, s.phaseLen = phase, os.clock(), len
	local now = workspace:GetServerTimeNow()
	for _, p in ipairs(s.players) do
		p:SetAttribute("Phase", phase)
		p:SetAttribute("PhaseStart", now)
		p:SetAttribute("PhaseLen", len)
		p:SetAttribute("Day", s.day)
	end
end

local function endSession(s)
	if s.ended then
		return
	end
	s.ended = true
	clearMonsters(s, false)
	for _, p in ipairs(table.clone(s.players)) do
		local st = state[p]
		if st and p.Parent then
			st.session = nil
			st.downed = false
			p:SetAttribute("Downed", false)
			p:SetAttribute("InMatch", false)
			freshInventory(p)
			p:LoadCharacter()
		end
	end
	s.folder:Destroy()
	World.ClearTerrain(s.O)
	usedSlots[s.slot] = nil
	sessions[s] = nil
end

local function leaveSession(p)
	local st = state[p]
	local s = st and st.session
	if not s then
		return
	end
	st.session = nil
	local i = table.find(s.players, p)
	if i then
		table.remove(s.players, i)
	end
	if #s.players == 0 then
		endSession(s)
	end
end

local function connectSessionPrompts(s)
	s.clearing.supplyPrompt.Triggered:Connect(function(p)
		local st = state[p]
		if not st or st.session ~= s then
			return
		end
		if st.gotSupply then
			notify(p, "Ты уже забрал свои припасы")
			return
		end
		st.gotSupply = true
		addRes(p, "wood", 14)
		addRes(p, "stone", 6)
		addRes(p, "fiber", 3)
		addRes(p, "berry", 3)
		notify(p, "Припасы: +14 дерева, +6 камня, +3 травы, +3 ягоды. Нажми C — крафт.")
	end)
	for _, pr in ipairs(s.folder:GetDescendants()) do
		if pr:IsA("ProximityPrompt") then
			if CollectionService:HasTag(pr, "NodePrompt") then
				pr.Triggered:Connect(function(p)
					local st = state[p]
					if not st or st.session ~= s or st.downed then
						return
					end
					local model = pr.Parent:FindFirstAncestorWhichIsA("Model")
					local nd = model and Items.Nodes[model:GetAttribute("Node")]
					if not nd then
						return
					end
					local tool = bestTool(p, nd.Tool)
					if not tool then
						notify(p, nd.Tool == "axe" and "Нужен топор" or "Нужна кирка")
						return
					end
					hitNode(p, model, tool)
				end)
			elseif CollectionService:HasTag(pr, "BerryPrompt") then
				pr.Triggered:Connect(function(p)
					if sessionOf(p) ~= s then
						return
					end
					local now = os.clock()
					if (pr:GetAttribute("Next") or 0) > now then
						notify(p, "Ягоды ещё не выросли")
						return
					end
					pr:SetAttribute("Next", now + 40)
					addRes(p, "berry", 3)
					notify(p, "+3 ягоды (H — съесть, лечит)")
				end)
			elseif CollectionService:HasTag(pr, "FiberPrompt") then
				pr.Triggered:Connect(function(p)
					if sessionOf(p) ~= s then
						return
					end
					local now = os.clock()
					if (pr:GetAttribute("Next") or 0) > now then
						notify(p, "Трава ещё не отросла")
						return
					end
					pr:SetAttribute("Next", now + 30)
					addRes(p, "fiber", 2)
					notify(p, "+2 травы (для бинтов, факелов, копья)")
				end)
			end
		end
	end
	for _, c in ipairs(s.maze.chests) do
		c.prompt.Triggered:Connect(function(p)
			local st = state[p]
			if not st or st.session ~= s then
				return
			end
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
				local glow = c.model:FindFirstChild("KeyGlow")
				if glow then
					glow:Destroy()
				end
				gain("key", 1)
				gain("crystal", 3)
				gain("iron", 5)
				notifySession(s, p.DisplayName .. " нашёл КЛЮЧ ЛАБИРИНТА! Теперь найдите выход!")
			else
				local depth = c.model:GetAttribute("Depth") or 5
				local pool = { { "wood", 4, 8 }, { "stone", 4, 8 }, { "berry", 2, 4 }, { "fiber", 2, 4 }, { "bandage", 1, 2 } }
				if depth > 6 then
					table.insert(pool, { "iron", 2, 5 })
				end
				if depth > 14 then
					table.insert(pool, { "crystal", 1, 3 })
				end
				for _ = 1, 2 do
					local e = pool[math.random(1, #pool)]
					gain(e[1], math.random(e[2], e[3]))
				end
				if math.random() < 0.2 then
					local tool = ({ "spear", "stone_sword", "torch" })[math.random(1, 3)]
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
	if s.maze.exitPrompt then
		s.maze.exitPrompt.Triggered:Connect(function(p)
			local st = state[p]
			if not st or st.session ~= s or s.won then
				return
			end
			local hasKey = false
			for _, q in ipairs(s.players) do
				if state[q] and (state[q].res.key or 0) > 0 then
					hasKey = true
				end
			end
			if not hasKey then
				notify(p, "Заперто. Нужен Ключ Лабиринта — он в золотом сундуке в самом дальнем тупике (над ним светится ключ).")
				return
			end
			s.won = true
			clearMonsters(s, true)
			TweenService:Create(s.maze.exitDoor, TweenInfo.new(3), { CFrame = s.maze.exitDoor.CFrame + V(0, World.HALF, 0) }):Play()
			local coins = Config.CoinsEscape * s.diff.Coins
			for _, q in ipairs(s.players) do
				addCoins(q, coins)
				local hrp = hrpOf(q)
				if hrp then
					hrp.Anchored = true
				end
				R.Outro:FireClient(q, s.maze.helipad, s.maze.exitOut, s.players, s.day, coins)
			end
			task.delay(20, function()
				endSession(s)
			end)
		end)
	end
end

local function sessionLoop(s)
	while not s.ended do
		setPhase(s, "day", s.diff.Day)
		if s.gatesClosed then
			moveGates(s, false, 6)
			notifySession(s, "Рассвет. Врата открываются. День " .. s.day .. ".")
		end
		clearMonsters(s, true)
		local t0 = os.clock()
		local warned = false
		while not s.ended and os.clock() - t0 < s.diff.Day and not s.skip do
			if not warned and s.diff.Day - (os.clock() - t0) <= Config.WarningTime then
				warned = true
				notifySession(s, "Скоро закат! Врата закроются через " .. Config.WarningTime .. " секунд — возвращайтесь на поляну!")
			end
			task.wait(0.25)
		end
		s.skip = false
		if s.ended then
			break
		end
		setPhase(s, "night", s.diff.Night)
		moveGates(s, true, 8)
		notifySession(s, "Ночь. Врата закрылись. В лабиринте — Скрежетники...")
		task.delay(6, function()
			if s.phase == "night" and not s.won then
				spawnMonsters(s)
			end
		end)
		t0 = os.clock()
		while not s.ended and os.clock() - t0 < s.diff.Night and not s.skip do
			task.wait(0.25)
		end
		s.skip = false
		if s.ended then
			break
		end
		s.day += 1
		-- монеты за прожитую ночь
		for _, p in ipairs(s.players) do
			local st = state[p]
			if st and not st.downed then
				local c = Config.CoinsPerDay * s.diff.Coins
				addCoins(p, c)
				notify(p, "Ты пережил ночь! +" .. c .. " монет")
			end
		end
	end
end

local function openLiftGrate(s)
	local grate = s.clearing.grate
	local closed = s.clearing.grateClosed
	task.spawn(function()
		for i = 1, 30 do
			grate:PivotTo(closed + V(0, 15 * i / 30, 0))
			task.wait(0.03)
		end
		-- решётка остаётся открытой, чтобы никто не оказался заперт в лифте
	end)
end

local function startSession(riders, diffId)
	local slot
	for i = 1, 50 do
		if not usedSlots[i] then
			slot = i
			break
		end
	end
	if not slot then
		for _, p in ipairs(riders) do
			notify(p, "Все лабиринты заняты, попробуйте позже")
		end
		return
	end
	usedSlots[slot] = true
	local O = V(slot * Config.SlotSpacing, 0, 0)
	local s = {
		slot = slot,
		O = O,
		diff = Config.Difficulty[diffId],
		diffId = diffId,
		players = riders,
		monsters = {},
		benches = {},
		day = 1,
		gatesClosed = true,
	}
	sessions[s] = s
	s.folder = Instance.new("Folder")
	s.folder.Name = "Session_" .. slot
	s.folder.Parent = workspace
	local seed = math.random(1, 1e6)
	World.BuildTerrain(O)
	s.clearing = World.BuildClearing(s.folder, seed, O)
	s.gates = World.BuildClearingWalls(s.folder, O)
	s.maze = World.BuildMaze(s.folder, seed + 7, O)
	connectSessionPrompts(s)
	for _, p in ipairs(riders) do
		local st = state[p]
		st.session = s
		st.downed = false
		freshInventory(p)
		p:SetAttribute("InMatch", true)
		p:SetAttribute("Difficulty", diffId)
	end
	-- лифт приехал
	for i, p in ipairs(riders) do
		local off = V(((i - 1) % 3 - 1) * 4, 0, math.floor((i - 1) / 3) * 4)
		place(p, s.clearing.liftSpawn + off, true)
		R.Arrive:FireClient(p, s.clearing.liftPos, riders)
	end
	openLiftGrate(s)
	moveGates(s, false, 0.1)
	task.delay(7, function()
		for _, p in ipairs(s.players) do
			local hrp = hrpOf(p)
			if hrp then
				hrp.Anchored = false
			end
		end
	end)
	task.spawn(sessionLoop, s)
end

function respawnAtClearing(p)
	local st = state[p]
	if not st then
		return
	end
	st.downed = false
	p:SetAttribute("Downed", false)
	if st.revivePrompt then
		st.revivePrompt:Destroy()
		st.revivePrompt = nil
	end
	p:LoadCharacter()
end

------------------------------------------------------------------
-- Лифты в лобби: настройки хозяина (только друзья, сколько игроков), отсчёт
------------------------------------------------------------------
local lifts = {}
for id, e in pairs(lobby.elevators) do
	lifts[id] = { id = id, label = e.label, zone = e.zone, outside = e.outside, host = nil, friendsOnly = false, max = Config.Elevator.MaxPlayers, countdownEnd = nil, riding = false, goNow = false }
end
local friendCache = {}
local function isFriend(a, b)
	local key = math.min(a.UserId, b.UserId) .. "_" .. math.max(a.UserId, b.UserId)
	if friendCache[key] == nil then
		local ok, res = pcall(function()
			return a:IsFriendsWith(b.UserId)
		end)
		friendCache[key] = ok and res or false
	end
	return friendCache[key]
end

local function inZone(zone, pos)
	local rel = zone.CFrame:PointToObjectSpace(pos)
	local h = zone.Size / 2
	return math.abs(rel.X) < h.X and math.abs(rel.Y) < h.Y + 4 and math.abs(rel.Z) < h.Z
end

R.LiftSettings.OnServerEvent:Connect(function(p, action, value)
	for _, lift in pairs(lifts) do
		if lift.host == p then
			if action == "friends" and typeof(value) == "boolean" then
				lift.friendsOnly = value
			elseif action == "max" and typeof(value) == "number" then
				lift.max = math.clamp(math.floor(value), 1, Config.Elevator.MaxPlayers)
			elseif action == "go" then
				lift.goNow = true
			end
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(0.4)
		for _, lift in pairs(lifts) do
			if not lift.riding then
				local inside = {}
				for _, p in ipairs(Players:GetPlayers()) do
					local st = state[p]
					local hrp = hrpOf(p)
					if st and not st.session and hrp and inZone(lift.zone, hrp.Position) then
						table.insert(inside, p)
					end
				end
				if lift.host and not table.find(inside, lift.host) then
					lift.host = nil
				end
				if not lift.host and inside[1] then
					lift.host = inside[1]
					lift.friendsOnly = false
					lift.max = Config.Elevator.MaxPlayers
				end
				-- кто не проходит по правилам — выходит из лифта
				local allowed = {}
				for _, p in ipairs(inside) do
					local ok = true
					if p ~= lift.host then
						if lift.friendsOnly and not isFriend(p, lift.host) then
							ok = false
							notify(p, "Этот лифт только для друзей " .. lift.host.DisplayName)
						elseif #allowed >= lift.max then
							ok = false
							notify(p, "Лифт заполнен (" .. lift.max .. " игроков)")
						end
					end
					if ok then
						table.insert(allowed, p)
					else
						place(p, lift.outside, false)
					end
				end
				if #allowed > 0 then
					lift.countdownEnd = lift.countdownEnd or (os.clock() + Config.Elevator.Countdown)
				else
					lift.countdownEnd = nil
					lift.goNow = false
				end
				local left = lift.countdownEnd and math.max(0, math.ceil(lift.countdownEnd - os.clock())) or -1
				local dname = Config.Difficulty[lift.id].Name
				if lift.label then
					lift.label.Text = #allowed > 0 and (dname .. "  " .. #allowed .. "/" .. lift.max .. "  ·  " .. left .. "с") or dname
				end
				for _, p in ipairs(Players:GetPlayers()) do
					if table.find(allowed, p) then
						p:SetAttribute("LiftId", lift.id)
						p:SetAttribute("LiftHost", p == lift.host)
						p:SetAttribute("LiftHostName", lift.host and lift.host.DisplayName or "")
						p:SetAttribute("LiftFriends", lift.friendsOnly)
						p:SetAttribute("LiftMax", lift.max)
						p:SetAttribute("LiftCount", #allowed)
						p:SetAttribute("LiftCountdown", left)
					elseif p:GetAttribute("LiftId") == lift.id then
						p:SetAttribute("LiftId", nil)
					end
				end
				if #allowed > 0 and (left <= 0 or lift.goNow) then
					lift.riding = true
					lift.countdownEnd = nil
					lift.goNow = false
					lift.host = nil
					for _, p in ipairs(allowed) do
						p:SetAttribute("LiftId", nil)
						local hrp = hrpOf(p)
						if hrp then
							hrp.Anchored = true
						end
						R.PlayElevator:FireClient(p, allowed, Config.Elevator.RideTime, lift.id)
					end
					task.spawn(function()
						task.wait(Config.Elevator.RideTime)
						local riders = {}
						for _, p in ipairs(allowed) do
							if p.Parent then
								table.insert(riders, p)
							end
						end
						if #riders > 0 then
							startSession(riders, lift.id)
						end
						lift.riding = false
					end)
				end
			end
		end
	end
end)

------------------------------------------------------------------
-- Торговец классами
------------------------------------------------------------------
lobby.merchantPrompt.Triggered:Connect(function(p)
	R.ShopOpen:FireClient(p)
end)

local function classById(id)
	for _, c in ipairs(Config.Classes) do
		if c.Id == id then
			return c
		end
	end
end

R.ShopBuy.OnServerEvent:Connect(function(p, id)
	local pr = profiles[p]
	local c = typeof(id) == "string" and classById(id)
	if not pr or not c then
		return
	end
	if table.find(pr.owned, id) then
		pr.class = id
	elseif pr.coins >= c.Price then
		pr.coins -= c.Price
		table.insert(pr.owned, id)
		pr.class = id
		notify(p, "Куплен класс «" .. c.Name .. "»!")
	else
		notify(p, "Не хватает монет: нужно " .. c.Price)
		return
	end
	syncProfile(p)
	saveProfile(p)
end)

------------------------------------------------------------------
-- Пригнуться (Ctrl): пролезать в щели
------------------------------------------------------------------
R.Crouch.OnServerEvent:Connect(function(p, on)
	local _, char = hrpOf(p)
	if not char or typeof(on) ~= "boolean" then
		return
	end
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = on and "Crawler" or "Default"
		end
	end
	p:SetAttribute("Crouched", on)
end)

------------------------------------------------------------------
-- Игроки
------------------------------------------------------------------
-- Квадратный персонаж (R6) из аватара игрока: одежда и цвета сохраняются
local animTemplate = Shared:WaitForChild("R6Animate")
local descCache = {}
local function morphR6(p, oldChar)
	local desc = descCache[p]
	if not desc then
		local ok, d = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(math.max(1, p.UserId))
		end)
		desc = ok and d or Instance.new("HumanoidDescription")
		descCache[p] = desc
	end
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
	end)
	if not ok or not model or not oldChar.Parent then
		return false
	end
	model.Name = p.Name
	model:SetAttribute("Morphed", true)
	local oldAnim = model:FindFirstChild("Animate")
	if oldAnim then
		oldAnim:Destroy()
	end
	local anim = animTemplate:Clone()
	anim.Name = "Animate"
	anim.Disabled = false
	anim.Parent = model
	model:PivotTo(oldChar:GetPivot())
	p.Character = model
	model.Parent = workspace
	oldChar:Destroy()
	return true
end

local function onCharacter(p, char)
	local st = state[p]
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	local hum = char:WaitForChild("Humanoid", 5)
	if not hrp or not hum or not st then
		return
	end
	if hum.RigType == Enum.HumanoidRigType.R15 and not char:GetAttribute("Morphed") then
		if morphR6(p, char) then
			return -- CharacterAdded сработает ещё раз уже для квадратного персонажа
		end
	end
	hum.BreakJointsOnDeath = false
	hum.WalkSpeed = Config.WalkSpeed
	if classOf(p) == "warrior" then
		hum.MaxHealth = 140
		hum.Health = 140
	end
	-- смерть от чего-то другого (например, падение) = ранение
	hum.HealthChanged:Connect(function(h)
		if h <= 0 and st.session and not st.downed then
			hum.Health = 1
			down(p)
		end
	end)
	p:SetAttribute("Crouched", false)
	task.wait()
	if st.session then
		place(p, st.session.clearing.liftSpawn, false)
	else
		char:PivotTo(lobby.spawn.CFrame + V(math.random(-4, 4), 4, math.random(-2, 2)))
	end
	updateHeld(p)
end

local function onPlayer(p)
	state[p] = { res = {}, tools = {} }
	loadProfile(p)
	freshInventory(p)
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
	task.spawn(onPlayer, p)
end
Players.PlayerRemoving:Connect(function(p)
	leaveSession(p)
	saveProfile(p)
	state[p] = nil
	profiles[p] = nil
end)

------------------------------------------------------------------
-- Тестовые кнопки
------------------------------------------------------------------
R.Dev.OnServerEvent:Connect(function(p, action, value)
	if not Config.DevTools then
		return
	end
	local s = sessionOf(p)
	if action == "ghost" and typeof(value) == "boolean" then
		p:SetAttribute("DevGhost", value)
	elseif action == "phase" and s then
		s.skip = true
	elseif action == "res" then
		for k in pairs(Items.Resources) do
			addRes(p, k, k == "key" and 1 or 30)
		end
		notify(p, "[Тест] +30 всех ресурсов и Ключ")
	elseif action == "toexit" and s and s.maze.exitOut then
		place(p, s.maze.exitOut * CFrame.new(0, 4, -30), false)
	elseif action == "coins" then
		addCoins(p, 500)
	elseif action == "down" and s then
		down(p)
	end
end)
