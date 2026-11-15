-- Помощники для постройки уровня из простых деталей (Part).

local CollectionService = game:GetService("CollectionService")

local Parts = {}

local V = Vector3.new
local GLASS = Color3.fromRGB(38, 46, 58)
local BOARD = Color3.fromRGB(62, 48, 36)

function Parts.box(parent, name, cf, size, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color or Color3.fromRGB(120, 120, 120)
	p.Material = material or Enum.Material.SmoothPlastic
	if props then
		for k, v in pairs(props) do
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end

-- Деталь между двумя углами (a и b — локальные координаты относительно origin)
function Parts.span(parent, name, origin, a, b, color, material, props)
	local minV = V(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
	local maxV = V(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
	return Parts.box(parent, name, CFrame.new(origin + (minV + maxV) / 2), maxV - minV, color, material, props)
end

-- Стена с проёмами.
-- axis "X": стена идёт вдоль X на z = fixed. axis "Z": вдоль Z на x = fixed.
-- openings: { {c = центр, w = ширина, b = высота низа проёма, h = высота проёма, glass = true, boarded = true}, ... }
function Parts.wall(parent, origin, axis, fixed, a1, a2, y0, height, openings, color, material, thickness)
	thickness = thickness or 1
	local half = thickness / 2

	local function seg(s, e, yb, yt)
		if e - s < 0.05 or yt - yb < 0.05 then
			return
		end
		if axis == "X" then
			Parts.span(parent, "Wall", origin, V(s, yb, fixed - half), V(e, yt, fixed + half), color, material)
		else
			Parts.span(parent, "Wall", origin, V(fixed - half, yb, s), V(fixed + half, yt, e), color, material)
		end
	end

	local ops = table.clone(openings or {})
	table.sort(ops, function(p, q)
		return p.c < q.c
	end)

	local cursor = a1
	for _, op in ipairs(ops) do
		local l, r = op.c - op.w / 2, op.c + op.w / 2
		local b = op.b or 0
		seg(cursor, l, y0, y0 + height)
		seg(l, r, y0, y0 + b)
		seg(l, r, y0 + b + op.h, y0 + height)

		if op.glass then
			local yb, yt = y0 + b, y0 + b + op.h
			if axis == "X" then
				Parts.span(parent, "Window", origin, V(l, yb, fixed - 0.1), V(r, yt, fixed + 0.1), GLASS, Enum.Material.Glass, { Transparency = 0.5 })
			else
				Parts.span(parent, "Window", origin, V(fixed - 0.1, yb, l), V(fixed + 0.1, yt, r), GLASS, Enum.Material.Glass, { Transparency = 0.5 })
			end
			if op.boarded then
				local center = (axis == "X") and V(op.c, (yb + yt) / 2, fixed + half + 0.1)
					or V(fixed + half + 0.1, (yb + yt) / 2, op.c)
				local turn = (axis == "X") and CFrame.new() or CFrame.Angles(0, math.pi / 2, 0)
				for _, ang in ipairs({ 25, -20 }) do
					Parts.box(
						parent,
						"Board",
						CFrame.new(origin + center) * turn * CFrame.Angles(0, 0, math.rad(ang)),
						V(op.w * 1.2, 0.7, 0.2),
						BOARD,
						Enum.Material.WoodPlanks
					)
				end
			end
		end
		cursor = r
	end
	seg(cursor, a2, y0, y0 + height)
end

-- Лестница: видимые ступени (без коллизии) + невидимый пандус, по которому удобно ходить
-- и игроку, и Топотуну (pathfinding).
function Parts.stairs(parent, origin, x1, x2, zStart, yStart, zEnd, yEnd, steps, color, material)
	local dz = (zEnd - zStart) / steps
	local dy = (yEnd - yStart) / steps
	for k = 1, steps do
		local za = zStart + dz * (k - 1)
		local zb = zStart + dz * k
		Parts.span(parent, "Step", origin, V(x1, yStart - 1, za), V(x2, yStart + dy * k, zb), color, material, { CanCollide = false })
		-- невидимый твёрдый блок на ступень ниже: снизу и сбоку под лестницу не пройти,
		-- а ходить по ней всё равно удобно (по пандусу)
		if k > 1 then
			Parts.span(parent, "StairFill", origin, V(x1, yStart - 1, za), V(x2, yStart + dy * (k - 1), zb), color, material, { Transparency = 1 })
		end
	end
	local run = math.abs(zEnd - zStart)
	local rise = yEnd - yStart
	local length = math.sqrt(run * run + rise * rise) + 0.6
	local mid = V((x1 + x2) / 2, (yStart + yEnd) / 2 + dy / 2, (zStart + zEnd) / 2)
	local sign = (zEnd < zStart) and 1 or -1
	local angle = math.atan2(rise, run) * sign
	Parts.box(
		parent,
		"StairRamp",
		CFrame.new(origin + mid) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, -0.5, 0),
		V(math.abs(x2 - x1), 1, length),
		color,
		material,
		{ Transparency = 1 }
	)
end

function Parts.light(part, range, brightness, color, flicker)
	local l = Instance.new("PointLight")
	l.Range = range
	l.Brightness = brightness
	l.Color = color or Color3.fromRGB(255, 170, 90)
	l.Shadows = true
	l.Parent = part
	if flicker then
		CollectionService:AddTag(l, "FlickerLight")
	end
	return l
end

function Parts.deadTree(parent, pos, rng)
	local wood = Color3.fromRGB(36, 31, 28)
	local h = rng:NextNumber(12, 22)
	Parts.box(parent, "Trunk", CFrame.new(pos + V(0, h / 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), V(1.6, h, 1.6), wood, Enum.Material.Wood)
	for _ = 1, rng:NextInteger(3, 6) do
		local len = rng:NextNumber(4, 9)
		local y = rng:NextNumber(h * 0.45, h * 0.95)
		local base = CFrame.new(pos + V(0, y, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0) * CFrame.Angles(0, 0, rng:NextNumber(0.5, 1.15))
		Parts.box(parent, "Branch", base * CFrame.new(0, len / 2, 0), V(0.55, len, 0.55), wood, Enum.Material.Wood)
	end
end

return Parts
