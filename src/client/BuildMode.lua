-- Строительство на клиенте:
--  * чертёж: прозрачный предпросмотр детали по сетке, R — круговое меню выбора детали, ЛКМ — поставить;
--  * молоток: R — круговое меню улучшения (дерево / камень / металл / снести), ЛКМ — следующий уровень;
--  * верстак, кровать, сундук: предпросмотр самой модели, зелёный — можно, красный — нельзя,
--    R — повернуть, ЛКМ — поставить.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Building = require(Shared:WaitForChild("Building"))
local Items = require(Shared:WaitForChild("Items"))
local Deployables = require(Shared:WaitForChild("Deployables"))

local player = Players.LocalPlayer
local V = Vector3.new
local RGB = Color3.fromRGB

local BuildMode = {}

local index = 1
local ghost, ghostKey
local current -- {id, a} для чертежа, {tool, cf} для предмета
local hint
local rot = 0
local aimedPiece

local GOOD, BAD = RGB(90, 220, 120), RGB(255, 80, 70)

local function costText(cost)
	local parts = {}
	for k, n in pairs(cost) do
		local have = player:GetAttribute("Res_" .. k) or 0
		table.insert(parts, (Items.Resources[k] and Items.Resources[k].Name or k) .. " " .. have .. "/" .. n)
	end
	return table.concat(parts, ", ")
end

local function enough(cost)
	for k, n in pairs(cost) do
		if (player:GetAttribute("Res_" .. k) or 0) < n then
			return false
		end
	end
	return true
end

local function clearGhost()
	if ghost then
		ghost:Destroy()
		ghost, ghostKey = nil, nil
	end
end

local function styleGhost(m)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Material = Enum.Material.ForceField
			d.Transparency = 0.15
		end
	end
	m.Parent = workspace.CurrentCamera
end

local function pieceGhost(id)
	if ghostKey == "piece:" .. id then
		return
	end
	clearGhost()
	local def = Building.ById[id]
	local m = Instance.new("Model")
	local p = Instance.new(id == "stairs" and "WedgePart" or "Part")
	p.Size = def.Size
	p.Parent = m
	m.PrimaryPart = p
	styleGhost(m)
	ghost, ghostKey = m, "piece:" .. id
end

local function deployGhost(dep)
	if ghostKey == "deploy:" .. dep then
		return
	end
	clearGhost()
	local m = Deployables.build(dep, CFrame.new())
	styleGhost(m)
	ghost, ghostKey = m, "deploy:" .. dep
end

local function setGhostColor(c, visible)
	if not ghost then
		return
	end
	for _, d in ipairs(ghost:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Color = c
			d.Transparency = visible and 0.15 or 1
		end
	end
end

function BuildMode.init(gui, make)
	hint = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -96),
		Size = UDim2.new(0, 600, 0, 46),
		BackgroundColor3 = RGB(15, 18, 24),
		BackgroundTransparency = 0.35,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = RGB(230, 236, 245),
		TextWrapped = true,
		Visible = false,
		Text = "",
	}, gui)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = hint
end

local function pieces()
	return CollectionService:GetTagged("BuildPiece")
end

-- круговое меню: какую деталь строить
function BuildMode.pieceMenu(Radial)
	local opts = {}
	for _, p in ipairs(Building.Pieces) do
		table.insert(opts, { label = p.Name, sub = costText(p.Cost), color = enough(p.Cost) and RGB(48, 70, 52) or RGB(70, 40, 40) })
	end
	Radial.open(opts, function(k)
		index = k
	end)
end

-- круговое меню молотка: до какого уровня улучшить
function BuildMode.hammerMenu(Radial, remote)
	local piece = aimedPiece
	if not piece then
		return false
	end
	local cur = piece:GetAttribute("Tier") or 0
	local opts = {}
	for t = 1, 3 do
		local d = Building.Tiers[t]
		local ok = t > cur and enough(d.Cost)
		table.insert(opts, {
			label = d.Name,
			sub = t <= cur and "уже есть" or costText(d.Cost),
			color = ok and RGB(48, 70, 52) or RGB(60, 50, 50),
			tier = t,
		})
	end
	table.insert(opts, { label = "Снести", sub = "вернётся половина досок", color = RGB(90, 40, 30), tier = "remove" })
	Radial.open(opts, function(_, o)
		remote:FireServer(piece, o.tier)
	end)
	return true
end

function BuildMode.rotate()
	rot = (rot + 1) % 4
end

-- вызывать каждый кадр. mode: "blueprint" / "hammer" / "deploy" / nil
function BuildMode.update(mode, rayParams, toolId)
	current = nil
	aimedPiece = nil
	if mode ~= "blueprint" and mode ~= "deploy" then
		clearGhost()
	end
	if not hint then
		return
	end
	local cam = workspace.CurrentCamera
	local O = player:GetAttribute("SessionO")
	if not mode or not O then
		hint.Visible = false
		clearGhost()
		return
	end
	hint.Visible = true
	local r = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 22, rayParams)

	if mode == "hammer" then
		local piece = r and Building.pieceOf(r.Instance)
		aimedPiece = piece
		if piece then
			local tier = piece:GetAttribute("Tier") or 0
			local nextT = Building.Tiers[tier + 1]
			hint.Text = piece.Name .. " · " .. Building.Tiers[tier].Name .. (nextT and ("  ·  ЛКМ: → " .. nextT.Name .. " (" .. costText(nextT.Cost) .. ")") or "  (максимум)") .. "\nR — круговое меню: выбрать уровень или снести"
		else
			hint.Text = "Молоток: наведи на постройку. ЛКМ — следующий уровень, R — меню улучшения"
		end
		return
	end

	if mode == "deploy" then
		local def = Items.Tools[toolId]
		local dep = def and def.Deploy
		if not dep then
			return
		end
		deployGhost(dep)
		hint.Text = "Поставить: " .. Deployables.Names[dep] .. "  ·  R — повернуть  ·  ЛКМ — поставить"
		if not r or r.Normal.Y < 0.7 then
			setGhostColor(BAD, false)
			return
		end
		local look = cam.CFrame.LookVector * V(1, 0, 1)
		local yaw = math.atan2(look.X, look.Z) + rot * math.pi / 2
		local cf = CFrame.new(r.Position) * CFrame.Angles(0, yaw, 0)
		ghost:PivotTo(cf)
		-- влезает ли
		local size = Deployables.Size[dep]
		local op = OverlapParams.new()
		op.FilterType = Enum.RaycastFilterType.Exclude
		op.FilterDescendantsInstances = { ghost, player.Character }
		op.RespectCanCollide = true
		local free = #workspace:GetPartBoundsInBox(cf * CFrame.new(0, size.Y / 2 + 0.3, 0), size - V(0.3, 0.3, 0.3), op) == 0
		local near = (r.Position - cam.CFrame.Position).Magnitude < 20
		setGhostColor((free and near) and GOOD or BAD, true)
		if free and near then
			current = { tool = toolId, cf = cf }
		end
		return
	end

	-- чертёж
	local def = Building.Pieces[index]
	pieceGhost(def.Id)
	local a = r and Building.snap(def.Id, O, r.Position, r.Instance, cam.CFrame.LookVector, pieces())
	hint.Text = def.Name .. "  ·  " .. costText(def.Cost) .. "\nR — выбрать деталь (круговое меню)  ·  ЛКМ — поставить" .. (def.Id == "foundation" and "" or def.Id == "door" and "  ·  наведи на проём" or "  ·  ставится на фундамент / стену")
	if not a then
		setGhostColor(BAD, false)
		return
	end
	ghost:PivotTo(Building.cframe(def.Id, O, a))
	local key = Building.key(def.Id, a)
	local free = true
	for _, p in ipairs(pieces()) do
		if p:GetAttribute("Key") == key then
			free = false
		end
	end
	setGhostColor((free and enough(def.Cost)) and GOOD or BAD, true)
	if free then
		current = { id = def.Id, a = a }
	end
end

-- ЛКМ с чертежом или предметом
function BuildMode.place(buildRemote, placeRemote)
	if current and current.id then
		buildRemote:FireServer(current.id, current.a)
		return true
	elseif current and current.tool then
		placeRemote:FireServer(current.tool, current.cf)
		return true
	end
	return false
end

return BuildMode
