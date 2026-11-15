-- Настройки игры «ЛАБИРИНТ». Здесь меняется всё: размер лабиринта, длина дня и ночи, монстры.

local Config = {}

Config.GameTitle = "ЛАБИРИНТ"

-- Тестовые кнопки (полный свет, полёт, день/ночь, ресурсы). Перед публикацией поставь false!
Config.DevTools = true

Config.Maze = {
	Cells = 21, -- лабиринт 21 x 21 клеток (нечётное число)
	CellSize = 24, -- ширина коридора
	WallHeight = 34,
	WallThickness = 3,
	ClearingCells = 5, -- поляна в центре 5 x 5 клеток
	ExtraOpenings = 0.08, -- доля лишних проходов, чтобы было несколько путей
	Mines = 4,
	Chests = 14,
}

-- Цикл дня и ночи (секунды)
Config.DayLength = 300
Config.NightLength = 150
Config.WarningTime = 30 -- за сколько секунд до заката предупреждать

-- Игрок
Config.WalkSpeed = 16
Config.SprintSpeed = 24
Config.StaminaMax = 100
Config.StaminaDrain = 22
Config.StaminaRegen = 14
Config.BerryHeal = 20

-- Скрежетники — ночные монстры лабиринта
Config.Monster = {
	Name = "Скрежетник",
	Health = 260,
	Damage = 22,
	AttackCooldown = 1.3,
	AttackRange = 6.5,
	ChaseSpeed = 19,
	PatrolSpeed = 10,
	SightRange = 90,
	HearRange = 30,
	BaseCount = 5, -- сколько выходит ночью
	PerPlayer = 1, -- + столько за каждого игрока
}

Config.Elevator = {
	Countdown = 10, -- отсчёт в лобби, пока игроки заходят в лифт
	RideTime = 9, -- сколько едет лифт
	MaxPlayers = 8,
}

Config.NodeRespawn = 90 -- через сколько секунд вырастают деревья и руда

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
	Idle = "rbxassetid://507766388",
	Walk = "rbxassetid://507777826",
	Run = "rbxassetid://507767714",
	R6Walk = "rbxassetid://180426354",
}

return Config
