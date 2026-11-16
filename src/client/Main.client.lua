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
local MonsterView = require(script.Parent:WaitForChild("MonsterView"))
local BuildMode = require(script.Parent:WaitForChild("BuildMode"))
MonsterView.start()

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
local appliedShake = CFrame.new()
-- перед обновлением камеры убираем тряску прошлого кадра, иначе мышь «уплывает» и дёргается
RunService:BindToRenderStep("LabyrinthUnshake", Enum.RenderPriority.Camera.Value - 1, function()
	local cam = workspace.CurrentCamera
	if appliedShake ~= CFrame.new() and cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CFrame = cam.CFrame * appliedShake:Inverse()
	end
	appliedShake = CFrame.new()
end)
RunService:BindToRenderStep("LabyrinthShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if trauma > 0 then
		local t = os.clock() * 30
		local s = trauma * trauma
		local cam = workspace.CurrentCamera
		local sh = CFrame.Angles(math.noise(t, 1) * 0.05 * s, math.noise(t, 2) * 0.05 * s, math.noise(t, 3) * 0.03 * s)
		cam.CFrame = cam.CFrame * sh
		if cam.CameraType ~= Enum.CameraType.Scriptable then
			appliedShake = sh
		end
		trauma = math.max(0, trauma - dt * 2)
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

local lastSwingAnim = 0
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
BuildMode.init(gui, make)

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
		local e = player:GetAttribute("Equipped")
		if e ~= equipped then
			equipped = e
			Viewmodel.setItem(e or "fists")
		end
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
remote("HitMarker").OnClientEvent:Connect(function(kind, toolKind)
	-- добыча на E: руки сами делают удар нужным инструментом
	if toolKind and os.clock() - lastSwingAnim > 0.3 then
		lastSwingAnim = os.clock()
		Viewmodel.swing(toolKind)
		sound(Config.Sounds.Swing, 0.5, 1)
	end
	hitMarker(kind)
end)

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

local benchLevel = nil -- nil — крафт из инвентаря (C), число — открыт верстак этого уровня
local function renderCraft()
	craftTitle.Text = benchLevel and ("ВЕРСТАК · уровень " .. benchLevel) or "КРАФТ (C) · подойди к верстаку для оружия"
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for i, r in ipairs(Items.Recipes) do
		local lockText
		if r.Station == "bench" then
			if not benchLevel then
				lockText = "нужен верстак"
			elseif r.Level > benchLevel then
				lockText = "нужен ур. " .. r.Level
			end
		end
		local locked = lockText ~= nil
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
			Text = (r.Name or Items.toolName(r.Id)) .. (locked and ("  · " .. lockText) or ""),
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
				if r.Id == "workbench" then
					craft.Visible = false
				else
					task.delay(0.3, renderCraft)
				end
			end
		end)
	end
end
remote("OpenCraft").OnClientEvent:Connect(function(level)
	benchLevel = level
	renderCraft()
	craft.Visible = true
end)
local function openHandCraft()
	if craft.Visible then
		craft.Visible = false
		return
	end
	benchLevel = nil
	renderCraft()
	craft.Visible = true
end

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
	if def.Kind == "blueprint" then
		if BuildMode.place(remote("Build")) then
			sound(Config.Sounds.Click, 0.6, 0.8)
		end
		return
	end
	if def.Kind == "torch" or player:GetAttribute("Downed") or player:GetAttribute("Hidden") or player:GetAttribute("Sleeping") then
		return -- факелом не бьют: он только светит
	end
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
local flyingNow = false
local crouched = false
local function setCrouch(on)
	crouched = on
	remote("Crouch"):FireServer(on)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		TweenService:Create(hum, TweenInfo.new(0.25), { CameraOffset = on and Vector3.new(0, -2.4, 0) or Vector3.zero }):Play()
	end
end
UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		sprintHeld = true
	end
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
		doSwing()
	elseif input.KeyCode == Enum.KeyCode.R and equipped == "blueprint" then
		BuildMode.cycle()
		sound(Config.Sounds.Click, 0.4, 1.2)
	elseif input.KeyCode == Enum.KeyCode.H then
		remote("Eat"):FireServer()
	elseif input.KeyCode == Enum.KeyCode.C and inMatch() and not cutscene then
		openHandCraft()
	elseif input.KeyCode == Enum.KeyCode.LeftControl and inMatch() and not cutscene and not flyingNow then
		setCrouch(not crouched)
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

remote("PlayElevator").OnClientEvent:Connect(function(riders, duration, diffId)
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
	local diff = Config.Difficulty[diffId or "normal"]
	subtitle.Text = (diff and ("[" .. diff.Name .. "]  ") or "") .. (#riders > 1 and ("Вас " .. #riders .. ". Лифт поднимается... Куда?") or "Лифт поднимается... Куда?")
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
	subtitle.Text = ""
	-- экран остаётся белым, пока сервер строит лабиринт; дальше — ролик прибытия
	task.delay(25, function()
		if cutscene and not inMatch() then
			cutscene = false
			cam.CameraType = Enum.CameraType.Custom
			TweenService:Create(fade, TweenInfo.new(1), { BackgroundTransparency = 1 }):Play()
		end
	end)
end)

------------------------------------------------------------------
-- Прибытие: решётка лифта поднимается, выходишь и осматриваешься
------------------------------------------------------------------
local function smoothstep(a)
	return a * a * (3 - 2 * a)
end
local function runFor(duration, fn)
	local t0 = os.clock()
	while true do
		local a = math.clamp((os.clock() - t0) / duration, 0, 1)
		fn(a)
		if a >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
end

remote("Arrive").OnClientEvent:Connect(function(liftPos, riders)
	cutscene = true
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local eye0 = liftPos + V(0, 5.6, 4)
	local eye1 = liftPos + V(0, 5.8, -16)
	cam.CFrame = CFrame.lookAt(eye0, eye0 + V(0, 0, -10))
	TweenService:Create(fade, TweenInfo.new(1.6), { BackgroundTransparency = 1 }):Play()
	task.delay(1.6, function()
		fade.BackgroundColor3 = RGB(0, 0, 0)
	end)
	subtitle.Text = #riders > 1 and ("Вас " .. #riders .. ". Решётка поднимается...") or "Решётка поднимается..."
	shake(0.5)
	runFor(1.6, function()
		cam.CFrame = CFrame.lookAt(eye0, eye0 + V(0, 0.4, -10)) * CFrame.Angles(math.noise(os.clock() * 6) * 0.01, 0, 0)
	end)
	-- шаг из лифта
	runFor(2.4, function(a)
		local e = smoothstep(a)
		local pos = eye0:Lerp(eye1, e) + V(0, math.abs(math.sin(a * 2.4 * 7)) * 0.15, 0)
		cam.CFrame = CFrame.lookAt(pos, pos + V(0, 0.6 - e * 0.3, -10))
	end)
	subtitle.Text = "Поляна. Лес, река... и огромные стены со всех сторон."
	-- осматриваемся: налево, вверх на стены, направо, вперёд
	local function lookAt(yaw, pitch)
		return CFrame.new(eye1) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	end
	local keys = { { 0, 0.03 }, { 0.95, 0.12 }, { 0.6, 0.45 }, { -0.95, 0.15 }, { 0, 0.02 } }
	for k = 1, #keys - 1 do
		local a0, a1 = keys[k], keys[k + 1]
		runFor(1.3, function(a)
			local e = smoothstep(a)
			cam.CFrame = lookAt(a0[1] + (a1[1] - a0[1]) * e, a0[2] + (a1[2] - a0[2]) * e)
		end)
	end
	subtitle.Text = ""
	cam.CameraType = Enum.CameraType.Custom
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		cam.CameraSubject = hum
	end
	cutscene = false
	Viewmodel.rebuild()
	Viewmodel.setItem("fists")
	notify("Нажми C — крафт. Подойди к дереву и зажми E, чтобы рубить.")
end)

------------------------------------------------------------------
-- Финал: дверь открыта, вертолёт садится и уносит всех из лабиринта
------------------------------------------------------------------
local function buildHeli(cf)
	local m = Instance.new("Model")
	m.Name = "Helicopter"
	local function p(size, rel, color, mat, extra)
		local pt = make("Part", { Anchored = true, CanCollide = false, CanQuery = false, Size = size, Color = color, Material = mat or Enum.Material.SmoothPlastic }, m)
		if extra then
			for k, v in pairs(extra) do
				pt[k] = v
			end
		end
		pt:SetAttribute("Rel", rel)
		return pt
	end
	local white, red, dark, glass = RGB(232, 232, 236), RGB(200, 45, 40), RGB(35, 36, 40), RGB(60, 110, 140)
	local M = Enum.Material
	-- кабина: корпус, нос, стёкла, полосы
	p(V(7.5, 6.5, 11), CFrame.new(0, 4.8, 0), white, M.SmoothPlastic)
	p(V(7.6, 1, 11.1), CFrame.new(0, 3.2, 0), red, M.SmoothPlastic)
	p(V(6.5, 5, 4), CFrame.new(0, 4.4, -7), white, M.SmoothPlastic)
	p(V(6, 3, 0.3), CFrame.new(0, 5.6, -9.05), glass, M.Glass, { Transparency = 0.35 })
	for _, x in ipairs({ -3.8, 3.8 }) do
		p(V(0.2, 2.6, 3.6), CFrame.new(x, 5.8, -6.6), glass, M.Glass, { Transparency = 0.35 })
		p(V(0.2, 2.6, 3.4), CFrame.new(x, 5.8, -1.5), glass, M.Glass, { Transparency = 0.35 })
		p(V(0.25, 4.6, 3.6), CFrame.new(x, 4.6, 2.6), dark, M.Metal) -- проём двери
	end
	p(V(5, 1.2, 6), CFrame.new(0, 8.4, 1), white, M.SmoothPlastic) -- двигатель
	-- хвост
	p(V(1.8, 1.8, 16), CFrame.new(0, 6.2, 13), white, M.SmoothPlastic)
	p(V(1.85, 0.5, 16.1), CFrame.new(0, 6.6, 13), red, M.SmoothPlastic)
	p(V(0.4, 5, 3), CFrame.new(0, 8.5, 20.5), white, M.SmoothPlastic)
	p(V(5, 0.3, 2), CFrame.new(0, 6.4, 19), white, M.SmoothPlastic)
	-- полозья
	for _, x in ipairs({ -3.6, 3.6 }) do
		p(V(0.5, 0.5, 15), CFrame.new(x, 0.3, 0), dark, M.Metal)
		p(V(0.35, 1.8, 0.35), CFrame.new(x, 1.3, -3.5), dark, M.Metal)
		p(V(0.35, 1.8, 0.35), CFrame.new(x, 1.3, 3.5), dark, M.Metal)
	end
	-- винты
	p(V(0.8, 1.4, 0.8), CFrame.new(0, 9.6, 1), dark, M.Metal)
	for k = 0, 1 do
		local blade = p(V(34, 0.2, 1.3), CFrame.new(0, 10.3, 1), dark, M.Metal)
		blade:SetAttribute("Blade", k * math.pi / 2)
	end
	for k = 0, 1 do
		local tb = p(V(0.15, 4.5, 0.5), CFrame.new(0.5, 8.6, 21.5), dark, M.Metal)
		tb:SetAttribute("TailBlade", k * math.pi / 2)
	end
	local lamp = p(V(0.8, 0.8, 0.3), CFrame.new(0, 2.8, -9.1), RGB(255, 250, 220), M.Neon)
	make("SpotLight", { Face = Enum.NormalId.Front, Range = 60, Angle = 50, Brightness = 4 }, lamp)
	local beacon = p(V(0.5, 0.5, 0.5), CFrame.new(0, 8.4, 20.5), RGB(255, 40, 40), M.Neon)
	local _ = beacon
	m.Parent = workspace
	local spin = 0
	local function setCF(c, dt)
		spin += (dt or 0) * 25
		for _, d in ipairs(m:GetChildren()) do
			if d:IsA("BasePart") then
				local rel = d:GetAttribute("Rel")
				local b = d:GetAttribute("Blade")
				local tb = d:GetAttribute("TailBlade")
				if b then
					d.CFrame = c * rel * CFrame.Angles(0, spin + b, 0)
				elseif tb then
					d.CFrame = c * rel * CFrame.Angles(spin * 1.5 + tb, 0, 0)
				else
					d.CFrame = c * rel
				end
			end
		end
	end
	setCF(cf)
	return m, setCF
end

remote("Outro").OnClientEvent:Connect(function(pad, exitOut, players, day, coins, mazeCenter)
	cutscene = true
	craft.Visible = false
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local temp = {}
	mazeCenter = mazeCenter or (exitOut.Position - exitOut.LookVector * 500)

	-- вертолёт уже ждёт на лесной поляне, винты крутятся
	local heliCF = pad * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, math.pi / 2, 0)
	local heli, setCF = buildHeli(heliCF)
	table.insert(temp, heli)
	local rotor = make("Sound", { SoundId = Config.Sounds.Rumble, Looped = true, Volume = 0.8, PlaybackSpeed = 0.7 }, SoundService)
	rotor:Play()

	-- друзья идут рядом
	local friends = {}
	local k = 0
	for _, who in ipairs(players) do
		if who ~= player then
			k += 1
			local av = cloneAvatar(who)
			if av then
				av.Parent = workspace
				table.insert(temp, av)
				table.insert(friends, { m = av, side = (k % 2 == 1) and -4 or 4, back = 3 + math.floor((k - 1) / 2) * 4 })
			end
		end
	end

	-- 1. ворота поднимаются
	local start = exitOut * CFrame.new(0, 5.4, -40)
	subtitle.Text = "Ворота поднимаются... За ними — свет."
	runFor(4.5, function()
		cam.CFrame = start * CFrame.Angles(math.noise(os.clock() * 3) * 0.01, 0, 0)
		setCF(heliCF, 1 / 60)
	end)

	-- 2. идём от первого лица: покачивание камеры и хруст травы под ногами
	subtitle.Text = "Лес... Настоящий лес. Мы выбрались!"
	local target = pad * CFrame.new(0, 5.4, 16)
	local from, to = start.Position, target.Position
	local walkTime = 8
	local nextStep = 0
	local t0 = os.clock()
	runFor(walkTime, function(a)
		local t = os.clock() - t0
		local pos = from:Lerp(to, a)
		local bob = math.sin(t * 9) * 0.22
		local sideBob = math.cos(t * 4.5) * 0.12
		local look = pos + (to - from).Unit * 10 + V(math.sin(t * 0.7) * 2.5, -0.8, 0)
		cam.CFrame = CFrame.lookAt(pos + V(sideBob, bob, 0), look) * CFrame.Angles(0, 0, math.cos(t * 4.5) * 0.012)
		if t >= nextStep then
			nextStep = t + 0.48
			sound(Config.Sounds.Step, 0.35, 0.7 + math.random() * 0.15)
		end
		for _, f in ipairs(friends) do
			local fp = from:Lerp(to, math.max(0, a - 0.04)) + (exitOut.RightVector * f.side) + exitOut.LookVector * f.back - V(0, 2.4, 0) + V(0, math.abs(math.sin(t * 9)) * 0.3, 0)
			f.m:PivotTo(CFrame.lookAt(fp, fp - exitOut.LookVector))
		end
		setCF(heliCF, 1 / 60)
	end)

	-- 3. садимся в вертолёт
	subtitle.Text = "Залезаем!"
	fade.BackgroundColor3 = RGB(0, 0, 0)
	TweenService:Create(fade, TweenInfo.new(0.4), { BackgroundTransparency = 0 }):Play()
	task.wait(0.45)
	for _, f in ipairs(friends) do
		f.m:Destroy()
	end
	-- место у открытой боковой двери: камера снаружи корпуса, винт выше кадра
	local seat = CFrame.new(5.4, 4.6, 2.6)
	cam.CFrame = CFrame.lookAt((heliCF * seat).Position, (heliCF * CFrame.new(30, 2, 2.6)).Position)
	TweenService:Create(fade, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()

	-- 4. взлёт: поднимаемся высоко над лабиринтом и смотрим на него целиком
	subtitle.Text = "Взлетаем... Вот он — весь лабиринт."
	local liftTime = 10
	local high = heliCF.Position:Lerp(mazeCenter, 0.35) + V(0, 420, 0)
	runFor(liftTime, function(a)
		local e = a * a * (3 - 2 * a)
		local pos = heliCF.Position:Lerp(high, e)
		local toMaze = (mazeCenter - pos) * V(1, 0, 1)
		local hc = CFrame.lookAt(pos, pos + V(toMaze.Z, 0, -toMaze.X)) * CFrame.Angles(-0.08 * math.sin(a * math.pi), 0, 0)
		setCF(hc, 1 / 60)
		local eye = (hc * seat).Position
		cam.CFrame = CFrame.lookAt(eye, mazeCenter) * CFrame.Angles(math.noise(os.clock() * 5) * 0.006, 0, 0)
	end)
	task.wait(2.5)

	-- 5. улетаем
	subtitle.Text = "Прощай, лабиринт."
	local away = (high - mazeCenter) * V(1, 0, 1)
	away = away.Magnitude > 1 and away.Unit or V(1, 0, 0)
	runFor(5, function(a)
		local pos = high + away * 600 * a * a + V(0, 60 * a, 0)
		local hc = CFrame.lookAt(pos, pos + V(-away.Z, 0, away.X))
		setCF(hc, 1 / 60)
		cam.CFrame = CFrame.lookAt((hc * seat).Position, mazeCenter)
	end)
	rotor:Destroy()
	for _, d in ipairs(temp) do
		if d.Parent then
			d:Destroy()
		end
	end
	TweenService:Create(fade, TweenInfo.new(1.2), { BackgroundTransparency = 0 }):Play()
	task.wait(1.3)
	subtitle.Text = ""
	lobbyLabel.ZIndex = 22
	lobbyLabel.Text = "ВЫ ВЫБРАЛИСЬ ИЗ ЛАБИРИНТА!\nДней в лабиринте: " .. day .. "   ·   +" .. coins .. " монет"
	task.wait(4)
	-- ждём, пока сервер вернёт нас в лобби, и только потом убираем чёрный экран
	local waitT = os.clock()
	while inMatch() and os.clock() - waitT < 12 do
		task.wait(0.1)
	end
	local char = player.Character or player.CharacterAdded:Wait()
	local hum = char:WaitForChild("Humanoid", 5)
	task.wait(0.3)
	char = player.Character
	hum = char and char:FindFirstChildOfClass("Humanoid") or hum
	cam.CameraType = Enum.CameraType.Custom
	if hum then
		cam.CameraSubject = hum
	end
	lobbyLabel.Text = ""
	lobbyLabel.ZIndex = 1
	cutscene = false
	TweenService:Create(fade, TweenInfo.new(1.5), { BackgroundTransparency = 1 }):Play()
end)

------------------------------------------------------------------
-- Каждый кадр: интерфейс, прицел, руки, бег
------------------------------------------------------------------
local devCursorOn = false
local fullLightOn = false
local function cursorForced()
	return devCursorOn
end
local function staminaMax()
	return Config.StaminaMax + (player:GetAttribute("Class") == "runner" and 60 or 0)
end
local function className(id)
	for _, c in ipairs(Config.Classes) do
		if c.Id == id then
			return c.Name
		end
	end
	return "Без класса"
end

-- освещение: у каждой группы своё время суток
local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
local function applyLighting(phase, a)
	if fullLightOn then
		return
	end
	atmo = atmo or Lighting:FindFirstChildOfClass("Atmosphere")
	cc = cc or Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	rays = rays or Lighting:FindFirstChildOfClass("SunRaysEffect")
	local clock, night = 14, 0
	if phase == "day" then
		clock = 6.5 + a * 11.5
		night = math.clamp((clock - 16.5) / 2, 0, 1) * 0.5 + math.clamp((7.5 - clock) / 1, 0, 1) * 0.5
	elseif phase == "night" then
		clock = (18.2 + a * 12.1) % 24
		night = 0.5 + 0.5 * math.clamp(math.min(a, 1 - a) / 0.08, 0, 1)
	end
	local function mix(x, y)
		return x:Lerp(y, night)
	end
	Lighting.ClockTime = clock
	Lighting.Brightness = 4 - night * 2.6
	Lighting.ExposureCompensation = 0.35 - night * 0.1
	Lighting.Ambient = mix(RGB(120, 115, 105), RGB(48, 52, 72))
	Lighting.OutdoorAmbient = mix(RGB(185, 180, 170), RGB(70, 80, 110))
	if atmo then
		atmo.Density = 0.25 + night * 0.12
		atmo.Haze = 1.2 + night * 1.2
		atmo.Color = mix(RGB(200, 190, 170), RGB(60, 70, 100))
		atmo.Decay = mix(RGB(110, 100, 90), RGB(20, 22, 40))
	end
	if cc then
		cc.TintColor = mix(RGB(255, 245, 230), RGB(190, 205, 255))
		cc.Saturation = 0.1 - night * 0.35
		cc.Contrast = 0.12
	end
	if rays then
		rays.Intensity = 0.12 * (1 - night)
	end
end

-- монеты и класс (в лобби)
local coinsLabel = make("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -220, 0, 16),
	Size = UDim2.new(0, 360, 0, 32),
	BackgroundColor3 = RGB(20, 18, 14),
	BackgroundTransparency = 0.3,
	Font = UI_FONT,
	TextSize = 16,
	TextColor3 = RGB(255, 215, 100),
	Text = "",
}, gui)
corner(coinsLabel, 8)

-- окно лифта
local liftPanel = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.45, 0), Size = UDim2.new(0, 460, 0, 230), BackgroundColor3 = RGB(18, 20, 22), BackgroundTransparency = 0.15, Visible = false }, gui)
corner(liftPanel, 12)
local liftTitle = make("TextLabel", { Position = UDim2.new(0, 14, 0, 8), Size = UDim2.new(1, -28, 0, 34), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 22, TextColor3 = RGB(240, 230, 200), Text = "" }, liftPanel)
local liftInfo = make("TextLabel", { Position = UDim2.new(0, 14, 0, 42), Size = UDim2.new(1, -28, 0, 24), BackgroundTransparency = 1, Font = UI_FONT, TextSize = 16, TextColor3 = RGB(200, 200, 190), Text = "" }, liftPanel)
local function liftBtn(text, x, w, fn)
	local b = make("TextButton", { Position = UDim2.new(0, x, 0, 0), Size = UDim2.new(0, w, 1, 0), BackgroundColor3 = RGB(50, 54, 58), Font = UI_FONT, TextSize = 15, TextColor3 = RGB(240, 240, 240), Text = text }, nil)
	corner(b, 8)
	b.MouseButton1Click:Connect(fn)
	return b
end
local diffRow = make("Frame", { Position = UDim2.new(0, 14, 0, 72), Size = UDim2.new(1, -28, 0, 40), BackgroundTransparency = 1 }, liftPanel)
local diffButtons = {}
for i, id in ipairs({ "easy", "normal", "hard" }) do
	local d = Config.Difficulty[id]
	local b = make("TextButton", { Position = UDim2.new((i - 1) / 3, 2, 0, 0), Size = UDim2.new(1 / 3, -4, 1, 0), BackgroundColor3 = RGB(50, 54, 58), Font = UI_FONT, TextSize = 15, TextColor3 = RGB(d.Color[1], d.Color[2], d.Color[3]), Text = d.Name }, diffRow)
	corner(b, 8)
	b.MouseButton1Click:Connect(function()
		remote("LiftSettings"):FireServer("diff", id)
	end)
	diffButtons[id] = b
end
local hostRow = make("Frame", { Position = UDim2.new(0, 14, 0, 120), Size = UDim2.new(1, -28, 0, 40), BackgroundTransparency = 1 }, liftPanel)
local friendsB = liftBtn("Только друзья: ВЫКЛ", 0, 180, function()
	remote("LiftSettings"):FireServer("friends", not player:GetAttribute("LiftFriends"))
end)
friendsB.Parent = hostRow
local minusB = liftBtn("−", 190, 40, function()
	remote("LiftSettings"):FireServer("max", (player:GetAttribute("LiftMax") or 5) - 1)
end)
minusB.Parent = hostRow
local maxLabel = make("TextLabel", { Position = UDim2.new(0, 232, 0, 0), Size = UDim2.new(0, 120, 1, 0), BackgroundTransparency = 1, Font = UI_FONT, TextSize = 15, TextColor3 = RGB(240, 240, 240), Text = "" }, hostRow)
local plusB = liftBtn("+", 352, 40, function()
	remote("LiftSettings"):FireServer("max", (player:GetAttribute("LiftMax") or 5) + 1)
end)
plusB.Parent = hostRow
local goB = make("TextButton", { Position = UDim2.new(0, 14, 0, 170), Size = UDim2.new(1, -28, 0, 46), BackgroundColor3 = RGB(60, 120, 60), Font = UI_FONT, TextSize = 18, TextColor3 = RGB(255, 255, 255), Text = "ЕХАТЬ СЕЙЧАС" }, liftPanel)
corner(goB, 8)
goB.MouseButton1Click:Connect(function()
	remote("LiftSettings"):FireServer("go")
end)

local function updateLiftPanel()
	local id = player:GetAttribute("LiftId")
	liftPanel.Visible = id ~= nil and not inMatch() and not cutscene
	if not liftPanel.Visible then
		return
	end
	local d = Config.Difficulty[player:GetAttribute("LiftDiff") or "normal"]
	liftTitle.Text = "ЛИФТ · сложность: " .. d.Name
	liftTitle.TextColor3 = RGB(d.Color[1], d.Color[2], d.Color[3])
	local cd = player:GetAttribute("LiftCountdown") or -1
	liftInfo.Text = "Игроков: " .. (player:GetAttribute("LiftCount") or 1) .. "/" .. (player:GetAttribute("LiftMax") or 5) .. "   ·   отправление через " .. math.max(0, cd) .. " с"
	local host = player:GetAttribute("LiftHost") == true
	hostRow.Visible = host
	diffRow.Visible = host
	goB.Visible = host
	liftPanel.Size = UDim2.new(0, 460, 0, host and 230 or 76)
	for did, b in pairs(diffButtons) do
		b.BackgroundColor3 = (player:GetAttribute("LiftDiff") == did) and RGB(80, 86, 92) or RGB(36, 38, 42)
	end
	friendsB.Text = player:GetAttribute("LiftFriends") and "Только друзья: ВКЛ" or "Только друзья: ВЫКЛ"
	maxLabel.Text = "Максимум: " .. (player:GetAttribute("LiftMax") or 5)
	if not host then
		liftInfo.Text = liftInfo.Text .. "   ·   хозяин: " .. (player:GetAttribute("LiftHostName") or "")
	end
end

-- магазин классов
local shopPanel = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 560, 0, 470), BackgroundColor3 = RGB(26, 22, 18), Visible = false, ZIndex = 12 }, gui)
corner(shopPanel, 12)
make("TextLabel", { Position = UDim2.new(0, 16, 0, 10), Size = UDim2.new(1, -32, 0, 36), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 24, TextColor3 = RGB(255, 210, 90), Text = "ТОРГОВЕЦ КЛАССАМИ", ZIndex = 12 }, shopPanel)
local shopList = make("Frame", { Position = UDim2.new(0, 14, 0, 54), Size = UDim2.new(1, -28, 1, -116), BackgroundTransparency = 1, ZIndex = 12 }, shopPanel)
make("UIListLayout", { Padding = UDim.new(0, 6) }, shopList)
local shopClose = make("TextButton", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(0, 160, 0, 40), BackgroundColor3 = RGB(90, 40, 30), Font = UI_FONT, TextSize = 18, TextColor3 = RGB(255, 240, 230), Text = "Закрыть", Modal = true, ZIndex = 12 }, shopPanel)
corner(shopClose, 8)
shopClose.MouseButton1Click:Connect(function()
	shopPanel.Visible = false
end)
local function renderShop()
	for _, c in ipairs(shopList:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local owned = {}
	pcall(function()
		owned = HttpService:JSONDecode(player:GetAttribute("OwnedClasses") or "[]")
	end)
	for _, c in ipairs(Config.Classes) do
		local row = make("Frame", { Size = UDim2.new(1, 0, 0, 58), BackgroundColor3 = RGB(44, 38, 30), ZIndex = 12 }, shopList)
		corner(row, 8)
		make("TextLabel", { Position = UDim2.new(0, 10, 0, 4), Size = UDim2.new(1, -150, 0, 24), BackgroundTransparency = 1, Font = UI_FONT, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = RGB(245, 235, 210), Text = c.Name .. (c.Price > 0 and ("  ·  " .. c.Price .. " 🪙") or ""), ZIndex = 12 }, row)
		make("TextLabel", { Position = UDim2.new(0, 10, 0, 28), Size = UDim2.new(1, -150, 0, 24), BackgroundTransparency = 1, Font = TEXT_FONT, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = RGB(190, 180, 160), Text = c.Desc, ZIndex = 12 }, row)
		local has = table.find(owned, c.Id) ~= nil
		local current = player:GetAttribute("Class") == c.Id
		local b = make("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.new(0, 120, 0, 38), BackgroundColor3 = current and RGB(80, 80, 80) or (has and RGB(60, 90, 140) or RGB(60, 120, 60)), Font = UI_FONT, TextSize = 15, TextColor3 = RGB(255, 255, 255), Text = current and "Выбран" or (has and "Выбрать" or "Купить"), ZIndex = 12 }, row)
		corner(b, 6)
		b.MouseButton1Click:Connect(function()
			remote("ShopBuy"):FireServer(c.Id)
			task.delay(0.4, renderShop)
		end)
	end
end
remote("ShopOpen").OnClientEvent:Connect(function()
	renderShop()
	shopPanel.Visible = true
end)

-- записки
local notePanel = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 460, 0, 380), BackgroundColor3 = RGB(226, 214, 186), Visible = false, ZIndex = 14 }, gui)
corner(notePanel, 4)
local noteTitle = make("TextLabel", { Position = UDim2.new(0, 22, 0, 16), Size = UDim2.new(1, -44, 0, 32), BackgroundTransparency = 1, Font = Enum.Font.Merriweather, TextSize = 24, TextColor3 = RGB(70, 40, 25), Text = "", ZIndex = 14 }, notePanel)
local noteBody = make("TextLabel", { Position = UDim2.new(0, 26, 0, 60), Size = UDim2.new(1, -52, 1, -130), BackgroundTransparency = 1, Font = Enum.Font.Merriweather, TextSize = 19, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = RGB(45, 32, 25), Text = "", ZIndex = 14 }, notePanel)
local noteClose = make("TextButton", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.new(0, 150, 0, 38), BackgroundColor3 = RGB(80, 50, 35), Font = UI_FONT, TextSize = 17, TextColor3 = RGB(250, 240, 225), Text = "Закрыть", Modal = true, ZIndex = 14 }, notePanel)
corner(noteClose, 6)
noteClose.MouseButton1Click:Connect(function()
	notePanel.Visible = false
end)
remote("Note").OnClientEvent:Connect(function(title, text)
	noteTitle.Text = title
	noteBody.Text = text
	notePanel.Visible = true
	sound(Config.Sounds.Click, 0.4, 0.7)
end)

-- сон и укрытие в лианах
local restPanel = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = RGB(0, 0, 0), BackgroundTransparency = 1, Visible = false, ZIndex = 5 }, gui)
local restText = make("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.75), Size = UDim2.new(0.8, 0, 0, 60), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 22, TextColor3 = RGB(230, 235, 220), TextStrokeTransparency = 0.4, Text = "", ZIndex = 5 }, restPanel)
local leafFrames = {}
for k = 1, 14 do
	local a = k / 14 * math.pi * 2
	local f = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + math.cos(a) * 0.55, 0.5 + math.sin(a) * 0.6),
		Size = UDim2.fromScale(0.5, 0.5),
		Rotation = math.deg(a),
		BackgroundColor3 = RGB(30 + k % 3 * 10, 70 + k % 4 * 8, 30),
		BackgroundTransparency = 0.15,
		ZIndex = 5,
	}, restPanel)
	corner(f, 200)
	table.insert(leafFrames, f)
end

-- ранение
local downedPanel = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = RGB(90, 0, 0), BackgroundTransparency = 0.6, Visible = false, ZIndex = 6 }, gui)
local downedText = make("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.new(0.8, 0, 0, 120), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 26, TextColor3 = RGB(255, 230, 220), TextStrokeTransparency = 0.3, Text = "", ZIndex = 6 }, downedPanel)

player.CharacterAdded:Connect(function(c)
	task.wait(1)
	if not cutscene then
		local cam = workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Custom
		local h = c:FindFirstChildOfClass("Humanoid")
		if h then
			cam.CameraSubject = h
		end
	end
	crouched = false
	Viewmodel.rebuild()
	Viewmodel.setItem(equipped or "fists", true)
end)

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
	titleLabel.Visible = false
	if not cutscene then
		lobbyLabel.Text = ""
	end
	updateLiftPanel()
	coinsLabel.Visible = not inMatch()
	coinsLabel.Text = "🪙 " .. (player:GetAttribute("Coins") or 0) .. "  ·  класс: " .. className(player:GetAttribute("Class"))

	-- фаза дня (у каждой группы своя)
	phaseLabel.Visible = inMatch()
	local phase = player:GetAttribute("Phase") or "day"
	local pStart = player:GetAttribute("PhaseStart") or workspace:GetServerTimeNow()
	local pLen = player:GetAttribute("PhaseLen") or 300
	local elapsed = workspace:GetServerTimeNow() - pStart
	local left = pLen - elapsed
	local day = player:GetAttribute("Day") or 1
	local diff = Config.Difficulty[player:GetAttribute("Difficulty") or "normal"]
	local tagText = diff and ("[" .. diff.Name .. "]  ") or ""
	if phase == "day" then
		phaseLabel.Text = tagText .. "☀  День " .. day .. "  ·  врата закроются через " .. formatTime(left)
		phaseLabel.TextColor3 = left < Config.WarningTime and RGB(255, 120, 90) or RGB(240, 230, 200)
	else
		phaseLabel.Text = tagText .. "☾  Ночь  ·  врата закрыты  ·  рассвет через " .. formatTime(left)
		phaseLabel.TextColor3 = RGB(170, 190, 255)
	end
	applyLighting(inMatch() and phase or nil, math.clamp(elapsed / pLen, 0, 1))

	-- курсор только в меню
	UserInputService.MouseIconEnabled = not playing or craft.Visible or shopPanel.Visible or notePanel.Visible or cursorForced()

	-- ранение
	local downed = player:GetAttribute("Downed") == true
	downedPanel.Visible = downed and inMatch()
	local sleeping, hidden = player:GetAttribute("Sleeping") == true, player:GetAttribute("Hidden") == true
	restPanel.Visible = (sleeping or hidden) and inMatch()
	if restPanel.Visible then
		restPanel.BackgroundTransparency = sleeping and 0.15 or 0.75
		for _, f in ipairs(leafFrames) do
			f.Visible = hidden
		end
		restText.Text = sleeping and "Zzz... Ты спишь. Ночь пройдёт, когда уснут все.  (E у кровати — встать)" or "Ты в зарослях лиан. Скрежетники тебя не видят.  (E — вылезти)"
	end
	if downed then
		local dl = (player:GetAttribute("DownedEnd") or 0) - workspace:GetServerTimeNow()
		downedText.Text = "ТЫ РАНЕН\nДруг может поднять тебя бинтом (зажать E рядом с тобой)\nОчнёшься у лифта через " .. formatTime(dl)
	end
	if hum and inMatch() then
		hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	end

	-- здоровье и выносливость
	hpBack.Visible, stBack.Visible, hotbar.Visible = inMatch(), inMatch(), inMatch() and not cutscene
	resPanel.Visible = inMatch() and #resPanel:GetChildren() > 2
	if hum then
		hpFill.Size = UDim2.fromScale(math.clamp(hum.Health / hum.MaxHealth, 0, 1), 1)
		hpText.Text = math.floor(hum.Health) .. " / " .. hum.MaxHealth
		local moving = hum.MoveDirection.Magnitude > 0.1
		local sprinting = playing and sprintHeld and moving and not exhausted and stamina > 0 and not crouched
		if sprinting then
			stamina = math.max(0, stamina - Config.StaminaDrain * dt)
			exhausted = stamina <= 0
		else
			stamina = math.min(staminaMax(), stamina + Config.StaminaRegen * dt)
			if exhausted and stamina > 30 then
				exhausted = false
			end
		end
		local cls = player:GetAttribute("Class")
		local sprint = Config.SprintSpeed * (cls == "runner" and 1.3 or 1)
		if downed then
			hum.WalkSpeed = 0
		elseif crouched then
			hum.WalkSpeed = Config.CrouchSpeed
		else
			hum.WalkSpeed = sprinting and sprint or Config.WalkSpeed
		end
		stFill.Size = UDim2.fromScale(stamina / staminaMax(), 1)
		vmState.visible, vmState.moving, vmState.sprinting = playing, moving, sprinting

	else
		vmState.visible = false
	end

	-- строительство
	local eqKind = equipped and Items.Tools[equipped] and Items.Tools[equipped].Kind
	BuildMode.update((playing and (eqKind == "blueprint" or eqKind == "hammer")) and eqKind or nil, rayParams())

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
		devCursorOn = unlocker.Visible
		b.Text = unlocker.Visible and "Курсор: ВКЛ (M)" or "Курсор: ВЫКЛ (M)"
	end)
	-- полный свет (L): переписываем свет каждый кадр, т.к. сервер меняет время суток
	local full = false
	local fullB = btn("Полный свет: ВЫКЛ (L)", function(b)
		full = not full
		fullLightOn = full
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
		flyingNow = on
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
	btn("+500 монет", function()
		remote("Dev"):FireServer("coins")
	end)
	btn("Ранить себя (тест)", function()
		remote("Dev"):FireServer("down")
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.M then
			unlocker.Visible = not unlocker.Visible
			devCursorOn = unlocker.Visible
			cursorB.Text = unlocker.Visible and "Курсор: ВКЛ (M)" or "Курсор: ВЫКЛ (M)"
		elseif input.KeyCode == Enum.KeyCode.L then
			full = not full
			fullLightOn = full
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
	Size = UDim2.new(0, 760, 0, 20),
	BackgroundTransparency = 1,
	Font = TEXT_FONT,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Right,
	TextColor3 = RGB(200, 195, 180),
	Text = "ЛКМ — удар · E (зажать) — добыть/собрать · C — крафт · 1–9 — предмет · Ctrl — пригнуться · Shift — бег · H — ягоды",
}, gui)
