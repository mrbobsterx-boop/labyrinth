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
local Radial = require(script.Parent:WaitForChild("Radial"))
local PathfindingService = game:GetService("PathfindingService")
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
local armorText = make("TextLabel", { Position = UDim2.new(0, 288, 1, -50), Size = UDim2.new(0, 160, 0, 22), BackgroundTransparency = 1, Font = UI_FONT, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = RGB(190, 210, 240), TextStrokeTransparency = 0.5, Text = "" }, gui)
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
Radial.init(gui)
local toggleMap, updateMap, updatePings
local lobbyBar, updateMusic, settingsPanel, adminPanel
local spectating, spectateIndex = nil, 0
local musicOn = true

local function equip(id)
	if id == equipped then
		id = nil
	end
	equipped = id
	remote("Equip"):FireServer(id)
	Viewmodel.setItem(id or "fists")
	sound(Config.Sounds.Click, 0.4, 1.4)
end

-- в хотбаре: инструменты + то, что есть в инвентаре и можно держать (ключ-карта, карта, бинт, ягоды)
local HELD = { "res_key", "res_map", "res_bandage", "res_berry" }
local function hotbarList()
	local list = table.clone(tools)
	for _, id in ipairs(HELD) do
		local def = Items.Tools[id]
		if (player:GetAttribute("Res_" .. def.Res) or 0) > 0 then
			table.insert(list, id)
		end
	end
	return list
end

local function refreshHotbar()
	for _, c in ipairs(hotbar:GetChildren()) do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	for i, id in ipairs(hotbarList()) do
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
		local k = name:sub(5)
		if k == "key" or k == "map" or k == "bandage" or k == "berry" then
			refreshHotbar()
		end
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

------------------------------------------------------------------
-- Карта лабиринта (Tab): её нужно найти. Меняется вместе со стенами.
------------------------------------------------------------------
local mapPanel = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(600, 600),
	BackgroundColor3 = RGB(214, 196, 150),
	Visible = false,
	ZIndex = 25,
}, gui)
corner(mapPanel, 14)
make("UIStroke", { Color = RGB(90, 70, 40), Thickness = 4 }, mapPanel)
make("TextLabel", { Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 18, TextColor3 = RGB(70, 50, 30), Text = "КАРТА ЛАБИРИНТА  ·  Tab — закрыть", ZIndex = 26 }, mapPanel)
local mapCanvas = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 12), Size = UDim2.fromOffset(550, 550), BackgroundTransparency = 1, ZIndex = 26 }, mapPanel)
local mapMe = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = RGB(220, 30, 30), ZIndex = 29 }, mapCanvas)
corner(mapMe, 6)
local mapData
local function mapScale()
	return mapData and (550 / (mapData.radius * 2 + 80)) or 0.3
end
local function toMap(rel)
	local sc = mapScale()
	return UDim2.fromOffset(275 + rel.X * sc, 275 + rel.Z * sc)
end
local function drawMap()
	for _, c in ipairs(mapCanvas:GetChildren()) do
		if c ~= mapMe then
			c:Destroy()
		end
	end
	if not mapData then
		return
	end
	local sc = mapScale()
	local circle = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(275, 275), Size = UDim2.fromOffset(mapData.radius * 2 * sc, mapData.radius * 2 * sc), BackgroundTransparency = 1, ZIndex = 26 }, mapCanvas)
	corner(circle, 1000)
	make("UIStroke", { Color = RGB(120, 95, 60), Thickness = 2, Transparency = 0.5 }, circle)
	local ch = mapData.clearing
	local clr = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(275, 275), Size = UDim2.fromOffset(ch * 2 * sc, ch * 2 * sc), BackgroundColor3 = RGB(120, 160, 90), BackgroundTransparency = 0.3, ZIndex = 26 }, mapCanvas)
	make("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = RGB(40, 60, 30), Text = "ПОЛЯНА", ZIndex = 27 }, clr)
	for _, w in ipairs(mapData.walls) do
		local axis, fixedC, a, b, crack = w[1], w[2], w[3], w[4], w[5]
		local len = (b - a) * sc
		local thick = math.max(2, 4 * sc)
		local f
		if axis == 1 then
			f = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = toMap(V((a + b) / 2, 0, fixedC)), Size = UDim2.fromOffset(len, thick), BorderSizePixel = 0, ZIndex = 27 }, mapCanvas)
		else
			f = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = toMap(V(fixedC, 0, (a + b) / 2)), Size = UDim2.fromOffset(thick, len), BorderSizePixel = 0, ZIndex = 27 }, mapCanvas)
		end
		f.BackgroundColor3 = crack == 1 and RGB(160, 120, 70) or RGB(60, 45, 30)
	end
	local exitM = make("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = toMap(mapData.exit), Size = UDim2.fromOffset(70, 18), BackgroundColor3 = RGB(40, 140, 70), Font = Enum.Font.GothamBlack, TextSize = 12, TextColor3 = RGB(255, 255, 255), Text = "ВЫХОД", ZIndex = 28 }, mapCanvas)
	corner(exitM, 4)
end
remote("MapData").OnClientEvent:Connect(function(walls, O, clearing, radius, exitRel)
	mapData = { walls = walls, O = O, clearing = clearing, radius = radius, exit = exitRel }
	if mapPanel.Visible then
		drawMap()
	else
		mapData.dirty = true
	end
end)
function toggleMap()
	if mapPanel.Visible then
		mapPanel.Visible = false
		return
	end
	if (player:GetAttribute("Res_map") or 0) < 1 or not mapData then
		notify("У тебя нет карты. Она лежит на столе где-то в лабиринте.")
		return
	end
	mapData.dirty = false
	drawMap()
	mapPanel.Visible = true
end
function updateMap()
	if not mapPanel.Visible then
		return
	end
	if not inMatch() then
		mapPanel.Visible = false
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and mapData then
		mapMe.Position = toMap(hrp.Position - mapData.O)
		mapMe.Visible = true
	end
end

------------------------------------------------------------------
-- Сигнал раненого: подсветка сквозь стены и стрелки на полу к нему
------------------------------------------------------------------
local pingFx = {} -- [player] = {hl, arrows, nextPath}
local function clearPing(who)
	local fx = pingFx[who]
	if fx then
		if fx.hl then
			fx.hl:Destroy()
		end
		for _, a in ipairs(fx.arrows) do
			a:Destroy()
		end
		pingFx[who] = nil
	end
end
local pathObj = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = false, WaypointSpacing = 6 })
local function drawArrows(fx, points)
	for _, a in ipairs(fx.arrows) do
		a:Destroy()
	end
	fx.arrows = {}
	for k = 1, math.min(#points - 1, 16) do
		local a, b = points[k], points[k + 1]
		if (b - a).Magnitude > 0.5 then
			local arrow = Instance.new("WedgePart")
			arrow.Anchored = true
			arrow.CanCollide = false
			arrow.CanQuery = false
			arrow.CastShadow = false
			arrow.Size = V(2, 0.3, 2.4)
			arrow.Material = Enum.Material.Neon
			arrow.Color = RGB(255, 210, 60)
			local flat = V(b.X - a.X, 0, b.Z - a.Z)
			-- клин «смотрит» острым концом вперёд (-Z)
			arrow.CFrame = CFrame.lookAt(a + V(0, 0.3, 0), a + V(0, 0.3, 0) + flat)
			arrow.Parent = workspace.CurrentCamera
			table.insert(fx.arrows, arrow)
		end
	end
end
function updatePings()
	local now = workspace:GetServerTimeNow()
	local char = player.Character
	local myHrp = char and char:FindFirstChild("HumanoidRootPart")
	for _, who in ipairs(Players:GetPlayers()) do
		local active = who ~= player and inMatch() and (who:GetAttribute("PingUntil") or 0) > now and who:GetAttribute("Downed") == true and who.Character
		if not active then
			clearPing(who)
		else
			local fx = pingFx[who]
			if not fx then
				fx = { arrows = {}, nextPath = 0 }
				local hl = Instance.new("Highlight")
				hl.FillColor = RGB(255, 60, 60)
				hl.OutlineColor = RGB(255, 230, 120)
				hl.FillTransparency = 0.3
				hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				hl.Adornee = who.Character
				hl.Parent = workspace.CurrentCamera
				fx.hl = hl
				pingFx[who] = fx
			end
			local theirs = who.Character:FindFirstChild("HumanoidRootPart")
			if myHrp and theirs and os.clock() >= fx.nextPath and not fx.busy then
				fx.nextPath = os.clock() + 1.5
				fx.busy = true
				local from, to = myHrp.Position, theirs.Position
				task.spawn(function()
					local pts
					local ok = pcall(function()
						pathObj:ComputeAsync(from, to)
					end)
					if ok and pathObj.Status == Enum.PathStatus.Success then
						pts = {}
						for _, w in ipairs(pathObj:GetWaypoints()) do
							table.insert(pts, w.Position)
						end
					else
						pts = {}
						local dir = (to - from) * V(1, 0, 1)
						for k = 0, 8 do
							table.insert(pts, from - V(0, 2.8, 0) + dir.Unit * (4 + k * 5))
						end
					end
					fx.busy = false
					if pingFx[who] == fx then
						drawArrows(fx, pts)
					end
				end)
			end
		end
	end
end

-- раненое тело — тряпичная кукла (физику включаем на своём клиенте)
player:GetAttributeChangedSignal("Downed"):Connect(function()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	if player:GetAttribute("Downed") then
		hum:ChangeState(Enum.HumanoidStateType.Physics)
	else
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end)

-- мигающие лампы (туннель, лаборатория, костры)
task.spawn(function()
	while true do
		task.wait(0.09)
		for _, l in ipairs(CollectionService:GetTagged("FlickerLight")) do
			if l:IsA("Light") then
				local base = l:GetAttribute("B0")
				if not base then
					base = l.Brightness
					l:SetAttribute("B0", base)
				end
				local r = math.random()
				l.Brightness = r < 0.06 and base * 0.1 or base * (0.85 + math.random() * 0.25)
			end
		end
	end
end)

local function doSwing()
	if not inMatch() or cutscene or craft.Visible then
		return
	end
	if Radial.isOpen() then
		return
	end
	local def = Items.Tools[equipped or "fists"] or Items.Tools.fists
	if def.Kind == "blueprint" or def.Kind == "deploy" then
		if BuildMode.place(remote("Build"), remote("Place")) then
			sound(Config.Sounds.Click, 0.6, 0.8)
		end
		return
	end
	if def.Kind == "held" then
		if def.Res == "berry" then
			remote("Eat"):FireServer()
			Viewmodel.swing("fists")
		elseif def.Res == "map" then
			toggleMap()
		end
		return
	end
	if def.Kind == "torch" or player:GetAttribute("Downed") or player:GetAttribute("Hidden") or player:GetAttribute("Sleeping") or player:GetAttribute("Dragging") then
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
	elseif input.KeyCode == Enum.KeyCode.R and inMatch() and not cutscene then
		local kind = equipped and Items.Tools[equipped] and Items.Tools[equipped].Kind
		if player:GetAttribute("Downed") then
			remote("Ping"):FireServer()
		elseif kind == "blueprint" then
			BuildMode.pieceMenu(Radial)
		elseif kind == "hammer" then
			BuildMode.hammerMenu(Radial, remote("Upgrade"))
		elseif kind == "deploy" then
			BuildMode.rotate()
			sound(Config.Sounds.Click, 0.4, 1.2)
		end
	elseif input.KeyCode == Enum.KeyCode.Tab and inMatch() and not cutscene then
		toggleMap()
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
		local hb = hotbarList()
		if n >= 1 and n <= 9 and hb[n] then
			equip(hb[n])
			refreshHotbar()
		end
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.R and Radial.isOpen() then
		Radial.confirm()
	end
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
local function buildHeli(cf, K)
	K = K or 1
	local m = Instance.new("Model")
	m.Name = "Helicopter"
	local function p(size, rel, color, mat, extra)
		size = size * K
		rel = CFrame.new(rel.Position * K) * rel.Rotation
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

-- ходьба от первого лица по точкам: покачивание, шаги, друзья рядом
local function walkPath(cam, points, duration, opts)
	opts = opts or {}
	local total = 0
	local segLen = {}
	for k = 1, #points - 1 do
		segLen[k] = (points[k + 1] - points[k]).Magnitude
		total += segLen[k]
	end
	local t0 = os.clock()
	local nextStep = 0
	runFor(duration, function(a)
		local t = os.clock() - t0
		local dist = total * smoothstep(a)
		local k, acc = 1, 0
		while k < #points - 1 and acc + segLen[k] < dist do
			acc += segLen[k]
			k += 1
		end
		local f = segLen[k] > 0 and math.clamp((dist - acc) / segLen[k], 0, 1) or 1
		local pos = points[k]:Lerp(points[k + 1], f)
		local dir = (points[k + 1] - points[k])
		dir = dir.Magnitude > 0.01 and dir.Unit or V(0, 0, -1)
		local bob = math.sin(t * 9) * 0.2
		local side = math.cos(t * 4.5) * 0.1
		local look = opts.lookAt and opts.lookAt(a, pos) or (pos + dir * 10 + V(0, (opts.pitch or 0) * 10, 0))
		cam.CFrame = CFrame.lookAt(pos + V(side, bob, 0), look) * CFrame.Angles(0, 0, math.cos(t * 4.5) * 0.01)
		if t >= nextStep and a < 0.98 then
			nextStep = t + (opts.stepGap or 0.48)
			sound(Config.Sounds.Step, 0.35, (opts.stepPitch or 0.75) + math.random() * 0.15)
		end
		if opts.each then
			opts.each(a, pos, dir, t)
		end
	end)
end

-- ролик у выхода: туннель → мост над пропастью → дверь лаборатории и считыватель
remote("ExitIntro").OnClientEvent:Connect(function(pts, readerPos)
	cutscene = true
	craft.Visible = false
	Radial.close()
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local fwd = ((pts[3] - pts[1]) * V(1, 0, 1)).Unit
	local right = fwd:Cross(V(0, 1, 0))
	subtitle.Text = "Выход... Огромный проход — и сразу пропасть."
	walkPath(cam, { pts[1], pts[2] }, 1.8)
	subtitle.Text = "Не смотри вниз. Только по мосту."
	walkPath(cam, { pts[2], pts[3] }, 3.4, {
		stepGap = 0.6,
		stepPitch = 0.55,
		lookAt = function(a, pos)
			local down = math.sin(math.clamp((a - 0.1) / 0.5, 0, 1) * math.pi) * 9
			return pos + fwd * 10 - V(0, down, 0) + right * math.sin(a * 6) * 1.5
		end,
	})
	local eye = pts[3]
	local fromLook = eye + fwd * 10
	subtitle.Text = "Дверь... и считыватель. Ключ-карта! Нужно приложить ключ-карту."
	runFor(1.2, function(a)
		cam.CFrame = CFrame.lookAt(eye, fromLook:Lerp(readerPos, smoothstep(a)))
	end)
	task.wait(1.2)
	subtitle.Text = ""
	cam.CameraType = Enum.CameraType.Custom
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		cam.CameraSubject = hum
	end
	cutscene = false
	notify("Достань ключ-карту и приложи к считывателю (E). Ключ-карта — в золотом сундуке.")
end)

-- достаём ключ-карту из кармана и прикладываем к считывателю
remote("CardInsert").OnClientEvent:Connect(function(readerPos)
	cutscene = true
	Radial.close()
	local cam = workspace.CurrentCamera
	local eye = cam.CFrame.Position
	cam.CameraType = Enum.CameraType.Scriptable
	local from = cam.CFrame
	runFor(0.5, function(a)
		cam.CFrame = from:Lerp(CFrame.lookAt(eye, readerPos), smoothstep(a))
	end)
	Viewmodel.card()
	task.wait(1.1)
	sound(Config.Sounds.Click, 0.8, 1.6)
	task.wait(0.2)
	sound(Config.Sounds.Click, 0.8, 2)
end)

remote("MazeShift").OnClientEvent:Connect(function()
	shake(0.9)
	sound(Config.Sounds.Rumble, 1.5, 0.35)
	task.delay(1.2, function()
		shake(0.6)
	end)
end)

remote("Outro").OnClientEvent:Connect(function(info)
	cutscene = true
	craft.Visible = false
	Radial.close()
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local temp = {}
	local mazeCenter = info.mazeCenter
	local b = info.exitOut
	local fwd = b.LookVector

	-- друзья идут рядом
	local friends = {}
	local k = 0
	for _, who in ipairs(info.players) do
		if who ~= player then
			k += 1
			local av = cloneAvatar(who)
			if av then
				av.Parent = workspace
				table.insert(temp, av)
				table.insert(friends, { m = av, side = (k % 2 == 1) and -3.5 or 3.5, back = 2 + math.floor((k - 1) / 2) * 3.5 })
			end
		end
	end
	local function moveFriends(pos, dir, t)
		local right = dir:Cross(V(0, 1, 0))
		for _, f in ipairs(friends) do
			local fp = pos + right * f.side - dir * f.back - V(0, 2.4, 0) + V(0, math.abs(math.sin(t * 9)) * 0.25, 0)
			f.m:PivotTo(CFrame.lookAt(fp, fp + dir))
		end
	end

	-- 1. дверь лаборатории поднимается
	local eye0 = info.doorEye
	subtitle.Text = "Дверь открывается..."
	runFor(3, function()
		cam.CFrame = CFrame.lookAt(eye0, info.labStart.Position) * CFrame.Angles(math.noise(os.clock() * 3) * 0.008, 0, 0)
	end)

	-- 2. идём через пустую лабораторию
	subtitle.Text = "Лаборатория... Здесь никого нет. Будто все ушли в спешке."
	walkPath(cam, { eye0, info.labStart.Position, info.labEnd.Position }, 11, {
		stepPitch = 0.9,
		lookAt = function(a, pos)
			local sway = math.sin(a * math.pi * 3) * 6
			return pos + fwd * 10 + b.RightVector * sway - V(0, 1, 0)
		end,
		each = function(_, pos, dir, t)
			moveFriends(pos, dir, t)
		end,
	})

	-- 3. вторая дверь открывается — снаружи свет и шум винтов
	subtitle.Text = "Ещё одна дверь..."
	local back = info.backDoor
	if back and back.Parent then
		local goal = back.CFrame + V(0, 11, 0)
		TweenService:Create(back, TweenInfo.new(2.4, Enum.EasingStyle.Sine), { CFrame = goal }):Play()
	end
	local eye1 = info.labEnd.Position
	runFor(2.6, function()
		cam.CFrame = CFrame.lookAt(eye1, eye1 + fwd * 10) * CFrame.Angles(math.noise(os.clock() * 4) * 0.01, 0, 0)
	end)

	-- 4. огромный вертолёт садится на площадку
	local K = 1.8
	local pad = info.pad
	local heliCF = pad * CFrame.new(0, 0.6 * K, 0) * CFrame.Angles(0, math.pi / 2, 0)
	local startCF = heliCF + V(0, 140, 0) + fwd * 160
	local heli, setCF = buildHeli(startCF, K)
	table.insert(temp, heli)
	local rotor = make("Sound", { SoundId = Config.Sounds.Rumble, Looped = true, Volume = 1, PlaybackSpeed = 0.7 }, SoundService)
	rotor:Play()
	subtitle.Text = "Вертолёт! Он садится прямо перед нами!"
	local outside = (pad * CFrame.new(0, 5.3, 0)).Position - fwd * 34
	local heliNow = startCF
	walkPath(cam, { eye1, outside }, 9, {
		lookAt = function(_, pos)
			local hp = heliNow.Position
			return pos:Lerp(hp, 0.5) + (hp - pos).Unit * 10
		end,
		each = function(a, pos, dir, t)
			moveFriends(pos, dir, t)
			local e = smoothstep(math.clamp(a * 1.15, 0, 1))
			local cf = startCF:Lerp(heliCF, e) * CFrame.Angles(0.12 * (1 - e), 0, math.sin(t * 1.3) * 0.04 * (1 - e))
			heliNow = cf
			setCF(cf, 1 / 60)
			if e > 0.85 then
				shake(0.02)
			end
		end,
	})
	runFor(1.5, function()
		setCF(heliCF, 1 / 60)
		cam.CFrame = CFrame.lookAt(outside, heliCF.Position)
	end)

	-- 5. садимся у открытой боковой двери
	subtitle.Text = "Залезаем!"
	fade.BackgroundColor3 = RGB(0, 0, 0)
	TweenService:Create(fade, TweenInfo.new(0.4), { BackgroundTransparency = 0 }):Play()
	task.wait(0.45)
	for _, f in ipairs(friends) do
		f.m:Destroy()
	end
	local seat = CFrame.new(5.4 * K, 4.6 * K, 2.6 * K)
	cam.CFrame = CFrame.lookAt((heliCF * seat).Position, (heliCF * CFrame.new(30 * K, 2, 2.6 * K)).Position)
	TweenService:Create(fade, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()

	-- 6. взлёт: высоко над лабиринтом, смотрим на него целиком
	subtitle.Text = "Взлетаем... Вот он — весь лабиринт."
	local high = heliCF.Position:Lerp(mazeCenter, 0.35) + V(0, 520, 0)
	runFor(11, function(a)
		local e = smoothstep(a)
		local pos = heliCF.Position:Lerp(high, e)
		local toMaze = (mazeCenter - pos) * V(1, 0, 1)
		local hc = CFrame.lookAt(pos, pos + V(toMaze.Z, 0, -toMaze.X)) * CFrame.Angles(-0.08 * math.sin(a * math.pi), 0, 0)
		setCF(hc, 1 / 60)
		cam.CFrame = CFrame.lookAt((hc * seat).Position, mazeCenter) * CFrame.Angles(math.noise(os.clock() * 5) * 0.006, 0, 0)
	end)
	task.wait(2.5)

	-- 7. улетаем к горизонту
	subtitle.Text = "Прощай, лабиринт."
	local away = (high - mazeCenter) * V(1, 0, 1)
	away = away.Magnitude > 1 and away.Unit or V(1, 0, 0)
	runFor(5, function(a)
		local pos = high + away * 700 * a * a + V(0, 60 * a, 0)
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
	lobbyLabel.Text = "ВЫ ВЫБРАЛИСЬ ИЗ ЛАБИРИНТА!\nДней в лабиринте: " .. info.day .. "   ·   +" .. info.coins .. " монет"
	task.wait(4)
	-- ждём, пока сервер вернёт нас в лобби, и только потом убираем чёрный экран
	local waitT = os.clock()
	while inMatch() and os.clock() - waitT < 14 do
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

-- монеты (в лобби): золотая монета с гравировкой Скрежетника и счётчик
local coinWidget = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -18), Size = UDim2.fromOffset(330, 110), BackgroundTransparency = 1 }, gui)
local coin = make("Frame", { Size = UDim2.fromOffset(104, 104), BackgroundColor3 = RGB(232, 182, 60) }, coinWidget)
corner(coin, 100)
make("UIStroke", { Color = RGB(140, 96, 24), Thickness = 4 }, coin)
make("UIGradient", { Rotation = 45, Color = ColorSequence.new(RGB(255, 228, 130), RGB(196, 140, 40)) }, coin)
local inner = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(80, 80), BackgroundTransparency = 1 }, coin)
corner(inner, 100)
make("UIStroke", { Color = RGB(176, 124, 34), Thickness = 2 }, inner)
-- гравировка: тело-слизень, жало и восемь ног — одним цветом, как на старой монете
local ENG = RGB(150, 104, 28)
local function engr(pos, size, rot, round)
	local f = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Size = size, Rotation = rot or 0, BackgroundColor3 = ENG, BorderSizePixel = 0 }, coin)
	if round then
		corner(f, 100)
	end
	return f
end
engr(UDim2.fromOffset(52, 56), UDim2.fromOffset(40, 22), 0, true)
engr(UDim2.fromOffset(32, 54), UDim2.fromOffset(14, 14), 0, true)
for k, x in ipairs({ 38, 46, 56, 64 }) do
	local tilt = (k - 2.5) * 12
	engr(UDim2.fromOffset(x, 44), UDim2.fromOffset(3, 16), -25 + tilt, false)
	engr(UDim2.fromOffset(x - 3, 37), UDim2.fromOffset(3, 12), 30 + tilt, false)
	engr(UDim2.fromOffset(x, 68), UDim2.fromOffset(3, 16), 25 - tilt, false)
	engr(UDim2.fromOffset(x - 3, 75), UDim2.fromOffset(3, 12), -30 - tilt, false)
end
engr(UDim2.fromOffset(74, 46), UDim2.fromOffset(4, 16), 40, false)
engr(UDim2.fromOffset(78, 36), UDim2.fromOffset(4, 12), 0, false)
engr(UDim2.fromOffset(75, 29), UDim2.fromOffset(4, 8), -50, false)
local coinsLabel = make("TextLabel", {
	Position = UDim2.fromOffset(116, 14),
	Size = UDim2.fromOffset(210, 50),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextSize = 44,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = RGB(255, 222, 110),
	TextStrokeTransparency = 0,
	TextStrokeColor3 = RGB(90, 60, 10),
	Text = "0",
}, coinWidget)
local classLabel = make("TextLabel", {
	Position = UDim2.fromOffset(118, 62),
	Size = UDim2.fromOffset(210, 24),
	BackgroundTransparency = 1,
	Font = UI_FONT,
	TextSize = 16,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = RGB(240, 235, 220),
	TextStrokeTransparency = 0.4,
	Text = "",
}, coinWidget)

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

-- нижняя панель лобби: большие кнопки с картинками
lobbyBar = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(460, 120), BackgroundColor3 = RGB(20, 20, 24), BackgroundTransparency = 0.35 }, gui)
corner(lobbyBar, 16)
make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 14) }, lobbyBar)
local function barButton(title, icon, color, fn)
	local b = make("TextButton", { Size = UDim2.fromOffset(130, 104), BackgroundTransparency = 1, Text = "" }, lobbyBar)
	local ic = make("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.fromOffset(72, 72), BackgroundColor3 = color, Font = Enum.Font.FredokaOne, TextSize = 40, TextColor3 = RGB(255, 255, 255), TextStrokeTransparency = 0.2, Text = icon }, b)
	corner(ic, 18)
	make("UIStroke", { Color = RGB(255, 255, 255), Thickness = 3, Transparency = 0.3 }, ic)
	local t = make("TextLabel", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 15, TextColor3 = RGB(255, 255, 255), TextStrokeTransparency = 0.3, Text = title }, b)
	b.MouseEnter:Connect(function()
		TweenService:Create(ic, TweenInfo.new(0.12), { Size = UDim2.fromOffset(80, 80) }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(ic, TweenInfo.new(0.12), { Size = UDim2.fromOffset(72, 72) }):Play()
	end)
	b.MouseButton1Click:Connect(function()
		sound(Config.Sounds.Click, 0.5, 1)
		fn(t)
	end)
	return b
end
barButton("КЛАССЫ", "⚔", RGB(200, 70, 60), function()
	renderShop()
	shopPanel.Visible = true
end)
barButton("КАК ИГРАТЬ", "?", RGB(60, 130, 210), function()
	noteTitle.Text = "Как выжить в лабиринте"
	noteBody.Text = "Зайди в лифт и выбери сложность.\n\nДнём врата открыты: добывай ресурсы, ищи сундуки и записки.\nНа закате вернись на поляну — ночью врата закрыты, а в лабиринте Скрежетники. Каждую ночь стены сдвигаются.\n\nНайди карту (Tab) и ключ-карту в золотом сундуке. Выход — на краю внешнего кольца.\n\nC — крафт · R — меню стройки · Ctrl — пролезть в щель."
	notePanel.Visible = true
end)
barButton("НАСТРОЙКИ", "⚙", RGB(90, 96, 110), function()
	settingsPanel.Visible = not settingsPanel.Visible
end)

-- настройки: музыка, громкость, вход в админ-панель
local musicVolume = Config.Music.Volume or 0.4
settingsPanel = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(380, 300), BackgroundColor3 = RGB(24, 26, 30), BackgroundTransparency = 0.05, Visible = false, ZIndex = 16 }, gui)
corner(settingsPanel, 14)
-- «модальная» кнопка освобождает мышь, пока открыто окно (в виде от первого лица)
make("TextButton", { Size = UDim2.fromOffset(1, 1), BackgroundTransparency = 1, Text = "", Modal = true }, settingsPanel)
make("UIStroke", { Color = RGB(120, 130, 150), Thickness = 2 }, settingsPanel)
make("TextLabel", { Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, Font = Enum.Font.FredokaOne, TextSize = 28, TextColor3 = RGB(240, 240, 235), Text = "НАСТРОЙКИ", ZIndex = 17 }, settingsPanel)
local function sBtn(text, pos, size, color, fn)
	local b = make("TextButton", { Position = pos, Size = size, BackgroundColor3 = color, Font = UI_FONT, TextSize = 17, TextColor3 = RGB(255, 255, 255), Text = text, ZIndex = 17, AutoButtonColor = true }, settingsPanel)
	corner(b, 10)
	b.MouseButton1Click:Connect(function()
		sound(Config.Sounds.Click, 0.4, 1)
		fn(b)
	end)
	return b
end
sBtn("Музыка: ВКЛ", UDim2.fromOffset(30, 58), UDim2.fromOffset(320, 44), RGB(60, 140, 80), function(b)
	musicOn = not musicOn
	b.Text = musicOn and "Музыка: ВКЛ" or "Музыка: ВЫКЛ"
	b.BackgroundColor3 = musicOn and RGB(60, 140, 80) or RGB(110, 60, 60)
end)
local volLabel = make("TextLabel", { Position = UDim2.fromOffset(100, 112), Size = UDim2.fromOffset(180, 44), BackgroundTransparency = 1, Font = UI_FONT, TextSize = 18, TextColor3 = RGB(230, 230, 230), Text = "", ZIndex = 17 }, settingsPanel)
local function showVol()
	volLabel.Text = "Громкость: " .. math.floor(musicVolume * 100 + 0.5) .. "%"
end
showVol()
sBtn("−", UDim2.fromOffset(30, 112), UDim2.fromOffset(60, 44), RGB(70, 76, 90), function()
	musicVolume = math.max(0, musicVolume - 0.1)
	showVol()
end)
sBtn("+", UDim2.fromOffset(290, 112), UDim2.fromOffset(60, 44), RGB(70, 76, 90), function()
	musicVolume = math.min(1, musicVolume + 0.1)
	showVol()
end)
sBtn("Админ-панель", UDim2.fromOffset(30, 170), UDim2.fromOffset(320, 44), RGB(150, 90, 40), function()
	settingsPanel.Visible = false
	adminPanel.Visible = true
end)
sBtn("Закрыть", UDim2.fromOffset(110, 236), UDim2.fromOffset(160, 44), RGB(90, 40, 30), function()
	settingsPanel.Visible = false
end)

-- вход в админ-панель по коду (проверяет сервер)
adminPanel = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(380, 240), BackgroundColor3 = RGB(24, 26, 30), Visible = false, ZIndex = 18 }, gui)
corner(adminPanel, 14)
make("TextButton", { Size = UDim2.fromOffset(1, 1), BackgroundTransparency = 1, Text = "", Modal = true }, adminPanel)
make("UIStroke", { Color = RGB(200, 140, 60), Thickness = 2 }, adminPanel)
make("TextLabel", { Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Font = Enum.Font.FredokaOne, TextSize = 24, TextColor3 = RGB(255, 210, 140), Text = "Доступ к админ-панели", ZIndex = 19 }, adminPanel)
local codeBox = make("TextBox", { Position = UDim2.fromOffset(60, 60), Size = UDim2.fromOffset(260, 50), BackgroundColor3 = RGB(40, 44, 50), Font = Enum.Font.GothamBlack, TextSize = 28, TextColor3 = RGB(255, 255, 255), PlaceholderText = "Введите код", PlaceholderColor3 = RGB(140, 140, 150), Text = "", ClearTextOnFocus = true, ZIndex = 19 }, adminPanel)
corner(codeBox, 10)
local adminMsg = make("TextLabel", { Position = UDim2.fromOffset(0, 116), Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Font = UI_FONT, TextSize = 15, TextColor3 = RGB(255, 120, 110), Text = "", ZIndex = 19 }, adminPanel)
local function aBtn(text, x, color, fn)
	local b = make("TextButton", { Position = UDim2.fromOffset(x, 160), Size = UDim2.fromOffset(150, 46), BackgroundColor3 = color, Font = UI_FONT, TextSize = 17, TextColor3 = RGB(255, 255, 255), Text = text, ZIndex = 19 }, adminPanel)
	corner(b, 10)
	b.MouseButton1Click:Connect(fn)
end
aBtn("Войти", 30, RGB(60, 140, 80), function()
	remote("Admin"):FireServer(codeBox.Text)
	adminMsg.Text = "Проверяю..."
	task.delay(1, function()
		local lvl = player:GetAttribute("Admin") or 0
		if lvl == 2 then
			adminPanel.Visible = false
			notify("Главная админ-панель открыта! Кнопки — справа.")
		elseif lvl == 1 then
			adminPanel.Visible = false
			notify("Админ-панель для друзей открыта! Кнопки — справа.")
		else
			adminMsg.Text = "Неверный код"
		end
	end)
end)
aBtn("Отмена", 200, RGB(90, 40, 30), function()
	adminPanel.Visible = false
end)

-- музыка: спокойный плейлист по кругу, между треками — тишина
local playlist = table.clone(Config.Music.Playlist or {})
local musicSound = make("Sound", { Volume = 0, Looped = false }, SoundService)
local musicIndex = 0
local nextTrackAt = os.clock() + 3
musicSound.Ended:Connect(function()
	nextTrackAt = os.clock() + (Config.Music.Pause or 20)
end)
local function nextTrack()
	if #playlist == 0 then
		return
	end
	-- каждый раз в случайном порядке, без повтора подряд
	local k
	repeat
		k = math.random(1, #playlist)
	until #playlist == 1 or k ~= musicIndex
	musicIndex = k
	musicSound.SoundId = playlist[k]
	musicSound.TimePosition = 0
	musicSound:Play()
	-- трек не загрузился (закрыт) — через паузу пробуем следующий
	task.delay(8, function()
		if musicSound.SoundId == playlist[k] and not musicSound.IsPlaying and musicSound.TimeLength == 0 then
			nextTrackAt = os.clock() + 2
		end
	end)
end
function updateMusic(dt)
	if not musicSound.IsPlaying and nextTrackAt and os.clock() >= nextTrackAt then
		nextTrackAt = nil
		nextTrack()
	end
	local target = musicOn and musicVolume * (player:GetAttribute("Phase") == "night" and inMatch() and 0.7 or 1) or 0
	musicSound.Volume = musicSound.Volume + (target - musicSound.Volume) * math.min(1, (dt or 0.016) * 2)
end

-- кнопка настроек всегда на виду (справа вверху, в углу)
local gearB = make("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), Size = UDim2.fromOffset(46, 46), BackgroundColor3 = RGB(20, 22, 26), BackgroundTransparency = 0.3, Font = Enum.Font.GothamBlack, TextSize = 26, TextColor3 = RGB(240, 240, 240), Text = "⚙" }, gui)
corner(gearB, 100)
gearB.Activated:Connect(function()
	settingsPanel.Visible = not settingsPanel.Visible
end)

-- эффекты приколов админа (ядерка, цунами, денежный дождь)
local flashFrame = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = RGB(255, 255, 240), BackgroundTransparency = 1, ZIndex = 40 }, gui)
remote("Prank").OnClientEvent:Connect(function(kind)
	if kind == "siren" then
		for k = 0, 4 do
			task.delay(k, function()
				sound(Config.Sounds.Rumble, 1.2, 1.6)
				shake(0.15)
			end)
		end
	elseif kind == "flash" then
		flashFrame.BackgroundTransparency = 0
		TweenService:Create(flashFrame, TweenInfo.new(2.5), { BackgroundTransparency = 1 }):Play()
		sound(Config.Sounds.Rumble, 2, 0.3)
		shake(1)
		task.delay(1, function()
			shake(0.8)
		end)
	elseif kind == "rumble" then
		sound(Config.Sounds.Rumble, 2, 0.5)
		shake(0.6)
	elseif kind == "coins" then
		sound(Config.Sounds.Pickup, 1, 1.2)
	end
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

	-- камера: ранен — вид от третьего лица на своё тело
	local isDown = player:GetAttribute("Downed") == true and inMatch()
	if spectating and not (spectating.Parent and spectating.Character) then
		spectating = nil
		if hum then
			workspace.CurrentCamera.CameraSubject = hum
		end
	end
	player.CameraMode = (playing and not isDown and not spectating) and Enum.CameraMode.LockFirstPerson or Enum.CameraMode.Classic
	if isDown then
		player.CameraMinZoomDistance = 9
		player.CameraMaxZoomDistance = 16
	else
		player.CameraMinZoomDistance = 0.5
		if not playing then
			player.CameraMaxZoomDistance = 18
		end
	end
	Radial.update()
	updatePings()
	updateMap()

	-- лобби
	titleLabel.Visible = false
	if not cutscene then
		lobbyLabel.Text = ""
	end
	updateLiftPanel()
	coinWidget.Visible = not inMatch() and not cutscene
	lobbyBar.Visible = coinWidget.Visible
	coinsLabel.Text = tostring(player:GetAttribute("Coins") or 0)
	classLabel.Text = "Класс: " .. className(player:GetAttribute("Class"))
	updateMusic(dt)

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
	UserInputService.MouseIconEnabled = not playing or craft.Visible or shopPanel.Visible or notePanel.Visible or Radial.isOpen() or settingsPanel.Visible or adminPanel.Visible or cursorForced()

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
		local pn = (player:GetAttribute("PingNext") or 0) - workspace:GetServerTimeNow()
		downedText.Text = "ТЫ РАНЕН\nДруг может поднять тебя бинтом (E) или утащить за ногу (F)\n"
			.. (pn > 0 and ("Сигнал снова через " .. math.ceil(pn) .. " с") or "R — позвать на помощь (друзья увидят тебя и стрелки)")
			.. "\nОчнёшься у лифта через " .. formatTime(dl)
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
		local ar = Items.Armor[player:GetAttribute("Armor") or 0]
		armorText.Visible = inMatch()
		armorText.Text = ar and ("🛡 " .. ar.Name) or ""
		local moving = hum.MoveDirection.Magnitude > 0.1
		local dragging = player:GetAttribute("Dragging") == true
		local sprinting = playing and sprintHeld and moving and not exhausted and stamina > 0 and not crouched and not dragging
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
			hum.WalkSpeed = (sprinting and sprint or Config.WalkSpeed) * (dragging and 0.75 or 1)
		end
		stFill.Size = UDim2.fromScale(stamina / staminaMax(), 1)
		vmState.visible, vmState.moving, vmState.sprinting = playing and not downed, moving, sprinting

	else
		vmState.visible = false
	end

	-- строительство
	local eqKind = equipped and Items.Tools[equipped] and Items.Tools[equipped].Kind
	BuildMode.update((playing and not downed and (eqKind == "blueprint" or eqKind == "hammer" or eqKind == "deploy")) and eqKind or nil, rayParams(), equipped)

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
	local bar = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 68), Size = UDim2.new(0, 190, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, gui)
	-- админ-кнопки видны только после ввода кода в Настройки → Админ-панель
	-- уровень 1 (код друзей) — часть кнопок, уровень 2 (главный код) — все
	local levelOf = {}
	local function refreshAdmin()
		local lvl = player:GetAttribute("Admin") or 0
		if lvl == true then
			lvl = 2
		end
		bar.Visible = lvl >= 1
		for b, need in pairs(levelOf) do
			b.Visible = lvl >= need
		end
	end
	player:GetAttributeChangedSignal("Admin"):Connect(refreshAdmin)
	local title = make("TextLabel", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 14, TextColor3 = RGB(255, 200, 120), Text = "АДМИН-ПАНЕЛЬ", LayoutOrder = -1 }, bar)
	local _ = title
	make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, bar)
	local order = 0
	local function btn(text, fn, need, color)
		order += 1
		local b = make("TextButton", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = color or RGB(30, 30, 34), BackgroundTransparency = 0.25, Font = UI_FONT, TextSize = 13, TextColor3 = RGB(230, 230, 230), Text = text, LayoutOrder = order }, bar)
		corner(b, 6)
		levelOf[b] = need or 1
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
	-- только главная админка
	btn("+500 монет", function()
		remote("Dev"):FireServer("coins")
	end, 2)
	btn("Ранить себя (тест)", function()
		remote("Dev"):FireServer("down")
	end, 2)
	btn("Невидимость", function(b)
		remote("Dev"):FireServer("invisible")
		task.delay(0.4, function()
			b.Text = player:GetAttribute("Invisible") and "Невидимость: ВКЛ" or "Невидимость"
		end)
	end, 2, RGB(60, 40, 90))
	-- наблюдение за игроками: камера переходит к следующему игроку
	local others = {}
	local function nextPlayer()
		others = {}
		for _, q in ipairs(Players:GetPlayers()) do
			if q ~= player and q.Character and q.Character:FindFirstChildOfClass("Humanoid") then
				table.insert(others, q)
			end
		end
		if #others == 0 then
			notify("На сервере больше никого нет")
			return nil
		end
		spectateIndex = spectateIndex % #others + 1
		return others[spectateIndex]
	end
	btn("Наблюдать: следующий", function()
		local q = nextPlayer()
		if q then
			spectating = q
			workspace.CurrentCamera.CameraSubject = q.Character:FindFirstChildOfClass("Humanoid")
			notify("Наблюдаешь за " .. q.DisplayName)
		end
	end, 2, RGB(30, 60, 90))
	btn("Перестать наблюдать", function()
		spectating = nil
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			workspace.CurrentCamera.CameraSubject = hum
		end
	end, 2, RGB(30, 60, 90))
	btn("ТП к игроку", function()
		local q = spectating or nextPlayer()
		if q then
			remote("Dev"):FireServer("tpto", q.UserId)
		end
	end, 2, RGB(30, 60, 90))
	btn("☢ Ядерка на поляну", function()
		remote("Dev"):FireServer("nuke")
	end, 2, RGB(120, 60, 20))
	btn("🌊 Цунами", function()
		remote("Dev"):FireServer("tsunami")
	end, 2, RGB(20, 70, 120))
	btn("💰 Денежный дождь", function()
		remote("Dev"):FireServer("money")
	end, 2, RGB(120, 100, 20))
	refreshAdmin()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not player:GetAttribute("Admin") then
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

-- подсказка управления (на телефоне не нужна)
local keysHint = make("TextLabel", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -14),
	Size = UDim2.new(0, 760, 0, 20),
	BackgroundTransparency = 1,
	Font = TEXT_FONT,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Right,
	TextColor3 = RGB(200, 195, 180),
	Text = "ЛКМ — удар · E (зажать) — добыть/собрать · C — крафт · 1–9 — предмет · Ctrl — пригнуться · Shift — бег · H — ягоды · R — меню · Tab — карта",
}, gui)

------------------------------------------------------------------
-- Телефон и планшет: интерфейс подстраивается под экран, кнопки на экране
------------------------------------------------------------------
local uiScale = make("UIScale", {}, gui)
local function rescale()
	local vp = workspace.CurrentCamera.ViewportSize
	uiScale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 760), 0.55, 1)
end
rescale()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

local function touchMode()
	return UserInputService.TouchEnabled and (not UserInputService.KeyboardEnabled or UserInputService:GetLastInputType() == Enum.UserInputType.Touch)
end
keysHint.Visible = not touchMode()
if UserInputService.TouchEnabled then
	local pad = make("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -190), Size = UDim2.fromOffset(250, 330), BackgroundTransparency = 1 }, gui)
	local function tbtn(text, pos, size, color, fn)
		local b = make("TextButton", { AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Size = size, BackgroundColor3 = color, BackgroundTransparency = 0.25, Font = Enum.Font.GothamBlack, TextSize = 15, TextWrapped = true, TextColor3 = RGB(255, 255, 255), Text = text }, pad)
		corner(b, 100)
		make("UIStroke", { Color = RGB(255, 255, 255), Thickness = 2, Transparency = 0.4 }, b)
		b.Activated:Connect(function()
			fn(b)
		end)
		return b
	end
	-- большая кнопка удара/действия
	tbtn("УДАР\nРУБИТЬ", UDim2.fromOffset(185, 270), UDim2.fromOffset(110, 110), RGB(190, 60, 50), function()
		doSwing()
	end)
	local sprintB
	sprintB = tbtn("БЕГ", UDim2.fromOffset(70, 290), UDim2.fromOffset(70, 70), RGB(70, 110, 160), function()
		sprintHeld = not sprintHeld
		sprintB.BackgroundColor3 = sprintHeld and RGB(80, 170, 90) or RGB(70, 110, 160)
	end)
	tbtn("ПРИСЕСТЬ", UDim2.fromOffset(70, 205), UDim2.fromOffset(70, 70), RGB(90, 90, 100), function()
		if inMatch() and not cutscene then
			setCrouch(not crouched)
		end
	end)
	tbtn("КРАФТ", UDim2.fromOffset(150, 170), UDim2.fromOffset(66, 66), RGB(150, 110, 50), function()
		if inMatch() and not cutscene then
			openHandCraft()
		end
	end)
	tbtn("МЕНЮ", UDim2.fromOffset(225, 160), UDim2.fromOffset(66, 66), RGB(110, 80, 160), function()
		if not inMatch() or cutscene then
			return
		end
		local kind = equipped and Items.Tools[equipped] and Items.Tools[equipped].Kind
		if player:GetAttribute("Downed") then
			remote("Ping"):FireServer()
		elseif kind == "blueprint" then
			BuildMode.pieceMenu(Radial)
		elseif kind == "hammer" then
			BuildMode.hammerMenu(Radial, remote("Upgrade"))
		elseif kind == "deploy" then
			BuildMode.rotate()
		end
	end)
	tbtn("КАРТА", UDim2.fromOffset(150, 95), UDim2.fromOffset(60, 60), RGB(60, 130, 90), function()
		if inMatch() and not cutscene then
			toggleMap()
		end
	end)
	tbtn("ЕДА", UDim2.fromOffset(225, 85), UDim2.fromOffset(60, 60), RGB(170, 50, 80), function()
		remote("Eat"):FireServer()
	end)
	tbtn("УБРАТЬ", UDim2.fromOffset(70, 120), UDim2.fromOffset(60, 60), RGB(70, 70, 76), function()
		equip(nil)
		refreshHotbar()
	end)
	RunService.RenderStepped:Connect(function()
		local t = touchMode()
		pad.Visible = t and inMatch() and not cutscene
		keysHint.Visible = not t
	end)
end
