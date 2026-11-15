-- Ресурсы, инструменты, оружие и рецепты верстака.

local Items = {}

Items.Resources = {
	wood = { Name = "Дерево", Order = 1 },
	stone = { Name = "Камень", Order = 2 },
	iron = { Name = "Железо", Order = 3 },
	crystal = { Name = "Кристалл", Order = 4 },
	fang = { Name = "Клык Скрежетника", Order = 5 },
	berry = { Name = "Ягоды (H — съесть)", Order = 6 },
	key = { Name = "Ключ Лабиринта", Order = 7 },
}

-- kind: pickaxe / axe / weapon / torch. tier — какую руду/дерево может добывать.
Items.Tools = {
	fists = { Name = "Кулаки", Kind = "fists", Tier = 0, Damage = 5, Range = 7 },
	wood_pickaxe = { Name = "Деревянная кирка", Kind = "pickaxe", Tier = 1, Damage = 6, Range = 9, Color = { 120, 85, 50 } },
	stone_pickaxe = { Name = "Каменная кирка", Kind = "pickaxe", Tier = 2, Damage = 8, Range = 9, Color = { 120, 120, 125 } },
	iron_pickaxe = { Name = "Железная кирка", Kind = "pickaxe", Tier = 3, Damage = 11, Range = 9, Color = { 190, 190, 200 } },
	wood_axe = { Name = "Деревянный топор", Kind = "axe", Tier = 1, Damage = 9, Range = 9, Color = { 120, 85, 50 } },
	stone_axe = { Name = "Каменный топор", Kind = "axe", Tier = 2, Damage = 14, Range = 9, Color = { 120, 120, 125 } },
	spear = { Name = "Копьё", Kind = "spear", Tier = 0, Damage = 20, Range = 12, Color = { 120, 120, 125 } },
	stone_sword = { Name = "Каменный меч", Kind = "sword", Tier = 0, Damage = 26, Range = 9, Color = { 130, 130, 135 } },
	iron_sword = { Name = "Железный меч", Kind = "sword", Tier = 0, Damage = 40, Range = 9.5, Color = { 200, 200, 210 } },
	crystal_blade = { Name = "Кристальный клинок", Kind = "sword", Tier = 0, Damage = 65, Range = 10, Color = { 170, 90, 255 } },
	torch = { Name = "Факел", Kind = "torch", Tier = 0, Damage = 6, Range = 8, Color = { 255, 150, 60 } },
}

-- level — какой уровень верстака нужен
Items.Recipes = {
	{ Id = "torch", Level = 1, Cost = { wood = 3 } },
	{ Id = "stone_pickaxe", Level = 1, Cost = { wood = 5, stone = 8 } },
	{ Id = "stone_axe", Level = 1, Cost = { wood = 5, stone = 6 } },
	{ Id = "spear", Level = 1, Cost = { wood = 8, stone = 3 } },
	{ Id = "stone_sword", Level = 1, Cost = { wood = 4, stone = 12 } },
	{ Id = "upgrade2", Level = 1, Name = "Улучшить верстак до 2 уровня", Cost = { wood = 20, stone = 20, iron = 6 } },
	{ Id = "iron_pickaxe", Level = 2, Cost = { wood = 6, iron = 10 } },
	{ Id = "iron_sword", Level = 2, Cost = { wood = 6, iron = 14 } },
	{ Id = "crystal_blade", Level = 2, Cost = { iron = 8, crystal = 6, fang = 3 } },
}

-- Что добывается и чем
Items.Nodes = {
	tree = { Name = "Дерево", Tool = "axe", Tier = 1, Health = 40, Drop = "wood", Amount = 2 },
	stone = { Name = "Камень", Tool = "pickaxe", Tier = 1, Health = 40, Drop = "stone", Amount = 2 },
	iron = { Name = "Железная руда", Tool = "pickaxe", Tier = 2, Health = 60, Drop = "iron", Amount = 2 },
	crystal = { Name = "Кристалл", Tool = "pickaxe", Tier = 3, Health = 80, Drop = "crystal", Amount = 2 },
}

function Items.toolName(id)
	local t = Items.Tools[id]
	return t and t.Name or id
end

return Items
