-- Настройки игры «ЛАБИРИНТ». Здесь меняется всё: размер лабиринта, длина дня и ночи, монстры.

local Config = {}

Config.GameTitle = "ЛАБИРИНТ"

-- Тестовые кнопки (полный свет, полёт, день/ночь, ресурсы). Перед публикацией поставь false!
Config.DevTools = true

Config.Maze = {
	Cells = 33, -- лабиринт 33 x 33 клеток (≈ 1 км: 33 x 32 = 1056)
	CellSize = 32, -- ширина коридора
	WallHeight = 56,
	WallThickness = 4,
	ClearingCells = 13, -- поляна в центре 13 x 13 клеток (416 x 416)
	ExtraOpenings = 0.07,
	Mines = 8,
	Chests = 30,
	Cracks = 30, -- узкие щели в стенах (пролезть можно только пригнувшись)
}
Config.GateWidth = 32
Config.SlotSpacing = 3000 -- у каждой группы свой лабиринт, далеко друг от друга

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
Config.Classes = {
	{ Id = "none", Name = "Без класса", Price = 0, Desc = "Обычный выживший." },
	{ Id = "runner", Name = "Бегун", Price = 100, Desc = "+30% скорость бега, +60 выносливости." },
	{ Id = "lumber", Name = "Лесоруб", Price = 120, Desc = "Начинает с каменным топором. Дерева в 2 раза больше." },
	{ Id = "miner", Name = "Шахтёр", Price = 150, Desc = "Начинает с каменной киркой. Добыча руды +50%." },
	{ Id = "warrior", Name = "Воин", Price = 250, Desc = "+40 здоровья. Начинает с копьём." },
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

Config.Animations = {
	Walk = "rbxassetid://507777826",
	Run = "rbxassetid://507767714",
}

return Config
