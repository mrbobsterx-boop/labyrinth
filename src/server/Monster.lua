-- Скрежетник — ночной монстр лабиринта. Патрулирует, видит и слышит игроков,
-- гонится, бьёт когтями. Не заходит на поляну.

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local S = Config.Monster

local Monster = {}
Monster.__index = Monster

local V = Vector3.new
local RGB = Color3.fromRGB
local SKIN = RGB(26, 24, 28)
local EYE = RGB(140, 255, 120)

local function weld(part, base)
	local w = Instance.new("WeldConstraint")
	w.Part0 = base
	w.Part1 = part
	w.Parent = part
end

local function add(model, name, size, cf, color, material, base)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	weld(p, base)
	return p
end

local function buildRig()
	local ok, rig = pcall(function()
		local d = Instance.new("HumanoidDescription")
		d.HeightScale = 1.55
		d.WidthScale = 1.25
		d.DepthScale = 1.2
		d.HeadScale = 1.1
		d.BodyTypeScale = 0.6
		d.ProportionScale = 1
		for _, k in ipairs({ "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" }) do
			d[k] = SKIN
		end
		return Players:CreateHumanoidModelFromDescription(d, Enum.HumanoidRigType.R15)
	end)
	if ok and rig and rig:FindFirstChild("HumanoidRootPart") then
		return rig, true
	end
	-- запасная модель
	local m = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = V(3, 3, 1.5)
	root.Transparency = 1
	root.CanCollide = false
	root.Parent = m
	m.PrimaryPart = root
	local torso = add(m, "UpperTorso", V(3.4, 4, 1.8), root.CFrame * CFrame.new(0, 1, 0), SKIN, nil, root)
	torso.CanCollide = true
	torso.Massless = false
	add(m, "Head", V(1.8, 1.8, 1.8), root.CFrame * CFrame.new(0, 4, 0), SKIN, nil, root)
	for _, sx in ipairs({ -1, 1 }) do
		add(m, "Leg", V(1.2, 4.5, 1.2), root.CFrame * CFrame.new(0.9 * sx, -3.7, 0), SKIN, nil, root)
		add(m, sx < 0 and "LeftHand" or "RightHand", V(1, 5, 1), root.CFrame * CFrame.new(2.4 * sx, 0.3, 0), SKIN, nil, root)
	end
	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.HipHeight = 4.5
	hum.Parent = m
	return m, false
end

local function decorate(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Decal") then
			d:Destroy()
		end
	end
	local head = model:FindFirstChild("Head")
	if head then
		local hs = head.Size
		-- вытянутая морда и три светящихся глаза
		add(model, "Snout", V(hs.X * 0.6, hs.Y * 0.45, hs.Z * 0.7), head.CFrame * CFrame.new(0, -hs.Y * 0.2, -hs.Z * 0.6), SKIN, Enum.Material.Slate, head)
		for k, x in ipairs({ -0.28, 0, 0.28 }) do
			add(model, "Eye", V(0.18, 0.18, 0.06), head.CFrame * CFrame.new(x * hs.X, hs.Y * 0.12 + (k == 2 and 0.18 or 0), -hs.Z / 2 - 0.03), EYE, Enum.Material.Neon, head)
		end
		local glow = Instance.new("PointLight")
		glow.Color = EYE
		glow.Range = 9
		glow.Brightness = 1.2
		glow.Parent = head
		-- рога
		for _, sx in ipairs({ -1, 1 }) do
			add(model, "Horn", V(0.3, 1.6, 0.3), head.CFrame * CFrame.new(sx * hs.X * 0.35, hs.Y * 0.7, hs.Z * 0.1) * CFrame.Angles(math.rad(-25), 0, math.rad(-20 * sx)), RGB(60, 55, 50), Enum.Material.Slate, head)
		end
	end
	local torso = model:FindFirstChild("UpperTorso")
	if torso then
		-- шипы вдоль спины и бронепластины
		for k = 0, 4 do
			add(model, "Spike", V(0.35, 1.4 - k * 0.15, 0.35), torso.CFrame * CFrame.new(0, torso.Size.Y * 0.45 - k * 0.55, torso.Size.Z / 2 + 0.3) * CFrame.Angles(math.rad(35), 0, 0), RGB(70, 66, 60), Enum.Material.Slate, torso)
		end
		add(model, "ChestPlate", V(torso.Size.X * 0.9, torso.Size.Y * 0.55, 0.25), torso.CFrame * CFrame.new(0, 0.2, -torso.Size.Z / 2 - 0.1), RGB(50, 48, 46), Enum.Material.CorrodedMetal, torso)
	end
	-- когти
	for _, name in ipairs({ "LeftHand", "RightHand" }) do
		local hand = model:FindFirstChild(name)
		if hand then
			for k = -1, 1 do
				add(model, "Claw", V(0.12, 1.3, 0.12), hand.CFrame * CFrame.new(k * 0.22, -hand.Size.Y / 2 - 0.5, -0.1) * CFrame.Angles(math.rad(-15), 0, 0), RGB(210, 205, 190), Enum.Material.SmoothPlastic, hand)
			end
		end
	end
end

-- opts: parent, spawn (CFrame), patrol ({Vector3}), getPlayers(), inSafeZone(pos) -> bool,
-- damage(player, amount), health, speed, dmg
function Monster.new(opts)
	local self = setmetatable({}, Monster)
	self.opts = opts
	self.maxHealth = opts.health or 260
	self.chaseSpeed = opts.speed or 19
	self.dmg = opts.dmg or 22
	self.alive = true
	self.state = "patrol"
	self.lastAttack = 0
	local model, real = buildRig()
	model.Name = S.Name
	decorate(model)
	self.model = model
	self.humanoid = model:FindFirstChildOfClass("Humanoid")
	self.root = model:FindFirstChild("HumanoidRootPart")
	self.head = model:FindFirstChild("Head") or self.root
	local hum = self.humanoid
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	hum.MaxHealth = self.maxHealth
	hum.Health = self.maxHealth
	hum.WalkSpeed = S.PatrolSpeed
	model:SetAttribute("MaxHP", self.maxHealth)
	model:SetAttribute("HP", self.maxHealth)
	model:PivotTo(opts.spawn)
	model.Parent = opts.parent
	CollectionService:AddTag(model, "Monster")
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not d.Anchored then
			pcall(function()
				d:SetNetworkOwner(nil)
			end)
		end
	end
	self.path = PathfindingService:CreatePath({ AgentRadius = 3, AgentHeight = 9, AgentCanJump = false, WaypointSpacing = 6 })

	-- шаги и рычание
	local step = Instance.new("Sound")
	step.SoundId = Config.Sounds.Step
	step.Looped = true
	step.Volume = 1.4
	step.PlaybackSpeed = 0.45
	step.RollOffMaxDistance = 80
	step.Parent = self.root
	self.step = step
	if real then
		local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
		animator.Parent = hum
		local function load(id)
			local a = Instance.new("Animation")
			a.AnimationId = id
			local ok, t = pcall(function()
				return animator:LoadAnimation(a)
			end)
			return ok and t or nil
		end
		self.tracks = { walk = load(Config.Animations.Walk), run = load(Config.Animations.Run) }
	end
	hum.Running:Connect(function(speed)
		local moving = speed > 0.5
		if moving and not step.IsPlaying then
			step:Play()
		elseif not moving then
			step:Stop()
		end
		if self.tracks then
			local want = moving and ((speed > 14 and self.tracks.run) or self.tracks.walk) or nil
			if want ~= self.current then
				if self.current then
					self.current:Stop(0.2)
				end
				if want then
					want:Play(0.2)
				end
				self.current = want
			end
		end
	end)
	task.spawn(function()
		self:Loop()
	end)
	return self
end

function Monster:LineOfSight(from, to, char)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { self.model }
	local r = workspace:Raycast(from, to - from, params)
	return r == nil or r.Instance:IsDescendantOf(char)
end

function Monster:Navigate(goal)
	local pos = self.root.Position
	local flat = V(goal.X - pos.X, 0, goal.Z - pos.Z)
	if flat.Magnitude < 4 then
		self.humanoid:MoveTo(pos)
		self.waypoints = nil
		return true
	end
	local now = os.clock()
	if not self.waypoints or (self.goal - goal).Magnitude > 6 or now - self.pathTime > 2 then
		self.goal, self.pathTime = goal, now
		local ok = pcall(function()
			self.path:ComputeAsync(pos, goal)
		end)
		if ok and self.path.Status == Enum.PathStatus.Success then
			self.waypoints, self.wp = self.path:GetWaypoints(), 2
		else
			self.waypoints = nil
		end
	end
	if self.waypoints and self.waypoints[self.wp] then
		local w = self.waypoints[self.wp]
		if V(w.Position.X - pos.X, 0, w.Position.Z - pos.Z).Magnitude < 3 then
			self.wp += 1
			w = self.waypoints[self.wp] or w
		end
		self.humanoid:MoveTo(w.Position)
	else
		self.humanoid:MoveTo(goal)
	end
	return false
end

function Monster:Think()
	local now = os.clock()
	local best, bestD
	for _, p in ipairs(self.opts.getPlayers()) do
		local char = p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 and p:GetAttribute("DevGhost") ~= true and p:GetAttribute("Downed") ~= true and not self.opts.inSafeZone(hrp.Position) then
			local d = (hrp.Position - self.root.Position).Magnitude
			local sees = d < S.SightRange and self:LineOfSight(self.head.Position, hrp.Position, char)
			local hears = d < S.HearRange and hrp.AssemblyLinearVelocity.Magnitude > 18
			if (sees or hears) and (not best or d < bestD) then
				best, bestD = p, d
			end
		end
	end

	if best then
		self.state = "chase"
		self.target = best
		self.lastSeen = now
	elseif self.state == "chase" and now - (self.lastSeen or 0) > 5 then
		self.state = "patrol"
		self.patrolGoal = nil
	end

	if self.state == "chase" and self.target and self.target.Character then
		local hrp = self.target.Character:FindFirstChild("HumanoidRootPart")
		if not hrp or self.opts.inSafeZone(hrp.Position) or self.target:GetAttribute("Downed") == true then
			self.state = "patrol"
			return
		end
		self.humanoid.WalkSpeed = self.chaseSpeed
		local d = (hrp.Position - self.root.Position).Magnitude
		if d < S.AttackRange and now - self.lastAttack > S.AttackCooldown then
			self.lastAttack = now
			self:Attack(self.target)
		end
		if d < 16 then
			self.waypoints = nil
			self.humanoid:MoveTo(hrp.Position)
		else
			self:Navigate(hrp.Position)
		end
		return
	end

	self.humanoid.WalkSpeed = S.PatrolSpeed
	if not self.patrolGoal or now - (self.patrolSince or 0) > 30 then
		local cells = self.opts.patrol
		self.patrolGoal = cells[math.random(1, #cells)]
		self.patrolSince = now
	end
	if self:Navigate(self.patrolGoal) then
		self.patrolGoal = nil
	end
end

function Monster:Attack(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	-- рывок вперёд
	local root = self.root
	local look = (char.HumanoidRootPart.Position - root.Position) * V(1, 0, 1)
	if look.Magnitude > 0.1 then
		self.model:PivotTo(CFrame.lookAt(root.Position, root.Position + look))
	end
	self.opts.damage(player, self.dmg)
end

function Monster:TakeDamage(amount, fromPos)
	if not self.alive then
		return
	end
	local hum = self.humanoid
	hum.Health = math.max(0, hum.Health - amount)
	self.model:SetAttribute("HP", hum.Health)
	-- вспышка красным
	for _, d in ipairs(self.model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Eye" and d.Transparency < 1 then
			local old = d.Color
			d.Color = RGB(200, 40, 40)
			task.delay(0.12, function()
				if d.Parent then
					d.Color = old
				end
			end)
		end
	end
	-- отброс
	if fromPos then
		local dir = (self.root.Position - fromPos) * V(1, 0, 1)
		if dir.Magnitude > 0.1 then
			self.root.AssemblyLinearVelocity = dir.Unit * 30 + V(0, 8, 0)
		end
	end
	self.state = "chase"
	self.lastSeen = os.clock()
	if hum.Health <= 0 then
		self:Die()
		return true
	end
	return false
end

-- исчезает (утро или смерть)
function Monster:Die(retreat)
	if not self.alive then
		return
	end
	self.alive = false
	self.step:Stop()
	self.humanoid:MoveTo(self.root.Position)
	for _, d in ipairs(self.model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			TweenService:Create(d, TweenInfo.new(retreat and 2.5 or 1.2), { Transparency = 1, CFrame = d.CFrame - V(0, retreat and 8 or 3, 0) }):Play()
		elseif d:IsA("PointLight") then
			d.Enabled = false
		end
	end
	task.delay(3, function()
		self.model:Destroy()
	end)
end

function Monster:Loop()
	while self.alive and self.model.Parent do
		task.wait(0.15)
		if self.alive then
			local ok, err = pcall(function()
				self:Think()
			end)
			if not ok then
				warn("[Labyrinth] Ошибка ИИ:", err)
			end
		end
	end
end

return Monster
