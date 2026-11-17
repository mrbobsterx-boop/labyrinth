-- Строительство как в Rust: сетка 8x8, фундамент, стены, проём с дверью, окно,
-- перекрытие и лестница. Ставятся чертежом (из досок), улучшаются молотком:
-- чертёж → дерево → камень → металл.
-- Здесь общие для сервера и клиента вещи: список деталей, уровни и привязка к сетке.

local Building = {}

local V = Vector3.new
local RGB = Color3.fromRGB

Building.Grid = 8
Building.WallH = 8
local G = Building.Grid

Building.Pieces = {
	{ Id = "foundation", Name = "Фундамент", Cost = { planks = 6 }, Size = V(8, 3, 8) },
	{ Id = "wall", Name = "Стена", Cost = { planks = 4 }, Size = V(8, 8, 0.8), Edge = true },
	{ Id = "doorway", Name = "Дверной проём", Cost = { planks = 5 }, Size = V(8, 8, 0.8), Edge = true },
	{ Id = "door", Name = "Дверь (в проём)", Cost = { planks = 3 }, Size = V(3.6, 6.2, 0.4), Door = true },
	{ Id = "window", Name = "Стена с окном", Cost = { planks = 4 }, Size = V(8, 8, 0.8), Edge = true },
	{ Id = "floor", Name = "Перекрытие / крыша", Cost = { planks = 4 }, Size = V(8, 0.8, 8) },
	{ Id = "stairs", Name = "Лестница", Cost = { planks = 5 }, Size = V(7.6, 8, 8) },
}
Building.ById = {}
for i, p in ipairs(Building.Pieces) do
	p.Index = i
	Building.ById[p.Id] = p
end

Building.Tiers = {
	[0] = { Name = "Чертёж", Color = RGB(205, 180, 125), Material = Enum.Material.WoodPlanks, HP = 40 },
	[1] = { Name = "Дерево", Color = RGB(118, 82, 50), Material = Enum.Material.WoodPlanks, HP = 150, Cost = { wood = 6 } },
	[2] = { Name = "Камень", Color = RGB(128, 128, 124), Material = Enum.Material.Slate, HP = 400, Cost = { stone = 8 } },
	[3] = { Name = "Металл", Color = RGB(92, 96, 102), Material = Enum.Material.DiamondPlate, HP = 900, Cost = { iron = 4 } },
}

-- CFrame детали по параметрам привязки
-- cell-детали: {cx, cz, y, rot}; y — поверхность, на которую ставим (у фундамента — его верх)
-- edge-детали: {ex, ez, axis, y}
function Building.cframe(id, O, a)
	if id == "foundation" then
		return CFrame.new(O + V((a.cx + 0.5) * G, a.y - 1.5, (a.cz + 0.5) * G))
	elseif id == "floor" then
		return CFrame.new(O + V((a.cx + 0.5) * G, a.y + 0.4, (a.cz + 0.5) * G))
	elseif id == "stairs" then
		return CFrame.new(O + V((a.cx + 0.5) * G, a.y + 4, (a.cz + 0.5) * G)) * CFrame.Angles(0, (a.rot or 0) * math.pi / 2, 0)
	else
		if id == "door" then
			return Building.cframe("wall", O, a) * CFrame.new(0, -0.9, 0)
		end
		if a.axis == "X" then
			return CFrame.new(O + V((a.ex + 0.5) * G, a.y + 4, a.ez * G))
		else
			return CFrame.new(O + V(a.ex * G, a.y + 4, (a.ez + 0.5) * G)) * CFrame.Angles(0, math.pi / 2, 0)
		end
	end
end

-- уникальный ключ места (две детали в одно место поставить нельзя)
function Building.key(id, a)
	local y = math.floor(a.y * 2 + 0.5)
	if id == "door" then
		return "D:" .. a.ex .. ":" .. a.ez .. ":" .. a.axis .. ":" .. y
	elseif Building.ById[id].Edge then
		return "E:" .. a.ex .. ":" .. a.ez .. ":" .. a.axis .. ":" .. y
	elseif id == "stairs" then
		return "S:" .. a.cx .. ":" .. a.cz .. ":" .. y
	else
		return "C:" .. a.cx .. ":" .. a.cz .. ":" .. y
	end
end

-- верх детали — сюда ставится следующая
function Building.top(id, a)
	if id == "foundation" then
		return a.y
	elseif id == "floor" then
		return a.y + 0.8
	else
		return a.y + Building.WallH
	end
end

local function pieceOf(inst)
	while inst and inst ~= workspace do
		if inst:IsA("Model") and inst:GetAttribute("BKind") then
			return inst
		end
		inst = inst.Parent
	end
end
Building.pieceOf = pieceOf

local function dominant(v)
	if math.abs(v.X) > math.abs(v.Z) then
		return v.X > 0 and 1 or -1, 0
	end
	return 0, v.Z > 0 and 1 or -1
end

-- куда встанет деталь, если смотреть в точку pos (hitInst — во что попали)
-- pieces — список уже стоящих деталей (Model с атрибутами)
function Building.snap(id, O, pos, hitInst, look, pieces)
	local piece = pieceOf(hitInst)
	local rel = pos - O
	local flat = V(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.01 and flat.Unit or V(0, 0, -1)
	local pk = piece and piece:GetAttribute("BKind")
	local def = Building.ById[id]
	if id == "door" then
		if pk == "doorway" or pk == "door" then
			return { ex = piece:GetAttribute("EX"), ez = piece:GetAttribute("EZ"), axis = piece:GetAttribute("Axis"), y = piece:GetAttribute("Base") }
		end
		return nil
	elseif id == "foundation" then
		if pk == "foundation" then
			local dx, dz = dominant(flat)
			return { cx = piece:GetAttribute("CX") + dx, cz = piece:GetAttribute("CZ") + dz, y = piece:GetAttribute("Top") }
		end
		if piece then
			return nil
		end
		local cx, cz = math.floor(rel.X / G), math.floor(rel.Z / G)
		local y = pos.Y + 0.8
		-- рядом уже есть фундамент — встаём с ним вровень
		for _, p in ipairs(pieces) do
			if p:GetAttribute("BKind") == "foundation" then
				local px, pz = p:GetAttribute("CX"), p:GetAttribute("CZ")
				if math.abs(px - cx) + math.abs(pz - cz) == 1 and math.abs(p:GetAttribute("Top") - y) < 4 then
					y = p:GetAttribute("Top")
					break
				end
			end
		end
		return { cx = cx, cz = cz, y = y }
	elseif def.Edge then
		if pk == "foundation" or pk == "floor" then
			local cx, cz = piece:GetAttribute("CX"), piece:GetAttribute("CZ")
			local u, w = rel.X - cx * G, rel.Z - cz * G
			local y = piece:GetAttribute("Top")
			local best = math.min(u, G - u, w, G - w)
			if best == u then
				return { ex = cx, ez = cz, axis = "Z", y = y }
			elseif best == G - u then
				return { ex = cx + 1, ez = cz, axis = "Z", y = y }
			elseif best == w then
				return { ex = cx, ez = cz, axis = "X", y = y }
			else
				return { ex = cx, ez = cz + 1, axis = "X", y = y }
			end
		elseif pk and Building.ById[pk].Edge then
			-- стена на стену (второй этаж без перекрытия)
			return { ex = piece:GetAttribute("EX"), ez = piece:GetAttribute("EZ"), axis = piece:GetAttribute("Axis"), y = piece:GetAttribute("Top") }
		end
		return nil
	elseif id == "floor" then
		if pk and Building.ById[pk].Edge then
			local q = rel + flat * 4
			return { cx = math.floor(q.X / G), cz = math.floor(q.Z / G), y = piece:GetAttribute("Top") }
		elseif pk == "floor" then
			local dx, dz = dominant(flat)
			return { cx = piece:GetAttribute("CX") + dx, cz = piece:GetAttribute("CZ") + dz, y = piece:GetAttribute("Base") }
		end
		return nil
	elseif id == "stairs" then
		if pk == "foundation" or pk == "floor" then
			local dx, dz = dominant(flat)
			-- клин поднимается от игрока вперёд (высокий край клина — его +Z)
			local rot = (dz == -1 and 2) or (dx == -1 and 3) or (dz == 1 and 0) or 1
			return { cx = piece:GetAttribute("CX"), cz = piece:GetAttribute("CZ"), y = piece:GetAttribute("Top"), rot = rot }
		end
		return nil
	end
end

return Building
