-- Анимации квадратного (R6) персонажа: стоять, идти, прыгать, падать.
-- Копируется в персонажа сервером (лежит в ReplicatedStorage и сам там не работает).

local char = script.Parent
if not char:IsA("Model") or not char:FindFirstChildOfClass("Humanoid") then
	return
end
local hum = char:FindFirstChildOfClass("Humanoid")
local animator = hum:FindFirstChildOfClass("Animator")
if not animator then
	animator = Instance.new("Animator")
	animator.Parent = hum
end

local function load(id, looped)
	local a = Instance.new("Animation")
	a.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(a)
	end)
	if ok and track then
		track.Looped = looped
		return track
	end
	return nil
end

local idle = load("rbxassetid://180435571", true)
local walk = load("rbxassetid://180426354", true)
local jump = load("rbxassetid://125750702", false)
local fall = load("rbxassetid://180436148", true)

if idle then
	idle:Play()
end

hum.Running:Connect(function(speed)
	if speed > 0.5 then
		if walk and not walk.IsPlaying then
			walk:Play(0.2)
		end
		if walk then
			walk:AdjustSpeed(math.clamp(speed / 14, 0.5, 2))
		end
		if idle then
			idle:Stop(0.2)
		end
	else
		if walk then
			walk:Stop(0.2)
		end
		if idle and not idle.IsPlaying then
			idle:Play(0.2)
		end
	end
end)
hum.Jumping:Connect(function(active)
	if active and jump then
		jump:Play(0.1)
	end
end)
hum.FreeFalling:Connect(function(active)
	if fall then
		if active then
			fall:Play(0.2)
		else
			fall:Stop(0.2)
		end
	end
end)
