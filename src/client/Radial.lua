-- Круговое меню (как в Rust): кольцо из секторов, выбран тот, на который смотрит мышь.
-- Отпусти клавишу или нажми ЛКМ — выбор применяется.

local UserInputService = game:GetService("UserInputService")

local Radial = {}

local RGB = Color3.fromRGB
local V2 = Vector2.new

local root, center, centerTitle, centerSub, modal
local segs = {}
local options, onPick, selected

function Radial.init(gui)
	root = Instance.new("Frame")
	root.Name = "Radial"
	root.AnchorPoint = V2(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(420, 420)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.ZIndex = 30
	root.Parent = gui
	center = Instance.new("Frame")
	center.AnchorPoint = V2(0.5, 0.5)
	center.Position = UDim2.fromScale(0.5, 0.5)
	center.Size = UDim2.fromOffset(150, 150)
	center.BackgroundColor3 = RGB(16, 18, 22)
	center.BackgroundTransparency = 0.15
	center.ZIndex = 30
	center.Parent = root
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = center
	local stroke = Instance.new("UIStroke")
	stroke.Color = RGB(200, 210, 160)
	stroke.Thickness = 2
	stroke.Parent = center
	centerTitle = Instance.new("TextLabel")
	centerTitle.Size = UDim2.new(1, -16, 0, 50)
	centerTitle.Position = UDim2.fromOffset(8, 30)
	centerTitle.BackgroundTransparency = 1
	centerTitle.Font = Enum.Font.GothamBlack
	centerTitle.TextSize = 17
	centerTitle.TextWrapped = true
	centerTitle.TextColor3 = RGB(245, 240, 220)
	centerTitle.ZIndex = 31
	centerTitle.Parent = center
	centerSub = Instance.new("TextLabel")
	centerSub.Size = UDim2.new(1, -16, 0, 50)
	centerSub.Position = UDim2.fromOffset(8, 80)
	centerSub.BackgroundTransparency = 1
	centerSub.Font = Enum.Font.Gotham
	centerSub.TextSize = 12
	centerSub.TextWrapped = true
	centerSub.TextColor3 = RGB(200, 200, 190)
	centerSub.ZIndex = 31
	centerSub.Parent = center
	-- кнопка-«модал» освобождает мышь в виде от первого лица
	modal = Instance.new("TextButton")
	modal.Size = UDim2.fromScale(1, 1)
	modal.BackgroundTransparency = 1
	modal.Text = ""
	modal.Modal = true
	modal.ZIndex = 29
	modal.Parent = root
	modal.MouseButton1Click:Connect(function()
		Radial.confirm()
	end)
end

function Radial.isOpen()
	return root and root.Visible
end

-- opts: { {label=, sub=, color=}, ... }
function Radial.open(opts, pick)
	if not root then
		return
	end
	for _, s in ipairs(segs) do
		s:Destroy()
	end
	segs = {}
	options, onPick, selected = opts, pick, nil
	local n = #opts
	for k, o in ipairs(opts) do
		-- сектор: «треугольник» — повёрнутая плашка, смотрящая от центра
		local a = (k - 1) / n * math.pi * 2 - math.pi / 2
		local f = Instance.new("TextButton")
		f.AutoButtonColor = false
		f.AnchorPoint = V2(0.5, 0.5)
		f.Position = UDim2.new(0.5, math.cos(a) * 150, 0.5, math.sin(a) * 150)
		f.Size = UDim2.fromOffset(n > 6 and 104 or 120, 64)
		f.BackgroundColor3 = o.color or RGB(40, 44, 50)
		f.BackgroundTransparency = 0.2
		f.Font = Enum.Font.GothamBold
		f.TextSize = 13
		f.TextWrapped = true
		f.TextColor3 = RGB(240, 240, 235)
		f.Text = o.label
		f.ZIndex = 31
		f.Parent = root
		local cr = Instance.new("UICorner")
		cr.CornerRadius = UDim.new(0, 10)
		cr.Parent = f
		local st = Instance.new("UIStroke")
		st.Thickness = 0
		st.Color = RGB(255, 230, 120)
		st.Parent = f
		-- «остриё» треугольника к центру
		local tip = Instance.new("Frame")
		tip.AnchorPoint = V2(0.5, 0.5)
		tip.Size = UDim2.fromOffset(16, 16)
		tip.Rotation = 45
		tip.Position = UDim2.new(0.5, -math.cos(a) * 40, 0.5, -math.sin(a) * 40)
		tip.BackgroundColor3 = o.color or RGB(40, 44, 50)
		tip.BackgroundTransparency = 0.2
		tip.ZIndex = 30
		tip.Parent = f
		f.MouseButton1Click:Connect(function()
			selected = k
			Radial.confirm()
		end)
		table.insert(segs, f)
	end
	root.Visible = true
end

function Radial.close()
	if root then
		root.Visible = false
	end
	options, onPick = nil, nil
end

function Radial.confirm()
	local o, pick, k = options, onPick, selected
	Radial.close()
	if o and pick and k and o[k] then
		pick(k, o[k])
	end
end

function Radial.update()
	if not Radial.isOpen() or not options then
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	local abs = root.AbsolutePosition + root.AbsoluteSize / 2
	local d = mouse - abs
	selected = nil
	if d.Magnitude > 50 then
		local a = math.atan2(d.Y, d.X) + math.pi / 2
		local n = #options
		selected = math.floor((a / (math.pi * 2)) * n + 0.5) % n + 1
	end
	for k, f in ipairs(segs) do
		local on = k == selected
		f.UIStroke.Thickness = on and 3 or 0
		f.BackgroundTransparency = on and 0 or 0.25
		f.Size = on and UDim2.fromOffset(#segs > 6 and 116 or 132, 72) or UDim2.fromOffset(#segs > 6 and 104 or 120, 64)
	end
	local o = selected and options[selected]
	centerTitle.Text = o and o.label or "Наведи мышь"
	centerSub.Text = o and (o.sub or "") or ""
end

return Radial
