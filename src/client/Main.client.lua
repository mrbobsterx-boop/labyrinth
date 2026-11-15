-- Клиент «ЛАБИРИНТ»: интерфейс, прицел, руки, удары, тряска камеры, верстак, лифт, победа.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local SoundService = game:GetService("SoundService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Viewmodel = require(script.Parent:WaitForChild("Viewmodel"))

local function remote(n)
	return Remotes:WaitForChild(n)
end

local V = Vector3.new
local RGB = Color3.fromRGB
local UI_FONT = Enum.Font.GothamBold
local TEXT_FONT = Enum.Font.Gotham

------------------------------------------------------------------
-- Помощники
------------------------------------------------------------------
local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end
local function corner(o, r)
	make("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o)
end
local function sound(id, vol, speed)
	if not id or id == "" then
		return
	end
	local s = make("Sound", { SoundId = id, Volume = vol or 1, PlaybackSpeed = speed or 1 }, SoundService)
	s:Play()
	task.delay(4, function()
		s:Destroy()
	end)
end

local gui = make("ScreenGui", { Name = "LabyrinthUI", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))

local function inMatch()
	return player:GetAttribute("InMatch") == true
end
local cutscene = false

------------------------------------------------------------------
-- Тряска камеры
------------------------------------------------------------------
local trauma = 0
local function shake(amount)
	trauma = math.min(1, trauma + amount)
end
RunService:BindToRenderStep("LabyrinthShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if trauma > 0 then
		local t = os.clock() * 30
		local s = trauma * trauma
		local cam = workspace.CurrentCamera
		cam.CFrame = cam.CFrame * CFrame.Angles(math.noise(t, 1) * 0.06 * s, math.noise(t, 2) * 0.06 * s, math.noise(t, 3) * 0.04 * s)
		trauma = math.max(0, trauma - dt * 1.6)
	end
end)

------------------------------------------------------------------
-- Прицел: кольцо с четырьмя «усиками», разъезжаются при ударе,
-- красный на монстре, золотой на ресурсе
------------------------------------------------------------------
local cross = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 60, 0, 60), BackgroundTransparency = 1 }, gui)
local ring = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 14, 0, 14), BackgroundTransparency = 1 }, cross)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
local ringStroke = make("UIStroke", { Thickness = 1.6, Color = RGB(240, 240, 240), Transparency = 0.15 }, ring)
local ticks = {}
for k, d in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
	local vert = d[1] == 0
	local t = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = vert and UDim2.new(0, 2, 0, 7) or UDim2.new(0, 7, 0, 2),
		BackgroundColor3 = RGB(240, 240, 240),
		BorderSizePixel = 0,
	}, cross)
	ticks[k] = { frame = t, dir = d }
end
local hitX = {}
for _, rot in ipairs({ 45, -45 }) do
	table.insert(hitX, make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 22, 0, 2),
		Rotation = rot,
		BackgroundColor3 = RGB(255, 255, 255),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, cross))
end
local targetLabel = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.5, 26),
	Size = UDim2.new(0, 360, 0, 22),
	BackgroundTransparency = 1,
	Font = UI_FONT,
	TextSize = 14,
	TextColor3 = RGB(240, 235, 220),
	TextStrokeTransparency = 0.4,
	Text = "",
}, gui)
local targetHP = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 48), Size = UDim2.new(0, 120, 0, 5), BackgroundColor3 = RGB(40, 10, 10), BorderSizePixel = 0, Visible = false }, gui)
local targetHPFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = RGB(220, 50, 40), BorderSizePixel = 0 }, targetHP)
local spread = 0

local function hitMarker(kind)
	local c = kind == "kill" and RGB(255, 60, 60) or (kind == "monster" and RGB(255, 200, 200) or RGB(255, 220, 120))
	for _, f in ipairs(hitX) do
		f.BackgroundColor3 = c
		f.BackgroundTransparency = 0
		TweenService:Create(f, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
	end
	sound(Config.Sounds.Hit, 0.5, kind == "node" and 1.6 or 0.9)
	shake(kind == "kill" and 0.5 or 0.18)
end

------------------------------------------------------------------
-- Интерфейс: фаза дня, здоровье, выносливость, ресурсы, хотбар
------------------------------------------------------------------
local phaseLabel = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 14),
	Size = UDim2.new(0, 520, 0, 34),
	BackgroundColor3 = RGB(12, 14, 12),
	BackgroundTransparency = 0.35,
	Font = UI_FONT,
	TextSize = 18,
	TextColor3 = RGB(240, 230, 200),
	Text = "",
}, gui)
corner(phaseLabel, 10)

local hpBack = make("Frame", { Position = UDim2.new(0, 20, 1, -46), Size = UDim2.new(0, 260, 0, 14), BackgroundColor3 = RGB(30, 12, 12), BorderSizePixel = 0 }, gui)
corner(hpBack, 6)
local hpFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = RGB(200, 50, 45), BorderSizePixel = 0 }, hpBack)
corner(hpFill, 6)
local hpText = make("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = UI_FONT, TextSize = 11, TextColor3 = RGB(255, 255, 255), Text = "" }, hpBack)
local stBack = make("Frame", { Position = UDim2.new(0, 20, 1, -26), Size = UDim2.new(0, 260, 0, 6), BackgroundColor3 = RGB(30, 30, 20), BorderSizePixel = 0 }, gui)
corner(stBack, 3)
local stFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = RGB(220, 200, 120), BorderSizePixel = 0 }, stBack)
corner(stFill, 3)

local resPanel = make("Frame", { Position = UDim2.new(0, 20, 0, 70), Size = UDim2.new(0, 230, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = RGB(12, 14, 12), BackgroundTransparency = 0.4 }, gui)
corner(resPanel, 10)
make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, resPanel)
make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, resPanel)

local function refreshRes()
	for _, c in ipairs(resPanel:GetChildren()) do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	for k, def in pairs(Items.Resources) do
		local n = player:GetAttribute("Res_" .. k) or 0
		if n > 0 then
			make("TextLabel", {
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				Font = TEXT_FONT,
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = k == "key" and RGB(255, 210, 90) or RGB(235, 230, 215),
				Text = def.Name .. ":  " .. n,
				LayoutOrder = def.Order,
			}, resPanel)
		end
	end
	resPanel.Visible = #resPanel:GetChildren() > 2
end

local hotbar = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.new(0, 0, 0, 64), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, gui)
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, hotbar)
local tools = {}
local equipped = nil

local function equip(id)
	if id == equipped then
		id = nil
	end
	equipped = id
	remote("Equip"):FireServer(id)
	Viewmodel.setItem(id or "fists")
	sound(Config.Sounds.Click, 0.4, 1.4)
end

local function refreshHotbar()
	for _, c in ipairs(hotbar:GetChildren()) do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	for i, id in ipairs(tools) do
		local b = make("TextButton", {
			Size = UDim2.new(0, 96, 0, 64),
			BackgroundColor3 = id == equipped and RGB(70, 90, 50) or RGB(18, 20, 18),
			BackgroundTransparency = 0.25,
			Font = UI_FONT,
			TextSize = 12,
			TextWrapped = true,
			TextColor3 = RGB(235, 230, 215),
			Text = i .. "\n" .. Items.toolName(id),
			LayoutOrder = i,
		}, hotbar)
		corner(b, 8)
		if id == equipped then
			make("UIStroke", { Color = RGB(200, 230, 140), Thickness = 2 }, b)
		end
		b.MouseButton1Click:Connect(function()
			equip(id)
			refreshHotbar()
		end)
	end
end

player.AttributeChanged:Connect(function(name)
	if name:sub(1, 4) == "Res_" then
		refreshRes()
	elseif name == "Tools" then
		local ok, list = pcall(function()
			return HttpService:JSONDecode(player:GetAttribute("Tools") or "[]")
		end)
		tools = ok and list or {}
		refreshHotbar()
	elseif name == "Equipped" then
		equipped = player:GetAttribute("Equipped")
		refreshHotbar()
	elseif name == "InMatch" then
		if not inMatch() then
			equipped = nil
			Viewmodel.setItem("fists", true)
		end
	end
end)
refreshRes()

-- уведомления
local notifyLabel = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.72),
	Size = UDim2.new(0.8, 0, 0, 50),
	BackgroundTransparency = 1,
	Font = UI_FONT,
	TextSize = 20,
	TextWrapped = true,
	TextColor3 = RGB(245, 240, 225),
	TextStrokeTransparency = 0.3,
	TextTransparency = 1,
	Text = "",
}, gui)
local notifyToken = 0
local function notify(text)
	notifyToken += 1
	local tk = notifyToken
	notifyLabel.Text = text
	notifyLabel.TextTransparency = 0
	notifyLabel.TextStrokeTransparency = 0.3
	task.delay(4, function()
		if tk == notifyToken then
			TweenService:Create(notifyLabel, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end
remote("Notify").OnClientEvent:Connect(notify)

-- лобби
local lobbyLabel = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.3),
	Size = UDim2.new(0.8, 0, 0, 80),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextSize = 32,
	TextColor3 = RGB(240, 230, 200),
	TextStrokeTransparency = 0.4,
	Text = "",
}, gui)
local titleLabel = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 60),
	Size = UDim2.new(0.8, 0, 0, 70),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = RGB(200, 230, 150),
	TextStrokeTransparency = 0.5,
	Text = Config.GameTitle,
}, gui)

-- красная вспышка при ударе по тебе
local hurtFlash = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = RGB(160, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5 }, gui)
remote("Hurt").OnClientEvent:Connect(function()
	hurtFlash.BackgroundTransparency = 0.45
	TweenService:Create(hurtFlash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	shake(0.7)
	sound(Config.Sounds.Hurt, 0.7, 1.1)
end)
remote("HitMarker").OnClientEvent:Connect(hitMarker)

------------------------------------------------------------------
-- Верстак
------------------------------------------------------------------
local craft = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0, 520, 0, 470),
	BackgroundColor3 = RGB(28, 24, 20),
	Visible = false,
	ZIndex = 10,
}, gui)
corner(craft, 12)
local craftTitle = make("TextLabel", { Position = UDim2.new(0, 16, 0, 10), Size = UDim2.new(1, -32, 0, 34), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 22, TextColor3 = RGB(240, 220, 170), TextXAlignment = Enum.TextXAlignment.Left, Text = "ВЕРСТАК", ZIndex = 10 }, craft)
local list = make("ScrollingFrame", { Position = UDim2.new(0, 12, 0, 50), Size = UDim2.new(1, -24, 1, -110), BackgroundTransparency = 1, ScrollBarThickness = 6, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 10 }, craft)
make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
local craftClose = make("TextButton", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(0, 160, 0, 40), BackgroundColor3 = RGB(90, 40, 30), Font = UI_FONT, TextSize = 18, TextColor3 = RGB(255, 240, 230), Text = "Закрыть", Modal = true, ZIndex = 10 }, craft)
corner(craftClose, 8)
craftClose.MouseButton1Click:Connect(function()
	craft.Visible = false
end)

local function costText(cost)
	local parts = {}
	for k, n in pairs(cost) do
		local have = player:GetAttribute("Res_" .. k) or 0
		table.insert(parts, (have >= n and "" or "✗ ") .. Items.Resources[k].Name .. " " .. have .. "/" .. n)
	end
	return table.concat(parts, "   ")
end

local function renderCraft()
	local level = ReplicatedStorage:GetAttribute("WorkbenchLevel") or 1
	craftTitle.Text = "ВЕРСТАК · уровень " .. level
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for i, r in ipairs(Items.Recipes) do
		local locked = r.Level > level
		local row = make("Frame", { Size = UDim2.new(1, -8, 0, 58), BackgroundColor3 = locked and RGB(30, 28, 26) or RGB(45, 40, 32), LayoutOrder = i, ZIndex = 10 }, list)
		corner(row, 8)
		make("TextLabel", {
			Position = UDim2.new(0, 10, 0, 4),
			Size = UDim2.new(1, -140, 0, 24),
			BackgroundTransparency = 1,
			Font = UI_FONT,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = locked and RGB(130, 120, 110) or RGB(245, 235, 210),
			Text = (r.Name or Items.toolName(r.Id)) .. (locked and ("  · нужен ур. " .. r.Level) or ""),
			ZIndex = 10,
		}, row)
		make("TextLabel", {
			Position = UDim2.new(0, 10, 0, 28),
			Size = UDim2.new(1, -140, 0, 24),
			BackgroundTransparency = 1,
			Font = TEXT_FONT,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = RGB(190, 180, 160),
			Text = costText(r.Cost),
			ZIndex = 10,
		}, row)
		local b = make("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.new(0, 110, 0, 38),
			BackgroundColor3 = locked and RGB(50, 50, 50) or RGB(60, 110, 50),
			Font = UI_FONT,
			TextSize = 15,
			TextColor3 = RGB(245, 245, 240),
			Text = locked and "Закрыто" or "Создать",
			AutoButtonColor = not locked,
			ZIndex = 10,
		}, row)
		corner(b, 6)
		b.MouseButton1Click:Connect(function()
			if not locked then
				remote("Craft"):FireServer(r.Id)
				sound(Config.Sounds.Click, 0.6, 1)
				task.delay(0.3, renderCraft)
			end
		end)
	end
end
remote("OpenCraft").OnClientEvent:Connect(function()
	renderCraft()
	craft.Visible = true
end)

------------------------------------------------------------------
-- Ввод: удар, предметы 1–9, еда, бег
------------------------------------------------------------------
local lastSwing = 0
local function rayParams()
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = { player.Character, workspace.CurrentCamera }
	return p
end

local function aimRay(range)
	local cam = workspace.CurrentCamera
	return workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * (range + 4), rayParams())
end

local function doSwing()
	if not inMatch() or cutscene or craft.Visible then
		return
	end
	local def = Items.Tools[equipped or "fists"] or Items.Tools.fists
	if os.clock() - lastSwing < 0.42 then
		return
	end
	lastSwing = os.clock()
	Viewmodel.swing()
	spread = 1
	sound(Config.Sounds.Swing, 0.6, 0.9 + math.random() * 0.3)
	shake(0.08)
	task.delay(0.16, function()
		local r = aimRay(def.Range)
		if r then
			remote("Swing"):FireServer(r.Instance, r.Position)
		end
	end)
end

local sprintHeld = false
UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		sprintHeld = true
	end
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
		doSwing()
	elseif input.KeyCode == Enum.KeyCode.H then
		remote("Eat"):FireServer()
	elseif input.KeyCode == Enum.KeyCode.Q then
		equip(nil)
		refreshHotbar()
	else
		local n = input.KeyCode.Value - Enum.KeyCode.One.Value + 1
		if n >= 1 and n <= 9 and tools[n] then
			equip(tools[n])
			refreshHotbar()
		end
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		sprintHeld = false
	end
end)

------------------------------------------------------------------
-- Лифт: поездка с друзьями
------------------------------------------------------------------
local fade = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = RGB(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 20 }, gui)
local subtitle = make("TextLabel", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -90), Size = UDim2.new(0.8, 0, 0, 40), BackgroundTransparency = 1, Font = UI_FONT, TextSize = 24, TextColor3 = RGB(240, 235, 220), TextStrokeTransparency = 0.3, Text = "", ZIndex = 21 }, gui)

local function cloneAvatar(who)
	local char = who.Character
	if not char then
		return nil
	end
	local ok, c = pcall(function()
		char.Archivable = true
		return char:Clone()
	end)
	if not ok or not c then
		return nil
	end
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.LocalTransparencyModifier = 0
		end
	end
	local hum = c:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	return c
end

remote("PlayElevator").OnClientEvent:Connect(function(riders, duration)
	cutscene = true
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local O = V(6000, 200, 0)
	local m = Instance.new("Model")
	m.Name = "ElevatorRide"
	local function p(size, cf, color, mat, props)
		local pt = make("Part", { Anchored = true, CanCollide = false, CanQuery = false, Size = size, CFrame = cf, Color = color, Material = mat or Enum.Material.DiamondPlate }, m)
		if props then
			for k, v in pairs(props) do
				pt[k] = v
			end
		end
		return pt
	end
	local metal = RGB(64, 66, 70)
	p(V(16, 0.5, 16), CFrame.new(O), metal)
	p(V(16, 0.5, 16), CFrame.new(O + V(0, 14, 0)), metal)
	p(V(0.5, 14, 16), CFrame.new(O + V(-8, 7, 0)), metal)
	p(V(0.5, 14, 16), CFrame.new(O + V(8, 7, 0)), metal)
	p(V(16, 14, 0.5), CFrame.new(O + V(0, 7, 8)), metal)
	local lamp = p(V(10, 0.3, 2), CFrame.new(O + V(0, 13.6, 0)), RGB(255, 220, 170), Enum.Material.Neon)
	make("PointLight", { Range = 18, Brightness = 1.2, Color = RGB(255, 220, 170) }, lamp)
	-- решётка спереди и стена шахты за ней (бегущие вниз лампы — лифт едет вверх)
	for x = -7, 7, 1.4 do
		p(V(0.2, 13.5, 0.2), CFrame.new(O + V(x, 7, -8)), RGB(40, 40, 44), Enum.Material.Metal)
	end
	p(V(20, 80, 1), CFrame.new(O + V(0, 7, -12)), RGB(48, 46, 44), Enum.Material.Concrete)
	local strips = {}
	for k = 0, 5 do
		local s = p(V(14, 0.4, 0.4), CFrame.new(O + V(0, k * 12 - 20, -11.4)), RGB(255, 200, 140), Enum.Material.Neon)
		make("PointLight", { Range = 10, Brightness = 1, Color = RGB(255, 190, 120) }, s)
		table.insert(strips, s)
	end
	m.Parent = workspace
	-- друзья в лифте
	local spots = { V(-3.5, 0, 2), V(3.5, 0, 2), V(-4, 0, -3.5), V(4, 0, -3.5), V(0, 0, 5), V(-5.5, 0, 5), V(5.5, 0, 5) }
	local k = 0
	for _, who in ipairs(riders) do
		if who ~= player then
			k += 1
			local av = cloneAvatar(who)
			if av and spots[k] then
				local pos = O + spots[k] + V(0, 3, 0)
				av:PivotTo(CFrame.lookAt(pos, pos + V(0, 0, -1)))
				av.Parent = m
			end
		end
	end
	fade.BackgroundTransparency = 0
	TweenService:Create(fade, TweenInfo.new(1), { BackgroundTransparency = 1 }):Play()
	subtitle.Text = #riders > 1 and ("Вас " .. #riders .. ". Лифт поднимается... Куда?") or "Лифт поднимается... Куда?"
	local rumble = make("Sound", { SoundId = Config.Sounds.Rumble, Looped = true, Volume = 0.8, PlaybackSpeed = 0.3 }, SoundService)
	rumble:Play()
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - t0
		for _, s in ipairs(strips) do
			local y = s.Position.Y - dt * 22
			if y < O.Y - 30 then
				y += 72
			end
			s.CFrame = CFrame.new(s.Position.X, y, s.Position.Z)
		end
		local jitter = CFrame.Angles(math.noise(t * 8, 1) * 0.01, math.noise(t * 8, 2) * 0.01, 0)
		cam.CFrame = CFrame.lookAt(O + V(0, 5.2, 4), O + V(0, 5.6, -8)) * jitter
		if t > duration - 2 and fade.BackgroundTransparency > 0.99 then
			fade.BackgroundColor3 = RGB(255, 250, 235)
			TweenService:Create(fade, TweenInfo.new(1.5), { BackgroundTransparency = 0 }):Play()
			subtitle.Text = "Свет... Мы наверху."
		end
	end)
	task.wait(duration)
	conn:Disconnect()
	rumble:Destroy()
	m:Destroy()
	cam.CameraType = Enum.CameraType.Custom
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		cam.CameraSubject = hum
	end
	TweenService:Create(fade, TweenInfo.new(2), { BackgroundTransparency = 1 }):Play()
	task.delay(2, function()
		fade.BackgroundColor3 = RGB(0, 0, 0)
	end)
	subtitle.Text = "Поляна. Лес, река... и огромные стены вокруг."
	task.delay(4, function()
		subtitle.Text = ""
	end)
	cutscene = false
	shake(0.6)
	Viewmodel.setItem("fists")
end)

------------------------------------------------------------------
-- Победа
------------------------------------------------------------------
remote("Win").OnClientEvent:Connect(function(who, day)
	cutscene = true
	fade.BackgroundColor3 = RGB(255, 255, 255)
	TweenService:Create(fade, TweenInfo.new(2.5), { BackgroundTransparency = 0 }):Play()
	task.wait(2.5)
	lobbyLabel.ZIndex = 22
	lobbyLabel.TextColor3 = RGB(30, 40, 30)
	lobbyLabel.Text = "ВЫ ВЫБРАЛИСЬ ИЗ ЛАБИРИНТА!\n" .. who .. " открыл выход · день " .. day
	task.wait(6)
	lobbyLabel.Text = ""
	lobbyLabel.TextColor3 = RGB(240, 230, 200)
	lobbyLabel.ZIndex = 1
	TweenService:Create(fade, TweenInfo.new(1.5), { BackgroundTransparency = 1 }):Play()
	task.delay(1.5, function()
		fade.BackgroundColor3 = RGB(0, 0, 0)
	end)
	cutscene = false
end)

------------------------------------------------------------------
-- Каждый кадр: интерфейс, прицел, руки, бег
------------------------------------------------------------------
local stamina = Config.StaminaMax
local exhausted = false
local vmState = { visible = false, moving = false, sprinting = false }
-- руки обновляются строго после камеры и тряски, чтобы не дрожали
RunService:BindToRenderStep("LabyrinthViewmodel", Enum.RenderPriority.Camera.Value + 2, function(dt)
	Viewmodel.update(dt, vmState.visible, vmState.moving, vmState.sprinting)
end)

local function formatTime(t)
	t = math.max(0, math.floor(t))
	return string.format("%d:%02d", t // 60, t % 60)
end

RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local playing = inMatch() and not cutscene

	-- камера
	player.CameraMode = playing and Enum.CameraMode.LockFirstPerson or Enum.CameraMode.Classic
	if not playing then
		player.CameraMaxZoomDistance = 18
	end

	-- лобби
	titleLabel.Visible = not inMatch() and not cutscene
	if not inMatch() and not cutscene then
		local cd = ReplicatedStorage:GetAttribute("LiftCountdown") or -1
		lobbyLabel.Text = cd >= 0 and ("Лифт отправляется через " .. cd .. "...") or "Зайди в лифт, чтобы отправиться на поляну"
		lobbyLabel.TextSize = cd >= 0 and 36 or 22
	elseif not cutscene then
		lobbyLabel.Text = ""
	end

	-- фаза дня
	phaseLabel.Visible = inMatch()
	local phase = ReplicatedStorage:GetAttribute("Phase") or "day"
	local left = (ReplicatedStorage:GetAttribute("PhaseEnd") or 0) - workspace:GetServerTimeNow()
	local day = ReplicatedStorage:GetAttribute("Day") or 1
	if phase == "day" then
		phaseLabel.Text = "☀  День " .. day .. "  ·  врата закроются через " .. formatTime(left)
		phaseLabel.TextColor3 = left < Config.WarningTime and RGB(255, 120, 90) or RGB(240, 230, 200)
	else
		phaseLabel.Text = "☾  Ночь  ·  врата закрыты  ·  рассвет через " .. formatTime(left)
		phaseLabel.TextColor3 = RGB(170, 190, 255)
	end

	-- здоровье и выносливость
	hpBack.Visible, stBack.Visible, hotbar.Visible = inMatch(), inMatch(), inMatch() and not cutscene
	resPanel.Visible = inMatch() and #resPanel:GetChildren() > 2
	if hum then
		hpFill.Size = UDim2.fromScale(math.clamp(hum.Health / hum.MaxHealth, 0, 1), 1)
		hpText.Text = math.floor(hum.Health) .. " / " .. hum.MaxHealth
		local moving = hum.MoveDirection.Magnitude > 0.1
		local sprinting = playing and sprintHeld and moving and not exhausted and stamina > 0
		if sprinting then
			stamina = math.max(0, stamina - Config.StaminaDrain * dt)
			exhausted = stamina <= 0
		else
			stamina = math.min(Config.StaminaMax, stamina + Config.StaminaRegen * dt)
			if exhausted and stamina > 30 then
				exhausted = false
			end
		end
		hum.WalkSpeed = sprinting and Config.SprintSpeed or Config.WalkSpeed
		stFill.Size = UDim2.fromScale(stamina / Config.StaminaMax, 1)
		vmState.visible, vmState.moving, vmState.sprinting = playing, moving, sprinting
		if sprinting then
			trauma = math.max(trauma, 0.08)
		end
	else
		vmState.visible = false
	end

	-- прицел
	cross.Visible = playing
	spread = math.max(0, spread - dt * 4)
	local gap = 10 + spread * 10
	for _, t in ipairs(ticks) do
		t.frame.Position = UDim2.new(0.5, t.dir[1] * gap, 0.5, t.dir[2] * gap)
	end
	local color = RGB(240, 240, 240)
	targetLabel.Text = ""
	targetHP.Visible = false
	if playing then
		local def = Items.Tools[equipped or "fists"] or Items.Tools.fists
		local r = aimRay(def.Range)
		if r then
			local model = r.Instance:FindFirstAncestorWhichIsA("Model")
			local mon = model
			while mon and not CollectionService:HasTag(mon, "Monster") and mon.Parent and mon.Parent:IsA("Model") do
				mon = mon.Parent
			end
			if mon and CollectionService:HasTag(mon, "Monster") then
				color = RGB(255, 70, 60)
				targetLabel.Text = Config.Monster.Name
				targetHP.Visible = true
				targetHPFill.Size = UDim2.fromScale(math.clamp((mon:GetAttribute("HP") or 1) / (mon:GetAttribute("MaxHP") or 1), 0, 1), 1)
			else
				local nodeModel = model
				while nodeModel and nodeModel:GetAttribute("Node") == nil and nodeModel.Parent and nodeModel.Parent:IsA("Model") do
					nodeModel = nodeModel.Parent
				end
				local kind = nodeModel and nodeModel:GetAttribute("Node")
				if kind and not nodeModel:GetAttribute("Depleted") then
					local nd = Items.Nodes[kind]
					local okTool = def.Kind == nd.Tool and def.Tier >= nd.Tier
					color = okTool and RGB(255, 210, 90) or RGB(160, 160, 160)
					local need = nd.Tool == "axe" and "топор" or ("кирка ур. " .. nd.Tier)
					targetLabel.Text = nd.Name .. (okTool and "" or ("  ·  нужен(а) " .. need))
				end
			end
		end
	end
	ringStroke.Color = color
	for _, t in ipairs(ticks) do
		t.frame.BackgroundColor3 = color
	end
end)

------------------------------------------------------------------
-- Тестовые кнопки
------------------------------------------------------------------
if Config.DevTools then
	local bar = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 60), Size = UDim2.new(0, 190, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, gui)
	make("UIListLayout", { Padding = UDim.new(0, 5) }, bar)
	local function btn(text, fn)
		local b = make("TextButton", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = RGB(30, 30, 34), BackgroundTransparency = 0.25, Font = UI_FONT, TextSize = 13, TextColor3 = RGB(230, 230, 230), Text = text }, bar)
		corner(b, 6)
		b.MouseButton1Click:Connect(function()
			fn(b)
		end)
		return b
	end
	-- курсор (M)
	local unlocker = make("TextButton", { Size = UDim2.new(0, 1, 0, 1), BackgroundTransparency = 1, Text = "", Modal = true, Visible = false }, gui)
	local cursorB = btn("Курсор: ВЫКЛ (M)", function(b)
		unlocker.Visible = not unlocker.Visible
		b.Text = unlocker.Visible and "Курсор: ВКЛ (M)" or "Курсор: ВЫКЛ (M)"
	end)
	-- полный свет (L): переписываем свет каждый кадр, т.к. сервер меняет время суток
	local full = false
	local fullB = btn("Полный свет: ВЫКЛ (L)", function(b)
		full = not full
		b.Text = full and "Полный свет: ВКЛ (L)" or "Полный свет: ВЫКЛ (L)"
	end)
	RunService.RenderStepped:Connect(function()
		if full then
			Lighting.ClockTime = 13
			Lighting.Brightness = 3
			Lighting.Ambient = RGB(200, 200, 200)
			Lighting.OutdoorAmbient = RGB(200, 200, 200)
			local a = Lighting:FindFirstChildOfClass("Atmosphere")
			if a then
				a.Density = 0.1
			end
		end
	end)
	-- полёт (N)
	local flying, flyConn = false, nil
	local function setFly(on)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp then
			return
		end
		flying = on
		remote("Dev"):FireServer("ghost", on)
		hum.PlatformStand = on
		if flyConn then
			flyConn:Disconnect()
			flyConn = nil
		end
		if on then
			flyConn = RunService.RenderStepped:Connect(function(dt)
				local cam = workspace.CurrentCamera
				local mv = Vector3.zero
				local K = Enum.KeyCode
				if UserInputService:IsKeyDown(K.W) then
					mv += cam.CFrame.LookVector
				end
				if UserInputService:IsKeyDown(K.S) then
					mv -= cam.CFrame.LookVector
				end
				if UserInputService:IsKeyDown(K.D) then
					mv += cam.CFrame.RightVector
				end
				if UserInputService:IsKeyDown(K.A) then
					mv -= cam.CFrame.RightVector
				end
				if UserInputService:IsKeyDown(K.Space) then
					mv += Vector3.yAxis
				end
				if UserInputService:IsKeyDown(K.LeftControl) then
					mv -= Vector3.yAxis
				end
				local pos = hrp.Position
				if mv.Magnitude > 0 then
					pos += mv.Unit * (UserInputService:IsKeyDown(K.LeftShift) and 140 or 55) * dt
				end
				local flat = V(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
				hrp.CFrame = CFrame.lookAt(pos, pos + (flat.Magnitude > 0.01 and flat or V(0, 0, -1)))
				hrp.AssemblyLinearVelocity = Vector3.zero
				for _, d in ipairs(char:GetDescendants()) do
					if d:IsA("BasePart") then
						d.CanCollide = false
					end
				end
			end)
		end
	end
	local flyB = btn("Полёт: ВЫКЛ (N)", function(b)
		setFly(not flying)
		b.Text = flying and "Полёт: ВКЛ (N)" or "Полёт: ВЫКЛ (N)"
	end)
	btn("Сменить день/ночь", function()
		remote("Dev"):FireServer("phase")
	end)
	btn("+30 ресурсов и Ключ", function()
		remote("Dev"):FireServer("res")
	end)
	btn("Телепорт к выходу", function()
		remote("Dev"):FireServer("toexit")
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.M then
			unlocker.Visible = not unlocker.Visible
			cursorB.Text = unlocker.Visible and "Курсор: ВКЛ (M)" or "Курсор: ВЫКЛ (M)"
		elseif input.KeyCode == Enum.KeyCode.L then
			full = not full
			fullB.Text = full and "Полный свет: ВКЛ (L)" or "Полный свет: ВЫКЛ (L)"
		elseif input.KeyCode == Enum.KeyCode.N then
			setFly(not flying)
			flyB.Text = flying and "Полёт: ВКЛ (N)" or "Полёт: ВЫКЛ (N)"
		end
	end)
end

-- подсказка управления
make("TextLabel", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -14),
	Size = UDim2.new(0, 520, 0, 20),
	BackgroundTransparency = 1,
	Font = TEXT_FONT,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Right,
	TextColor3 = RGB(200, 195, 180),
	Text = "ЛКМ — удар/добыча · 1–9 — предмет · Q — убрать · Shift — бег · H — съесть ягоды · E — действие",
}, gui)
