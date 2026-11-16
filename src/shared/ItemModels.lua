-- 3D-модели инструментов и оружия. Используются и в руках персонажа (видят другие игроки),
-- и в виде от первого лица (руки игрока).
-- Модель строится вдоль оси Y: рукоять в начале координат, рабочая часть вверху.

local Items = require(script.Parent.Items)

local ItemModels = {}

local V = Vector3.new
local RGB = Color3.fromRGB
local WOOD = RGB(110, 76, 46)

local function part(model, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

-- build(id, base): base — CFrame рукояти. Возвращает Model с PrimaryPart "Grip".
function ItemModels.build(id, base)
	base = base or CFrame.new()
	local def = Items.Tools[id]
	local m = Instance.new("Model")
	m.Name = "Item_" .. id
	if not def or def.Kind == "fists" then
		local grip = part(m, "Grip", V(0.1, 0.1, 0.1), base, WOOD)
		grip.Transparency = 1
		m.PrimaryPart = grip
		return m
	end
	local c = def.Color and RGB(def.Color[1], def.Color[2], def.Color[3]) or RGB(150, 150, 150)
	local metal = (id:find("iron") or id:find("crystal")) and Enum.Material.Metal or Enum.Material.Slate
	if id:find("crystal") then
		metal = Enum.Material.Neon
	end

	if def.Kind == "pickaxe" then
		local grip = part(m, "Grip", V(0.25, 3.2, 0.25), base * CFrame.new(0, 1.2, 0), WOOD, Enum.Material.Wood)
		-- голова кирки лежит в плоскости удара (острия вперёд и назад)
		part(m, "Head", V(0.35, 0.35, 2.4), base * CFrame.new(0, 2.7, 0), c, metal)
		part(m, "Collar", V(0.45, 0.5, 0.45), base * CFrame.new(0, 2.7, 0), RGB(70, 60, 50), Enum.Material.Metal)
		for _, sz in ipairs({ -1, 1 }) do
			part(m, "Tip", V(0.22, 0.22, 0.7), base * CFrame.new(0, 2.55, sz * 1.4) * CFrame.Angles(math.rad(25 * sz), 0, 0), c, metal)
		end
		m.PrimaryPart = grip
	elseif def.Kind == "axe" then
		local grip = part(m, "Grip", V(0.25, 3, 0.25), base * CFrame.new(0, 1.1, 0), WOOD, Enum.Material.Wood)
		part(m, "Head", V(0.25, 1, 1.3), base * CFrame.new(0, 2.25, -0.55), c, metal)
		part(m, "Edge", V(0.12, 1.3, 0.25), base * CFrame.new(0, 2.25, -1.25), RGB(200, 200, 205), Enum.Material.Metal)
		m.PrimaryPart = grip
	elseif def.Kind == "sword" then
		local grip = part(m, "Grip", V(0.25, 0.9, 0.25), base * CFrame.new(0, 0.2, 0), RGB(50, 34, 24), Enum.Material.Wood)
		part(m, "Pommel", V(0.35, 0.25, 0.35), base * CFrame.new(0, -0.35, 0), c, metal)
		part(m, "Guard", V(1.1, 0.18, 0.3), base * CFrame.new(0, 0.72, 0), RGB(90, 80, 60), Enum.Material.Metal)
		local blade = part(m, "Blade", V(0.12, 3.3, 0.38), base * CFrame.new(0, 2.45, 0), c, metal)
		blade.Reflectance = 0.15
		part(m, "BladeTip", V(0.12, 0.45, 0.26), base * CFrame.new(0, 4.25, 0), c, metal)
		if id:find("crystal") then
			local l = Instance.new("PointLight")
			l.Color = c
			l.Range = 8
			l.Brightness = 1.2
			l.Parent = blade
		end
		m.PrimaryPart = grip
	elseif def.Kind == "spear" then
		local grip = part(m, "Grip", V(0.2, 6, 0.2), base * CFrame.new(0, 1.5, 0), WOOD, Enum.Material.Wood)
		part(m, "Tip", V(0.14, 1, 0.38), base * CFrame.new(0, 5, 0), c, metal)
		part(m, "Binding", V(0.28, 0.4, 0.28), base * CFrame.new(0, 4.4, 0), RGB(140, 120, 80), Enum.Material.Fabric)
		m.PrimaryPart = grip
	elseif def.Kind == "torch" then
		local grip = part(m, "Grip", V(0.28, 2.2, 0.28), base * CFrame.new(0, 0.6, 0), WOOD, Enum.Material.Wood)
		local head = part(m, "Flame", V(0.5, 0.55, 0.5), base * CFrame.new(0, 1.9, 0), RGB(255, 140, 40), Enum.Material.Neon)
		local l = Instance.new("PointLight")
		l.Color = RGB(255, 170, 90)
		l.Range = 26
		l.Brightness = 1.6
		l.Shadows = true
		l.Parent = head
		local fire = Instance.new("Fire")
		fire.Size = 2
		fire.Heat = 4
		fire.Parent = head
		m.PrimaryPart = grip
	end
	if def.Kind == "blueprint" then
		-- свёрнутый синий чертёж
		local grip = part(m, "Grip", V(0.5, 1.8, 0.5), base * CFrame.new(0, 0.5, 0), RGB(60, 100, 180), Enum.Material.Fabric)
		part(m, "Sheet", V(0.08, 1.6, 1.4), base * CFrame.new(0.3, 0.9, -0.5), RGB(90, 140, 220), Enum.Material.SmoothPlastic)
		part(m, "Line", V(0.1, 1.2, 0.06), base * CFrame.new(0.32, 0.9, -0.5), RGB(230, 240, 255), Enum.Material.Neon)
		m.PrimaryPart = grip
	elseif def.Kind == "hammer" then
		local grip = part(m, "Grip", V(0.25, 2.2, 0.25), base * CFrame.new(0, 0.8, 0), WOOD, Enum.Material.Wood)
		part(m, "Head", V(0.5, 0.5, 1.3), base * CFrame.new(0, 2, -0.1), c, Enum.Material.Metal)
		m.PrimaryPart = grip
	end
	-- точка опоры модели = рукоять (base), чтобы PivotTo ставил рукоять в руку
	if m.PrimaryPart then
		m.PrimaryPart.PivotOffset = m.PrimaryPart.CFrame:ToObjectSpace(base)
	end
	return m
end

return ItemModels
