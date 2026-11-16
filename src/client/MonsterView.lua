-- Внешний вид Скрежетника (рисуется на клиенте): тело-слизень, костяные шипы,
-- 8 механических ног с настоящей походкой (каждая нога сама ищет, куда наступить),
-- хвост с жалом. В узком месте ноги поджимаются и поднимаются выше, чтобы не
-- проходить сквозь стены. Сервер управляет только невидимым корпусом.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local MonsterView = {}

local V = Vector3.new
local RGB = Color3.fromRGB
local UP = V(0, 1, 0)

local FLESH = RGB(118, 124, 92)
local FLESH2 = RGB(92, 98, 72)
local METAL = RGB(38, 40, 44)
local BONE = RGB(200, 196, 176)
local GLOW = RGB(90, 170, 255)

local GROUND = 5.6 -- от центра корпуса до земли
local L1, L2 = 7.5, 8.5 -- бедро и голень
local HIPS = { -3.6, -1.3, 1.3, 3.6 }

local folder = Instance.new("Folder")
folder.Name = "MonsterViews"
folder.Parent = workspace

local views = {}

local function newPart(model, size, color, material, shape)
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function build(monster)
	local root = monster:WaitForChild("HumanoidRootPart", 5)
	if not root then
		return
	end
	local m = Instance.new("Model")
	m.Name = "Grieverview"
	m.Parent = folder
	local v = { monster = monster, root = root, model = m, body = {}, legs = {}, tail = {}, parts = {}, t = math.random() * 10 }

	local function body(size, color, material, cf, shape, refl)
		local p = newPart(m, size, color, material, shape)
		p.Reflectance = refl or 0
		table.insert(v.body, { part = p, cf = cf })
		return p
	end
	local ball = Enum.PartType.Ball
	-- тело-слизень: несколько влажных «сегментов»
	body(V(7.4, 7.4, 7.4), FLESH, nil, CFrame.new(0, 1.2, 3.2), ball, 0.12)
	body(V(6.6, 6.6, 6.6), FLESH2, nil, CFrame.new(0, 1.5, 0), ball, 0.12)
	body(V(5.4, 5.4, 5.4), FLESH, nil, CFrame.new(0, 1.5, -3.2), ball, 0.12)
	body(V(4.2, 4.2, 4.2), FLESH2, nil, CFrame.new(0, 1.2, -5.8), ball, 0.1)
	-- вены
	for k = 1, 6 do
		local a = k * 1.05
		body(V(0.18, 0.18, 4.5), RGB(70, 30, 40), nil, CFrame.new(math.sin(a) * 3.3, 1.4 + math.cos(a) * 3.2, 1.5) * CFrame.Angles(0, 0, a))
	end
	-- металлические пластины и шипы на спине
	for k = 0, 6 do
		local z = -4 + k * 1.35
		local h = 2.6 + (k % 2) * 1.2
		body(V(0.35, h, 0.35), METAL, Enum.Material.Metal, CFrame.new(((k % 2) * 2 - 1) * 0.8, 4.4 + h / 2 - 0.6, z) * CFrame.Angles(math.rad(-25), 0, math.rad(((k % 2) * 2 - 1) * 12)))
	end
	body(V(3.2, 0.4, 5), METAL, Enum.Material.DiamondPlate, CFrame.new(0, 4.6, -1) * CFrame.Angles(math.rad(-6), 0, 0))
	-- голова: пасть с зубами и синий «глаз»-огонёк
	body(V(2.6, 1.6, 1.4), RGB(20, 10, 12), nil, CFrame.new(0, 0.6, -7.6))
	for k = -2, 2 do
		body(V(0.25, 0.9, 0.25), BONE, nil, CFrame.new(k * 0.5, 1.3, -8.15) * CFrame.Angles(0, 0, math.rad(180)))
		body(V(0.22, 0.7, 0.22), BONE, nil, CFrame.new(k * 0.5 + 0.25, -0.05, -8.15))
	end
	local eye = body(V(0.8, 0.8, 0.8), GLOW, Enum.Material.Neon, CFrame.new(1.2, 3.1, -6.2), ball)
	local light = Instance.new("PointLight")
	light.Color = GLOW
	light.Range = 16
	light.Brightness = 2
	light.Parent = eye
	for k = -1, 1, 2 do
		body(V(0.35, 0.35, 0.35), RGB(160, 255, 120), Enum.Material.Neon, CFrame.new(k * 0.9, 2.2, -7.6), ball)
	end
	-- ноги
	for side = -1, 1, 2 do
		for i, z in ipairs(HIPS) do
			local leg = {
				side = side,
				z = z,
				group = ((i + (side > 0 and 1 or 0)) % 2),
				femur = newPart(m, V(0.7, 0.7, L1), METAL, Enum.Material.Metal),
				tibia = newPart(m, V(0.45, 0.45, L2), METAL, Enum.Material.Metal),
				knee = newPart(m, V(1.1, 1.1, 1.1), RGB(25, 25, 28), Enum.Material.Metal, ball),
				hip = newPart(m, V(1.2, 1.2, 1.2), FLESH2, nil, ball),
				claw = newPart(m, V(0.3, 0.3, 1.8), BONE),
				spike = newPart(m, V(0.25, 0.25, 1.6), METAL, Enum.Material.Metal),
			}
			table.insert(v.legs, leg)
		end
	end
	-- хвост с жалом
	for k = 1, 8 do
		local s = 1.25 - k * 0.09
		local p = newPart(m, V(s, s, 1.8), k % 2 == 0 and METAL or FLESH2, k % 2 == 0 and Enum.Material.Metal or nil)
		table.insert(v.tail, p)
	end
	v.sting = newPart(m, V(0.3, 0.3, 2.4), RGB(150, 20, 30), Enum.Material.Neon)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(v.parts, d)
			d:SetAttribute("C0", d.Color)
		end
	end
	v.room = { [-1] = 9, [1] = 9 }
	v.roomT = 0
	v.attacks = monster:GetAttribute("Attacks") or 0
	monster:GetAttributeChangedSignal("Attacks"):Connect(function()
		v.attackT = 0
	end)
	monster:GetAttributeChangedSignal("Flash"):Connect(function()
		for _, p in ipairs(v.parts) do
			if p.Material ~= Enum.Material.Neon then
				p.Color = RGB(200, 40, 40)
			end
		end
		task.delay(0.12, function()
			for _, p in ipairs(v.parts) do
				p.Color = p:GetAttribute("C0")
			end
		end)
	end)
	views[monster] = v
end

local function rayParams(v)
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local list = { v.monster, folder }
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(list, pl.Character)
		end
	end
	p.FilterDescendantsInstances = list
	p.IgnoreWater = true
	return p
end

local function seg(_, a, b)
	local len = (b - a).Magnitude
	if len < 0.01 then
		return CFrame.new(a)
	end
	return CFrame.lookAt(a, b) * CFrame.new(0, 0, -len / 2)
end

local function solveKnee(hip, foot, out)
	local dir = foot - hip
	local d = math.clamp(dir.Magnitude, 0.5, L1 + L2 - 0.05)
	local u = dir.Unit
	local a = (L1 * L1 - L2 * L2 + d * d) / (2 * d)
	local h = math.sqrt(math.max(0, L1 * L1 - a * a))
	local pole = UP + out
	local perp = pole - u * pole:Dot(u)
	if perp.Magnitude < 0.01 then
		perp = UP
	end
	return hip + u * a + perp.Unit * h, hip + u * d
end

local function update(v, dt)
	local root = v.root
	if not root.Parent then
		return
	end
	v.t += dt
	local cf = root.CFrame
	local vel = root.AssemblyLinearVelocity * V(1, 0, 1)
	local speed = vel.Magnitude
	local params = v.params

	-- сколько места по бокам (раз в 0.2 c)
	v.roomT -= dt
	if v.roomT <= 0 or not params then
		v.roomT = 0.2
		params = rayParams(v)
		v.params = params
		for side = -1, 1, 2 do
			local r = workspace:Raycast(cf.Position, cf.RightVector * side * 14, params)
			local room = r and (r.Position - cf.Position).Magnitude or 14
			v.room[side] = math.clamp(room - 1.6, 3.4, 9)
		end
	end

	-- тело: покачивание и дыхание, выпад при атаке
	local lunge = 0
	if v.attackT then
		v.attackT += dt / 0.45
		if v.attackT >= 1 then
			v.attackT = nil
		else
			lunge = math.sin(v.attackT * math.pi)
		end
	end
	local bob = math.sin(v.t * (speed > 1 and 9 or 2)) * (speed > 1 and 0.25 or 0.12)
	local bodyCF = cf * CFrame.new(0, bob, -lunge * 2) * CFrame.Angles(lunge * 0.25, 0, math.sin(v.t * 4.5) * 0.03 * math.min(speed, 10) / 10)
	local parts, cfs = {}, {}
	local function put(p, c)
		table.insert(parts, p)
		table.insert(cfs, c)
	end
	for _, b in ipairs(v.body) do
		put(b.part, bodyCF * b.cf)
	end

	-- ноги
	local stepping = { [0] = 0, [1] = 0 }
	for _, leg in ipairs(v.legs) do
		if leg.stepT then
			stepping[leg.group] += 1
		end
	end
	local stepLen = speed > 12 and 5 or 3.6
	local stepTime = speed > 12 and 0.13 or 0.2
	for _, leg in ipairs(v.legs) do
		local out = v.room[leg.side]
		local hip = (bodyCF * CFrame.new(leg.side * 2.4, 1.8, leg.z)).Position
		-- где нога хочет стоять
		local restLocal = V(leg.side * out, 0, leg.z * 1.45)
		local rest = (cf * CFrame.new(restLocal)).Position + vel * 0.12
		local flat = V(rest.X, cf.Position.Y, rest.Z)
		local toRest = flat - cf.Position
		local r = toRest.Magnitude > 0.1 and workspace:Raycast(cf.Position, toRest, params)
		if r then
			flat = r.Position - toRest.Unit * 1.2
		end
		local g = workspace:Raycast(flat + V(0, 1, 0), V(0, -14, 0), params)
		local target = g and g.Position or (flat - V(0, GROUND, 0))
		if not leg.foot then
			leg.foot = target
		end
		if not leg.stepT and stepping[1 - leg.group] == 0 and (leg.foot - target).Magnitude > stepLen then
			leg.stepT, leg.from = 0, leg.foot
			stepping[leg.group] += 1
		end
		local foot = leg.foot
		if leg.stepT then
			leg.stepT += dt / stepTime
			local a = math.min(1, leg.stepT)
			foot = leg.from:Lerp(target, a) + V(0, math.sin(a * math.pi) * 2.6, 0)
			if a >= 1 then
				leg.stepT = nil
				leg.foot = target
				foot = target
			end
		end
		-- передние ноги поднимаются для удара
		if lunge > 0 and leg.z == HIPS[1] then
			foot = foot:Lerp((bodyCF * CFrame.new(leg.side * 2, 5, -9)).Position, lunge)
		end
		local outDir = cf.RightVector * leg.side * (out / 9) * 0.7
		local knee, tip = solveKnee(hip, foot, outDir)
		put(leg.femur, seg(leg.femur, hip, knee))
		put(leg.tibia, seg(leg.tibia, knee, tip))
		put(leg.knee, CFrame.new(knee))
		put(leg.hip, CFrame.new(hip))
		put(leg.claw, seg(leg.claw, tip + V(0, 1.4, 0) + (tip - knee).Unit * 0.2, tip - V(0, 0.4, 0)))
		put(leg.spike, CFrame.lookAt(knee, knee + UP + outDir) * CFrame.new(0, 0, -0.8))
	end

	-- хвост: загибается вверх и вперёд, жало покачивается
	local p = (bodyCF * CFrame.new(0, 3.2, 6.2)).Position
	local back = bodyCF.LookVector * -1
	for k, part in ipairs(v.tail) do
		local ang = k * 0.32 + math.sin(v.t * 2 + k * 0.6) * 0.08 + lunge * 0.4
		local dir = (back * math.cos(ang) + UP * math.sin(ang) * 1.3).Unit
		if k > 5 then
			dir = (dir - back * (k - 5) * 0.6).Unit
		end
		local q = p + dir * 1.6
		put(part, seg(part, p, q))
		p = q
	end
	put(v.sting, CFrame.lookAt(p, p + (bodyCF.LookVector + UP * 0.3).Unit) * CFrame.new(0, 0, -1.1))

	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

local function fade(v, mode)
	if v.dying then
		return
	end
	v.dying = true
	local t0 = os.clock()
	local dur = mode == "retreat" and 2.5 or 1.2
	task.spawn(function()
		while v.model.Parent do
			local a = math.min(1, (os.clock() - t0) / dur)
			for _, p in ipairs(v.parts) do
				p.Transparency = a
			end
			if a >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
	end)
end

function MonsterView.start()
	local function added(monster)
		if monster:IsA("Model") and not views[monster] then
			task.spawn(function()
				local ok, err = pcall(build, monster)
				if not ok then
					warn("[Labyrinth] MonsterView:", err)
				end
			end)
		end
	end
	for _, m in ipairs(CollectionService:GetTagged("Monster")) do
		added(m)
	end
	CollectionService:GetInstanceAddedSignal("Monster"):Connect(added)
	RunService.RenderStepped:Connect(function(dt)
		local cam = workspace.CurrentCamera
		for monster, v in pairs(views) do
			if not monster.Parent then
				v.model:Destroy()
				views[monster] = nil
			else
				if monster:GetAttribute("Dead") then
					fade(v, monster:GetAttribute("Dead"))
				end
				local far = cam and (v.root.Position - cam.CFrame.Position).Magnitude > 400
				if not far then
					local ok, err = pcall(update, v, dt)
					if not ok and not v.warned then
						v.warned = true
						warn("[Labyrinth] MonsterView:", err)
					end
				end
			end
		end
	end)
end

return MonsterView
