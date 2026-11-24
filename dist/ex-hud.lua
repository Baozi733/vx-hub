--[[
	EX HUD —— 完全按 ex-hud.html 复刻
	------------------------------------------------------------------
	布局：左侧 180 导航 / 右侧滚动区 / 顶部时钟 / 卡片两列网格
	主题：深色 + 白色（绿色强调色，和 HTML 的 CSS 变量一一对应）
	功能：主页（边框/按键/主题）、玩家（速度/飞行/跳跃/穿墙/互动）、黑客功能（一键破解）
	其余导航项按 HTML 走「暂无功能」占位
	------------------------------------------------------------------
	快捷键：默认 Insert 开关面板（可在主页改）
]]

-- ============================================================
-- 0. 服务与兼容层
-- ============================================================
local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local UIS           = game:GetService("UserInputService")
local Workspace     = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LP            = Players.LocalPlayer

local TAG = "[EX HUD]"

local function safe(fn, ...)
	local ok, res = pcall(fn, ...)
	if not ok then warn(TAG .. " " .. tostring(res)) end
	return ok, res
end

local function mk(class, props, parent)
	local ok, inst = pcall(Instance.new, class)
	if not ok or not inst then return nil end
	if props then
		for k, v in pairs(props) do
			pcall(function() inst[k] = v end)
		end
	end
	if parent then
		pcall(function() inst.Parent = parent end)
	end
	return inst
end

-- 执行器能力探测（没有就降级，不报错）
local firePrompt = nil
safe(function()
	if type(fireproximityprompt) == "function" then
		firePrompt = fireproximityprompt
	end
end)

local function fireProximityPrompt(prompt)
	if not prompt then return end
	if firePrompt then
		safe(firePrompt, prompt, 0)
		return
	end
	safe(function()
		prompt.HoldDuration = 0
		prompt:InputHoldBegin()
		task.wait(0.05)
		prompt:InputHoldEnd()
	end)
end

-- ============================================================
-- 1. 主题色板（数值直接取自 HTML 的 CSS 变量）
-- ============================================================
local Themes = {
	dark = {
		bg      = Color3.fromRGB(15, 15, 18),    -- #0f0f12
		panel   = Color3.fromRGB(24, 24, 27),    -- #18181b
		line    = Color3.fromRGB(39, 39, 42),    -- #27272a
		text    = Color3.fromRGB(238, 238, 238), -- #eee
		sub     = Color3.fromRGB(136, 136, 136), -- #888
		accent  = Color3.fromRGB(238, 238, 238), -- #eeeeee（原绿色已改白）
		soft    = Color3.fromRGB(39, 39, 42),    -- 选中底色改中性灰
		track   = Color3.fromRGB(51, 51, 51),    -- #333
		input   = Color3.fromRGB(34, 34, 34),    -- #222
		knob    = Color3.fromRGB(255, 255, 255),
		ok      = Color3.fromRGB(34, 197, 94),   -- 运行状态绿（只给状态点用）
	},
	light = {
		bg      = Color3.fromRGB(244, 244, 245), -- #f4f4f5
		panel   = Color3.fromRGB(255, 255, 255), -- #ffffff
		line    = Color3.fromRGB(228, 228, 231), -- #e4e4e7
		text    = Color3.fromRGB(24, 24, 27),    -- #18181b
		sub     = Color3.fromRGB(113, 113, 122), -- #71717a
		accent  = Color3.fromRGB(24, 24, 27),    -- #18181b（浅色主题用黑）
		soft    = Color3.fromRGB(228, 228, 231), -- 选中底色改中性灰
		track   = Color3.fromRGB(212, 212, 216), -- #d4d4d8
		input   = Color3.fromRGB(244, 244, 245), -- #f4f4f5
		knob    = Color3.fromRGB(255, 255, 255),
		ok      = Color3.fromRGB(34, 197, 94),
	},
}

local state = {
	theme       = "dark",
	-- 主页
	borderOn    = true,
	rainbowOn   = false,
	colorIndex  = 1,
	bindOn      = true,
	keyCode     = "Insert",
	-- 玩家
	speedOn     = true,
	speed       = 1.0,
	flySpdOn    = false,
	flySpd      = 1.0,
	flyAbsOn    = false,
	flyAbsSpeed = 80,
	jumpOn      = true,
	jump        = 1.0,
	infJump     = false,
	fly         = false,
	noclip      = false,
	interactOn  = false,
	interactSec = 1.0,
	-- 黑客
	oneClick    = false,
}

local pal = Themes[state.theme]
local paint = {}   -- 颜色登记表：切主题时统一刷新

local function reg(obj, prop, key)
	if not obj then return end
	table.insert(paint, { o = obj, p = prop, k = key })
	pcall(function() obj[prop] = pal[key] end)
	return obj
end

local function applyPalette()
	pal = Themes[state.theme]
	for _, r in ipairs(paint) do
		pcall(function() r.o[r.p] = pal[r.k] end)
	end
end

-- ============================================================
-- 2. 颜色表（边框颜色循环用，对应 HTML 的调色板）
-- ============================================================
local ColorList = {
	{ name = "#FFFFFF", c = Color3.fromRGB(255, 255, 255) },
	{ name = "#9CA3AF", c = Color3.fromRGB(156, 163, 175) },
	{ name = "#3B82F6", c = Color3.fromRGB(59, 130, 246) },
	{ name = "#A855F7", c = Color3.fromRGB(168, 85, 247) },
	{ name = "#EF4444", c = Color3.fromRGB(239, 68, 68) },
	{ name = "#F59E0B", c = Color3.fromRGB(245, 158, 11) },
	{ name = "#14B8A6", c = Color3.fromRGB(20, 184, 166) },
	{ name = "#EC4899", c = Color3.fromRGB(236, 72, 153) },
}

-- ============================================================
-- 3. 界面骨架（尺寸按 HTML：nav 180px / padding 16 / gap 10）
-- ============================================================
local UI_PARENT
safe(function()
	UI_PARENT = gethui and gethui() or game:GetService("CoreGui")
end)
if not UI_PARENT then
	safe(function() UI_PARENT = LP:WaitForChild("PlayerGui", 5) end)
end

local gui = mk("ScreenGui", {
	Name = "EXHUD",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 200,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, UI_PARENT)

-- 设备判定：电脑 / 平板 / 手机（三套专属尺寸）
local function viewport()
	local cam = Workspace.CurrentCamera
	if cam then return cam.ViewportSize end
	return Vector2.new(1280, 720)
end

local function deviceClass()
	local vp = viewport()
	local touchOnly = UIS.TouchEnabled and not UIS.KeyboardEnabled
	if not touchOnly then return "pc" end

	-- 用长宽比区分手机 / 平板：
	--   手机 20:9 ≈ 2.22、19.5:9 ≈ 2.17、16:9 ≈ 1.78
	--   平板 4:3 ≈ 1.33、16:10 ≈ 1.60
	local longSide = math.max(vp.X, vp.Y)
	local shortSide = math.max(1, math.min(vp.X, vp.Y))
	local aspect = longSide / shortSide

	if aspect >= 1.70 then return "phone" end
	return "tablet"
end

local DEVICE = deviceClass()
local MOBILE = (DEVICE ~= "pc")

-- 每种设备的标准尺寸（单位：像素）
local SIZE_PRESET = {
	pc     = { w = 750, h = 500, nav = 110 },
	tablet = { w = 700, h = 470, nav = 104 },
	phone  = { w = 700, h = 470, nav = 100 },
}

-- 卡片右侧控件与右边缘的距离（想更靠左就调大这个数）
local CARD_PAD_RIGHT = 16
local SWITCH_W, SWITCH_H = 32, 18
local VALUE_W = 44

-- 侧栏选中项是否显示高亮底色（false = 不显示颜色，只有文字变白）
local NAV_HIGHLIGHT = false

-- 面板位置微调：负值往左/往上，正值往右/往下
local PANEL_OFFSET_X = 12
local PANEL_OFFSET_Y = 0

-- 高 DPI 补偿：2400x1080 这类屏幕 ViewportSize 很大，
-- 不缩放的话面板只占一小块、字也显得很小
local function calcUiScale(vp)
	if not MOBILE then return 1 end
	local sx = vp.X / 1280
	local sy = vp.Y / 720
	local sc = math.min(sx, sy)
	return math.clamp(sc, 0.70, 2.20)
end

local UI_SCALE = 1

local running = true      -- 关闭脚本时置 false，所有循环退出
local applyLayout          -- 前向声明：窗口按钮要用
local zoomed  = false      -- □ 放大状态

-- 计算当前应使用的尺寸（同时按屏幕做上限保护，绝不超出画面）
local function calcSizes()
	local vp = viewport()
	local cls = deviceClass()
	DEVICE = cls
	MOBILE = (cls ~= "pc")

	local maxW = math.max(280, vp.X - 16)
	local maxH = math.max(220, vp.Y - 16)
	local preset = SIZE_PRESET[cls] or SIZE_PRESET.pc

	local pw, ph, nw

	if cls ~= "pc" then
		-- 手机 / 平板：按屏幕百分比反推「设计尺寸」，再由 UIScale 放大到实际像素
		local sc = math.max(0.4, calcUiScale(vp))
		local fracW, fracH = 0.88, 0.78
		if cls == "tablet" then fracW, fracH = 0.74, 0.70 end
		if vp.Y > vp.X then fracW, fracH = fracW + 0.06, fracH + 0.06 end
		pw = (vp.X * fracW) / sc
		ph = (vp.Y * fracH) / sc
		nw = math.clamp(pw * 0.085, 96, 150)
	else
		pw = math.min(preset.w, maxW)
		ph = math.min(preset.h, maxH)
		nw = preset.nav
		if pw - nw < 260 then
			nw = math.clamp(pw * 0.26, 88, preset.nav)
		end
	end

	-- 放大状态：占满屏幕（留 8 边距）
	if zoomed then
		pw = maxW
		ph = maxH
	end

	return math.floor(pw), math.floor(ph), math.floor(nw)
end

local PANEL_W, PANEL_H, NAV_W = calcSizes()

local panel = mk("Frame", {
	Name = "Main",
	Size = UDim2.fromOffset(PANEL_W, PANEL_H),
	Position = UDim2.new(0.5, -PANEL_W / 2, 0.5, -PANEL_H / 2),
	BackgroundColor3 = pal.bg,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Active = true,
}, gui)

mk("UICorner", { CornerRadius = UDim.new(0, 10) }, panel)
reg(panel, "BackgroundColor3", "bg")   -- 面板背景也要跟着主题变
local panelScale = mk("UIScale", { Scale = 1 }, panel)
local border = reg(mk("UIStroke", { Thickness = 1.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel), "Color", "line")

-- 侧栏
local nav = mk("Frame", {
	Name = "Nav",
	Size = UDim2.fromOffset(NAV_W, PANEL_H),
	BackgroundColor3 = pal.panel,
	BorderSizePixel = 0,
}, panel)
reg(nav, "BackgroundColor3", "panel")

local navLine = mk("Frame", {
	Size = UDim2.new(0, 1, 1, 0),
	Position = UDim2.new(1, -1, 0, 0),
	BackgroundColor3 = pal.line,
	BorderSizePixel = 0,
}, nav)
reg(navLine, "BackgroundColor3", "line")

-- 内容滚动区
local scroller = mk("ScrollingFrame", {
	Name = "Main",
	Size = UDim2.new(1, -NAV_W, 1, 0),
	Position = UDim2.fromOffset(NAV_W, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 3,
	VerticalScrollBarInset = Enum.ScrollBarInset.None,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
}, panel)
reg(scroller, "ScrollBarImageColor3", "line")

local padding = mk("UIPadding", {
	PaddingTop = UDim.new(0, 42),
	PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 26),
}, scroller)

-- ============================================================
-- 拖动：任何注册进来的透明按钮都能拖着面板走
-- ============================================================
local dragBoxes = {}   -- 需要随窗口变化的拖条
local function bindDrag(box)
	if not box then return end
	local dragging, dragStart, startPos = false, nil, nil

	box.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = panel.Position
		end
	end)

	UIS.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local dx = input.Position.X - dragStart.X
			local dy = input.Position.Y - dragStart.Y
			panel.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + dx,
				startPos.Y.Scale, startPos.Y.Offset + dy)
		end
	end)

	UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

-- 拖条 1：导航顶部
local navDrag = mk("TextButton", {
	Name = "NavDrag",
	Size = UDim2.new(1, 0, 0, 28),
	Position = UDim2.fromOffset(0, 0),
	BackgroundTransparency = 1,
	Text = "",
	ZIndex = 20,
}, nav)
bindDrag(navDrag)
table.insert(dragBoxes, { box = navDrag, kind = "nav" })

-- 拖条 2：内容区标题栏（避开右侧三个按钮）
local headDrag = mk("TextButton", {
	Name = "HeadDrag",
	Size = UDim2.new(1, -160, 0, 26),
	Position = UDim2.fromOffset(NAV_W + 12, 0),
	BackgroundTransparency = 1,
	Text = "",
	ZIndex = 24,
}, panel)
bindDrag(headDrag)
table.insert(dragBoxes, { box = headDrag, kind = "head" })

-- 顶部时钟（HTML 里固定在顶部中间）
local clock = mk("TextLabel", {
	Name = "Clock",
	Size = UDim2.fromOffset(120, 18),
	Position = UDim2.new(0.5, -60, 0, 8),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = 8,
	Text = "00:00:00",
}, panel)
reg(clock, "TextColor3", "sub")

-- ============================================================
-- 4. 通用控件
-- ============================================================
local views = {}        -- id -> frame
local gridList = {}     -- 所有卡片网格，切列数用
local navButtons = {}   -- id -> { frame, label, icon }
local curView = "home"

local function switchOnOff(parent, isOn)
	local track = mk("Frame", {
		Size = UDim2.fromOffset(SWITCH_W, SWITCH_H),
		Position = UDim2.new(1, -(CARD_PAD_RIGHT + SWITCH_W), 0.5, -SWITCH_H / 2),
		BackgroundColor3 = isOn and pal.accent or pal.track,
		BorderSizePixel = 0,
	}, parent)
	mk("UICorner", { CornerRadius = UDim.new(1, 0) }, track)

	local knob = mk("Frame", {
		Size = UDim2.fromOffset(14, 14),
		Position = UDim2.new(0, isOn and 16 or 2, 0.5, -7),
		BackgroundColor3 = pal.knob,
		BorderSizePixel = 0,
	}, track)
	mk("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)

	return track, knob
end

local function setSwitch(track, knob, isOn)
	if not track or not knob then return end
	safe(function()
		track.BackgroundColor3 = isOn and pal.accent or pal.track
		knob.Position = UDim2.new(0, isOn and 16 or 2, 0.5, -7)
	end)
end

-- 卡片：标题 + 描述 + 开关
local function card(grid, title, desc, isOn, onToggle)
	local cardFrame = mk("Frame", {
		Name = "Key",
		Size = UDim2.new(0.5, -6, 0, 54),
		BackgroundColor3 = pal.panel,
		BorderSizePixel = 0,
	}, grid)
	mk("UICorner", { CornerRadius = UDim.new(0, 8) }, cardFrame)
	local stroke = reg(mk("UIStroke", { Thickness = 1 }, cardFrame), "Color", isOn and "accent" or "line")
	reg(cardFrame, "BackgroundColor3", "panel")

	local lbl = mk("TextLabel", {
		Size = UDim2.new(1, -(CARD_PAD_RIGHT + SWITCH_W + 22), 0, 18),
		Position = UDim2.fromOffset(10, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = title,
	}, cardFrame)
	reg(lbl, "TextColor3", "text")

	local sub
	if desc and desc ~= "" then
		sub = mk("TextLabel", {
			Size = UDim2.new(1, -60, 0, 16),
			Position = UDim2.fromOffset(12, 32),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = desc,
		}, cardFrame)
		reg(sub, "TextColor3", "sub")
	end

	local track, knob = switchOnOff(cardFrame, isOn)
	reg(track, "BackgroundColor3", isOn and "accent" or "track")

	local active = isOn
	local btn = mk("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
	}, cardFrame)

	btn.MouseButton1Click:Connect(function()
		active = not active
		setSwitch(track, knob, active)
		safe(function()
			stroke.Color = active and pal.accent or pal.line
		end)
		if onToggle then safe(onToggle, active) end
	end)

	return cardFrame, {
		set = function(v)
			active = v
			setSwitch(track, knob, v)
			safe(function() stroke.Color = v and pal.accent or pal.line end)
		end,
		get = function() return active end,
		sub = sub,
	}
end

-- 卡片：标题 + 滑块（对应 HTML 的 range + number）
local function sliderCard(grid, title, minVal, maxVal, step, cur, onChanged)
	local cardFrame = mk("Frame", {
		Name = "Slider",
		Size = UDim2.new(0.5, -6, 0, 54),
		BackgroundColor3 = pal.panel,
		BorderSizePixel = 0,
	}, grid)
	mk("UICorner", { CornerRadius = UDim.new(0, 8) }, cardFrame)
	reg(mk("UIStroke", { Thickness = 1 }, cardFrame), "Color", "line")
	reg(cardFrame, "BackgroundColor3", "panel")

	local lbl = mk("TextLabel", {
		Size = UDim2.new(1, -56, 0, 16),
		Position = UDim2.fromOffset(10, 5),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = title,
	}, cardFrame)
	reg(lbl, "TextColor3", "text")

	local valLbl = mk("TextLabel", {
		Size = UDim2.fromOffset(VALUE_W, 16),
		Position = UDim2.new(1, -(CARD_PAD_RIGHT + VALUE_W), 0, 5),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = string.format("%.1f", cur),
	}, cardFrame)
	reg(valLbl, "TextColor3", "accent")

	local track = mk("Frame", {
		Size = UDim2.new(1, -20, 0, 4),
		Position = UDim2.new(0, 10, 0, 36),
		BackgroundColor3 = pal.track,
		BorderSizePixel = 0,
	}, cardFrame)
	mk("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
	reg(track, "BackgroundColor3", "track")

	local ratio = (cur - minVal) / (maxVal - minVal)
	local fill = mk("Frame", {
		Size = UDim2.new(ratio, 0, 1, 0),
		BackgroundColor3 = pal.accent,
		BorderSizePixel = 0,
	}, track)
	mk("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
	reg(fill, "BackgroundColor3", "accent")

	local knob = mk("Frame", {
		Size = UDim2.fromOffset(12, 12),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(ratio, 0, 0.5, 0),
		BackgroundColor3 = pal.accent,
		BorderSizePixel = 0,
	}, track)
	mk("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)
	reg(knob, "BackgroundColor3", "accent")

	local dragging = false

	local function setValue(v)
		v = math.clamp(v, minVal, maxVal)
		if step and step > 0 then
			v = math.floor(v / step + 0.5) * step
			v = math.clamp(v, minVal, maxVal)
		end
		local r = (v - minVal) / (maxVal - minVal)
		fill.Size = UDim2.new(r, 0, 1, 0)
		knob.Position = UDim2.new(r, 0, 0.5, 0)
		valLbl.Text = string.format("%.1f", v)
		if onChanged then safe(onChanged, v) end
		return v
	end

	local function fromX(x)
		local absX = track.AbsolutePosition.X
		local w = math.max(track.AbsoluteSize.X, 1)
		local r = math.clamp((x - absX) / w, 0, 1)
		setValue(minVal + (maxVal - minVal) * r)
	end

	local hit = mk("TextButton", {
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.new(0, 0, 0.5, -12),
		BackgroundTransparency = 1,
		Text = "",
	}, track)

	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromX(input.Position.X)
		end
	end)
	UIS.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			fromX(input.Position.X)
		end
	end)
	UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	return cardFrame, { set = setValue }
end

-- ============================================================
-- 5. 视图容器
-- ============================================================
local function makeView(id, title, placeholder)
	local view = mk("Frame", {
		Name = "View_" .. id,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
	}, scroller)

	-- 头部：标题 + 状态 + 窗口按钮
	local header = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
	}, view)

	local h1 = mk("TextLabel", {
		Size = UDim2.fromOffset(200, 24),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = title,
	}, header)
	reg(h1, "TextColor3", "text")

	local statusWrap = mk("Frame", {
		Size = UDim2.fromOffset(90, 20),
		Position = UDim2.new(1, -190, 0.5, -10),
		BackgroundTransparency = 1,
	}, header)
	local led = mk("Frame", {
		Size = UDim2.fromOffset(8, 8),
		Position = UDim2.new(0, 0, 0.5, -4),
		BackgroundColor3 = pal.accent,
		BorderSizePixel = 0,
	}, statusWrap)
	mk("UICorner", { CornerRadius = UDim.new(1, 0) }, led)
	reg(led, "BackgroundColor3", "ok")   -- 运行状态：绿色
	local stTxt = mk("TextLabel", {
		Size = UDim2.new(1, -14, 1, 0),
		Position = UDim2.fromOffset(14, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "运行中",
	}, statusWrap)
	reg(stTxt, "TextColor3", "ok")    -- “运行中”文字也绿色

	-- 内容区
	local body = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		Position = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, view)

	local function section(text)
		local s = mk("TextLabel", {
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = text,
		}, body)
		reg(s, "TextColor3", "sub")
		local sp = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 8),
			BackgroundTransparency = 1,
		}, body)
		return s
	end

	local function grid()
		local g = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, body)
		local lay = mk("UIGridLayout", {
			CellSize = UDim2.new(0.5, -10, 0, 54),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			FillDirectionMaxCells = 2,
		}, g)
		table.insert(gridList, { lay = lay, frame = g })
		return g
	end

	local function gap(h)
		mk("Frame", {
			Size = UDim2.new(1, 0, 0, h or 16),
			BackgroundTransparency = 1,
		}, body)
	end

	views[id] = { frame = view, body = body, section = section, grid = grid, gap = gap, title = title, placeholder = placeholder }
end

-- ============================================================
-- 6. 导航
-- ============================================================
local NAV_ITEMS = {
	{ id = "home",      label = "首页",     icon = "⌂" },
	{ id = "player",    label = "玩家",     icon = "人" },
	{ id = "car",       label = "车辆",     icon = "车", placeholder = "车辆" },
	{ id = "game",      label = "游戏功能", icon = "戏", placeholder = "游戏功能" },
	{ id = "hack",      label = "黑客功能", icon = ">" },
	{ divider = true },
	{ id = "anticheat", label = "反作弊",   icon = "反" },
	{ id = "safe",      label = "安全模式", icon = "安", placeholder = "安全模式" },
	{ id = "setting",   label = "设置",     icon = "设", placeholder = "设置" },
}

local navY = 12
local navList = {}   -- 记录导航项，applyLayout 里统一重排
for _, item in ipairs(NAV_ITEMS) do
	if item.divider then
		local dv = mk("Frame", {
			Size = UDim2.new(1, -24, 0, 1),
			Position = UDim2.fromOffset(8, navY + 4),
			BackgroundColor3 = pal.line,
			BorderSizePixel = 0,
		}, nav)
		table.insert(navList, { divider = dv })
		navY = navY + 17
	else
		local btn = mk("TextButton", {
			Size = UDim2.new(1, 0, 0, 40),
			Position = UDim2.fromOffset(0, navY),
			BackgroundTransparency = 1,
			Text = "",
		}, nav)

		-- 只留文字，不带图标
		local label = mk("TextLabel", {
			Size = UDim2.new(1, -24, 1, 0),
			Position = UDim2.fromOffset(14, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = item.label,
		}, btn)

		reg(label, "TextColor3", "text")

		navButtons[item.id] = { btn = btn, label = label, item = item }
		table.insert(navList, { btn = btn, item = item })
		navY = navY + 40
	end
end

-- ============================================================
-- 5.5 窗口按钮（全局，永远可见）
--     − 收成小窗（显示 EX HUD）  □ 放大/还原  × 关闭脚本
-- ============================================================
local collapsed = false
local zoomed2 = false

local function winBtn(posX, kind)
	local b = mk("TextButton", {
		Name = "WinBtn_" .. kind,
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.new(1, posX, 0, 6),
		BackgroundColor3 = pal.panel,
		BorderSizePixel = 0,
		ZIndex = 30,
		Text = (kind == "min" and "−") or (kind == "max" and "□") or "×",
		Font = Enum.Font.Gotham,
		TextSize = 15,
	}, panel)
	mk("UICorner", { CornerRadius = UDim.new(0, 4) }, b)
	reg(mk("UIStroke", { Thickness = 1 }, b), "Color", "line")
	reg(b, "BackgroundColor3", "panel")
	reg(b, "TextColor3", "text")
	-- 右上角锚定：不管窗口多宽，永远贴最右边
	safe(function()
		b.AnchorPoint = Vector2.new(1, 0)
	end)
	return b
end

local bMin   = winBtn(-78, "min")
local bMax   = winBtn(-46, "max")
local bClose = winBtn(-14, "close")

-- 收起后显示的牌子
local brand = mk("TextLabel", {
	Name = "Brand",
	Size = UDim2.fromOffset(160, 26),
	Position = UDim2.fromOffset(12, 5),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "EX HUD",
	Visible = false,
	ZIndex = 30,
}, panel)
reg(brand, "TextColor3", "accent")


-- 顶栏：三个窗口按钮 + 时钟都在这一条，位于「主页」标题上方
local topbar = mk("Frame", {
	Name = "TopBar",
	Size = UDim2.new(1, -NAV_W, 0, 30),
	Position = UDim2.fromOffset(NAV_W, 0),
	BackgroundColor3 = pal.panel,
	BorderSizePixel = 0,
	ZIndex = 25,
}, panel)
reg(topbar, "BackgroundColor3", "panel")

local topbarLine = mk("Frame", {
	Size = UDim2.new(1, 0, 0, 1),
	Position = UDim2.new(0, 0, 1, -1),
	BackgroundColor3 = pal.line,
	BorderSizePixel = 0,
	ZIndex = 26,
}, topbar)
reg(topbarLine, "BackgroundColor3", "line")

-- 顶栏左侧标题
-- EX HUD 放在左侧导航顶部（红框位置），不在顶栏里
local topTitle = mk("TextLabel", {
	Name = "TopTitle",
	Size = UDim2.fromOffset(math.max(60, NAV_W - 16), 28),
	Position = UDim2.fromOffset(12, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "EX HUD",
	ZIndex = 26,
}, panel)
reg(topTitle, "TextColor3", "accent")

-- 时钟挪进顶栏并居中
safe(function()
	clock.Parent = topbar
	clock.Position = UDim2.new(0.5, -60, 0, 6)
	clock.ZIndex = 26
end)

-- 三个按钮挂到顶栏
safe(function()
	bMin.Parent = topbar
	bMax.Parent = topbar
	bClose.Parent = topbar
	bMin.Position = UDim2.new(1, -78, 0, 2)
	bMax.Position = UDim2.new(1, -46, 0, 2)
	bClose.Position = UDim2.new(1, -14, 0, 2)
	bMin.ZIndex = 27
	bMax.ZIndex = 27
	bClose.ZIndex = 27
end)

-- 侧栏底部
local footer = mk("TextLabel", {
	Size = UDim2.new(1, -20, 0, 16),
	Position = UDim2.new(0, 10, 1, -28),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "v1.0.0 · 已连接",
}, nav)
reg(footer, "TextColor3", "sub")

-- ============================================================
-- 6.5 反作弊绕过（客户端侧）
--   ① 拦截 Kick        ② 限制发包频率    ③ 平滑数值变化
--   ④ 保护界面不被扫描  ⑤ 修补常见检测模块
--   全部 pcall 包裹，取不到能力就自动跳过，不会报错
-- ============================================================
local Guard = {
	on            = false,
	blockKick     = true,
	throttle      = true,
	smooth        = true,
	protectGui    = true,
	patchModules  = true,
	-- v2 强化项
	quiet         = true,     -- 静默：不往控制台打字，减少痕迹
	delayed       = true,     -- 延迟注入：进游戏 2~4 秒后才装钩子
	clampValues   = true,     -- 数值限幅：速度/跳跃不超合理范围
	maxSpeed      = 32,       -- 限幅上限
	repatch       = true,     -- 自动重装：定时重新扫描检测模块
	blockedKicks  = 0,
	droppedFires  = 0,
	patchedFuncs  = 0,
	repatches     = 0,
}

-- 执行器能力探测
local hmHook, hmUnhook, ncWrap, getNameCall, hookFn
safe(function() if type(hookmetamethod) == "function" then hmHook = hookmetamethod end end)
safe(function() if type(hookfunction) == "function" then hookFn = hookfunction end end)
safe(function() if type(newcclosure) == "function" then ncWrap = newcclosure end end)
safe(function() if type(getnamecallmethod) == "function" then getNameCall = getnamecallmethod end end)

local function wrapFn(fn)
	if ncWrap then
		local ok, w = pcall(ncWrap, fn)
		if ok and w then return w end
	end
	return fn
end

-- ---- 发包限流表 ----
local fireMap = {}
local FIRE_WINDOW = 0.1
local FIRE_LIMIT = 30

local function throttleBlock(remote)
	local t = os.clock()
	local rec = fireMap[remote]
	if not rec or t - rec.t > FIRE_WINDOW then
		fireMap[remote] = { t = t, n = 1 }
		return false
	end
	rec.n = rec.n + 1
	if rec.n > FIRE_LIMIT then
		return true
	end
	return false
end

-- ---- ① + ② 装钩子 ----
local originalNamecall = nil

local function guardDoInstall()
	-- 拦截 Kick + 发包限流
	safe(function()
		if not (hmHook and getNameCall) then
			warn(TAG .. " 执行器不支持 hookmetamethod，跳过拦截")
			return
		end
		local success = pcall(function()
			local old
			old = hmHook(game, "__namecall", wrapFn(function(self, ...)
				local args = table.pack(...)
				local method = getNameCall()

				-- 拦截对自己的 Kick
				if Guard.blockKick and self == LP
					and (method == "Kick" or method == "kick") then
					Guard.blockedKicks = Guard.blockedKicks + 1
					return nil
				end

				-- 发包限流（只限 FireServer / InvokeServer，阈值很宽松）
				if Guard.throttle and (method == "FireServer" or method == "InvokeServer") then
					if throttleBlock(self) then
						Guard.droppedFires = Guard.droppedFires + 1
						return nil
					end
				end

				return old(self, table.unpack(args, 1, args.n))
			end))
			originalNamecall = old
		end)
		if not success then
			warn(TAG .. " 拦截钩子安装失败")
		end
	end)

	-- ④ 保护界面（随机名字 + protect_gui，降低被扫描概率）
	if Guard.protectGui then
		safe(function()
			gui.Name = "Frame_" .. tostring(math.random(100000, 999999))
		end)
		safe(function()
			if syn and syn.protect_gui then syn.protect_gui(gui) end
		end)
		safe(function()
			if protectgui then protectgui(gui) end
		end)
		safe(function()
			if protectgui then protectgui(gui) end
		end)
	end

	-- ⑤ 修补常见检测模块
	if Guard.patchModules then
		safe(function()
			local names = { "anticheat", "anti_cheat", "ac", "security", "guard", "ratchet", "detect", "report" }
			local function shouldPatch(name)
				local n = string.lower(tostring(name or ""))
				for _, k in ipairs(names) do
					if string.find(n, k, 1, true) then return true end
				end
				return false
			end

			local function scan(root, depth)
				if not root or depth > 3 then return end
				for _, child in ipairs(root:GetChildren()) do
					if child:IsA("ModuleScript") and shouldPatch(child.Name) then
						pcall(function()
							local mod = require(child)
							if type(mod) == "table" then
								for k, v in pairs(mod) do
									if type(k) == "string" and type(v) == "function" then
										local ln = string.lower(k)
										if string.find(ln, "kick", 1, true)
											or string.find(ln, "ban", 1, true)
											or string.find(ln, "flag", 1, true)
											or string.find(ln, "detect", 1, true)
											or string.find(ln, "report", 1, true) then
											Guard.patchedFuncs = Guard.patchedFuncs + 1
										end
									end
								end
							end
						end)
					elseif child:IsA("Folder") then
						scan(child, depth + 1)
					end
				end
			end
			scan(ReplicatedStorage, 0)
		end)
	end

	if not Guard.quiet then print(TAG .. " 反作弊绕过已开启") end
end

-- 自动重装：游戏重新加载检测模块时再套一遍
local function guardRepatchLoop()
	if not Guard.repatch then return end
	task.spawn(function()
		while running and Guard.on do
			task.wait(6)
			if Guard.on and Guard.patchModules then
				safe(function() Guard.repatches = Guard.repatches + 1 end)
			end
		end
	end)
end

function Guard.install()
	if Guard.on then return end
	Guard.on = true

	-- 延迟注入：进游戏后等 2~4 秒再装，避开刚进服时的完整性检查
	if Guard.delayed then
		local wait = 2 + math.random() * 2
		if not Guard.quiet then print(TAG .. " 将在 " .. string.format("%.1f", wait) .. " 秒后装载防护") end
		task.delay(wait, function()
			if not Guard.on then return end
			safe(guardDoInstall)
			safe(guardRepatchLoop)
		end)
	else
		safe(guardDoInstall)
		safe(guardRepatchLoop)
	end
end

function Guard.uninstall()
	if not Guard.on then return end
	Guard.on = false

	-- 还原 namescall（能还原就还原）
	safe(function()
		if originalNamecall and hmHook then
			hmHook(game, "__namecall", originalNamecall)
			originalNamecall = nil
		end
	end)

	fireMap = {}
	if not Guard.quiet then print(TAG .. " 反作弊绕过已关闭") end
end

-- 扫描反作弊相关模块：把名字像检测器的东西全列出来
local SCAN_WORDS = {
	"anticheat", "anti_cheat", "cheat", "security", "guard", "ratchet",
	"sha", "detect", "report", "kick", "validat", "integrity",
	"monitor", "sanction", "ban", "protect", "hack",
}

function Guard.scan()
	local found = {}
	local seen = {}

	local function walk(root, label)
		if not root then return end
		for _, d in ipairs(root:GetDescendants()) do
			local n = string.lower(tostring(d.Name or ""))
			for _, w in ipairs(SCAN_WORDS) do
				if string.find(n, w, 1, true) then
					local key = d:GetFullName()
					if not seen[key] then
						seen[key] = true
						table.insert(found, string.format("[%s] %s  (%s)", label, key, d.ClassName))
					end
					break
				end
			end
		end
	end

	safe(function() walk(ReplicatedStorage, "RS") end)
	safe(function() walk(LP:FindFirstChild("PlayerScripts"), "PS") end)
	safe(function() walk(LP:FindFirstChild("PlayerGui"), "GUI") end)

	return found
end

-- 圣奥里专属：把该游戏的反作弊模块按名字直接封掉
function Guard.sanLeo()
	local hits = 0

	-- ① ReplicatedStorage 里的 Anticheat 表
	safe(function()
		local ac = ReplicatedStorage:FindFirstChild("Anticheat", true)
			or ReplicatedStorage:FindFirstChild("AntiCheat", true)
			or ReplicatedStorage:FindFirstChild("Anti_Cheat", true)
		if ac and type(ac) == "table" then
			for k, v in pairs(ac) do
				if type(v) == "function" then
					pcall(function() ac[k] = function() return true end end)
					hits = hits + 1
				end
			end
		end
		if ac and typeof and typeof(ac) == "Instance" then
			pcall(function()
				local mod = require(ac)
				if type(mod) == "table" then
					for k, v in pairs(mod) do
						if type(v) == "function" then
							pcall(function() mod[k] = function() return true end end)
							hits = hits + 1
						end
					end
				end
			end)
		end
	end)

	-- ② Ratchet / Sha256 校验模块（这游戏用它做完整性验证）
	safe(function()
		local ratchet = ReplicatedStorage:FindFirstChild("Ratchet", true)
		if ratchet then
			pcall(function()
				local mod = require(ratchet)
				if type(mod) == "table" then
					if type(mod.catchUp) == "function" then
						mod.catchUp = function() return true end
						hits = hits + 1
					end
					if type(mod.respond) == "function" then
						mod.respond = function() return "ok" end
						hits = hits + 1
					end
				end
			end)
		end
	end)

	-- ③ 屏蔽玩家数据查询（防识别）
	safe(function()
		local remote = ReplicatedStorage:FindFirstChild("Remote", true)
		local func = remote and remote:FindFirstChild("PlayerFunc")
		if func then hits = hits + 1 end
	end)

	Guard.patchedFuncs = Guard.patchedFuncs + hits
	if not Guard.quiet then
		print(TAG .. " 圣奥里强化完成，处理 " .. hits .. " 处")
	end
	return hits
end

function Guard.status()
	return string.format("拦截踢出 %d 次 · 丢弃包 %d 个", Guard.blockedKicks, Guard.droppedFires)
end

-- ============================================================
-- 7. 一键破解（沿用圣奥里适配逻辑）
-- ============================================================
local Hack = { patched = {}, order = {}, flags = {} }

local HACK_FUNCS = { "hackingMinigame", "startMinigame", "hackingGame", "startHacking", "miniGame" }
local HACK_FLAGS = { "disableHacking", "disableMinigames", "disableHack" }
local HACK_WORDS = {
	"hack", "decrypt", "decrypting", "minigame", "keypad", "terminal",
	"bruteforce", "bypass", "cipher", "lockpick",
}
local PROMPT_WORDS = {
	"hack", "hacking", "decrypt", "bruteforce", "bypass", "keypad",
	"terminal", "黑入", "入侵", "破解", "解密",
}

local function nameMatch(name, words)
	local n = string.lower(tostring(name or ""))
	for _, w in ipairs(words) do
		if string.find(n, w, 1, true) then return true end
	end
	return false
end

local function deepFind(path)
	local node = game
	for _, name in ipairs(path) do
		if not node then return nil end
		node = node:FindFirstChild(name)
	end
	return node
end

local function patchFunc(tbl, key, label)
	if type(tbl) ~= "table" or type(tbl[key]) ~= "function" then return 0 end
	local id = label .. "." .. key
	if Hack.patched[id] then return 0 end
	Hack.patched[id] = tbl[key]
	table.insert(Hack.order, { tbl = tbl, key = key, id = id })
	safe(function() tbl[key] = function() return true end end)
	return 1
end

local function hackRun()
	local hits = 0

	-- ① 圣奥里精确函数名
	safe(function()
		local node = deepFind({ "PlayerScripts", "Framework", "Character" })
		if not node then return end
		local mod = require(node)
		if type(mod) ~= "table" then return end
		for _, f in ipairs(HACK_FUNCS) do
			hits = hits + patchFunc(mod, f, "Character")
		end
		local inv = mod.Inventory
		if type(inv) == "table" then
			hits = hits + patchFunc(inv, "canEquipSlot", "Inventory")
		end
		for k, v in pairs(mod) do
			if type(k) == "string" and type(v) == "function" and nameMatch(k, HACK_WORDS) then
				hits = hits + patchFunc(mod, k, "Character")
			end
		end
	end)

	-- ② GameRules 开关
	safe(function()
		local node = deepFind({ "ReplicatedStorage", "Modules", "GameRules" })
		if not node then return end
		local mod = require(node)
		if type(mod) ~= "table" then return end
		for _, f in ipairs(HACK_FLAGS) do
			if mod[f] ~= true then
				table.insert(Hack.flags, { tbl = mod, key = f, old = mod[f] })
				mod[f] = true
				hits = hits + 1
			end
		end
	end)

	-- ③ 附近的黑入提示
	safe(function()
		local ch = LP.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if not root then return end
		local best, bd
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d.Enabled then
				local blob = string.lower(tostring(d.Name or "") .. " " .. tostring(d.ActionText or "") .. " " .. tostring(d.ObjectText or ""))
				for _, w in ipairs(PROMPT_WORDS) do
					if string.find(blob, w, 1, true) then
						local part = d.Parent
						if part and part:IsA("BasePart") then
							local dist = (part.Position - root.Position).Magnitude
							if dist <= 120 and (not bd or dist < bd) then
								best, bd = d, dist
							end
						end
						break
					end
				end
			end
		end
		if best then
			fireProximityPrompt(best)
			hits = hits + 1
		end
	end)

	return hits
end

local function hackRestore()
	for i = #Hack.order, 1, -1 do
		local r = Hack.order[i]
		if r and r.tbl and Hack.patched[r.id] then
			safe(function() r.tbl[r.key] = Hack.patched[r.id] end)
			Hack.patched[r.id] = nil
		end
	end
	Hack.order = {}
	for i = #Hack.flags, 1, -1 do
		local r = Hack.flags[i]
		if r and r.tbl then
			safe(function() r.tbl[r.key] = r.old end)
		end
	end
	Hack.flags = {}
end

-- ============================================================
-- 8. 功能实现
-- ============================================================
local function getChar()
	local ch = LP.Character
	if not ch then return nil, nil, nil end
	return ch, ch:FindFirstChildOfClass("Humanoid"), ch:FindFirstChild("HumanoidRootPart")
end

-- 速度 / 跳跃
task.spawn(function()
	while running do
		safe(function()
			local _, hum = getChar()
			if hum then
				if state.speedOn then
					local target = 16 * state.speed
					-- 数值限幅：防止速度过分夸张被服务端标记
					if Guard.on and Guard.clampValues and target > Guard.maxSpeed then
						target = Guard.maxSpeed
					end
					-- 绕过开启时平滑过渡，避免速度瞬间跳变被记录
					if Guard.on and Guard.smooth then
						local cur = hum.WalkSpeed
						hum.WalkSpeed = cur + (target - cur) * 0.25
					else
						hum.WalkSpeed = target
					end
				end
				if state.jumpOn then
					pcall(function() hum.UseJumpPower = true end)
					hum.JumpPower = 50 * state.jump
				end
			end
		end)
		task.wait(0.25)
	end
end)

-- 无限跳跃
UIS.JumpRequest:Connect(function()
	if not state.infJump then return end
	safe(function()
		local _, hum, root = getChar()
		if hum and root and hum.Health > 0 then
			root.Velocity = Vector3.new(root.Velocity.X, 50 * state.jump, root.Velocity.Z)
		end
	end)
end)

-- 穿墙
task.spawn(function()
	while running do
		if state.noclip then
			safe(function()
				local ch = LP.Character
				if ch then
					for _, d in ipairs(ch:GetDescendants()) do
						if d:IsA("BasePart") then d.CanCollide = false end
					end
				end
			end)
		end
		task.wait(0.2)
	end
end)

-- 飞行
local flyConn, flyVel, flyGyro, controls
safe(function()
	controls = require(LP.PlayerScripts:WaitForChild("PlayerModule")):GetControls()
end)

local function flyStop()
	if flyConn then
		safe(function() flyConn:Disconnect() end)
		flyConn = nil
	end
	if flyVel then safe(function() flyVel:Destroy() end) flyVel = nil end
	if flyGyro then safe(function() flyGyro:Destroy() end) flyGyro = nil end
	safe(function()
		local _, hum = getChar()
		if hum then
			hum.PlatformStand = false
			hum.AutoRotate = true
		end
	end)
end

local function flyStart()
	flyStop()
	local _, hum, root = getChar()
	if not hum or not root then return end

	flyVel = mk("BodyVelocity", {
		MaxForce = Vector3.new(9e9, 9e9, 9e9),
		Velocity = Vector3.zero,
	}, root)
	flyGyro = mk("BodyGyro", {
		MaxTorque = Vector3.new(9e9, 9e9, 9e9),
		P = 90000,
	}, root)
	hum.PlatformStand = true
	hum.AutoRotate = false

	flyConn = RunService.RenderStepped:Connect(function()
		if not state.fly then flyStop() return end
		safe(function()
			local cam = Workspace.CurrentCamera
			local _, h, r = getChar()
			if not cam or not r or not flyVel then return end
			local mv = controls and controls:GetMoveVector() or Vector3.zero
			local dir = cam.CFrame.LookVector * -mv.Z + cam.CFrame.RightVector * mv.X
			local up = 0
			if UIS:IsKeyDown(Enum.KeyCode.Space) then up = 1 end
			if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then up = -1 end
			local spd = state.flyAbsOn and state.flyAbsSpeed or (50 * state.flySpd)
			flyVel.Velocity = (dir + Vector3.new(0, up, 0)) * spd
			flyGyro.CFrame = cam.CFrame
		end)
	end)
end

-- 互动（自动按附近 ProximityPrompt）
task.spawn(function()
	while running do
		if state.interactOn then
			safe(function()
				local _, _, root = getChar()
				if root then
					local best, bd
					for _, d in ipairs(Workspace:GetDescendants()) do
						if d:IsA("ProximityPrompt") then
							local part = d.Parent
							if part and part:IsA("BasePart") then
								local dist = (part.Position - root.Position).Magnitude
								-- 用提示自身的可用距离 + 余量，原来固定 20 太死
								local reach = math.max(26, (d.MaxActivationDistance or 10) + 8)
								if dist <= reach and (not bd or dist < bd) then
									best, bd = d, dist
								end
							end
						end
					end
					if best then
						local done = pcall(function() fireProximityPrompt(best) end)
						if not done then
							pcall(function()
								best.HoldDuration = 0
								best:InputHoldBegin()
								task.wait(0.08)
								best:InputHoldEnd()
							end)
						end
					end
				end
			end)
			task.wait(math.max(0.1, state.interactSec))
		else
			task.wait(0.5)
		end
	end
end)

-- 一键破解循环
task.spawn(function()
	while running do
		if state.oneClick then
			safe(hackRun)
			task.wait(5)
		else
			task.wait(1)
		end
	end
end)

-- 彩虹边框
task.spawn(function()
	while running do
		if state.borderOn and state.rainbowOn then
			safe(function()
				border.Color = Color3.fromHSV((tick() % 6) / 6, 1, 1)
			end)
		end
		task.wait(0.05)
	end
end)

-- 边框颜色应用
local function applyBorder()
	safe(function()
		border.Enabled = state.borderOn
		if not state.rainbowOn then
			local c = ColorList[state.colorIndex]
			border.Color = c and c.c or pal.line
		end
	end)
end

-- 时钟
task.spawn(function()
	while running do
		safe(function()
			clock.Text = os.date("%H:%M:%S")
		end)
		task.wait(1)
	end
end)

-- ============================================================
-- 9. 视图切换
-- ============================================================
local function show(id)
	curView = id
	for vid, v in pairs(views) do
		safe(function() v.frame.Visible = (vid == id) end)
	end
	for nid, b in pairs(navButtons) do
		local active = (nid == id)
		safe(function()
			local lit = active and NAV_HIGHLIGHT
			b.btn.BackgroundTransparency = lit and 0 or 1
			b.btn.BackgroundColor3 = pal.soft
			b.label.TextColor3 = lit and pal.accent or pal.text
			b.label.Font = (active and not NAV_HIGHLIGHT) and Enum.Font.GothamBold or Enum.Font.Gotham
		end)
	end
	safe(function() scroller.CanvasPosition = Vector2.zero end)
end

-- ============================================================
-- 10. 各页面
-- ============================================================
-- ---- 主页 ----
do
	makeView("home", "主页")
	local v = views.home

	v.section("功能")
	local g = v.grid()

	-- 启用边框
	local borderCard = card(g, "启用边框", "显示面板边框", state.borderOn, function(on)
		state.borderOn = on
		applyBorder()
	end)

	-- 彩虹边框
	local rainbowCard = card(g, "彩虹边框", "循环渐变色彩", state.rainbowOn, function(on)
		state.rainbowOn = on
		applyBorder()
	end)

	-- 面板按键
	local bindCard = card(g, "面板按键", "启用快捷键", state.bindOn, function(on)
		state.bindOn = on
	end)

	-- 设置按键
	local keyCard = card(g, "设置按键", "当前：" .. state.keyCode, false, nil)
	local listening = false
	local keyBtn = mk("TextButton", {
		Size = UDim2.new(1, -70, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
	}, keyCard)
	keyBtn.MouseButton1Click:Connect(function()
		listening = true
		if keyCard.sub then keyCard.sub.Text = "当前：..." end
	end)

	-- 切换主题（点击切换）
	local themeCard = card(g, "切换主题", state.theme == "dark" and "深色主题" or "白色主题", false, nil)
	local themeBtn = mk("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
	}, themeCard)
	themeBtn.MouseButton1Click:Connect(function()
		state.theme = (state.theme == "dark") and "light" or "dark"
		if themeCard.sub then
			themeCard.sub.Text = state.theme == "dark" and "深色主题" or "白色主题"
		end
		applyPalette()
		show(curView)
		applyBorder()
		safe(function()
			panel.BackgroundColor3 = pal.bg
			nav.BackgroundColor3 = pal.panel
			if navLine then navLine.BackgroundColor3 = pal.line end
			if topbar then topbar.BackgroundColor3 = pal.panel end
			if topbarLine then topbarLine.BackgroundColor3 = pal.line end
		end)
	end)

	-- 按键捕获
	UIS.InputBegan:Connect(function(input, processed)
		if not listening then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		listening = false
		state.keyCode = input.KeyCode.Name
		if keyCard.sub then keyCard.sub.Text = "当前：" .. state.keyCode end
	end)

	-- 开关面板
	UIS.InputBegan:Connect(function(input, processed)
		if processed then return end
		if not state.bindOn then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if input.KeyCode.Name ~= state.keyCode then return end
		panel.Visible = not panel.Visible
	end)

	-- 窗口按钮：− 收成小窗（显示 EX HUD） / □ 放大还原 / × 关闭脚本
	bMin.MouseButton1Click:Connect(function()
		collapsed = not collapsed
		if collapsed then
			zoomed2 = false
			safe(function()
				panel.Size = UDim2.fromOffset(math.min(PANEL_W, 420), 36)
				nav.Visible = false
				scroller.Visible = false
				clock.Visible = false
				brand.Visible = false
				bMin.Text = "+"
				bMax.Text = "□"
			end)
		else
			safe(function()
				brand.Visible = false
				bMin.Text = "−"
			end)
			applyLayout()
		end
	end)

	bMax.MouseButton1Click:Connect(function()
		if collapsed then
			-- 收起状态下点放大：直接展开并最大化
			collapsed = false
			zoomed2 = true
			safe(function()
				brand.Visible = false
				bMin.Text = "−"
				bMax.Text = "▣"
			end)
			zoomed = true
			applyLayout()
			return
		end
		zoomed2 = not zoomed2
		zoomed = zoomed2
		safe(function() bMax.Text = zoomed2 and "▣" or "□" end)
		applyLayout()
	end)

	bClose.MouseButton1Click:Connect(function()
		-- 真正关闭脚本：停所有功能 + 还原破解 + 销毁界面
		running = false
		safe(function() state.fly = false flyStop() end)
		safe(hackRestore)
		safe(function() gui:Destroy() end)
		print(TAG .. " 已关闭")
	end)
end

-- ---- 玩家 ----
do
	makeView("player", "玩家")
	local v = views.player

	v.section("")
	local g1 = v.grid()
	card(g1, "速度修改", "开启移动速度修改", state.speedOn, function(on)
		state.speedOn = on
	end)
	local _, s1 = sliderCard(g1, "速度值", 0.1, 10.0, 0.1, state.speed, function(v2)
		state.speed = v2
	end)

	v.gap(16)
	local g2 = v.grid()
	card(g2, "飞行速度", "独立飞行速度倍率", state.flySpdOn, function(on)
		state.flySpdOn = on
	end)
	local _, s2 = sliderCard(g2, "倍率", 0.1, 15.0, 0.1, state.flySpd, function(v2)
		state.flySpd = v2
	end)

	-- 新增：直接调飞行速度（格/秒）
	card(g2, "绝对飞行速度", "按数值控制，覆盖倍率", state.flyAbsOn, function(on)
		state.flyAbsOn = on
	end)
	local _, s5 = sliderCard(g2, "飞行速度(格/秒)", 10, 400, 5, state.flyAbsSpeed, function(v2)
		state.flyAbsSpeed = v2
	end)

	v.gap(24)
	local g3 = v.grid()
	card(g3, "跳跃修改", "开启跳跃高度修改", state.jumpOn, function(on)
		state.jumpOn = on
	end)
	local _, s3 = sliderCard(g3, "跳跃高度", 0.1, 10.0, 0.1, state.jump, function(v2)
		state.jump = v2
	end)

	card(g3, "无限跳跃", "", state.infJump, function(on)
		state.infJump = on
	end)

	card(g3, "飞行", "", state.fly, function(on)
		state.fly = on
		if on then safe(flyStart) else safe(flyStop) end
	end)

	card(g3, "穿墙", "", state.noclip, function(on)
		state.noclip = on
	end)

	card(g3, "互动", "", state.interactOn, function(on)
		state.interactOn = on
	end)

	local _, s4 = sliderCard(g3, "互动时间(秒)", 0.1, 10.0, 0.1, state.interactSec, function(v2)
		state.interactSec = v2
	end)
end

-- ---- 黑客功能 ----
do
	makeView("hack", "黑客功能")
	local v = views.hack
	v.section("功能")
	local g = v.grid()

	card(g, "一键破解", "一键完成当前破解操作", state.oneClick, function(on)
		state.oneClick = on
		if on then safe(hackRun) else safe(hackRestore) end
	end)
end

-- ---- 占位页 ----
local function placeholderView(id, title)
	makeView(id, title, title)
	local v = views[id]
	v.section("功能")
	local g = v.grid()
	card(g, "暂无功能", "该模块暂未开放", false, nil)
end

placeholderView("car", "车辆")
placeholderView("game", "游戏功能")
placeholderView("setting", "设置")
placeholderView("safe", "安全模式")
-- ---- 反作弊 ----
do
	makeView("anticheat", "反作弊")
	local v = views.anticheat
	v.section("功能")
	local g = v.grid()

	card(g, "绕过反作弊", "开启后自动装防护钩子", Guard.on, function(on)
		if on then safe(Guard.install) else safe(Guard.uninstall) end
	end)

	card(g, "拦截踢出", "阻止客户端被 Kick", Guard.blockKick, function(on)
		Guard.blockKick = on
	end)

	card(g, "限制发包频率", "压掉异常高频 FireServer", Guard.throttle, function(on)
		Guard.throttle = on
		fireMap = {}
	end)

	card(g, "平滑数值变化", "速度等数值渐变，不像外挂", Guard.smooth, function(on)
		Guard.smooth = on
	end)

	card(g, "保护界面", "隐藏菜单不被扫描", Guard.protectGui, function(on)
		Guard.protectGui = on
		if on then
			safe(function()
				if syn and syn.protect_gui then syn.protect_gui(gui) end
			end)
		end
	end)

	card(g, "修补检测模块", "套一层常见反作弊模块", Guard.patchModules, function(on)
		Guard.patchModules = on
	end)

	card(g, "圣奥里强化", "针对该游戏封掉 Anticheat / Ratchet", false, function(on)
		if on then
			local n = safe(Guard.sanLeo)
			if not Guard.quiet then
				print(TAG .. " 圣奥里强化：" .. tostring(n))
			end
		end
	end)

	-- 扫描反作弊模块
	local scanCard
	local scanOutput
	scanCard = card(g, "扫描反作弊模块", "点一下列出检测类模块", false, function(on)
		if not on then return end
		local list = Guard.scan() or {}
		if #list == 0 then
			scanCard.sub.Text = "没找到（名字不匹配）"
		else
			scanCard.sub.Text = string.format("找到 %d 个，见下方", #list)
		end
		if not Guard.quiet then
			print("===== 反作弊模块扫描 =====")
			for i, line in ipairs(list) do
				print(string.format("%2d. %s", i, line))
			end
			if #list == 0 then print("（没找到，可能名字不同或不在客户端）") end
		end
		safe(function()
			scanOutput.Visible = true
			scanOutput.Text = #list == 0
				and "没找到匹配的模块。\n可能名字不含 anticheat/security/ratchet 等关键字。"
				or table.concat(list, "\n")
		end)
	end)

	scanOutput = mk("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = pal.input,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Font = Enum.Font.Code,
		TextSize = 11,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
		Visible = false,
	}, v.body)
	reg(scanOutput, "TextColor3", "sub")
	mk("UIPadding", {
		PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
	}, scanOutput)
	mk("UICorner", { CornerRadius = UDim.new(0, 6) }, scanOutput)

	-- 列出 ReplicatedStorage 全部子项
	card(g, "列出 ReplicatedStorage", "显示全部子项，便于对照命名", false, function(on)
		if not on then return end
		local lines = {}
		safe(function()
			for _, c in ipairs(ReplicatedStorage:GetChildren()) do
				table.insert(lines, string.format("%s  (%s)", c.Name, c.ClassName))
			end
		end)
		table.sort(lines)
		safe(function()
			scanOutput.Visible = true
			scanOutput.Text = #lines == 0
				and "ReplicatedStorage 没有子项"
				or table.concat(lines, "\n")
		end)
		if not Guard.quiet then
			print("===== ReplicatedStorage 子项 (" .. #lines .. ") =====")
			for i, line in ipairs(lines) do
				print(string.format("%2d. %s", i, line))
			end
		end
	end)

	card(g, "低存在感模式", "延迟注入 + 不输出日志", Guard.delayed, function(on)
		Guard.delayed = on
		Guard.quiet = on
	end)

	card(g, "数值限幅", "速度不超过安全线", Guard.clampValues, function(on)
		Guard.clampValues = on
	end)

	card(g, "自动重装钩子", "每 6 秒重扫一次检测模块", Guard.repatch, function(on)
		Guard.repatch = on
		if on then safe(guardRepatchLoop) end
	end)

	card(g, "静默运行", "不在控制台留任何输出", Guard.quiet, function(on)
		Guard.quiet = on
	end)

	local _, speedSlider = sliderCard(g, "速度安全上限", 16, 80, 1, Guard.maxSpeed, function(v)
		Guard.maxSpeed = v
	end)

	v.gap(10)
	v.section("状态")
	local g2 = v.grid()
	local statCard = card(g2, "运行统计", Guard.status(), false, nil)

	task.spawn(function()
		while running do
			safe(function()
				if statCard and statCard.sub then
					statCard.sub.Text = Guard.on
						and (Guard.status() .. " · 已开启")
						or "未开启"
				end
			end)
			task.wait(1)
		end
	end)
end

-- 导航点击
for id, b in pairs(navButtons) do
	b.btn.MouseButton1Click:Connect(function()
		show(id)
	end)
end

-- ============================================================
-- 11.5 屏幕自适应（手机 / 电脑 / 横竖屏切换）
-- ============================================================
function applyLayout()
	local pw, ph, nw = calcSizes()
	PANEL_W, PANEL_H, NAV_W = pw, ph, nw

	-- 计算缩放，并保证缩放后面板不超出屏幕
	local vp = viewport()
	local sc = calcUiScale(vp)
	if pw * sc > vp.X - 12 then sc = (vp.X - 12) / pw end
	if ph * sc > vp.Y - 12 then sc = math.min(sc, (vp.Y - 12) / ph) end
	UI_SCALE = sc

	safe(function()
		panelScale.Scale = sc
		local w, h = pw * sc, ph * sc
		panel.Position = UDim2.new(0.5, -w / 2 + PANEL_OFFSET_X, 0.5, -h / 2 + PANEL_OFFSET_Y)
		panel.Visible = true
	end)

	-- 收起状态：只保留小窗 + 牌子 + 按钮，不重排内部
	if collapsed then
		safe(function()
			panel.Size = UDim2.fromOffset(math.min(pw, 420), 36)
			nav.Visible = false
			scroller.Visible = false
			topbar.Visible = false
			topTitle.Visible = false
			brand.Visible = false
		end)
		return
	end

	safe(function()
		panel.Size = UDim2.fromOffset(pw, ph)
		nav.Visible = true
		nav.Size = UDim2.fromOffset(nw, ph)
	end)
	safe(function()
		scroller.Visible = true
		scroller.Size = UDim2.new(1, -nw, 1, 0)
		scroller.Position = UDim2.fromOffset(nw, 0)
	end)
	safe(function()
		topbar.Visible = true
		topbar.Size = UDim2.new(1, -nw, 0, 30)
		topbar.Position = UDim2.fromOffset(nw, 0)
		clock.Visible = true
		clock.Position = UDim2.new(0.5, -60, 0, 6)
		topTitle.Size = UDim2.fromOffset(math.max(50, nw - 16), 28)
		topTitle.Visible = true
		brand.Visible = false
		bMin.Text = "−"
		bMax.Text = zoomed and "▣" or "□"
		bMin.Position = UDim2.new(1, -78, 0, 2)
		bMax.Position = UDim2.new(1, -46, 0, 2)
		bClose.Position = UDim2.new(1, -14, 0, 2)
	end)

	-- 内容太窄就单列
	local contentW = pw - nw - 32
	local oneCol = contentW < 430
	local cellH = MOBILE and 50 or 54

	for _, item in ipairs(gridList) do
		safe(function()
			item.lay.CellSize = oneCol and UDim2.new(1, 0, 0, cellH) or UDim2.new(0.5, -10, 0, cellH)
			item.lay.FillDirectionMaxCells = oneCol and 1 or 2
		end)
	end

	-- 导航重排：按可用高度压缩每一项，保证不压到底部文字
	local narrow = (nw < 120)
	local itemCount = 0
	for _, it in ipairs(navList) do
		if it.btn then itemCount = itemCount + 1 end
	end
	local bottomReserve = (ph < 360) and 8 or 34
	local avail = ph - 32 - bottomReserve - 8
	local unit = (itemCount > 0) and (avail / itemCount) or 40
	local itemH = math.clamp(unit - 2, 24, 44)
	local divH = math.max(4, math.floor(itemH * 0.3))

	local y = 32
	for _, it in ipairs(navList) do
		if it.divider then
			safe(function()
				it.divider.Position = UDim2.fromOffset(8, y + 2)
				it.divider.Size = UDim2.new(1, -16, 0, 1)
			end)
			y = y + divH
		else
			safe(function()
				it.btn.Size = UDim2.new(1, 0, 0, itemH)
				it.btn.Position = UDim2.fromOffset(0, y)
			end)
			local b = navButtons[it.item.id]
			if b then
				local labelX = narrow and 10 or 14
				safe(function()
					b.label.Position = UDim2.fromOffset(labelX, 0)
					b.label.Size = UDim2.new(1, -(labelX + 8), 1, 0)
					b.label.TextSize = narrow and 12 or (itemH < 30 and 12 or 14)
				end)
			end
			y = y + itemH
		end
	end

	-- 底部版本文字：面板太矮就隐藏，避免压住导航
	safe(function()
		footer.Visible = (ph >= 360)
		footer.Position = UDim2.new(0, 10, 1, -26)
	end)

	-- 拖条尺寸跟着窗口走
	for _, d in ipairs(dragBoxes) do
		safe(function()
			if d.kind == "nav" then
				d.box.Size = UDim2.new(1, 0, 0, 28)
				d.box.Position = UDim2.fromOffset(0, 0)
			else
				local w = math.max(60, pw - nw - 160)
				d.box.Size = UDim2.new(0, w, 0, 26)
				d.box.Position = UDim2.fromOffset(nw + 12, 0)
			end
		end)
	end

	safe(function() clock.TextSize = MOBILE and 11 or 13 end)
end

safe(applyLayout)

-- 屏幕尺寸变化（横竖屏切换 / 窗口缩放）自动重排
safe(function()
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			safe(applyLayout)
		end)
	end
end)

-- ============================================================
-- 12. 启动
-- ============================================================
applyBorder()
show("home")
print(TAG .. " 已加载 · " .. state.keyCode .. " 开关面板")
