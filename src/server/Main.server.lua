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
local Build = require(script.Parent.Build)
local Building = require(Shared:WaitForChild("Building"))

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
	"Outro", "Dev", "Crouch", "Note", "LiftSettings", "ShopOpen", "ShopBuy", "ShopSelect", "Build",
	"ExitIntro", "CardInsert", "MapData", "MazeShift", "Ping", "Upgrade", "Place", "Admin", "Prank",
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

-- сохранение: несколько попыток; если профиль не загрузился — НЕ сохраняем,
-- чтобы не затереть монеты и классы игрока нулями
local function saveProfile(p, wait)
	local pr = profiles[p]
	if not pr or not profileStore or pr.loadFailed then
		return
	end
	local data = HttpService:JSONEncode({ coins = pr.coins, owned = pr.owned, class = pr.class })
	local key = "u" .. p.UserId
	local function run()
		for attempt = 1, 3 do
			local ok = pcall(function()
				profileStore:SetAsync(key, data)
			end)
			if ok then
				pr.dirty = false
				return
			end
			task.wait(2 * attempt)
		end
		warn("[Labyrinth] не удалось сохранить профиль", p.Name)
	end
	if wait then
		run()
	else
		task.spawn(run)
	end
end

local function loadProfile(p)
	local pr = { coins = 0, owned = { "none" }, class = "none" }
	if profileStore then
		local loaded = false
		for attempt = 1, 3 do
			local ok, json = pcall(function()
				return profileStore:GetAsync("u" .. p.UserId)
			end)
			if ok then
				loaded = true
				if typeof(json) == "string" then
					local ok2, data = pcall(function()
						return HttpService:JSONDecode(json)
					end)
					if ok2 and typeof(data) == "table" then
						pr.coins = tonumber(data.coins) or 0
						pr.owned = typeof(data.owned) == "table" and data.owned or { "none" }
						pr.class = typeof(data.class) == "string" and data.class or "none"
					end
				end
				break
			end
			task.wait(2 * attempt)
		end
		if not loaded then
			pr.loadFailed = true
			task.delay(3, function()
				if p.Parent then
					R.Notify:FireClient(p, "Не удалось загрузить сохранение. Монеты в этот раз не сохранятся — перезайди позже.")
				end
			end)
		end
	end
	profiles[p] = pr
	syncProfile(p)
end

local function addCoins(p, n)
	local pr = profiles[p]
	if pr then
		pr.coins += n
		pr.dirty = true
		syncProfile(p)
	end
end

-- автосохранение раз в минуту (только у кого что-то поменялось)
task.spawn(function()
	while true do
		task.wait(60)
		for p, pr in pairs(profiles) do
			if pr.dirty and p.Parent then
				saveProfile(p)
			end
		end
	end
end)

-- сервер выключается (например, вышло обновление) — сохраняем всех
game:BindToClose(function()
	local left = 0
	for p in pairs(profiles) do
		left += 1
		task.spawn(function()
			saveProfile(p, true)
			left -= 1
		end)
	end
	local t0 = os.clock()
	while left > 0 and os.clock() - t0 < 25 do
		task.wait(0.2)
	end
end)

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

local updateHeld
local applyInvisible
local putInJail
local function addRes(p, k, n)
	local st = state[p]
	st.res[k] = math.max(0, (st.res[k] or 0) + n)
	p:SetAttribute("Res_" .. k, st.res[k])
	-- закончился предмет, который держали в руке
	local eq = st.equipped and Items.Tools[st.equipped]
	if eq and eq.Kind == "held" and eq.Res == k and st.res[k] <= 0 then
		st.equipped = nil
		p:SetAttribute("Equipped", nil)
		if updateHeld then
			updateHeld(p)
		end
	end
end

-- броня: видна на персонаже, уменьшает урон
local function armorVisual(p)
	local st = state[p]
	local char = p.Character
	if not st or not char then
		return
	end
	local old = char:FindFirstChild("ArmorModel")
	if old then
		old:Destroy()
	end
	local a = st.armor and Items.Armor[st.armor]
	local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
	if not a or not torso then
		return
	end
	local m = Instance.new("Model")
	m.Name = "ArmorModel"
	local col = Color3.fromRGB(a.Color[1], a.Color[2], a.Color[3])
	local mat = st.armor == 1 and Enum.Material.Leather or (st.armor == 3 and Enum.Material.Glass or Enum.Material.Metal)
	local function piece(partName, size, offset)
		local base = char:FindFirstChild(partName)
		if not base then
			return
		end
		local pt = Instance.new("Part")
		pt.Name = "Armor"
		pt.Size = size
		pt.Color = col
		pt.Material = mat
		pt.CanCollide = false
		pt.CanQuery = false
		pt.Massless = true
		pt.CFrame = base.CFrame * offset
		local w = Instance.new("WeldConstraint")
		w.Part0 = base
		w.Part1 = pt
		w.Parent = pt
		pt.Parent = m
	end
	piece(torso.Name, V(2.15, 1.7, 1.2), CFrame.new(0, 0.1, 0))
	piece("Left Arm", V(1.15, 0.7, 1.15), CFrame.new(0, 0.7, 0))
	piece("Right Arm", V(1.15, 0.7, 1.15), CFrame.new(0, 0.7, 0))
	piece("Left Leg", V(1.1, 0.8, 1.1), CFrame.new(0, -0.2, 0))
	piece("Right Leg", V(1.1, 0.8, 1.1), CFrame.new(0, -0.2, 0))
	m.Parent = char
end

local function giveArmor(p, tier, silent)
	local st = state[p]
	if not st then
		return
	end
	if (st.armor or 0) >= tier then
		if not silent then
			notify(p, "У тебя уже есть броня не хуже")
		end
		return false
	end
	st.armor = tier
	p:SetAttribute("Armor", tier)
	armorVisual(p)
	notify(p, "Надета: " .. Items.Armor[tier].Name .. " (урон меньше на " .. math.floor(Items.Armor[tier].Reduce * 100) .. "%)")
	return true
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
	st.armor = nil
	p:SetAttribute("Armor", 0)
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
	if s.exit then
		local lp = s.exit.zone.cf:PointToObjectSpace(pos)
		if math.abs(lp.X) < s.exit.zone.size.X / 2 and math.abs(lp.Z) < s.exit.zone.size.Z / 2 then
			return true
		end
	end
	local h = World.CLEARING_HALF - 3
	local rel = pos - s.O
	return math.abs(rel.X) < h and math.abs(rel.Z) < h and rel.Y > -20 and rel.Y < 300
end

local function classOf(p)
	return profiles[p] and profiles[p].class or "none"
end

-- предмет в руке (виден другим игрокам)
function updateHeld(p)
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
	if not st or (id ~= nil and typeof(id) ~= "string") then
		return
	end
	local def = id and Items.Tools[id]
	-- предмет из инвентаря (ключ-карта, карта, бинт, ягоды) можно держать, если он есть
	local heldOk = def and def.Kind == "held" and (st.res[def.Res] or 0) > 0
	if id ~= nil and not table.find(st.tools, id) and not heldOk then
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
local returnToLobby

-- тряпичная кукла: суставы становятся шарнирами, тело падает и болтается
local function setRagdoll(char, on)
	local torso = char and char:FindFirstChild("Torso")
	if not torso then
		return
	end
	for _, d in ipairs(char:GetDescendants()) do
		if d.Name == "RagJoint" or d.Name == "RagAtt" then
			d:Destroy()
		end
	end
	for _, m in ipairs(torso:GetChildren()) do
		if m:IsA("Motor6D") and m.Part0 and m.Part1 then
			if on then
				local a0 = Instance.new("Attachment")
				a0.Name = "RagAtt"
				a0.CFrame = m.C0
				a0.Parent = m.Part0
				local a1 = Instance.new("Attachment")
				a1.Name = "RagAtt"
				a1.CFrame = m.C1
				a1.Parent = m.Part1
				local bs = Instance.new("BallSocketConstraint")
				bs.Name = "RagJoint"
				bs.Attachment0 = a0
				bs.Attachment1 = a1
				bs.LimitsEnabled = true
				bs.UpperAngle = m.Name == "Neck" and 35 or 75
				bs.TwistLimitsEnabled = true
				bs.TwistLowerAngle = -40
				bs.TwistUpperAngle = 40
				bs.Parent = torso
			end
			m.Enabled = not on
			if m.Part1.Name ~= "Head" then
				m.Part1.CanCollide = on
			end
		end
	end
end

local function stopDrag(dragger)
	local dst = state[dragger]
	local victim = dst and dst.dragging
	if not victim then
		return
	end
	dst.dragging = nil
	dragger:SetAttribute("Dragging", false)
	if dst.dragRope then
		dst.dragRope:Destroy()
		dst.dragRope = nil
	end
	for _, a in ipairs(dst.dragAtts or {}) do
		a:Destroy()
	end
	dst.dragAtts = nil
	local vst = state[victim]
	if vst then
		vst.draggedBy = nil
	end
	local char = victim.Character
	if char then
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") then
				pcall(function()
					d:SetNetworkOwner(victim)
				end)
			end
		end
	end
end

local function startDrag(dragger, victim)
	local dst, vst = state[dragger], state[victim]
	local dh = hrpOf(dragger)
	local leg = victim.Character and (victim.Character:FindFirstChild("Right Leg") or victim.Character:FindFirstChild("RightLowerLeg"))
	if not dst or not vst or not dh or not leg then
		return
	end
	if vst.draggedBy then
		notify(dragger, "Его уже тащит " .. vst.draggedBy.DisplayName)
		return
	end
	dst.dragging = victim
	vst.draggedBy = dragger
	dragger:SetAttribute("Dragging", true)
	local a0 = Instance.new("Attachment")
	a0.Name = "DragAtt"
	a0.Position = V(0.6, -1, 1.2)
	a0.Parent = dh
	local a1 = Instance.new("Attachment")
	a1.Name = "DragAtt"
	a1.Position = V(0, -leg.Size.Y / 2 + 0.2, 0)
	a1.Parent = leg
	local rope = Instance.new("RopeConstraint")
	rope.Attachment0 = a0
	rope.Attachment1 = a1
	rope.Length = 3.5
	rope.Restitution = 0
	rope.Parent = dh
	dst.dragRope, dst.dragAtts = rope, { a0, a1 }
	-- физику тела считает тот, кто тащит, — так оно не дёргается
	for _, d in ipairs(victim.Character:GetDescendants()) do
		if d:IsA("BasePart") then
			pcall(function()
				d:SetNetworkOwner(dragger)
			end)
		end
	end
	notify(dragger, "Ты тащишь " .. victim.DisplayName .. " за ногу. F — отпустить.")
end

local function setDownedVisual(p, on)
	local _, char = hrpOf(p)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.PlatformStand = on
		hum.WalkSpeed = on and 0 or Config.WalkSpeed
		hum.JumpPower = on and 0 or 50
	end
	setRagdoll(char, on)
	if not on then
		local hrp = hrpOf(p)
		if hrp then
			hrp.CFrame = CFrame.new(hrp.Position + V(0, 2.5, 0)) * CFrame.Angles(0, select(2, hrp.CFrame:ToEulerAnglesYXZ()), 0)
		end
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
	if st.dragPrompt then
		st.dragPrompt:Destroy()
		st.dragPrompt = nil
	end
	if st.draggedBy then
		stopDrag(st.draggedBy)
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
	-- поднять некому — все возвращаются в лобби
	notifySession(s, "Все ранены, и помочь некому... Вы возвращаетесь в лобби.")
	local list = table.clone(s.players)
	task.delay(3, function()
		for _, p in ipairs(list) do
			if state[p] and state[p].session == s then
				returnToLobby(p)
			end
		end
	end)
end

local function down(p)
	local st = state[p]
	local s = st and st.session
	if not s or st.downed then
		return
	end
	st.downed = true
	st.downedAt = os.clock()
	stopDrag(p)
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
				notify(by, "Нужен бинт! Сделай его из травы (C → Бинт). Или тащи друга за ногу (F).")
				return
			end
			addRes(by, "bandage", -1)
			revive(p, by)
		end)
		-- тащить за ногу (F)
		local dp = Instance.new("ProximityPrompt")
		dp.ActionText = "Тащить за ногу"
		dp.ObjectText = p.DisplayName
		dp.KeyboardKeyCode = Enum.KeyCode.F
		dp.GamepadKeyCode = Enum.KeyCode.ButtonY
		dp.HoldDuration = 0.3
		dp.MaxActivationDistance = 9
		dp.RequiresLineOfSight = false
		dp.UIOffset = Vector2.new(0, 80)
		dp.Parent = hrp
		st.dragPrompt = dp
		dp.Triggered:Connect(function(by)
			local bst = state[by]
			if by == p or not bst or bst.session ~= s or bst.downed then
				return
			end
			if bst.dragging == p then
				stopDrag(by)
			elseif not bst.dragging then
				startDrag(by, p)
			end
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
			notify(p, "Тебя не успели поднять... Ты в лобби.")
			returnToLobby(p)
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
	-- броня уменьшает урон
	local armor = st.armor and Items.Armor[st.armor]
	if armor then
		amount = amount * (1 - armor.Reduce)
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
		-- от дерева остаётся пень, потом оно заново вырастает
		local stump
		local trunk = kind == "tree" and model:FindFirstChild("Trunk")
		if trunk then
			local base = trunk.Position - V(0, trunk.Size.Y / 2, 0)
			model.WorldPivot = CFrame.new(base)
			stump = Instance.new("Part")
			stump.Name = "Stump"
			stump.Anchored = true
			stump.Size = V(trunk.Size.X + 0.3, 1.4, trunk.Size.Z + 0.3)
			stump.CFrame = CFrame.new(base + V(0, 0.7, 0))
			stump.Color = trunk.Color
			stump.Material = Enum.Material.Wood
			stump.Parent = model.Parent
		end
		task.delay(Config.NodeRespawn, function()
			if not model.Parent then
				return
			end
			if stump then
				stump:Destroy()
				pcall(function()
					model:ScaleTo(0.15)
				end)
				setNodeVisible(model, true)
				for i = 1, 40 do
					task.wait(0.25)
					pcall(function()
						model:ScaleTo(0.15 + 0.85 * i / 40)
					end)
				end
			else
				setNodeVisible(model, true)
			end
			model:SetAttribute("Depleted", false)
			model:SetAttribute("HP", nd.Health)
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
	-- молоток: улучшение постройки
	local piece = Building.pieceOf(hit)
	if piece and def.Kind == "hammer" and piece:IsDescendantOf(s.folder) then
		local tier = (piece:GetAttribute("Tier") or 0) + 1
		local t = Building.Tiers[tier]
		if not t then
			notify(p, "Это уже металл — сильнее не бывает")
			return
		end
		for k, n in pairs(t.Cost) do
			if (st.res[k] or 0) < n then
				notify(p, "Для улучшения до «" .. t.Name .. "» нужно: " .. Items.Resources[k].Name .. " " .. n)
				return
			end
		end
		for k, n in pairs(t.Cost) do
			addRes(p, k, -n)
		end
		Build.setTier(piece, tier, true)
		R.HitMarker:FireClient(p, "node", "axe")
		notify(p, piece.Name .. " → " .. t.Name)
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
local connectBed, connectChest
local sendMap
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

------------------------------------------------------------------
-- Кровать, сундук, прятки в лианах
------------------------------------------------------------------
local function wake(p)
	local st = state[p]
	if not st or not st.sleeping then
		return
	end
	st.sleeping = nil
	p:SetAttribute("Sleeping", false)
	local hrp, char = hrpOf(p)
	if hrp then
		hrp.Anchored = false
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.PlatformStand = false
		end
		char:PivotTo(hrp.CFrame * CFrame.new(0, 1, 0) * CFrame.Angles(math.rad(-90), 0, 0) + V(0, 1.5, 0))
	end
end

local function checkSleep(s)
	if s.phase ~= "night" then
		return
	end
	local awake = 0
	for _, q in ipairs(s.players) do
		local st = state[q]
		if st and not st.downed and not st.sleeping then
			awake += 1
		end
	end
	if awake == 0 and #s.players > 0 then
		notifySession(s, "Все уснули... Ночь проходит.")
		s.skip = true
	end
end

function connectBed(s, bed, pr)
	pr.Triggered:Connect(function(p)
		local st = state[p]
		if not st or st.session ~= s or st.downed then
			return
		end
		if st.sleeping then
			wake(p)
			return
		end
		if s.phase ~= "night" then
			notify(p, "Спать можно только ночью")
			return
		end
		local hrp, char = hrpOf(p)
		if not hrp then
			return
		end
		st.sleeping = bed
		p:SetAttribute("Sleeping", true)
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.PlatformStand = true
		end
		hrp.Anchored = true
		char:PivotTo(bed:GetAttribute("SleepCF") * CFrame.Angles(math.rad(90), 0, 0))
		notify(p, "Ты спишь. Если уснут все — ночь пройдёт. E у кровати — встать.")
		checkSleep(s)
	end)
end

function connectChest(s, chest, put, take)
	local store = {}
	local function label()
		local n = 0
		for _, v in pairs(store) do
			n += v
		end
		put.ObjectText = n > 0 and ("Сундук (" .. n .. " шт.)") or "Сундук (пусто)"
	end
	put.Triggered:Connect(function(p)
		local st = state[p]
		if not st or st.session ~= s then
			return
		end
		for k, n in pairs(st.res) do
			if k ~= "key" and n > 0 then
				store[k] = (store[k] or 0) + n
				addRes(p, k, -n)
			end
		end
		label()
		notify(p, "Ресурсы сложены в сундук")
	end)
	take.Triggered:Connect(function(p)
		local st = state[p]
		if not st or st.session ~= s then
			return
		end
		for k, n in pairs(store) do
			addRes(p, k, n)
		end
		store = {}
		label()
		notify(p, "Ты забрал всё из сундука")
	end)
	local _ = chest
end

local function unhide(p)
	local st = state[p]
	if not st or not st.hidden then
		return
	end
	local spot = st.hidden
	st.hidden = nil
	p:SetAttribute("Hidden", false)
	spot:SetAttribute("Occupied", false)
	local pr = spot:FindFirstChildOfClass("ProximityPrompt")
	if pr then
		pr.ActionText = "Спрятаться"
	end
	local hrp, char = hrpOf(p)
	if hrp then
		hrp.Anchored = false
		local out = (spot:GetAttribute("Out") or spot.Position + V(0, 0, 6))
		char:PivotTo(CFrame.lookAt(out + V(0, 1, 0), out + V(0, 1, 0) + (out - spot.Position) * V(1, 0, 1)))
	end
end

------------------------------------------------------------------
-- Строительство (чертёж)
------------------------------------------------------------------
R.Build.OnServerEvent:Connect(function(p, id, a)
	local st = state[p]
	local s = st and st.session
	local def = typeof(id) == "string" and Building.ById[id]
	local hrp = hrpOf(p)
	if not s or not def or not hrp or st.downed or st.equipped ~= "blueprint" or typeof(a) ~= "table" then
		return
	end
	-- проверка параметров
	local ok = typeof(a.y) == "number" and a.y == a.y and math.abs(a.y) < 400
	if def.Edge or def.Door then
		ok = ok and typeof(a.ex) == "number" and typeof(a.ez) == "number" and (a.axis == "X" or a.axis == "Z")
		ok = ok and a.ex % 1 == 0 and a.ez % 1 == 0
	else
		ok = ok and typeof(a.cx) == "number" and typeof(a.cz) == "number" and a.cx % 1 == 0 and a.cz % 1 == 0
	end
	if not ok then
		return
	end
	local args = { cx = a.cx, cz = a.cz, ex = a.ex, ez = a.ez, axis = a.axis, y = a.y, rot = (typeof(a.rot) == "number" and a.rot % 1 == 0) and a.rot % 4 or 0 }
	local key = Building.key(id, args)
	if s.pieces[key] and s.pieces[key].Parent then
		notify(p, "Здесь уже стоит постройка")
		return
	end
	if id == "door" then
		local frame = s.pieces[Building.key("doorway", args)]
		if not frame or not frame.Parent or frame:GetAttribute("BKind") ~= "doorway" then
			notify(p, "Дверь ставится в дверной проём")
			return
		end
	end
	local cf = Building.cframe(id, s.O, args)
	if (cf.Position - hrp.Position).Magnitude > 32 then
		return
	end
	if (cf.Position - s.O).Magnitude < 16 then
		notify(p, "Слишком близко к лифту")
		return
	end
	-- не строим внутри стен, деревьев и игроков
	-- selene: allow(undefined_variable)
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = { s.buildFolder }
	op.RespectCanCollide = true
	local size = def.Size - V(0.6, 0.6, 0.6)
	if id == "foundation" then
		size = V(7.4, 1.2, 7.4)
		cf = cf * CFrame.new(0, 0.8, 0)
	end
	for _, part in ipairs(workspace:GetPartBoundsInBox(cf, V(math.max(0.2, size.X), math.max(0.2, size.Y), math.max(0.2, size.Z)), op)) do
		if not part:IsA("Terrain") then
			notify(p, "Мешает: " .. part.Name)
			return
		end
	end
	for k, n in pairs(def.Cost) do
		if (st.res[k] or 0) < n then
			notify(p, "Не хватает: " .. Items.Resources[k].Name .. " (" .. n .. "). Доски делаются в крафте (C).")
			return
		end
	end
	for k, n in pairs(def.Cost) do
		addRes(p, k, -n)
	end
	s.pieces[key] = Build.piece(s.buildFolder, id, s.O, args)
	R.HitMarker:FireClient(p, "node", "axe")
end)

-- поставить верстак / кровать / сундук (с предпросмотром на клиенте)
local Deployables = require(Shared:WaitForChild("Deployables"))
R.Place.OnServerEvent:Connect(function(p, toolId, cf)
	local st = state[p]
	local s = st and st.session
	local def = typeof(toolId) == "string" and Items.Tools[toolId]
	local hrp = hrpOf(p)
	if not s or not def or def.Kind ~= "deploy" or not table.find(st.tools, toolId) or typeof(cf) ~= "CFrame" or not hrp or st.downed then
		return
	end
	if (cf.Position - hrp.Position).Magnitude > 24 then
		return
	end
	-- только поворот вокруг вертикали
	local _, yaw = cf:ToEulerAnglesYXZ()
	cf = CFrame.new(cf.Position) * CFrame.Angles(0, yaw, 0)
	local size = Deployables.Size[def.Deploy]
	local op = OverlapParams.new()
	op.RespectCanCollide = true
	for _, part in ipairs(workspace:GetPartBoundsInBox(cf * CFrame.new(0, size.Y / 2 + 0.3, 0), size - V(0.3, 0.3, 0.3), op)) do
		if not part:IsA("Terrain") then
			notify(p, "Здесь не помещается: мешает " .. part.Name)
			return
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { p.Character }
	local g = workspace:Raycast(cf.Position + V(0, 2, 0), V(0, -5, 0), params)
	if not g then
		notify(p, "Ставить можно только на землю или пол")
		return
	end
	table.remove(st.tools, table.find(st.tools, toolId))
	if st.equipped == toolId then
		st.equipped = nil
		p:SetAttribute("Equipped", nil)
		updateHeld(p)
	end
	p:SetAttribute("Tools", HttpService:JSONEncode(st.tools))
	if def.Deploy == "workbench" then
		local b = World.BuildWorkbench(s.folder, cf)
		table.insert(s.benches, b)
		connectBench(s, b)
		notifySession(s, p.DisplayName .. " поставил верстак")
	elseif def.Deploy == "bed" then
		local bed, pr = Build.bed(s.folder, cf)
		connectBed(s, bed, pr)
		notify(p, "Кровать поставлена. Ночью ляг спать — если уснут все, ночь пройдёт.")
	elseif def.Deploy == "chest" then
		local chest, put, take = Build.chest(s.folder, cf)
		connectChest(s, chest, put, take)
		notify(p, "Сундук поставлен: E — положить всё, F — забрать всё.")
	end
	R.HitMarker:FireClient(p, "node", "axe")
end)

-- круговое меню молотка: сразу до выбранного уровня, или снести
R.Upgrade.OnServerEvent:Connect(function(p, piece, tier)
	local st = state[p]
	local s = st and st.session
	local hrp = hrpOf(p)
	if not s or not hrp or st.downed or st.equipped ~= "hammer" or typeof(piece) ~= "Instance" or not piece:IsDescendantOf(s.buildFolder) then
		return
	end
	local cf = piece:GetBoundingBox()
	if (cf.Position - hrp.Position).Magnitude > 20 then
		return
	end
	if tier == "remove" then
		local def = Building.ById[piece:GetAttribute("BKind")]
		for k, n in pairs(def and def.Cost or {}) do
			addRes(p, k, math.floor(n / 2))
		end
		s.pieces[piece:GetAttribute("Key")] = nil
		piece:Destroy()
		notify(p, "Снесено (вернулась половина досок)")
		return
	end
	local cur = piece:GetAttribute("Tier") or 0
	local t = typeof(tier) == "number" and Building.Tiers[tier]
	if not t or tier <= cur then
		notify(p, "Уже не хуже, чем «" .. Building.Tiers[cur].Name .. "»")
		return
	end
	for k, n in pairs(t.Cost) do
		if (st.res[k] or 0) < n then
			notify(p, "Для «" .. t.Name .. "» нужно: " .. Items.Resources[k].Name .. " " .. n)
			return
		end
	end
	for k, n in pairs(t.Cost) do
		addRes(p, k, -n)
	end
	Build.setTier(piece, tier, true)
	R.HitMarker:FireClient(p, "node", "axe")
	notify(p, piece.Name .. " → " .. t.Name)
end)

-- раненый подаёт сигнал: 15 секунд друзья видят, где он, и стрелки к нему
R.Ping.OnServerEvent:Connect(function(p)
	local st = state[p]
	if not st or not st.downed then
		return
	end
	local now = os.clock()
	if now - (st.lastPing or -100) < 20 then
		return
	end
	st.lastPing = now
	p:SetAttribute("PingUntil", workspace:GetServerTimeNow() + 15)
	p:SetAttribute("PingNext", workspace:GetServerTimeNow() + 20)
	for _, q in ipairs(st.session and st.session.players or {}) do
		if q ~= p then
			notify(q, p.DisplayName .. " зовёт на помощь! Иди по стрелкам.")
		end
	end
end)

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
			notify(p, "Нужен верстак рядом. Сделай его: C → Верстак, потом поставь.")
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
	-- инструмент того же вида, но лучше — уже есть
	local newDef = Items.Tools[r.Id]
	local function power(d)
		return d.Kind == "sword" and d.Damage or d.Tier
	end
	local unique = newDef and (newDef.Kind == "torch" or newDef.Kind == "deploy" or newDef.Kind == "blueprint" or newDef.Kind == "hammer")
	if newDef and not unique then
		for _, t in ipairs(st.tools) do
			local d = Items.Tools[t]
			if d and d.Kind == newDef.Kind and power(d) >= power(newDef) then
				notify(p, "У тебя уже есть лучше: " .. d.Name)
				return
			end
		end
	end
	if r.Armor and (st.armor or 0) >= r.Armor then
		notify(p, "У тебя уже есть броня не хуже")
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
	if r.Place then
		local look = hrp.CFrame.LookVector * V(1, 0, 1)
		local pos = hrp.Position + look.Unit * 7
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { p.Character }
		local hit = workspace:Raycast(pos + V(0, 6, 0), V(0, -30, 0), params)
		local ground = hit and hit.Position or (pos - V(0, 3, 0))
		local cf = CFrame.lookAt(ground, ground - look)
		if r.Place == "workbench" then
			local b = World.BuildWorkbench(s.folder, cf)
			table.insert(s.benches, b)
			connectBench(s, b)
			notifySession(s, p.DisplayName .. " поставил верстак")
		elseif r.Place == "bed" then
			local bed, pr = Build.bed(s.folder, cf)
			connectBed(s, bed, pr)
			notify(p, "Кровать поставлена. Ночью ляг спать — если уснут все, ночь пройдёт быстрее.")
		elseif r.Place == "chest" then
			local chest, put, take = Build.chest(s.folder, cf)
			connectChest(s, chest, put, take)
			notify(p, "Сундук поставлен: E — положить всё, F — забрать всё.")
		end
	elseif r.Id == "upgrade2" then
		bench.model:SetAttribute("Level", 2)
		bench.label.Text = "Верстак · ур. 2"
		notifySession(s, p.DisplayName .. " улучшил верстак до 2 уровня!")
	elseif r.Armor then
		giveArmor(p, r.Armor)
	elseif r.Res then
		addRes(p, r.Res, r.Amount or 1)
		notify(p, "Создано: " .. Items.Resources[r.Res].Name)
	else
		-- новый инструмент заменяет старый того же вида (каменная кирка вместо деревянной)
		local slot
		for i = #st.tools, 1, -1 do
			local d = Items.Tools[st.tools[i]]
			if d and newDef and d.Kind == newDef.Kind and not unique then
				if st.equipped == st.tools[i] then
					st.equipped = r.Id
				end
				table.remove(st.tools, i)
				slot = i
			end
		end
		table.insert(st.tools, slot or #st.tools + 1, r.Id)
		p:SetAttribute("Tools", HttpService:JSONEncode(st.tools))
		if st.equipped == r.Id then
			p:SetAttribute("Equipped", r.Id)
			updateHeld(p)
		end
		notify(p, "Создано: " .. Items.toolName(r.Id) .. (slot and " (заменил старый)" or (newDef and newDef.Kind == "deploy") and " — возьми в руку, R — повернуть, ЛКМ — поставить" or " (выбери цифрой)"))
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
			st.hidden, st.sleeping = nil, nil
			p:SetAttribute("Downed", false)
			p:SetAttribute("Hidden", false)
			p:SetAttribute("Sleeping", false)
			p:SetAttribute("InMatch", false)
			freshInventory(p)
			p:LoadCharacter()
		end
	end
	s.folder:Destroy()
	World.ClearTerrain(s.O, s.exit and s.exit.pit)
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

-- вернуть игрока в лобби (умер, и поднять некому)
function returnToLobby(p)
	local st = state[p]
	if not st then
		return
	end
	if st.revivePrompt then
		st.revivePrompt:Destroy()
		st.revivePrompt = nil
	end
	if st.dragPrompt then
		st.dragPrompt:Destroy()
		st.dragPrompt = nil
	end
	if st.draggedBy then
		stopDrag(st.draggedBy)
	end
	stopDrag(p)
	st.downed = false
	st.hidden, st.sleeping = nil, nil
	leaveSession(p)
	p:SetAttribute("Downed", false)
	p:SetAttribute("Hidden", false)
	p:SetAttribute("Sleeping", false)
	p:SetAttribute("InMatch", false)
	freshInventory(p)
	p:LoadCharacter()
end

-- упал в пропасть или в пустоту — возвращаем обратно
task.spawn(function()
	while true do
		task.wait(0.5)
		for _, p in ipairs(Players:GetPlayers()) do
			local st = state[p]
			local hrp = hrpOf(p)
			if st and hrp and not p:GetAttribute("Jailed") then
				local s = st.session
				local floorY = s and s.O.Y or World.LOBBY.Y
				if hrp.Position.Y < floorY - 30 then
					if s then
						local nearExit = s.exit and (hrp.Position - s.exit.exitOut.Position).Magnitude < 200
						if nearExit then
							place(p, s.exit.exitOut * CFrame.new(0, 4, 6), false)
						else
							place(p, s.clearing.liftSpawn, false)
						end
					else
						place(p, lobby.spawn.CFrame + V(0, 4, 0), false)
					end
					notify(p, "Ты упал! Возвращаем обратно.")
				end
			end
		end
	end
end)

-- карта лабиринта: стены отправляются клиентам (рисуются по Tab)
function sendMap(s)
	local walls = {}
	for _, w in ipairs(s.maze.mapWalls) do
		table.insert(walls, { w[1] == "X" and 1 or 2, math.floor(w[2] * 10) / 10, math.floor(w[3] * 10) / 10, math.floor(w[4] * 10) / 10, w[5] })
	end
	for _, q in ipairs(s.players) do
		R.MapData:FireClient(q, walls, s.O, World.CLEARING_HALF, World.RADIUS, s.exit.exitOut.Position - s.O)
	end
end

local function connectPrompts(s, root, chests)
	for _, pr in ipairs(root:GetDescendants()) do
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
			elseif CollectionService:HasTag(pr, "NotePrompt") then
				pr.Triggered:Connect(function(p)
					if sessionOf(p) == s then
						R.Note:FireClient(p, pr:GetAttribute("Title") or "Записка", pr:GetAttribute("Text") or "")
					end
				end)
			elseif CollectionService:HasTag(pr, "LootPrompt") then
				pr.Triggered:Connect(function(p)
					local st = state[p]
					if not st or st.session ~= s then
						return
					end
					if pr:GetAttribute("Looted") then
						notify(p, "Пусто")
						return
					end
					pr:SetAttribute("Looted", true)
					pr.Enabled = false
					local pool = { { "wood", 3, 6 }, { "stone", 3, 6 }, { "fiber", 2, 4 }, { "berry", 2, 3 }, { "bandage", 1, 1 }, { "iron", 1, 3 } }
					local got = {}
					for _ = 1, 2 do
						local e = pool[math.random(1, #pool)]
						local n = math.random(e[2], e[3])
						addRes(p, e[1], n)
						table.insert(got, "+" .. n .. " " .. Items.Resources[e[1]].Name)
					end
					notify(p, (pr.ObjectText ~= "" and pr.ObjectText or "Находка") .. ": " .. table.concat(got, ", "))
				end)
			elseif CollectionService:HasTag(pr, "MapPrompt") then
				pr.Triggered:Connect(function(p)
					local st = state[p]
					if not st or st.session ~= s or s.mazeFixed.mapFound then
						return
					end
					s.mazeFixed.mapFound = true
					pr.Parent:Destroy()
					for _, q in ipairs(s.players) do
						addRes(q, "map", 1)
					end
					sendMap(s)
					notifySession(s, p.DisplayName .. " нашёл КАРТУ ЛАБИРИНТА! Нажми Tab, чтобы открыть. Карта сама меняется вместе со стенами.")
				end)
			elseif CollectionService:HasTag(pr, "HidePrompt") then
				local spot = pr.Parent
				pr.Triggered:Connect(function(p)
					local st = state[p]
					if not st or st.session ~= s or st.downed then
						return
					end
					if st.hidden then
						unhide(p)
						return
					end
					if spot:GetAttribute("Occupied") then
						notify(p, "Тут уже кто-то прячется")
						return
					end
					local hrp, char = hrpOf(p)
					if not hrp then
						return
					end
					-- откуда залезли — туда и вылезем
					local flat = (hrp.Position - spot.Position) * V(1, 0, 1)
					spot:SetAttribute("Out", spot.Position * V(1, 0, 1) + V(0, hrp.Position.Y - 1, 0) + (flat.Magnitude > 0.1 and flat.Unit or V(0, 0, 1)) * 6)
					spot:SetAttribute("Occupied", true)
					st.hidden = spot
					p:SetAttribute("Hidden", true)
					pr.ActionText = "Вылезти"
					hrp.Anchored = true
					char:PivotTo(CFrame.lookAt(spot.Position, spot.Position - flat))
					notify(p, "Ты спрятался в лианах. Скрежетники тебя не видят. E — вылезти.")
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
	for _, c in ipairs(chests or {}) do
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
				s.mazeFixed.keyTaken = true
				gain("crystal", 3)
				gain("iron", 5)
				notifySession(s, p.DisplayName .. " нашёл КЛЮЧ-КАРТУ! Найдите выход и вставьте её в считыватель.")
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
				-- иногда в сундуке броня
				if math.random() < 0.12 then
					local tier = depth > 14 and 2 or 1
					if giveArmor(p, tier, true) then
						table.insert(got, Items.Armor[tier].Name)
					end
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
end

local function connectExit(s)
	local ex = s.exit
	-- подошёл к туннелю — ролик: идём по мосту к двери лаборатории
	ex.trigger.Touched:Connect(function(hit)
		local p = Players:GetPlayerFromCharacter(hit.Parent)
		local st = p and state[p]
		if not st or st.session ~= s or st.introSeen or st.downed or s.won then
			return
		end
		st.introSeen = true
		local hrp = hrpOf(p)
		if hrp then
			hrp.Anchored = true
		end
		R.ExitIntro:FireClient(p, ex.introPts, ex.reader.Position)
		task.delay(7.5, function()
			if st.session == s and not s.won then
				place(p, ex.doorFront, false)
			end
		end)
	end)
	ex.exitPrompt.Triggered:Connect(function(p)
		local st = state[p]
		if not st or st.session ~= s or s.won or st.downed then
			return
		end
		if (st.res.key or 0) < 1 then
			for _, q in ipairs(s.players) do
				if state[q] and (state[q].res.key or 0) > 0 then
					notify(p, "Ключ-карта у " .. q.DisplayName .. " — пусть приложит её сам.")
					return
				end
			end
			notify(p, "Нужна ключ-карта — она в золотом сундуке в самом дальнем тупике.")
			return
		end
		s.won = true
		clearMonsters(s, true)
		local hrp = hrpOf(p)
		if hrp then
			hrp.Anchored = true
		end
		R.CardInsert:FireClient(p, ex.reader.Position)
		task.delay(1.8, function()
			ex.readerLight.Color = Color3.fromRGB(60, 255, 90)
			notifySession(s, p.DisplayName .. " приложил ключ-карту! Дверь открывается...")
			TweenService:Create(ex.exitDoor, TweenInfo.new(3, Enum.EasingStyle.Sine), { CFrame = ex.exitDoor.CFrame + V(0, 15.5, 0) }):Play()
			local coins = Config.CoinsEscape * s.diff.Coins
			for _, q in ipairs(s.players) do
				addCoins(q, coins)
				local qh = hrpOf(q)
				if qh then
					qh.Anchored = true
				end
				R.Outro:FireClient(q, {
					exitOut = ex.exitOut,
					doorFront = ex.doorFront,
					doorEye = ex.doorEye,
					labStart = ex.labStart,
					labEnd = ex.labEnd,
					backDoor = ex.labBackDoor,
					pad = ex.helipad,
					mazeCenter = s.O,
					players = s.players,
					day = s.day,
					coins = coins,
				})
			end
			task.delay(48, function()
				endSession(s)
			end)
		end)
	end)
end

-- каждую ночь лабиринт перестраивается: другие коридоры, сундуки, шахты
local function regenMaze(s)
	local old = s.maze.model
	s.maze = World.BuildMazeLayout(s.folder, math.random(1, 1e6), s.O, s.mazeFixed)
	old:Destroy()
	connectPrompts(s, s.maze.model, s.maze.chests)
	sendMap(s)
	-- новые стены раздавили постройки — убираем их
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Include
	op.FilterDescendantsInstances = { s.maze.model }
	for key, piece in pairs(s.pieces) do
		if piece.Parent then
			local cf, size = piece:GetBoundingBox()
			for _, hitPart in ipairs(workspace:GetPartBoundsInBox(cf, size - V(0.5, 0.5, 0.5), op)) do
				if hitPart.Name == "MazeWall" then
					piece:Destroy()
					s.pieces[key] = nil
					break
				end
			end
		end
	end
	-- игроков, оказавшихся в стене, выталкиваем в ближайший коридор
	for _, q in ipairs(s.players) do
		local hrp = hrpOf(q)
		if hrp and not inSafeZone(s, hrp.Position) then
			R.MazeShift:FireClient(q)
			local stuck = false
			for _, hitPart in ipairs(workspace:GetPartBoundsInBox(hrp.CFrame, V(2, 4, 2), op)) do
				if hitPart.Name == "MazeWall" or hitPart.Name == "CrawlCover" then
					stuck = true
				end
			end
			if stuck then
				local best, bd
				for _, c in ipairs(s.maze.cells) do
					local d = (c - hrp.Position).Magnitude
					if not bd or d < bd then
						best, bd = c, d
					end
				end
				if best then
					place(q, CFrame.new(best + V(0, 4, 0)), false)
				end
			end
		end
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
	connectPrompts(s, s.clearing.model, {})
	connectPrompts(s, s.maze.model, s.maze.chests)
	connectExit(s)
end

local function sessionLoop(s)
	while not s.ended do
		setPhase(s, "day", s.diff.Day)
		for _, q in ipairs(s.players) do
			wake(q)
		end
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
		task.delay(9, function()
			if s.phase == "night" and not s.ended and not s.won then
				regenMaze(s)
				notifySession(s, "Земля дрожит... Стены лабиринта сдвинулись. Коридоры теперь другие.")
			end
		end)
		notifySession(s, "Ночь. Врата закрылись. В лабиринте — Скрежетники...")
		task.delay(11, function()
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
	s.pieces = {}
	s.buildFolder = Instance.new("Folder")
	s.buildFolder.Name = "Buildings"
	s.buildFolder.Parent = s.folder
	local seed = math.random(1, 1e6)
	World.BuildTerrain(O)
	s.clearing = World.BuildClearing(s.folder, seed, O)
	World.BuildClearingTerrain(O, s.clearing.lakeCenter)
	s.gates = World.BuildClearingWalls(s.folder, O)
	s.mazeFixed = { keyTaken = false, mapFound = false }
	s.maze = World.BuildMazeLayout(s.folder, seed + 7, O, s.mazeFixed)
	s.mazeFixed.exit = s.maze.exit
	s.exit = World.BuildExit(s.folder, O, s.maze.exit)
	World.BuildOuterForest(s.folder, O, seed, { s.exit.zone })
	connectSessionPrompts(s)
	for _, p in ipairs(riders) do
		local st = state[p]
		st.session = s
		st.introSeen = false
		st.downed = false
		freshInventory(p)
		p:SetAttribute("InMatch", true)
		p:SetAttribute("Difficulty", diffId)
		p:SetAttribute("SessionO", O)
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
	if st.dragPrompt then
		st.dragPrompt:Destroy()
		st.dragPrompt = nil
	end
	if st.draggedBy then
		stopDrag(st.draggedBy)
	end
	stopDrag(p)
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
			elseif action == "diff" and typeof(value) == "string" and Config.Difficulty[value] then
				lift.diff = value
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
					lift.diff = "normal"
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
				local dname = Config.Difficulty[lift.diff or "normal"].Name
				if lift.label then
					lift.label.Text = #allowed > 0 and (dname .. "  " .. #allowed .. "/" .. lift.max .. "  ·  " .. left .. "с") or "ЛИФТ"
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
						p:SetAttribute("LiftDiff", lift.diff or "normal")
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
						R.PlayElevator:FireClient(p, allowed, Config.Elevator.RideTime, lift.diff or "normal")
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
							startSession(riders, lift.diff or "normal")
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
	-- поза приседа видна всем: туловище ниже и наклонено, ноги согнуты
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local torso = char:FindFirstChild("Torso")
	local joints = {
		hrp and hrp:FindFirstChild("RootJoint"),
		torso and torso:FindFirstChild("Right Hip"),
		torso and torso:FindFirstChild("Left Hip"),
	}
	for k, j in ipairs(joints) do
		if j and j:IsA("Motor6D") then
			local c0 = j:GetAttribute("C0Base")
			if not c0 then
				c0 = j.C0
				j:SetAttribute("C0Base", c0)
			end
			if not on then
				j.C0 = c0
			elseif k == 1 then
				j.C0 = CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(-20), 0, 0) * c0
			else
				local pivot = c0.Position
				j.C0 = CFrame.new(pivot) * CFrame.Angles(math.rad(55), 0, 0) * CFrame.new(-pivot) * c0
			end
		end
	end
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
	hum.RequiresNeck = false
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
	task.delay(0.5, function()
		armorVisual(p)
		if p:GetAttribute("Invisible") then
			applyInvisible(p)
		end
		-- из тюрьмы не сбежать перезаходом в персонажа
		if p:GetAttribute("Jailed") then
			putInJail(p)
		end
	end)
	p:SetAttribute("Hidden", false)
	p:SetAttribute("Sleeping", false)
	st.hidden, st.sleeping = nil, nil
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
	local st = state[p]
	if st then
		stopDrag(p)
		if st.draggedBy then
			stopDrag(st.draggedBy)
		end
	end
	leaveSession(p)
	saveProfile(p)
	state[p] = nil
	profiles[p] = nil
end)

------------------------------------------------------------------
-- Тестовые кнопки
------------------------------------------------------------------
-- админ-панель: коды проверяются только на сервере
-- одна админ-панель (полная), код 3535
local ADMIN_CODES = { ["3535"] = 2 }
local adminTries = {}
R.Admin.OnServerEvent:Connect(function(p, code)
	local n = (adminTries[p] or 0) + 1
	adminTries[p] = n
	if n > 10 or typeof(code) ~= "string" then
		return
	end
	local lvl = ADMIN_CODES[code:gsub("%s", "")]
	if lvl and lvl > (p:GetAttribute("Admin") or 0) then
		p:SetAttribute("Admin", lvl)
	end
end)

------------------------------------------------------------------
-- Приколы главной админки
------------------------------------------------------------------
-- невидимость: ни тела, ни ника, монстры не трогают
function applyInvisible(p)
	local char = p.Character
	if not char then
		return
	end
	local on = p:GetAttribute("Invisible") == true
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") then
			if d:GetAttribute("T0") == nil then
				d:SetAttribute("T0", d.Transparency)
			end
			d.Transparency = on and 1 or d:GetAttribute("T0")
		end
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = on and Enum.HumanoidDisplayDistanceType.None or Enum.HumanoidDisplayDistanceType.Viewer
		hum.NameDisplayDistance = on and 0 or 100
	end
	p:SetAttribute("DevGhost", on)
end

-- тюрьма: каменная клетка далеко-далеко в пустоте
local JAIL = V(-6000, 400, -6000)
local function buildJail()
	local m = Instance.new("Model")
	m.Name = "Jail"
	local function box(cf, size, color, mat, transp)
		local pt = Instance.new("Part")
		pt.Anchored = true
		pt.Size = size
		pt.CFrame = cf
		pt.Color = color
		pt.Material = mat
		pt.Transparency = transp or 0
		pt.Parent = m
		return pt
	end
	local stone, dark = Color3.fromRGB(70, 70, 74), Color3.fromRGB(40, 40, 44)
	box(CFrame.new(JAIL), V(24, 2, 24), stone, Enum.Material.Slate)
	box(CFrame.new(JAIL + V(0, 16, 0)), V(24, 2, 24), stone, Enum.Material.Slate)
	for _, d in ipairs({ V(1, 0, 0), V(-1, 0, 0), V(0, 0, 1), V(0, 0, -1) }) do
		local wallCF = CFrame.new(JAIL + d * 11 + V(0, 8, 0))
		local size = d.X ~= 0 and V(2, 14, 24) or V(24, 14, 2)
		if d.Z == -1 then
			-- стена из решётки: всё видно, но не выйти
			box(wallCF, size, dark, Enum.Material.Glass, 0.7)
			for k = -10, 10, 2 do
				box(CFrame.new(JAIL + d * 11 + V(k, 8, 0)), V(0.4, 14, 0.4), dark, Enum.Material.Metal)
			end
		else
			box(wallCF, size, stone, Enum.Material.Slate)
		end
	end
	local lamp = box(CFrame.new(JAIL + V(0, 14.6, 0)), V(4, 0.4, 4), Color3.fromRGB(255, 230, 180), Enum.Material.Neon)
	local l = Instance.new("PointLight")
	l.Range = 24
	l.Parent = lamp
	local sign = box(CFrame.new(JAIL + V(0, 13, -9.8)), V(12, 2.4, 0.2), Color3.fromRGB(20, 20, 20), Enum.Material.SmoothPlastic)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.Parent = sign
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = Color3.fromRGB(255, 80, 70)
	t.Text = "ТЮРЬМА"
	t.Parent = sg
	m.Parent = workspace
end
buildJail()

function putInJail(p)
	local hrp = hrpOf(p)
	if hrp then
		place(p, CFrame.new(JAIL + V(0, 4, 0)), false)
	end
end

-- центр «главного острова»: поляна сессии админа или лобби
local function prankTarget(p)
	local s = sessionOf(p)
	if s then
		return s.O, s.players, s
	end
	local list = {}
	for _, q in ipairs(Players:GetPlayers()) do
		if not sessionOf(q) then
			table.insert(list, q)
		end
	end
	return World.LOBBY, list, nil
end

local function prankAll(list, kind, msg)
	for _, q in ipairs(list) do
		R.Prank:FireClient(q, kind)
		if msg then
			notify(q, msg)
		end
	end
end

local function nuke(p)
	local center, list = prankTarget(p)
	prankAll(list, "siren", "☢ ВНИМАНИЕ! ЯДЕРНЫЙ УДАР ЧЕРЕЗ 5 СЕКУНД! ☢")
	local folder = Instance.new("Folder")
	folder.Name = "Nuke"
	folder.Parent = workspace
	local rocket = Instance.new("Part")
	rocket.Anchored = true
	rocket.CanCollide = false
	rocket.Size = V(3, 12, 3)
	rocket.Color = Color3.fromRGB(60, 70, 60)
	rocket.Material = Enum.Material.Metal
	rocket.CFrame = CFrame.new(center + V(0, 500, 0))
	rocket.Parent = folder
	local fireTail = Instance.new("Fire")
	fireTail.Size = 8
	fireTail.Parent = rocket
	TweenService:Create(rocket, TweenInfo.new(5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(center + V(0, 8, 0)) }):Play()
	task.delay(5, function()
		rocket:Destroy()
		prankAll(list, "flash")
		local ex = Instance.new("Explosion")
		ex.Position = center + V(0, 5, 0)
		ex.BlastRadius = 90
		ex.BlastPressure = 250000
		ex.DestroyJointRadiusPercent = 0
		ex.Parent = workspace
		-- огненный шар и гриб
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Anchored = true
		ball.CanCollide = false
		ball.CanQuery = false
		ball.Material = Enum.Material.Neon
		ball.Color = Color3.fromRGB(255, 150, 40)
		ball.Size = V(10, 10, 10)
		ball.CFrame = CFrame.new(center + V(0, 10, 0))
		ball.Parent = folder
		TweenService:Create(ball, TweenInfo.new(3, Enum.EasingStyle.Quad), { Size = V(220, 220, 220), Transparency = 1 }):Play()
		local stem = Instance.new("Part")
		stem.Anchored = true
		stem.CanCollide = false
		stem.CanQuery = false
		stem.Material = Enum.Material.Slate
		stem.Color = Color3.fromRGB(120, 100, 90)
		stem.Size = V(20, 10, 20)
		stem.CFrame = CFrame.new(center + V(0, 5, 0))
		stem.Parent = folder
		TweenService:Create(stem, TweenInfo.new(5), { Size = V(30, 160, 30), CFrame = CFrame.new(center + V(0, 80, 0)) }):Play()
		local cap = Instance.new("Part")
		cap.Shape = Enum.PartType.Ball
		cap.Anchored = true
		cap.CanCollide = false
		cap.CanQuery = false
		cap.Material = Enum.Material.Slate
		cap.Color = Color3.fromRGB(150, 120, 100)
		cap.Size = V(30, 20, 30)
		cap.CFrame = CFrame.new(center + V(0, 20, 0))
		cap.Parent = folder
		TweenService:Create(cap, TweenInfo.new(5), { Size = V(140, 70, 140), CFrame = CFrame.new(center + V(0, 170, 0)) }):Play()
		task.delay(8, function()
			for _, d in ipairs(folder:GetChildren()) do
				if d:IsA("BasePart") then
					TweenService:Create(d, TweenInfo.new(4), { Transparency = 1 }):Play()
				end
			end
			task.delay(4.5, function()
				folder:Destroy()
			end)
		end)
	end)
end

local function tsunami(p)
	local center, list, s = prankTarget(p)
	if not s then
		notify(p, "Цунами работает только в матче (на поляне)")
		return
	end
	prankAll(list, "rumble", "🌊 ЦУНАМИ! Держитесь!")
	local E = World.CLEARING_HALF
	local wave = Instance.new("Part")
	wave.Anchored = true
	wave.CanCollide = false
	wave.CanQuery = false
	wave.Material = Enum.Material.Glass
	wave.Color = Color3.fromRGB(40, 110, 150)
	wave.Transparency = 0.25
	wave.Size = V(E * 2 + 60, 46, 26)
	local from, to = center + V(0, 23, -E - 40), center + V(0, 23, E + 40)
	wave.CFrame = CFrame.new(from)
	wave.Parent = workspace
	local foam = Instance.new("Part")
	foam.Anchored = true
	foam.CanCollide = false
	foam.CanQuery = false
	foam.Material = Enum.Material.Neon
	foam.Color = Color3.fromRGB(230, 245, 255)
	foam.Size = V(E * 2 + 60, 4, 30)
	foam.CFrame = CFrame.new(from + V(0, 24, 0))
	foam.Parent = workspace
	local t0 = os.clock()
	local dur = 9
	local hitBy = {}
	while true do
		local a = math.min(1, (os.clock() - t0) / dur)
		local pos = from:Lerp(to, a)
		wave.CFrame = CFrame.new(pos)
		foam.CFrame = CFrame.new(pos + V(0, 24, 0))
		for _, q in ipairs(list) do
			local hrp = hrpOf(q)
			if hrp and math.abs(hrp.Position.Z - pos.Z) < 16 and math.abs(hrp.Position.X - pos.X) < E + 30 and not hitBy[q] then
				hitBy[q] = true
				hrp.AssemblyLinearVelocity = V(0, 45, 90)
			end
		end
		if a >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end
	wave:Destroy()
	foam:Destroy()
	-- поляну затопило: настоящая вода, можно плавать
	local region = CFrame.new(center + V(0, 4, 0))
	pcall(function()
		workspace.Terrain:FillBlock(region, V(E * 2 - 8, 8, E * 2 - 8), Enum.Material.Water)
	end)
	prankAll(list, nil, "Поляну затопило! Вода уйдёт через 25 секунд.")
	task.delay(25, function()
		pcall(function()
			workspace.Terrain:FillBlock(region, V(E * 2 - 8, 8, E * 2 - 8), Enum.Material.Air)
		end)
	end)
end

-- денежный дождь: монеты падают на центр, кто подобрал — тому монеты по-настоящему
local function moneyRain(p)
	local center, list = prankTarget(p)
	prankAll(list, "coins", "💰 С неба падают монеты! Собирай у центра!")
	local folder = Instance.new("Folder")
	folder.Name = "MoneyRain"
	folder.Parent = workspace
	task.spawn(function()
		for _ = 1, 45 do
			local a, r = math.random() * math.pi * 2, 6 + math.random() * 30
			local c = Instance.new("Part")
			c.Name = "RainCoin"
			c.Shape = Enum.PartType.Cylinder
			c.Size = V(0.4, 2.4, 2.4)
			c.Color = Color3.fromRGB(255, 205, 60)
			c.Material = Enum.Material.Neon
			c.CFrame = CFrame.new(center + V(math.cos(a) * r, 70 + math.random() * 30, math.sin(a) * r)) * CFrame.Angles(0, 0, math.pi / 2)
			c.Parent = folder
			local taken = false
			c.Touched:Connect(function(hit)
				local q = Players:GetPlayerFromCharacter(hit.Parent)
				if q and not taken then
					taken = true
					addCoins(q, 10)
					notify(q, "+10 монет!")
					c:Destroy()
				end
			end)
			task.wait(0.15)
		end
	end)
	task.delay(45, function()
		folder:Destroy()
	end)
end

R.Dev.OnServerEvent:Connect(function(p, action, value)
	local lvl = p:GetAttribute("Admin") or 0
	if not Config.DevTools or lvl < 1 then
		return
	end
	local s = sessionOf(p)
	-- уровень 1 (друзья)
	if action == "ghost" and typeof(value) == "boolean" then
		p:SetAttribute("DevGhost", value)
	elseif action == "phase" and s then
		s.skip = true
	elseif action == "res" then
		for k in pairs(Items.Resources) do
			addRes(p, k, k == "key" and 1 or 30)
		end
		notify(p, "[Админ] +30 всех ресурсов и Ключ")
	elseif action == "toexit" and s and s.exit then
		place(p, s.exit.exitOut * CFrame.new(0, 4, 8), false)
	elseif lvl < 2 then
		return
	-- уровень 2 (главная)
	elseif action == "coins" then
		addCoins(p, 500)
	elseif action == "down" and s then
		down(p)
	elseif action == "invisible" then
		p:SetAttribute("Invisible", not p:GetAttribute("Invisible"))
		applyInvisible(p)
		notify(p, p:GetAttribute("Invisible") and "Ты невидим: ни тела, ни ника" or "Ты снова видим")
	elseif action == "tpto" and typeof(value) == "number" then
		local target = Players:GetPlayerByUserId(value)
		local th = target and hrpOf(target)
		if th then
			place(p, th.CFrame * CFrame.new(0, 0, 6), false)
		end
	elseif action == "bring" and typeof(value) == "number" then
		-- телепортировать игрока к себе
		local target = Players:GetPlayerByUserId(value)
		local mh = hrpOf(p)
		if target and target ~= p and mh and not target:GetAttribute("Jailed") then
			place(target, mh.CFrame * CFrame.new(0, 0, -6), false)
			notify(target, "Админ телепортировал тебя к себе")
		end
	elseif action == "kick" and typeof(value) == "number" then
		-- выгнать с сервера (зайти снова можно)
		local target = Players:GetPlayerByUserId(value)
		if target and target ~= p then
			target:Kick("Тебя выгнал админ. Можешь зайти снова.")
		end
	elseif action == "jail" and typeof(value) == "number" then
		-- посадить в тюрьму / выпустить
		local target = Players:GetPlayerByUserId(value)
		if target and target ~= p then
			if target:GetAttribute("Jailed") then
				target:SetAttribute("Jailed", false)
				target:LoadCharacter()
				notify(target, "Тебя выпустили из тюрьмы!")
				notify(p, target.DisplayName .. " на свободе")
			else
				leaveSession(target)
				local tst = state[target]
				if tst then
					tst.downed = false
				end
				target:SetAttribute("InMatch", false)
				target:SetAttribute("Downed", false)
				target:SetAttribute("Jailed", true)
				-- новый персонаж сразу появится в тюрьме
				target:LoadCharacter()
				notify(target, "Админ посадил тебя в тюрьму!")
				notify(p, target.DisplayName .. " в тюрьме")
			end
		end
	elseif action == "nuke" then
		nuke(p)
	elseif action == "tsunami" then
		task.spawn(tsunami, p)
	elseif action == "money" then
		moneyRain(p)
	end
end)
