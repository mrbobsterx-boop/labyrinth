-- Режим строительства (в руке чертёж): прозрачный предпросмотр детали по сетке,
-- R — сменить деталь, ЛКМ — поставить. С молотком — подсказка, во что улучшится.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Building = require(Shared:WaitForChild("Building"))
local Items = require(Shared:WaitForChild("Items"))

local player = Players.LocalPlayer
local V = Vector3.new
local RGB = Color3.fromRGB

local BuildMode = {}

local index = 1
local ghost
local current -- {id, a}
local hint

local function costText(cost)
	local parts = {}
	for k, n in pairs(cost) do
		local have = player:GetAttribute("Res_" .. k) or 0
		table.insert(parts, (Items.Resources[k] and Items.Resources[k].Name or k) .. " " .. have .. "/" .. n)
	end
	return table.concat(parts, ", ")
end

local function makeGhost(id)
	if ghost then
		ghost:Destroy()
	end
	local def = Building.ById[id]
	local p = Instance.new(id == "stairs" and "WedgePart" or "Part")
	p.Name = "BuildGhost"
	p.Size = def.Size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.ForceField
	p.Transparency = 0.2
	p.Parent = workspace.CurrentCamera
	ghost = p
end

function BuildMode.init(gui, make)
	hint = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -96),
		Size = UDim2.new(0, 560, 0, 46),
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

function BuildMode.cycle()
	index = index % #Building.Pieces + 1
	makeGhost(Building.Pieces[index].Id)
end

local function pieces()
	return CollectionService:GetTagged("BuildPiece")
end

-- вызывать каждый кадр. mode: "blueprint", "hammer" или nil
function BuildMode.update(mode, rayParams)
	current = nil
	if mode ~= "blueprint" then
		if ghost then
			ghost:Destroy()
			ghost = nil
		end
	end
	if not hint then
		return
	end
	hint.Visible = mode ~= nil
	local cam = workspace.CurrentCamera
	local O = player:GetAttribute("SessionO")
	if not mode or not O then
		hint.Visible = false
		return
	end
	local r = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 22, rayParams)
	if mode == "hammer" then
		local piece = r and Building.pieceOf(r.Instance)
		if piece then
			local tier = piece:GetAttribute("Tier") or 0
			local nextT = Building.Tiers[tier + 1]
			hint.Text = piece.Name .. " · " .. Building.Tiers[tier].Name .. (nextT and ("   →   ЛКМ: " .. nextT.Name .. " (" .. costText(nextT.Cost) .. ")") or "   (максимум)")
		else
			hint.Text = "Молоток: наведи на постройку и бей ЛКМ — улучшить (чертёж → дерево → камень → металл)"
		end
		return
	end
	local def = Building.Pieces[index]
	if not ghost or ghost.Size ~= def.Size or (def.Id == "stairs") ~= ghost:IsA("WedgePart") then
		makeGhost(def.Id)
	end
	local a = r and Building.snap(def.Id, O, r.Position, r.Instance, cam.CFrame.LookVector, pieces())
	hint.Text = "R — сменить: " .. def.Name .. "  ·  " .. costText(def.Cost) .. "\nЛКМ — поставить" .. (def.Id == "foundation" and "" or "  ·  ставится на фундамент / стену")
	if not a then
		ghost.Transparency = 1
		return
	end
	local cf = Building.cframe(def.Id, O, a)
	ghost.CFrame = cf
	local free = true
	for _, p in ipairs(pieces()) do
		if p:GetAttribute("Key") == Building.key(def.Id, a) then
			free = false
		end
	end
	local enough = true
	for k, n in pairs(def.Cost) do
		if (player:GetAttribute("Res_" .. k) or 0) < n then
			enough = false
		end
	end
	ghost.Transparency = 0.25
	ghost.Color = (free and enough) and RGB(90, 200, 255) or RGB(255, 80, 70)
	if free then
		current = { id = def.Id, a = a }
	end
end

-- ЛКМ с чертежом
function BuildMode.place(remote)
	if current then
		remote:FireServer(current.id, current.a)
		return true
	end
	return false
end

local _ = V
return BuildMode
