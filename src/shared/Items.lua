-- Ресурсы, инструменты, оружие и рецепты.

local Items = {}

Items.Resources = {
	wood = { Name = "Дерево", Order = 1 },
	stone = { Name = "Камень", Order = 2 },
	fiber = { Name = "Трава", Order = 3 },
	iron = { Name = "Железо", Order = 4 },
	crystal = { Name = "Кристалл", Order = 5 },
	fang = { Name = "Клык Скрежетника", Order = 6 },
	berry = { Name = "Ягоды (H — съесть)", Order = 7 },
	bandage = { Name = "Бинт (поднять друга)", Order = 8 },
	planks = { Name = "Доски", Order = 9 },
	key = { Name = "КЛЮЧ-КАРТА ВЫХОДА", Order = 10 },
}

-- Kind: pickaxe / axe / sword / spear / torch / blueprint / hammer. Tier — что может добывать.
Items.Tools = {
	fists = { Name = "Кулаки", Kind = "fists", Tier = 0, Damage = 5, Range = 7 },
	wood_pickaxe = { Name = "Деревянная кирка", Kind = "pickaxe", Tier = 1, Damage = 6, Range = 9, Color = { 120, 85, 50 } },
	stone_pickaxe = { Name = "Каменная кирка", Kind = "pickaxe", Tier = 2, Damage = 8, Range = 9, Color = { 120, 120, 125 } },
	iron_pickaxe = { Name = "Железная кирка", Kind = "pickaxe", Tier = 3, Damage = 11, Range = 9, Color = { 190, 190, 200 } },
	wood_axe = { Name = "Деревянный топор", Kind = "axe", Tier = 1, Damage = 9, Range = 9, Color = { 120, 85, 50 } },
	stone_axe = { Name = "Каменный топор", Kind = "axe", Tier = 2, Damage = 14, Range = 9, Color = { 120, 120, 125 } },
	spear = { Name = "Копьё", Kind = "spear", Tier = 0, Damage = 22, Range = 13, Color = { 120, 120, 125 } },
	stone_sword = { Name = "Каменный меч", Kind = "sword", Tier = 0, Damage = 26, Range = 9, Color = { 130, 130, 135 } },
	iron_sword = { Name = "Железный меч", Kind = "sword", Tier = 0, Damage = 40, Range = 9.5, Color = { 200, 200, 210 } },
	crystal_blade = { Name = "Кристальный клинок", Kind = "sword", Tier = 0, Damage = 65, Range = 10, Color = { 170, 90, 255 } },
	torch = { Name = "Факел", Kind = "torch", Tier = 0, Damage = 0, Range = 0, Color = { 255, 150, 60 } },
	blueprint = { Name = "Чертёж (строить)", Kind = "blueprint", Tier = 0, Damage = 0, Range = 0, Color = { 70, 110, 190 } },
	hammer = { Name = "Молоток (улучшать)", Kind = "hammer", Tier = 0, Damage = 4, Range = 10, Color = { 110, 110, 115 } },
}

-- Station: nil — крафт из инвентаря (C), "bench" — нужен верстак рядом (Level — его уровень)
Items.Recipes = {
	{ Id = "workbench", Name = "Верстак (поставить перед собой)", Cost = { wood = 12, stone = 4 }, Place = "workbench" },
	{ Id = "bandage", Name = "Бинт", Cost = { fiber = 3 }, Res = "bandage" },
	{ Id = "torch", Cost = { wood = 3, fiber = 1 } },
	{ Id = "planks", Name = "Доски ×4", Cost = { wood = 3 }, Res = "planks", Amount = 4 },
	{ Id = "blueprint", Cost = { planks = 4 } },
	{ Id = "hammer", Cost = { wood = 3, stone = 2 } },
	{ Id = "bed", Name = "Кровать (поставить; ночью — проспать ночь)", Cost = { planks = 8, fiber = 6 }, Place = "bed" },
	{ Id = "chest", Name = "Сундук-хранилище (поставить)", Cost = { planks = 10 }, Place = "chest" },
	{ Id = "stone_pickaxe", Station = "bench", Level = 1, Cost = { wood = 5, stone = 8 } },
	{ Id = "stone_axe", Station = "bench", Level = 1, Cost = { wood = 5, stone = 6 } },
	{ Id = "spear", Station = "bench", Level = 1, Cost = { wood = 8, stone = 3, fiber = 2 } },
	{ Id = "stone_sword", Station = "bench", Level = 1, Cost = { wood = 4, stone = 12 } },
	{ Id = "upgrade2", Station = "bench", Level = 1, Name = "Улучшить верстак до 2 уровня", Cost = { wood = 20, stone = 20, iron = 6 } },
	{ Id = "iron_pickaxe", Station = "bench", Level = 2, Cost = { wood = 6, iron = 10 } },
	{ Id = "iron_sword", Station = "bench", Level = 2, Cost = { wood = 6, iron = 14 } },
	{ Id = "crystal_blade", Station = "bench", Level = 2, Cost = { iron = 8, crystal = 6, fang = 3 } },
}

-- Что добывается и чем
Items.Nodes = {
	tree = { Name = "Дерево", Tool = "axe", Tier = 1, Health = 40, Drop = "wood", Amount = 2, Action = "Рубить" },
	stone = { Name = "Камень", Tool = "pickaxe", Tier = 1, Health = 40, Drop = "stone", Amount = 2, Action = "Добыть" },
	iron = { Name = "Железная руда", Tool = "pickaxe", Tier = 2, Health = 60, Drop = "iron", Amount = 2, Action = "Добыть" },
	crystal = { Name = "Кристалл", Tool = "pickaxe", Tier = 3, Health = 80, Drop = "crystal", Amount = 2, Action = "Добыть" },
}

function Items.toolName(id)
	local t = Items.Tools[id]
	return t and t.Name or id
end

return Items
