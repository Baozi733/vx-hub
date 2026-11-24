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
		accent  = Color3.fromRGB(34, 197, 94),   -- #22c55e
		soft    = Color3.fromRGB(26, 61, 40),    -- accent-soft 近似
		track   = Color3.fromRGB(51, 51, 51),    -- #333
		input   = Color3.fromRGB(34, 34, 34),    -- #222
		knob    = Color3.fromRGB(255, 255, 255),
	},
	light = {
		bg      = Color3.fromRGB(244, 244, 245), -- #f4f4f5
		panel   = Color3.fromRGB(255, 255, 255), -- #ffffff
		line    = Color3.fromRGB(228, 228, 231), -- #e4e4e7
		text    = Color3.fromRGB(24, 24, 27),    -- #18181b
		sub     = Color3.fromRGB(113, 113, 122), -- #71717a
		accent  = Color3.fromRGB(22, 163, 74),   -- #16a34a
		soft    = Color3.fromRGB(220, 240, 228), -- accent-soft 近似
		track   = Color3.fromRGB(212, 212, 216), -- #d4d4d8
		input   = Color3.fromRGB(244, 244, 245), -- #f4f4f5
		knob    = Color3.fromRGB(255, 255, 255),
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
	{ name = "#22C55E", c = Color3.fromRGB(34, 197, 94) },
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

-- 屏幕自适应：手机用百分比，电脑用固定值
local MOBILE = (UIS.TouchEnabled and not UIS.KeyboardEnabled)

local function viewport()
	local cam = Workspace.CurrentCamera
	if cam then return cam.ViewportSize end
	return Vector2.new(1280, 720)
end

local function calcSizes()
	local vp = viewport()
	local pw, ph, nw
	if MOBILE then
		pw = math.clamp(vp.X * 0.94, 300, 640)
		ph = math.clamp(vp.Y * 0.78, 250, 620)
		nw = math.clamp(pw * 0.28, 96, 140)
	else
		pw = math.min(720, vp.X * 0.92)
		ph = math.min(480, vp.Y * 0.86)
		nw = 180
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
	ScrollBarThickness = 4,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
}, panel)
reg(scroller, "ScrollBarImageColor3", "line")

local padding = mk("UIPadding", {
	PaddingTop = UDim.new(0, 16),
	PaddingBottom = UDim.new(0, 16),
	PaddingLeft = UDim.new(0, 16),
	PaddingRight = UDim.new(0, 16),
}, scroller)

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
		Size = UDim2.fromOffset(36, 20),
		Position = UDim2.new(1, -46, 0.5, -10),
		BackgroundColor3 = isOn and pal.accent or pal.track,
		BorderSizePixel = 0,
	}, parent)
	mk("UICorner", { CornerRadius = UDim.new(1, 0) }, track)

	local knob = mk("Frame", {
		Size = UDim2.fromOffset(16, 16),
		Position = UDim2.new(0, isOn and 18 or 2, 0.5, -8),
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
		knob.Position = UDim2.new(0, isOn and 18 or 2, 0.5, -8)
	end)
end

-- 卡片：标题 + 描述 + 开关
local function card(grid, title, desc, isOn, onToggle)
	local cardFrame = mk("Frame", {
		Name = "Key",
		Size = UDim2.new(0.5, -5, 0, 62),
		BackgroundColor3 = pal.panel,
		BorderSizePixel = 0,
	}, grid)
	mk("UICorner", { CornerRadius = UDim.new(0, 8) }, cardFrame)
	local stroke = reg(mk("UIStroke", { Thickness = 1 }, cardFrame), "Color", isOn and "accent" or "line")
	reg(cardFrame, "BackgroundColor3", "panel")

	local lbl = mk("TextLabel", {
		Size = UDim2.new(1, -60, 0, 20),
		Position = UDim2.fromOffset(12, 12),
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
		Size = UDim2.new(0.5, -5, 0, 62),
		BackgroundColor3 = pal.panel,
		BorderSizePixel = 0,
	}, grid)
	mk("UICorner", { CornerRadius = UDim.new(0, 8) }, cardFrame)
	reg(mk("UIStroke", { Thickness = 1 }, cardFrame), "Color", "line")
	reg(cardFrame, "BackgroundColor3", "panel")

	local lbl = mk("TextLabel", {
		Size = UDim2.new(1, -60, 0, 18),
		Position = UDim2.fromOffset(12, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = title,
	}, cardFrame)
	reg(lbl, "TextColor3", "text")

	local valLbl = mk("TextLabel", {
		Size = UDim2.fromOffset(52, 18),
		Position = UDim2.new(1, -64, 0, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = string.format("%.1f", cur),
	}, cardFrame)
	reg(valLbl, "TextColor3", "accent")

	local track = mk("Frame", {
		Size = UDim2.new(1, -24, 0, 4),
		Position = UDim2.new(0, 12, 0, 40),
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
		TextSize = 18,
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
	reg(led, "BackgroundColor3", "accent")
	local stTxt = mk("TextLabel", {
		Size = UDim2.new(1, -14, 1, 0),
		Position = UDim2.fromOffset(14, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "运行中",
	}, statusWrap)
	reg(stTxt, "TextColor3", "sub")

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
			CellSize = UDim2.new(0.5, -5, 0, 62),
			CellPadding = UDim2.fromOffset(10, 10),
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

	-- 窗口按钮（最小化 / 最大化 / 关闭）
	local function winBtn(posX, kind)
		local b = mk("TextButton", {
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.new(1, posX, 0, 0),
			BackgroundColor3 = pal.panel,
			BorderSizePixel = 0,
			Text = kind == "min" and "-" or (kind == "max" and "□" or "×"),
			Font = Enum.Font.Gotham,
			TextSize = 15,
		}, header)
		mk("UICorner", { CornerRadius = UDim.new(0, 4) }, b)
		reg(mk("UIStroke", { Thickness = 1 }, b), "Color", "line")
		reg(b, "BackgroundColor3", "panel")
		reg(b, "TextColor3", "text")
		return b
	end

	local bMin = winBtn(-96, "min")
	local bMax = winBtn(-64, "max")
	local bClose = winBtn(-32, "close")

	views[id] = { frame = view, body = body, section = section, grid = grid, gap = gap, title = title, placeholder = placeholder }

	return bMin, bMax, bClose
end

-- ============================================================
-- 6. 导航
-- ============================================================
local NAV_ITEMS = {
	{ id = "home",   label = "主页",     icon = "⌂" },
	{ id = "player", label = "玩家",     icon = "人" },
	{ id = "car",    label = "车辆",     icon = "车", placeholder = "车辆" },
	{ id = "game",   label = "游戏功能", icon = "戏", placeholder = "游戏功能" },
	{ id = "hack",   label = "黑客功能", icon = ">" },
	{ divider = true },
	{ id = "setting",label = "设置",     icon = "设", placeholder = "设置" },
	{ id = "safe",   label = "安全模式", icon = "安", placeholder = "安全模式" },
	{ id = "anticheat", label = "反作弊", icon = "反", placeholder = "反作弊" },
}

local navY = 12
for _, item in ipairs(NAV_ITEMS) do
	if item.divider then
		mk("Frame", {
			Size = UDim2.new(1, -24, 0, 1),
			Position = UDim2.fromOffset(12, navY + 4),
			BackgroundColor3 = pal.line,
			BorderSizePixel = 0,
		}, nav)
		navY = navY + 17
	else
		local btn = mk("TextButton", {
			Size = UDim2.new(1, 0, 0, 40),
			Position = UDim2.fromOffset(0, navY),
			BackgroundTransparency = 1,
			Text = "",
		}, nav)

		local iconBox = mk("Frame", {
			Size = UDim2.fromOffset(20, 20),
			Position = UDim2.fromOffset(16, 10),
			BackgroundTransparency = 1,
		}, btn)
		local icon = mk("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			Text = item.icon,
		}, iconBox)

		local label = mk("TextLabel", {
			Size = UDim2.new(1, -52, 1, 0),
			Position = UDim2.fromOffset(46, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = item.label,
		}, btn)

		reg(icon, "TextColor3", "text")
		reg(label, "TextColor3", "text")

		navButtons[item.id] = { btn = btn, label = label, icon = icon, item = item }
		navY = navY + 40
	end
end

-- 侧栏底部
local footer = mk("TextLabel", {
	Size = UDim2.new(1, -32, 0, 16),
	Position = UDim2.new(0, 16, 1, -28),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "v1.0.0 · 已连接",
}, nav)
reg(footer, "TextColor3", "sub")

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
	while true do
		safe(function()
			local _, hum = getChar()
			if hum then
				if state.speedOn then
					hum.WalkSpeed = 16 * state.speed
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
	while true do
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
			flyVel.Velocity = (dir + Vector3.new(0, up, 0)) * (50 * state.flySpd)
			flyGyro.CFrame = cam.CFrame
		end)
	end)
end

-- 互动（自动按附近 ProximityPrompt）
task.spawn(function()
	while true do
		if state.interactOn then
			safe(function()
				local _, _, root = getChar()
				if root then
					local best, bd
					for _, d in ipairs(Workspace:GetDescendants()) do
						if d:IsA("ProximityPrompt") and d.Enabled then
							local part = d.Parent
							if part and part:IsA("BasePart") then
								local dist = (part.Position - root.Position).Magnitude
								if dist <= 20 and (not bd or dist < bd) then
									best, bd = d, dist
								end
							end
						end
					end
					if best then fireProximityPrompt(best) end
				end
			end)
			task.wait(math.max(0.5, state.interactSec))
		else
			task.wait(0.5)
		end
	end
end)

-- 一键破解循环
task.spawn(function()
	while true do
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
	while true do
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
	while true do
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
			b.btn.BackgroundTransparency = active and 0 or 1
			b.btn.BackgroundColor3 = active and pal.soft or pal.panel
			b.label.TextColor3 = active and pal.accent or pal.text
			b.icon.TextColor3 = active and pal.accent or pal.text
		end)
	end
	safe(function() scroller.CanvasPosition = Vector2.zero end)
end

-- ============================================================
-- 10. 各页面
-- ============================================================
-- ---- 主页 ----
do
	local bMin, bMax, bClose = makeView("home", "主页")
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

	-- 边框颜色（点击循环）
	local colorCard = card(g, "边框颜色", ColorList[state.colorIndex].name, false, nil)
	local cardBtn = mk("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
	}, colorCard)
	cardBtn.MouseButton1Click:Connect(function()
		state.colorIndex = state.colorIndex % #ColorList + 1
		local c = ColorList[state.colorIndex]
		if colorCard.sub then colorCard.sub.Text = c.name end
		state.rainbowOn = false
		rainbowCard.set(false)
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

	-- 窗口按钮
	bMin.MouseButton1Click:Connect(function()
		local collapsed = panel.Size.Y.Offset <= 60
		panel.Size = UDim2.fromOffset(PANEL_W, collapsed and PANEL_H or 44)
		nav.Visible = not collapsed
		scroller.Visible = not collapsed
	end)
	bMax.MouseButton1Click:Connect(function()
		local big = panel.Size.X.Offset > 760
		panel.Size = UDim2.fromOffset(big and PANEL_W or 960, big and PANEL_H or 620)
	end)
	bClose.MouseButton1Click:Connect(function()
		safe(function() gui:Destroy() end)
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
placeholderView("anticheat", "反作弊")

-- 导航点击
for id, b in pairs(navButtons) do
	b.btn.MouseButton1Click:Connect(function()
		show(id)
	end)
end

-- ============================================================
-- 11. 面板拖动
-- ============================================================
do
	local dragging, dragStart, startPos = false, nil, nil
	-- 只占顶部 10px，避免盖住第一个导航项
	local handle = mk("TextButton", {
		Size = UDim2.new(1, 0, 0, 10),
		Position = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 10,
	}, panel)

	handle.InputBegan:Connect(function(input)
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
			panel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + dx,
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

-- ============================================================
-- 11.5 屏幕自适应（手机 / 电脑 / 横竖屏切换）
-- ============================================================
local function applyLayout()
	local pw, ph, nw = calcSizes()
	PANEL_W, PANEL_H, NAV_W = pw, ph, nw

	safe(function()
		panel.Size = UDim2.fromOffset(pw, ph)
		panel.Position = UDim2.new(0.5, -pw / 2, 0.5, -ph / 2)
	end)
	safe(function() nav.Size = UDim2.fromOffset(nw, ph) end)
	safe(function()
		scroller.Size = UDim2.new(1, -nw, 1, 0)
		scroller.Position = UDim2.fromOffset(nw, 0)
	end)

	-- 内容太窄就改单列
	local contentW = pw - nw - 32
	local oneCol = contentW < 430
	local cellH = MOBILE and 58 or 62

	for _, item in ipairs(gridList) do
		safe(function()
			item.lay.CellSize = oneCol and UDim2.new(1, 0, 0, cellH) or UDim2.new(0.5, -5, 0, cellH)
			item.lay.FillDirectionMaxCells = oneCol and 1 or 2
		end)
	end

	-- 导航字号：窄的时候缩一点
	for _, b in pairs(navButtons) do
		safe(function()
			b.label.TextSize = (nw < 130) and 12 or 14
			b.icon.TextSize = (nw < 130) and 12 or 14
			b.label.Position = UDim2.fromOffset((nw < 130) and 40 or 46, 0)
			b.label.Size = UDim2.new(1, -((nw < 130) and 46 or 52), 1, 0)
			b.icon.Parent.Position = UDim2.fromOffset((nw < 130) and 12 or 16, 10)
		end)
	end

	clock.TextSize = MOBILE and 11 or 13
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