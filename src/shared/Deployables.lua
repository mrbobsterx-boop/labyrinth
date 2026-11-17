-- Модели предметов, которые ставятся в мир: верстак, кровать, сундук.
-- Одни и те же модели — и настоящие (сервер), и прозрачный предпросмотр (клиент).

local Deployables = {}

local V = Vector3.new
local RGB = Color3.fromRGB
local M = Enum.Material
local WOOD = RGB(92, 64, 40)

Deployables.Names = {
	workbench = "Верстак",
	bed = "Кровать",
	chest = "Сундук",
}

local function box(m, name, cf, size, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Parent = m
	return p
end

-- cf — точка на земле, модель «смотрит» по -Z
function Deployables.build(id, cf)
	local m = Instance.new("Model")
	m.Name = id
	m.WorldPivot = cf
	if id == "workbench" then
		box(m, "Top", cf * CFrame.new(0, 3.45, 0), V(8, 0.5, 4), RGB(110, 80, 50), M.WoodPlanks)
		for _, x in ipairs({ -3.5, 3.5 }) do
			for _, z in ipairs({ -1.5, 1.5 }) do
				box(m, "Leg", cf * CFrame.new(x, 1.6, z), V(0.6, 3.2, 0.6), WOOD, M.Wood)
			end
		end
		box(m, "Shelf", cf * CFrame.new(0, 1, 0), V(7.4, 0.3, 3.4), WOOD, M.WoodPlanks)
		box(m, "Vise", cf * CFrame.new(3, 4.1, -1), V(1.1, 0.9, 1), RGB(70, 72, 76), M.Metal)
		box(m, "Saw", cf * CFrame.new(-1.7, 3.75, 0.9), V(2.5, 0.1, 0.8), RGB(170, 170, 175), M.Metal)
		box(m, "Hammer", cf * CFrame.new(0.8, 3.8, -1.05), V(1.6, 0.25, 0.3), WOOD, M.Wood)
	elseif id == "bed" then
		box(m, "Frame", cf * CFrame.new(0, 0.6, 0), V(4, 1.2, 7.5), RGB(100, 70, 44), M.Wood)
		box(m, "Mattress", cf * CFrame.new(0, 1.45, 0.2), V(3.6, 0.6, 7), RGB(200, 190, 170), M.Fabric)
		box(m, "Blanket", cf * CFrame.new(0, 1.8, 1.3), V(3.7, 0.25, 4.6), RGB(120, 50, 45), M.Fabric)
		box(m, "Pillow", cf * CFrame.new(0, 1.9, -2.6), V(2.6, 0.5, 1.2), RGB(235, 230, 220), M.Fabric)
		box(m, "Headboard", cf * CFrame.new(0, 2, -3.6), V(4, 2.8, 0.4), RGB(100, 70, 44), M.Wood)
	elseif id == "chest" then
		box(m, "Body", cf * CFrame.new(0, 1, 0), V(4.4, 2, 2.6), RGB(110, 76, 46), M.WoodPlanks)
		box(m, "Lid", cf * CFrame.new(0, 2.3, 0), V(4.6, 0.6, 2.8), RGB(90, 60, 36), M.WoodPlanks)
		box(m, "Lock", cf * CFrame.new(0, 1.9, -1.45), V(0.6, 0.7, 0.2), RGB(200, 170, 60), M.Metal)
	end
	return m
end

-- размер «коробки» для проверки, влезает ли предмет
Deployables.Size = {
	workbench = V(8, 4.4, 4),
	bed = V(4, 3, 7.6),
	chest = V(4.6, 2.6, 2.8),
}

return Deployables
