-- Настройки игры «ЛАБИРИНТ». Здесь меняется всё: размер лабиринта, длина дня и ночи, монстры.

local Config = {}

Config.GameTitle = "ЛАБИРИНТ"

-- Тестовые кнопки (полный свет, полёт, день/ночь, ресурсы). Перед публикацией поставь false!
Config.DevTools = true

Config.Maze = {
	Cells = 61, -- сетка 61 x 61 клеток, лабиринт круглый (как в фильме)
	Radius = 17, -- внутренний круг (обычные коридоры), в клетках
	OuterRadius = 29, -- внешнее кольцо: коридоры вдвое шире, стены выше (≈ 1850 studs в поперечнике)
	OuterWallHeight = 92,
	CellSize = 32, -- ширина коридора
	WallHeight = 56,
	WallThickness = 4,
	ClearingCells = 13, -- поляна в центре 13 x 13 клеток (416 x 416)
	ExtraOpenings = 0.07,
	Mines = 11,
	Chests = 42,
	Cracks = 44, -- узкие щели в стенах (пролезть можно только пригнувшись)
}
Config.GateWidth = 32
Config.SlotSpacing = 6000 -- у каждой группы свой лабиринт, далеко друг от друга

-- Сложность: выбирается лифтом в лобби
Config.Difficulty = {
	easy = { Name = "ЛЕГКО", Color = { 90, 200, 110 }, Day = 360, Night = 120, Monsters = 2, PerPlayer = 0.5, Damage = 14, Speed = 17, Health = 200, Coins = 1 },
	normal = { Name = "ОБЫЧНО", Color = { 230, 190, 70 }, Day = 300, Night = 150, Monsters = 4, PerPlayer = 1, Damage = 22, Speed = 19, Health = 260, Coins = 2 },
	hard = { Name = "ТЯЖЕЛО", Color = { 220, 70, 60 }, Day = 240, Night = 180, Monsters = 7, PerPlayer = 1.5, Damage = 30, Speed = 21, Health = 340, Coins = 3 },
}
Config.WarningTime = 30

-- Игрок
Config.WalkSpeed = 16
Config.SprintSpeed = 24
Config.CrouchSpeed = 7
Config.StaminaMax = 100
Config.StaminaDrain = 22
Config.StaminaRegen = 14
Config.BerryHeal = 20
Config.DownedTime = 45 -- сколько секунд раненый ждёт помощи
Config.ReviveHealth = 40

-- Монеты: за каждый прожитый день и за побег (умножаются на сложность)
Config.CoinsPerDay = 10
Config.CoinsEscape = 100

-- Классы у торговца в лобби
-- Улучшение классов за монеты: 3 стадии. Цена перехода на 2-ю и 3-ю стадию.
Config.ClassUpgradeCost = { [2] = 300, [3] = 800 }
-- что даёт каждая стадия (показывается в магазине)
Config.ClassLevels = {
	runner = { "Бег +30%", "Бег +45%, +выносливость", "Бег +60% и ПОДКАТ (Ctrl на бегу)" },
	lumber = { "Деревянный топор, дерево ×2", "Каменный топор, дерево ×2", "Каменный топор, дерево ×3" },
	miner = { "Деревянная кирка, руда +50%", "Каменная кирка, руда +75%", "Железная кирка, руда ×2" },
	warrior = { "+40 здоровья, копьё", "+70 здоровья, копьё", "+100 здоровья, копьё и железный меч" },
	builder = { "Чертёж, молоток, 20 досок", "+40 досок и сундук", "+60 досок, сундук и верстак" },
}

Config.Classes = {
	-- Items — с чем класс появляется в лабиринте (картинки в магазине)
	{ Id = "none", Name = "Без класса", Price = 0, Desc = "Обычный выживший.", Items = {} },
	{ Id = "runner", Name = "Бегун", Price = 100, Desc = "+30% скорость бега, +60 выносливости.", Items = {} },
	{ Id = "lumber", Name = "Лесоруб", Price = 120, Desc = "Каменный топор. Дерева в 2 раза больше.", Items = { "stone_axe" } },
	{ Id = "miner", Name = "Шахтёр", Price = 150, Desc = "Каменная кирка. Добыча руды +50%.", Items = { "stone_pickaxe" } },
	{ Id = "warrior", Name = "Воин", Price = 250, Desc = "+40 здоровья. Копьё.", Items = { "spear" } },
	-- выдаётся только админом (например, на админ-абьюзе), купить нельзя
	{ Id = "builder", Name = "Строитель", Price = 0, Hidden = true, Desc = "Чертёж, молоток и 20 досок с самого начала.", Items = { "blueprint", "hammer" } },
}

-- Скрежетники — ночные монстры лабиринта (урон, скорость, здоровье — из сложности)
Config.Monster = {
	Name = "Скрежетник",
	AttackCooldown = 1.3,
	AttackRange = 7,
	PatrolSpeed = 10,
	SightRange = 110,
	HearRange = 35,
}

Config.Elevator = {
	Countdown = 15,
	RideTime = 9,
	MaxPlayers = 5,
}

Config.NodeRespawn = 90

Config.Sounds = {
	Hit = "rbxasset://sounds/action_jump_land.mp3",
	Swing = "rbxasset://sounds/swoosh.wav",
	Pickup = "rbxasset://sounds/electronicpingshort.wav",
	Click = "rbxasset://sounds/button.wav",
	Hurt = "rbxasset://sounds/uuhhh.mp3",
	Rumble = "rbxasset://sounds/action_falling.mp3",
	Step = "rbxasset://sounds/action_footsteps_plastic.mp3",
}

-- Музыка: спокойные треки по очереди, между ними тишина.
-- Если какой-то трек не играет — замени его ID на трек из Toolbox (вкладка Audio).
Config.Music = {
	Playlist = {
		"rbxassetid://87225814557507", -- Midnight Chorus
		"rbxassetid://114227963529142", -- Stellar Strings
		"rbxassetid://76744235703007", -- Aurora's Harp
		"rbxassetid://131749976124955", -- Twilight Crickets
		"rbxassetid://135250174849411", -- Celestial Whispers
		"rbxassetid://94680453165710", -- Ethereal Constellations
	},
	Pause = 20, -- секунд тишины между треками
	Volume = 0.4,
}

Config.Animations = {
	Walk = "rbxassetid://507777826",
	Run = "rbxassetid://507767714",
}

return Config
