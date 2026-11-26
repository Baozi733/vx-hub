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
-- 1. 主题色板
-- ============================================================
local Themes = {
	dark = {
		bg      = Color3.fromRGB(6, 6, 8),       -- 接近纯黑
		panel   = Color3.fromRGB(22, 22, 25),    -- 卡片底色
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
	-- 纯白主题：白底黑字
	white = {
		bg      = Color3.fromRGB(255, 255, 255),
		panel   = Color3.fromRGB(255, 255, 255),
		line    = Color3.fromRGB(224, 224, 228),
		text    = Color3.fromRGB(0, 0, 0),
		sub     = Color3.fromRGB(88, 88, 96),
		accent  = Color3.fromRGB(10, 10, 10),
		soft    = Color3.fromRGB(238, 238, 240),
		track   = Color3.fromRGB(200, 200, 206),
		input   = Color3.fromRGB(245, 245, 247),
		knob    = Color3.fromRGB(255, 255, 255),
		ok      = Color3.fromRGB(22, 163, 74),
	},
}

local state = {
	theme       = "dark",
	-- 主页
	borderOn    = true,
	rainbowOn   = false,
	bindOn      = true,
	keyCode     = "Insert",
	-- 玩家
	speedOn     = true,
	speed       = 1.0,
	flySpeedValue = 100,   -- 飞行速度（格/秒），直接生效
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

local THEME_ORDER = { "dark", "white" }

local function nextThemeName(cur)
	for i, name in ipairs(THEME_ORDER) do
		if name == cur then
			return THEME_ORDER[i % #THEME_ORDER + 1]
		end
	end
	return "dark"
end

local THEME_LABEL = {
	dark = "深色主题",
	white = "纯白主题",
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
-- 2. 边框颜色（固定白色）
-- ============================================================

-- ============================================================
-- 3. 界面骨架
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
	pc     = { w = 750, h = 500, nav = 92 },
	tablet = { w = 700, h = 470, nav = 86 },
	phone  = { w = 700, h = 470, nav = 84 },
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


local running = true      -- 关闭脚本时置 false，所有循环退出
local started = false     -- 欢迎窗点「打开脚本」后置 true
local zoomed = false      -- □ 放大状态（启动后设为 true = 全屏）
local FLOAT_ICON = "rbxassetid://109221032399431"   -- EX HUD logo
local customSize = false  -- 用户手动拖过大小后，applyLayout 不再覆盖
local applyLayout          -- 前向声明：窗口按钮要用
local selectClose          -- 前向声明：切页时要关掉下拉
zoomed = false   -- 初始不放大（点开脚本后会设为 true）

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
		-- 手机 / 平板：直接按屏幕百分比算出「整数像素」，不再缩放
		-- （用小数 UIScale 会让文字发虚，这里改成整像素布局）
		local fracW, fracH = 0.88, 0.80
		if cls == "tablet" then fracW, fracH = 0.76, 0.74 end
		if vp.Y > vp.X then fracW, fracH = fracW + 0.06, fracH + 0.04 end
		pw = math.floor(vp.X * fracW)
		ph = math.floor(vp.Y * fracH)
		pw = math.max(280, pw)
		ph = math.max(220, ph)
		nw = math.floor(math.clamp(pw * 0.085, 80, 120))
	else
		pw = math.min(preset.w, maxW)
		ph = math.min(preset.h, maxH)
		nw = preset.nav
		if pw - nw < 260 then
			nw = math.clamp(pw * 0.22, 78, preset.nav)
		end
	end

	-- 放大状态：真正铺满全屏（不留边距）
	if zoomed then
		pw = vp.X
		ph = vp.Y
	end

	return math.floor(pw), math.floor(ph), math.floor(nw)
end

local PANEL_W, PANEL_H, NAV_W = calcSizes()

local gridList = {}     -- 所有卡片网格（缩放手柄与布局都会用）
local panel = mk("Frame", {
	Name = "Main",
	Size = UDim2.fromOffset(PANEL_W, PANEL_H),
	Position = UDim2.new(0.5, -PANEL_W / 2, 0.5, -PANEL_H / 2),
	BackgroundColor3 = pal.bg,
	BackgroundTransparency = 1,   -- 底色交给 screenBg，避免盖住黑边框
	BorderSizePixel = 0,
	ClipsDescendants = true,    -- 内容按面板圆角裁切
	Active = true,
}, gui)

mk("UICorner", { CornerRadius = UDim.new(0, 22) }, panel)   -- 屏幕圆角

-- 外圈黑边（模拟 iPad 的机身边框）
local frameBezel = mk("Frame", {
	Name = "FrameBezel",
	Size = UDim2.fromOffset(PANEL_W + 24, PANEL_H + 24),
	Position = UDim2.new(0.5, -(PANEL_W + 24) / 2, 0.5, -(PANEL_H + 24) / 2),
	BackgroundColor3 = Color3.fromRGB(8, 8, 10),
	BorderSizePixel = 0,
	ZIndex = 0,
}, gui)
mk("UICorner", { CornerRadius = UDim.new(0, 34) }, frameBezel)
frameBezel.Visible = false   -- 欢迎窗阶段先隐藏，点「打开脚本」后才出现

-- 屏幕底色（在黑边框之上、所有内容之下）
local screenBg = mk("Frame", {
	Name = "ScreenBg",
	Size = UDim2.fromScale(1, 1),
	Position = UDim2.fromOffset(0, 0),
	BackgroundColor3 = pal.bg,
	BorderSizePixel = 0,
	ZIndex = 1,
}, panel)
mk("UICorner", { CornerRadius = UDim.new(0, 22) }, screenBg)
reg(screenBg, "BackgroundColor3", "bg")   -- 22 + 12 = 34，正好贴合

-- 机身外沿不加描边（避免圆弧线露出来）
reg(panel, "BackgroundColor3", "bg")   -- 面板背景也要跟着主题变
local panelScale = mk("UIScale", { Scale = 1 }, panel)

-- 底部小白条（iPad 风格 Home Indicator）
local homeBar = mk("Frame", {
	Name = "HomeBar",
	Size = UDim2.fromOffset(130, 4),
	Position = UDim2.new(0.5, 0, 1, -10),
	AnchorPoint = Vector2.new(0.5, 1),
	BackgroundColor3 = Color3.fromRGB(250, 250, 252),
	BackgroundTransparency = 0.25,
	BorderSizePixel = 0,
	ZIndex = 46,
}, panel)
mk("UICorner", { CornerRadius = UDim.new(1, 0) }, homeBar)


-- ============================================================
-- 启动欢迎窗：点「打开脚本」才显示主面板
-- ============================================================
local splash = mk("Frame", {
	Name = "Splash",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
	ZIndex = 120,
}, gui)

local box = mk("Frame", {
	Name = "SplashBox",
	Size = UDim2.fromOffset(460, 160),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),        -- 纯黑
	BorderSizePixel = 0,
	ZIndex = 121,
}, splash)
mk("UICorner", { CornerRadius = UDim.new(0, 12) }, box)
local boxStroke = mk("UIStroke", { Thickness = 1 }, box)
boxStroke.Color = Color3.fromRGB(58, 58, 66)

mk("ImageLabel", {
	Size = UDim2.fromOffset(26, 26),
	Position = UDim2.fromOffset(18, 16),
	BackgroundTransparency = 1,
	Image = FLOAT_ICON,
	ScaleType = Enum.ScaleType.Fit,
	ZIndex = 122,
}, box)

mk("TextLabel", {
	Size = UDim2.fromOffset(220, 26),
	Position = UDim2.fromOffset(54, 16),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "EX HUD",
	TextColor3 = Color3.fromRGB(245, 245, 250),
	ZIndex = 122,
}, box)

mk("TextLabel", {
	Size = UDim2.new(1, -36, 0, 20),
	Position = UDim2.fromOffset(18, 60),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "欢迎使用 EX HUD",
	TextColor3 = Color3.fromRGB(235, 235, 242),
	ZIndex = 122,
}, box)

mk("TextLabel", {
	Size = UDim2.new(1, -36, 0, 20),
	Position = UDim2.fromOffset(18, 84),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "尊贵的 " .. LP.Name .. " 用户",
	TextColor3 = Color3.fromRGB(200, 204, 214),
	ZIndex = 122,
}, box)

local openBtn = mk("TextButton", {
	Size = UDim2.fromOffset(118, 38),
	Position = UDim2.new(1, -136, 1, -54),
	BackgroundColor3 = Color3.fromRGB(59, 91, 254),
	BorderSizePixel = 0,
	Text = "打开脚本",
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	ZIndex = 122,
}, box)
mk("UICorner", { CornerRadius = UDim.new(0, 6) }, openBtn)

openBtn.MouseButton1Click:Connect(function()
	started = true
	zoomed = false         -- 启动按预设尺寸（不铺满）
	safe(function() splash:Destroy() end)
	safe(function()
		panel.Visible = started
		applyLayout()
	end)
end)

-- 启动时先隐藏主面板
safe(function() panel.Visible = false end)
-- ============================================================
-- 缩放手柄：右下角 / 左下角拖动即可自由改面板大小
--   双击手柄 = 恢复默认尺寸
-- ============================================================
local function makeGrip(side)
	local isRight = (side == "br")
	local grip = mk("TextButton", {
		Name = "Grip_" .. side,
		Size = UDim2.fromOffset(20, 20),
		Position = isRight and UDim2.new(1, -28, 1, -28) or UDim2.new(0, 8, 1, -28),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 40,
	}, panel)

	-- 视觉提示：两条 45° 短线
	for i = 1, 2 do
		local line = mk("Frame", {
			Size = UDim2.fromOffset(9 - (i - 1) * 4, 2),
			Position = isRight
				and UDim2.new(1, -13 + (i - 1) * 4, 1, -4 - (i - 1) * 5)
				or UDim2.fromOffset(4 + (i - 1) * 4, 0),
			BackgroundColor3 = pal.sub,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Rotation = -45,
			ZIndex = 40,
		}, grip)
		reg(line, "BackgroundColor3", "sub")
	end

	local dragging = false
	local startSize, startPos, startMouse = nil, nil, nil

	grip.InputBegan:Connect(function(input)
		local hit = input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		if not hit then return end
		dragging = true
		startMouse = input.Position
		startSize = panel.AbsoluteSize
		startPos = panel.Position
	end)

	UIS.InputChanged:Connect(function(input)
		if not dragging then return end
		local isMove = input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		if not isMove then return end

		local dx = input.Position.X - startMouse.X
		local dy = input.Position.Y - startMouse.Y
		local vp = viewport()
		local minW, minH = 360, 240
		local maxW = math.max(minW, vp.X - 16)
		local maxH = math.max(minH, vp.Y - 16)

		local newW, newH
		if isRight then
			newW = math.clamp(startSize.X + dx, minW, maxW)
			newH = math.clamp(startSize.Y + dy, minH, maxH)
			panel.Size = UDim2.fromOffset(newW, newH)
		else
			newW = math.clamp(startSize.X - dx, minW, maxW)
			newH = math.clamp(startSize.Y + dy, minH, maxH)
			panel.Size = UDim2.fromOffset(newW, newH)
			panel.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + (startSize.X - newW),
				startPos.Y.Scale, startPos.Y.Offset)
		end

		PANEL_W, PANEL_H = newW, newH
		customSize = true

		-- 关键：整块面板按新尺寸重排，侧栏 / 内容 / 卡片一起缩
		safe(function() applyLayout(newW, newH, true) end)
	end)

	UIS.InputEnded:Connect(function(input)
		local up = input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		if up then dragging = false end
	end)

	return grip
end

-- 只保留右下角把手（左下角已去掉）
makeGrip("br")

-- ============================================================
-- 边缘拖拽缩放：拖动面板的右 / 下 / 左边缘即可改大小
-- ============================================================
local function bindEdge(kind)
	local box = mk("TextButton", {
		Name = "Edge_" .. kind,
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 41,
	}, panel)

	if kind == "right" then
		box.Size = UDim2.new(0, 8, 1, -40)
		box.Position = UDim2.new(1, -8, 0, 30)
	elseif kind == "left" then
		box.Size = UDim2.new(0, 8, 1, -40)
		box.Position = UDim2.new(0, 0, 0, 30)
	elseif kind == "bottom" then
		box.Size = UDim2.new(1, -40, 0, 8)
		box.Position = UDim2.new(0, 0, 1, -8)
	end

	local dragging, startSize, startPos, startMouse = false, nil, nil, nil

	box.InputBegan:Connect(function(input)
		local hit = input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		if not hit then return end
		dragging = true
		startMouse = input.Position
		startSize = panel.AbsoluteSize
		startPos = panel.Position
	end)

	UIS.InputChanged:Connect(function(input)
		if not dragging then return end
		local isMove = input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		if not isMove then return end

		local dx = input.Position.X - startMouse.X
		local dy = input.Position.Y - startMouse.Y
		local vp = viewport()
		local minW, minH = 360, 240

		local newW, newH = startSize.X, startSize.Y
		local newX, newY = startPos.X.Offset, startPos.Y.Offset

		if kind == "right" then
			newW = math.clamp(startSize.X + dx, minW, math.max(minW, vp.X))
		elseif kind == "bottom" then
			newH = math.clamp(startSize.Y + dy, minH, math.max(minH, vp.Y))
		elseif kind == "left" then
			newW = math.clamp(startSize.X - dx, minW, math.max(minW, vp.X))
			newX = startPos.X.Offset + (startSize.X - newW)
		end

		panel.Size = UDim2.fromOffset(newW, newH)
		panel.Position = UDim2.new(0, newX, 0, newY)

		PANEL_W, PANEL_H = newW, newH
		customSize = true
		safe(function() applyLayout(newW, newH, true) end)
	end)

	UIS.InputEnded:Connect(function(input)
		local up = input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		if up then dragging = false end
	end)
end

bindEdge("right")
bindEdge("bottom")
bindEdge("left")
local border = reg(mk("UIStroke", { Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel), "Color", "line")
border.Transparency = 0.35

-- 侧栏
local nav = mk("Frame", {
	Name = "Nav",
	Size = UDim2.fromOffset(NAV_W, PANEL_H),
	BackgroundColor3 = pal.bg,
	BorderSizePixel = 0,
	ZIndex = 2,
	ClipsDescendants = true,   -- 不让内部元素溢出到顶栏
}, panel)
reg(nav, "BackgroundColor3", "bg")
mk("UICorner", { CornerRadius = UDim.new(0, 22) }, nav)   -- 与面板同半径，盖住方角

-- 搜索框（导航上方）
local navSearch = mk("TextBox", {
	Name = "NavSearch",
	Size = UDim2.new(1, -16, 0, 26),
	Position = UDim2.fromOffset(8, 32),
	BackgroundColor3 = pal.soft,
	BackgroundTransparency = 0.35,
	BorderSizePixel = 0,
	Font = Enum.Font.Gotham,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	PlaceholderText = "搜索功能…",
	PlaceholderColor3 = Color3.fromRGB(140, 140, 150),
	Text = "",
	ClearTextOnFocus = false,
	ZIndex = 3,
}, nav)
mk("UICorner", { CornerRadius = UDim.new(0, 6) }, navSearch)
mk("UIPadding", { PaddingLeft = UDim.new(0, 8) }, navSearch)
reg(navSearch, "BackgroundColor3", "soft")

-- 全站搜索索引：{ page = "combat", title = "杀戮光环" }
local SEARCH_INDEX = {}
local currentViewId = nil

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
	ZIndex = 2,
	ScrollBarThickness = 3,
	VerticalScrollBarInset = Enum.ScrollBarInset.None,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
}, panel)
reg(scroller, "ScrollBarImageColor3", "line")

mk("UIPadding", {
	PaddingTop = UDim.new(0, 42),
	PaddingBottom = UDim.new(0, 34),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 16),
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

			-- 自由拖动：不限制位置
			panel.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + dx,
				startPos.Y.Scale, startPos.Y.Offset + dy)
			-- 黑边框跟着走
			safe(function()
				if frameBezel then
					local px, py = panel.Position.X, panel.Position.Y
					frameBezel.Position = UDim2.new(px.Scale, px.Offset - 12, py.Scale, py.Offset - 12)
				end
			end)
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
local function card(grid, title, desc, isOn, onToggle, asButton)
	if currentViewId and title then
		table.insert(SEARCH_INDEX, { page = currentViewId, title = title })
	end
	local cardFrame = mk("Frame", {
		Name = "Key",
		Size = UDim2.new(0.5, -6, 0, 46),
		BackgroundColor3 = pal.panel,
		BorderSizePixel = 0,
	}, grid)
	mk("UICorner", { CornerRadius = UDim.new(0, 8) }, cardFrame)
	reg(mk("UIStroke", { Thickness = 1 }, cardFrame), "Color", "line")   -- 描边固定，不随开关变化
	reg(cardFrame, "BackgroundColor3", "panel")

	local lbl = mk("TextLabel", {
		Size = UDim2.new(1, -(CARD_PAD_RIGHT + SWITCH_W + 22), 0, 16),
		Position = UDim2.fromOffset(10, 6),
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

	local track, knob
	if not asButton then
		track, knob = switchOnOff(cardFrame, isOn)
		reg(track, "BackgroundColor3", isOn and "accent" or "track")
	end

	local active = isOn
	local btn = mk("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
	}, cardFrame)

	btn.MouseButton1Click:Connect(function()
		if asButton then
			-- 按钮模式：点击即执行（无开关、无反馈）
			if onToggle then safe(onToggle) end
			return
		end
		active = not active
		setSwitch(track, knob, active)
		-- 描边保持原色，不再变成白色高亮
		if onToggle then safe(onToggle, active) end
	end)

	return cardFrame, {
		set = function(v)
			active = v
			if track and knob then setSwitch(track, knob, v) end
		end,
		get = function() return active end,
		sub = sub,
	}
end

-- 卡片：标题 + 滑块（对应 HTML 的 range + number）
local function sliderCard(grid, title, minVal, maxVal, step, cur, onChanged)
	if currentViewId and title then
		table.insert(SEARCH_INDEX, { page = currentViewId, title = title })
	end
	local cardFrame = mk("Frame", {
		Name = "Slider",
		Size = UDim2.new(0.5, -6, 0, 46),
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
		Position = UDim2.new(0, 10, 0, 32),
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
	currentViewId = id
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
		mk("Frame", {
			Size = UDim2.new(1, 0, 0, 8),
			BackgroundTransparency = 1,
		}, body)
		return s
	end

	local function grid(h)
		local rowH = h or 46
		local g = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, body)
		-- 网格容器自己再留 14px 右边距（保证卡片轮廓一定露出来）
		mk("UIPadding", { PaddingRight = UDim.new(0, 25) }, g)

		local lay = mk("UIGridLayout", {
			CellSize = UDim2.new(0.5, -4, 0, rowH),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			FillDirectionMaxCells = 2,
		}, g)
		table.insert(gridList, { lay = lay, frame = g, h = rowH })
		return g
	end

	local function gap(h)
		mk("Frame", {
			Size = UDim2.new(1, 0, 0, h or 16),
			BackgroundTransparency = 1,
		}, body)
	end

	-- 页面底部预留 14px，保证最后一张卡片不贴底部边框
	mk(Frame, {
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		LayoutOrder = 9999,
	}, body)

	views[id] = { frame = view, body = body, section = section, grid = grid, gap = gap, title = title, placeholder = placeholder }
end

-- ============================================================
-- 6. 导航
-- ============================================================
local NAV_ITEMS = {
	{ id = "home",      label = "首页",     icon = "⌂" },
	{ id = "main",      label = "主要",     icon = "主", placeholder = "主要" },
	{ id = "combat",    label = "战斗",     icon = "战", placeholder = "战斗" },
	{ id = "aimbot",    label = "自瞄",     icon = "瞄", placeholder = "自瞄" },
	{ id = "fugitive",  label = "逃犯",     icon = "逃", placeholder = "逃犯" },
	{ id = "esp",       label = "透视",     icon = "透", placeholder = "透视" },
	{ id = "tp",        label = "传送",     icon = "传", placeholder = "传送" },
	{ id = "shop",      label = "商店",     icon = "商", placeholder = "商店" },
	{ id = "player",    label = "玩家",     icon = "人" },
	{ id = "car",       label = "车辆",     icon = "车", placeholder = "车辆" },
	{ id = "game",      label = "游戏功能", icon = "戏", placeholder = "游戏功能" },
	{ id = "hack",      label = "黑客功能", icon = ">" },
	{ divider = true },
	{ id = "anticheat", label = "反作弊",   icon = "反" },
	{ id = "safe",      label = "安全模式", icon = "安", placeholder = "安全模式" },
	{ id = "setting",   label = "设置",     icon = "设", placeholder = "设置" },
}

-- 导航滚动容器（项多时可上下滑动）
local navScroll = mk("ScrollingFrame", {
	Name = "NavScroll",
	Size = UDim2.new(1, 0, 1, -60),
	Position = UDim2.fromOffset(0, 28),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = pal.line,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ZIndex = 2,
}, nav)

navScroll.Position = UDim2.fromOffset(0, 66)
navScroll.Size = UDim2.new(1, 0, 1, -98)

local navY = 6
local navList = {}   -- 记录导航项，applyLayout 里统一重排
for _, item in ipairs(NAV_ITEMS) do
	if item.divider then
		local dv = mk("Frame", {
			Size = UDim2.new(1, -24, 0, 1),
			Position = UDim2.fromOffset(8, navY + 4),
			BackgroundColor3 = pal.line,
			BorderSizePixel = 0,
		}, navScroll)
		table.insert(navList, { divider = dv })
		navY = navY + 17
	else
		local btn = mk("TextButton", {
			Size = UDim2.new(1, 0, 0, 40),
			Position = UDim2.fromOffset(0, navY),
			BackgroundTransparency = 1,
			Text = "",
		}, navScroll)

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
-- 6.1 窗口按钮
--     − 收成小窗（显示 EX HUD）  □ 放大/还原  × 关闭脚本
-- ============================================================
local collapsed = false

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

local bMin   = winBtn(-90, "min")
local bMax   = winBtn(-58, "max")
local bClose = winBtn(-26, "close")

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
	BackgroundColor3 = pal.bg,
	BorderSizePixel = 0,
	ZIndex = 25,
}, panel)
reg(topbar, "BackgroundColor3", "bg")
mk("UICorner", { CornerRadius = UDim.new(0, 22) }, topbar)   -- 与面板同半径

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
	Size = UDim2.fromOffset(math.max(60, NAV_W - 12), 28),
	Position = UDim2.fromOffset(12, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "EX HUD",
	ZIndex = 26,
}, panel)
reg(topTitle, "TextColor3", "accent")

-- 顶栏右侧：运行状态（全局一份，位于按钮左边）
local runLed = mk("Frame", {
	Name = "RunLed",
	Size = UDim2.fromOffset(8, 8),
	Position = UDim2.new(1, -152, 0, 11),
	BackgroundColor3 = pal.accent,
	BorderSizePixel = 0,
	ZIndex = 27,
}, topbar)
mk("UICorner", { CornerRadius = UDim.new(1, 0) }, runLed)
reg(runLed, "BackgroundColor3", "ok")

local runTxt = mk("TextLabel", {
	Name = "RunTxt",
	Size = UDim2.fromOffset(60, 20),
	Position = UDim2.new(1, -140, 0, 5),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "运行中",
	ZIndex = 27,
}, topbar)
reg(runTxt, "TextColor3", "ok")

-- 时钟放到顶栏左侧（紧贴侧栏右边）
safe(function()
	clock.Parent = topbar
	clock.Size = UDim2.fromOffset(86, 18)
	clock.Position = UDim2.fromOffset(12, 6)
	clock.TextSize = 12
	clock.TextXAlignment = Enum.TextXAlignment.Left
	clock.ZIndex = 30
end)

-- 三个按钮挂到顶栏
safe(function()
	bMin.Parent = topbar
	bMax.Parent = topbar
	bClose.Parent = topbar
	bMin.Position = UDim2.new(1, -90, 0, 2)
	bMax.Position = UDim2.new(1, -58, 0, 2)
	bClose.Position = UDim2.new(1, -26, 0, 2)
	bMin.ZIndex = 27
	bMax.ZIndex = 27
	bClose.ZIndex = 27
end)

-- ============================================================
-- 收起后的悬浮图标（点一下恢复面板）
--   FLOAT_ICON 填 Roblox 图片 ID，例：local FLOAT_ICON = "rbxassetid://1234567890"
--   留空则显示「EX」兜底徽标
-- ============================================================
local floatBtn = mk("TextButton", {
	Name = "FloatIcon",
	Size = UDim2.fromScale(1, 1),
	Position = UDim2.fromOffset(0, 0),
	BackgroundTransparency = 1,
	Text = "",
	Visible = false,
	ZIndex = 60,
}, panel)

mk("ImageLabel", {
	Name = "FloatImg",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ScaleType = Enum.ScaleType.Fit,
	Image = FLOAT_ICON,
	Visible = (FLOAT_ICON ~= ""),
	ZIndex = 61,
}, floatBtn)

mk("TextLabel", {
	Name = "FloatTxt",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextSize = 20,
	Text = "EX",
	TextColor3 = Color3.fromRGB(240, 240, 245),
	Visible = (FLOAT_ICON == ""),
	ZIndex = 61,
}, floatBtn)

-- 收起：面板缩成 56x56 只显示图标
local function setFloating(on)
	collapsed = on
	safe(function()
		if on then
			safe(selectClose)
			panel.Size = UDim2.fromOffset(56, 56)
			nav.Visible = false
			scroller.Visible = false
			if topbar then topbar.Visible = false end
			if topTitle then topTitle.Visible = false end
			clock.Visible = false
			if runLed then runLed.Visible = false end
			if runTxt then runTxt.Visible = false end
			brand.Visible = false
			bMin.Visible = false
			bMax.Visible = false
			bClose.Visible = false
			floatBtn.Visible = true
			if homeBar then homeBar.Visible = false end
			if frameBezel then frameBezel.Visible = false end
			border.Enabled = state.borderOn
		else
			floatBtn.Visible = false
			if homeBar then homeBar.Visible = true end
			if frameBezel then frameBezel.Visible = started end
			bMin.Visible = true
			bMax.Visible = true
			bClose.Visible = true
			if runLed then runLed.Visible = true end
			if runTxt then runTxt.Visible = true end
			customSize = false
			applyLayout()
		end
	end)
end

-- 点图标 → 恢复面板
floatBtn.MouseButton1Click:Connect(function()
	if collapsed then setFloating(false) end
end)

-- 图标也能拖动
do
	local dragging, startMouse, startPos = false, nil, nil
	floatBtn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			startMouse = input.Position
			startPos = panel.Position
		end
	end)
	UIS.InputChanged:Connect(function(input)
		if not dragging or not collapsed then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			panel.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + (input.Position.X - startMouse.X),
				startPos.Y.Scale, startPos.Y.Offset + (input.Position.Y - startMouse.Y))
		end
	end)
	UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end


-- 侧栏底部
local footer = mk("TextLabel", {
	Size = UDim2.fromOffset(120, 18),
	Position = UDim2.fromOffset(74, 6),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "v1.0.0 · 已连接",
	ZIndex = 30,
}, nav)
reg(footer, "TextColor3", "sub")

-- ============================================================
-- 6.5 反作弊绕过（客户端侧）
--   ① 拦截 Kick        ② 限制发包频率    ③ 平滑数值变化
--   ④ 保护界面不被扫描  ⑤ 修补常见检测模块
--   全部 pcall 包裹，取不到能力就自动跳过，不会报错
-- ============================================================
-- ============================================================
-- 6.7 反作弊对抗（AntiCheatBypass）
--   目标客户端存在：
--     ReplicatedStorage.AntiCheat
--     ReplicatedStorage.Modules.Ratchet / Sha256 / Algorithms
--     Remote.PlayerEvent / Remote.PlayerFunc
-- ============================================================
local AntiCheatBypass = {
	config = {
		patchAntiCheat = true,
		patchRatchet = true,
		hookNamecall = true,
		hookIndex = true,
		selfGuard = true,
	},

	BLOCKED_EVENTS = {
		["combatMode"] = true,
		["takeDamage"] = true,
		["report"] = true,
		["reportPlayer"] = true,
		["antiCheat"] = true,
		["suspicious"] = true,
		["screenshot"] = true,
	},
	BLOCKED_FUNCS = {
		["getPlayerInfo"] = true,
		["checkPlayer"] = true,
		["getCharacter"] = true,
		["verify"] = true,
		["audit"] = true,
	},
}

local AB = AntiCheatBypass
local O = {}          -- 保存原始函数，供 uninstall 还原
local errors = {}
local installed = false

local function need(name, fn)
	if fn == nil then
		table.insert(errors, "缺少执行器函数：" .. name)
		return false
	end
	return true
end

local function findModule(name)
	local mods = ReplicatedStorage:FindFirstChild("Modules")
	local m = mods and mods:FindFirstChild(name)
	if m then
		local ok, res = pcall(require, m)
		if ok then return res end
	end
	return nil
end

-- ---------- ① 递归 patch AntiCheat 表 ----------
function AB.patchAntiCheatTable()
	local hits = 0
	local function walk(t, depth)
		if depth > 6 or type(t) ~= "table" then return end
		for k, v in pairs(t) do
			if type(v) == "function" then
				t[k] = function(...)
					local ok, res = pcall(v, ...)
					if not ok then return true end
					return res
				end
				hits = hits + 1
			elseif type(v) == "table" and k ~= "__index" then
				walk(v, depth + 1)
			end
		end
	end

	local root = ReplicatedStorage:FindFirstChild("AntiCheat")
	if root then
		local ok, t = pcall(require, root)
		if ok and type(t) == "table" then walk(t, 1) end
	end
	return hits
end

-- ---------- ② patch Ratchet ----------
function AB.patchRatchet()
	local ratchet = findModule("Ratchet")
	local sha = findModule("Sha256")
	if type(ratchet) ~= "table" then return 0 end
	if type(sha) ~= "function" then return 0 end

	local mt = getrawmetatable and getrawmetatable(ratchet) or getmetatable(ratchet)
	if type(mt) ~= "table" then return 0 end
	if mt.__patched then return 0 end

	local oldIndex = mt.__index
	if type(oldIndex) == "table" then
		O.ratchetAdvance = oldIndex.advance
		oldIndex.catchUp = function(self, target)
			local n = 0
			while (self.index or 0) < (target or 0) and n < 5000 do
				self.index = (self.index or 0) + 1
				n = n + 1
			end
			return true
		end
		oldIndex.respond = function(self, challenge)
			local ok, res = pcall(sha, "resp|" .. tostring(self.state) .. "|" .. tostring(self.index) .. "|" .. tostring(challenge))
			if ok then return res end
			return "ok"
		end
		mt.__patched = true
		return 1
	elseif type(oldIndex) == "function" then
		O.ratchetIndex = oldIndex
		local proxy = setmetatable({}, {
			__index = function(_, k)
				if k == "catchUp" then
					return function(self, target)
						local n = 0
						while (self.index or 0) < (target or 0) and n < 5000 do
							self.index = (self.index or 0) + 1
							n = n + 1
						end
						return true
					end
				end
				if k == "respond" then
					return function(self, challenge)
						local ok, res = pcall(sha, "resp|" .. tostring(self.state) .. "|" .. tostring(self.index) .. "|" .. tostring(challenge))
						if ok then return res end
						return "ok"
					end
				end
				return oldIndex(ratchet, k)
			end,
		})
		mt.__index = function(self, k) return proxy[k] end
		mt.__patched = true
		return 1
	end
	return 0
end

-- ---------- ③ hook __namecall ----------
function AB.hookNamecall()
	if not need("hookmetamethod", hookmetamethod) then return 0 end
	if not need("getnamecallmethod", getnamecallmethod) then return 0 end

	local hookFn = function(self, ...)
		local packed = table.pack(...)
		local method = getnamecallmethod()

		if method == "Kick" and self == LP then
			return nil
		end

		if method == "FireServer" and type(self) == "userdata" then
			local nm = self.Name
			local first = packed[1]
			if nm == "PlayerEvent" and type(first) == "string" and AB.BLOCKED_EVENTS[first] then
				return nil
			end
		end

		if method == "InvokeServer" and type(self) == "userdata" then
			local first = packed[1]
			if self.Name == "PlayerFunc" and type(first) == "string" and AB.BLOCKED_FUNCS[first] then
				return true
			end
		end

		if O.namecall then
			return O.namecall(self, table.unpack(packed, 1, packed.n))
		end
		return self[method](self, table.unpack(packed, 1, packed.n))
	end

	-- 有 newcclosure 就包一层，避免被检测为裸 Lua 闭包
	if type(newcclosure) == "function" then
		local ok, wrapped = pcall(newcclosure, hookFn)
		if ok then hookFn = wrapped end
	end

	O.namecall = hookmetamethod(game, "__namecall", hookFn)
	return 1
end

-- ---------- ④ hook __index（屏蔽 sniff 服务） ----------
function AB.hookIndex()
	if not need("hookmetamethod", hookmetamethod) then return 0 end
	local hide = { InsertService = true, Selection = true, Stats = true }
	O.index = hookmetamethod(game, "__index", function(self, k)
		if hide[k] then return nil end
		if O.index then return O.index(self, k) end
		return rawget(self, k)
	end)
	return 1
end

-- ---------- ⑥ 自身保护 ----------
function AB.selfGuard()
	if not need("clonefunction", clonefunction) then return 0 end
	O.request = http and http.request or nil
	O.traceback = debug.traceback
	O.info = debug.info
	O.pcall = pcall
	O.getfenv = getfenv
	O.tostring = tostring

	local snap = {}
	local function clone(name, fn)
		if type(fn) ~= "function" then return end
		local ok, c = pcall(clonefunction, fn)
		if ok then snap[name] = c end
	end
	clone("request", O.request)
	clone("traceback", O.traceback)
	clone("info", O.info)
	clone("pcall", O.pcall)
	clone("getfenv", O.getfenv)
	clone("tostring", O.tostring)

	local baseDepth = 0
	local okTb, tb = pcall(function() return debug.traceback("", 2) end)
	if okTb and type(tb) == "string" then
		for _ in string.gmatch(tb, "\n") do baseDepth = baseDepth + 1 end
	end
	O.baseDepth = baseDepth
	O.snapshot = snap

	-- 检查关键函数是否被替换成 Lua 闭包
	if iscclosure then
		for name, fn in pairs({ traceback = debug.traceback, pcall = pcall }) do
			if type(fn) == "function" and iscclosure(fn) then
				table.insert(errors, name .. " 已被替换为 Lua 闭包")
			end
		end
	end
	return 1
end

-- ---------- init / uninstall ----------
function AB.init()
	if installed or (_G.__EXHUD_ACB and _G.__EXHUD_ACB.installed) then
		return { ok = true, errors = errors, skipped = true }
	end
	errors = {}

	-- 顺序硬约束：先克隆原函数 → 再装 hook → 再 patch table
	local steps = {
		{ "selfGuard", AB.selfGuard },
		{ "hookNamecall", AB.hookNamecall },
		{ "hookIndex", AB.hookIndex },
		{ "ratchet", AB.patchRatchet },
		{ "antiCheatTable", AB.patchAntiCheatTable },
	}
	for _, st in ipairs(steps) do
		local ok, res = pcall(st[2])
		if not ok then
			table.insert(errors, st[1] .. " 失败：" .. tostring(res))
		end
	end

	installed = true
	_G.__EXHUD_ACB = { installed = true }
	return { ok = #errors == 0, errors = errors }
end

function AB.uninstall()
	safe(function()
		if O.namecall and hookmetamethod then
			hookmetamethod(game, "__namecall", O.namecall)
			O.namecall = nil
		end
		if O.index and hookmetamethod then
			hookmetamethod(game, "__index", O.index)
			O.index = nil
		end
	end)
	installed = false
	_G.__EXHUD_ACB = nil
	return true
end

function AB.status()
	if installed then
		return string.format("已启用 · 失败 %d 步", #errors)
	end
	return "未启用"
end

-- ============================================================
-- Guard：只保留 UI 需要的开关与扫描（旧绕过逻辑已删除）
-- ============================================================
local Guard = {
	quiet = true,
	on = false,
}

function Guard.status()
	return AB.status()
end

function Guard.install()
	return AB.init()
end

-- ============================================================
-- 自测断言（模板要求，控制台可验证）
-- ============================================================
do
	local function check(name, cond)
		if cond then
			print("[EX HUD] 自测通过：" .. name)
		else
			print("[EX HUD] 自测失败：" .. name)
		end
	end
	safe(function()
		check("模块字段完整", type(AB.init) == "function"
			and type(AB.uninstall) == "function" and type(AB.config) == "table")
		check("拦截表已定义", type(AB.BLOCKED_EVENTS) == "table"
			and AB.BLOCKED_EVENTS["combatMode"] == true
			and type(AB.BLOCKED_FUNCS) == "table")
		check("五个能力都在", type(AB.patchAntiCheatTable) == "function"
			and type(AB.patchRatchet) == "function"
			and type(AB.hookNamecall) == "function"
			and type(AB.hookIndex) == "function"
			and type(AB.selfGuard) == "function")
	end)
end

-- ============================================================
-- 6.8 主要功能
--   所有实现都用 pcall 包着，游戏里找不到对应模块就自动跳过
-- ============================================================
local Main = {
	stamina = false, hunger = false, combatBlock = false, noRagdoll = false,
	itemGuard = false, noFall = false, antiPull = false,
	vaultWatch = false, antiFling = false, autoMoney = false,
	infAmmo = false, rapidFire = false,
}

-- 取 Framework.Core（体力/饥饿在这个模块里）
local function coreModule()
	local mod = nil
	safe(function()
		local ps = LP:FindFirstChild("PlayerScripts")
		local fw = ps and ps:FindFirstChild("Framework")
		local core = fw and fw:FindFirstChild("Core")
		if core then mod = require(core) end
	end)
	return mod
end

-- 无限体力 / 无限饥饿
task.spawn(function()
	while running do
		if Main.stamina or Main.hunger then
			local core = coreModule()
			if core then
				if Main.stamina then pcall(function() core.stamina = 100 end) end
				if Main.hunger then pcall(function() core.food = 100 end) end
			end
		end
		task.wait(0.3)
	end
end)

-- 无限子弹
task.spawn(function()
	while running do
		if Main.infAmmo then
			safe(function()
				local ch = LP.Character
				local cfg = ch and ch:FindFirstChild("Config")
				if cfg then
					local a = cfg:FindFirstChild("Ammo")
					local t = cfg:FindFirstChild("TotalAmmo")
					if a then a.Value = 9999 end
					if t then t.Value = 9999 end
				end
			end)
		end
		task.wait(0.4)
	end
end)

-- 自动捡钱（自动触发附近的拾取提示）
task.spawn(function()
	while running do
		if Main.autoMoney then
			safe(function()
				local _, _, root = getChar()
				if root then
					for _, rec in ipairs(promptCache) do
						local d, part = rec.prompt, rec.part
						if d.Parent and part.Parent
							and (part.Position - root.Position).Magnitude < 60 then
							local blob = string.lower(tostring(d.Name) .. " " .. tostring(d.ActionText))
							if string.find(blob, "cash") or string.find(blob, "money")
								or string.find(blob, "pick") or string.find(blob, "collect") then
								fireProximityPrompt(d)
							end
						end
					end
				end
			end)
			task.wait(0.8)
		else
			task.wait(1)
		end
	end
end)

-- 按搜索词过滤导航项（同时匹配页面里的卡片名）
local function pageMatches(pageId, query)
	for _, rec in ipairs(SEARCH_INDEX) do
		if rec.page == pageId then
			if string.find(string.lower(rec.title), query, 1, true) then return true end
		end
	end
	return false
end

local function relayoutNav()
	local raw = navSearch.Text or ""
	local query = string.lower(raw)
	local y = 6
	local visibleCount = 0
	for _, rec in ipairs(navList) do
		local show = true
		if query ~= "" then
			if rec.divider then
				show = false
			else
				local lbl = string.lower(rec.item and rec.item.label or "")
				show = string.find(lbl, query, 1, true) ~= nil
					or pageMatches(rec.item and rec.item.id, query)
			end
		end
		if rec.divider then
			rec.divider.Visible = show
			if show then
				rec.divider.Position = UDim2.fromOffset(8, y + 4)
				y = y + 14
			end
		else
			rec.btn.Visible = show
			if show then
				visibleCount = visibleCount + 1
				rec.btn.Position = UDim2.fromOffset(0, y)
				y = y + (rec.btn.Size.Y.Offset > 0 and rec.btn.Size.Y.Offset or 34)
			end
		end
	end
	navScroll.CanvasSize = UDim2.new(0, 0, 0, y + 20)
	-- 只剩一个结果时自动跳过去
	if query ~= "" and visibleCount == 1 then
		safe(function()
			for _, rec in ipairs(navList) do
				if rec.btn and rec.btn.Visible and rec.item then
					show(rec.item.id)
					break
				end
			end
		end)
	end
end

navSearch:GetPropertyChangedSignal("Text"):Connect(function()
	safe(relayoutNav)
end)

-- 防甩飞（每帧把水平速度压回 0）
task.spawn(function()
	while running do
		if Main.antiFling then
			safe(function()
				local _, _, root = getChar()
				if root then
					local v = root.AssemblyLinearVelocity
					if math.abs(v.X) > 60 or math.abs(v.Z) > 60 then
						root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
					end
				end
			end)
		end
		task.wait(0.15)
	end
end)

-- 金库刷新提示
local seenVaults = {}
task.spawn(function()
	while running do
		if Main.vaultWatch then
			safe(function()
				for _, d in ipairs(Workspace:GetChildren()) do
					if not seenVaults[d] then
						local n = string.lower(tostring(d.Name))
						if string.find(n, "vault") or string.find(n, "金库")
							or string.find(n, "safe") or string.find(n, "robbery") then
							seenVaults[d] = true
							if not Guard.quiet then
								print(TAG .. " 金库刷新：" .. d:GetFullName())
							end
						end
					end
				end
			end)
			task.wait(6)
		else
			task.wait(2)
		end
	end
end)

-- 防监狱拉回 / 防布娃娃：改写游戏模块
local charPivotBackup, ragdollBackup = nil, nil

local function applyMainPatches()
	-- 防监狱拉回
	safe(function()
		local rs = ReplicatedStorage:FindFirstChild("Modules")
		local alg = rs and rs:FindFirstChild("Algorithms")
		if alg then
			local mod = require(alg)
			if type(mod) == "table" and type(mod.charPivotTo) == "function" then
				if Main.antiPull then
					if not charPivotBackup then charPivotBackup = mod.charPivotTo end
					mod.charPivotTo = function() return nil end
				elseif charPivotBackup then
					mod.charPivotTo = charPivotBackup
					charPivotBackup = nil
				end
			end
		end
	end)

	-- 防布娃娃
	safe(function()
		local rs = ReplicatedStorage:FindFirstChild("Modules")
		local rag = rs and rs:FindFirstChild("Ragdoll")
		if rag then
			local mod = require(rag)
			if type(mod) == "table" and type(mod.activate) == "function" then
				if Main.noRagdoll then
					if not ragdollBackup then ragdollBackup = mod.activate end
					mod.activate = function() return nil end
				elseif ragdollBackup then
					mod.activate = ragdollBackup
					ragdollBackup = nil
				end
			end
		end
	end)
end

-- 战斗拦截 / 防摔伤（需要执行器钩子，没有就跳过）
local combatHooked = false
local function applyCombatHooks()
	if combatHooked then return end
	safe(function()
		if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then return end
		local old
		old = hookmetamethod(game, "__namecall", function(self, ...)
			local args = table.pack(...)
			local method = getnamecallmethod()
			if method == "FireServer" then
				local first = args[1]
				if Main.combatBlock and first == "combatMode" then return nil end
				if Main.noFall and first == "takeDamage" then return nil end
			end
			return old(self, table.unpack(args, 1, args.n))
		end)
		combatHooked = true
	end)
end

-- 防物品减少：把库存里的扣减函数包一层（找不到就跳过）
local itemBackup = nil
local function applyItemGuard()
	safe(function()
		local ps = LP:FindFirstChild("PlayerScripts")
		local fw = ps and ps:FindFirstChild("Framework")
		local chMod = fw and fw:FindFirstChild("Character")
		if not chMod then return end
		local mod = require(chMod)
		local inv = type(mod) == "table" and mod.Inventory
		if type(inv) ~= "table" then return end
		if Main.itemGuard then
			if not itemBackup then
				itemBackup = {}
				for k, v in pairs(inv) do
					if type(k) == "string" and type(v) == "function" then
						local kn = string.lower(k)
						if string.find(kn, "decrease") or string.find(kn, "remove")
							or string.find(kn, "consume") or string.find(kn, "use") then
							itemBackup[k] = v
							inv[k] = function() return true end
						end
					end
				end
			end
		elseif itemBackup then
			for k, v in pairs(itemBackup) do pcall(function() inv[k] = v end) end
			itemBackup = nil
		end
	end)
end

-- 快速射击（getgc 扫射速字段，需要执行器）
task.spawn(function()
	while running do
		if Main.rapidFire and getgc then
			safe(function()
				for _, v in pairs(getgc(true)) do
					if type(v) == "table" then
						if rawget(v, "SHOOT_MODE") ~= nil then rawset(v, "SHOOT_MODE", 2) end
						if rawget(v, "RPM") ~= nil then rawset(v, "RPM", 3000) end
					end
				end
			end)
		end
		task.wait(1)
	end
end)

-- 显示聊天框
local function setChat(on)
	safe(function()
		game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Chat, on)
	end)
end

-- ============================================================
-- 6.9 扩展功能
-- ============================================================
-- 事件助手：统一往游戏主 Remote 发消息
local function mainRemote(kind)
	local names = kind == "event"
		and { "PlayerEvent", "MainEvent", "GameEvent" }
		or { "PlayerFunc", "MainFunction", "GameFunc" }
	for _, n in ipairs(names) do
		local r = ReplicatedStorage:FindFirstChild(n)
		if r and (r:IsA("RemoteEvent") or r:IsA("RemoteFunction")) then return r end
	end
	local ev = ReplicatedStorage:FindFirstChild("Events")
	if ev then
		for _, n in ipairs(names) do
			local r = ev:FindFirstChild(n)
			if r then return r end
		end
	end
	return nil
end

function fireEvent(name, ...)
	local args = table.pack(...)
	safe(function()
		local re = mainRemote("event")
		if re and re:IsA("RemoteEvent") then
			re:FireServer(name, table.unpack(args, 1, args.n))
		end
	end)
end

function invokeFunc(name, ...)
	local args = table.pack(...)
	local res = nil
	safe(function()
		local rf = mainRemote("func")
		if rf and rf:IsA("RemoteFunction") then
			res = rf:InvokeServer(name, table.unpack(args, 1, args.n))
		end
	end)
	return res
end

local Ext = {
	-- 战斗
	aura = false, auraPolice = false, auraCivil = false, auraCombat = false,
	auraRange = 60, auraMulti = false, auraDelay = 0.12, auraDamage = 3,
	bulletAim = false, npcAim = false, showFov = false, fovRange = 300,
	fovDist = 400, fovThick = 2, bulletPart = "Head",
	-- 逃犯
	evade = false, evadeRange = 120, evadeTpRange = 60,
	tpPlace = "警察局",
	-- 警察
	cuff = false, cuffTp = false, globalTp = false, arrest = false, policeCombat = false,
	-- 透视
	espOn = false, espName = true, espDist = true, espHp = true,
	espBone = false,
	espTeams = {},
	-- 传送
	tpTarget = nil, tpDir = "前面", tpDist = 5, tpLoop = false, watching = false, orbit = false,
	-- 商店
	shopSel = {}, weaponSel = {},
}

-- 队伍名单（圣奥里职业）
local TEAM_KEYS = {
	{ key = "Fugitive",  label = "逃犯" },
	{ key = "Chef",      label = "厨师" },
	{ key = "Civilian",  label = "平民" },
	{ key = "Delivery",  label = "配送员" },
	{ key = "Farmer",    label = "农民" },
	{ key = "Fire",      label = "消防员" },
	{ key = "Police",    label = "警察" },
	{ key = "Medical",   label = "医护人员" },
	{ key = "Prisoner",  label = "囚犯" },
	{ key = "RoadService", label = "道路服务" },
	{ key = "Transit",   label = "交通" },
}
for _, t in ipairs(TEAM_KEYS) do Ext.espTeams[t.label] = true end

-- 黑市物品 & 武器
local SHOP_ITEMS = { "解密电路", "撬锁装置", "入侵工具", "C4", "USB", "涂鸦" }
local WEAPONS = { "MP5", "M4A1" }

-- ---------- 工具 ----------
local function isPolice(p)
	return p.Team and p.Team.Name == "Police"
end

local function isCivilian(p)
	return p.Team and p.Team.Name == "Civilian"
end

local function inCombat(p)
	return p:GetAttribute("CombatMode") == true or p:GetAttribute("Pursuit") == true
end

local function rootOf(p)
	local ch = p.Character
	if not ch then return nil end
	return ch:FindFirstChild("HumanoidRootPart")
end

local function myRoot()
	local ch = LP.Character
	return ch and ch:FindFirstChild("HumanoidRootPart")
end

-- 朝目标发送伤害（圣奥里用 PlayerEvent:damage）
local function hitPlayer(target, partName, factor)
	local myR = myRoot()
	local tR = rootOf(target)
	if not myR or not tR then return end
	local part = target.Character and target.Character:FindFirstChild(partName or "Head")
	if not part then return end
	fireEvent("damage", {
		bodyParts = { { partName or "Head", 1 } },
		shotCode = { myR.Position, (part.Position - myR.Position).Unit },
		pos = part.Position,
		target = target,
		damageFactor = factor or 1,
		bulletProofTool = false,
	})
end

-- 找出范围内符合条件的玩家
local function candidates(range, onlyPolice, onlyCivil, combatOnly)
	local myR = myRoot()
	local list = {}
	if not myR then return list end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LP and p.Character then
			local hum = p.Character:FindFirstChildOfClass("Humanoid")
			local r = rootOf(p)
			if hum and hum.Health > 0 and r then
				local dist = (r.Position - myR.Position).Magnitude
				local okTeam = true
				if onlyPolice then okTeam = isPolice(p) end
				if onlyCivil then okTeam = isCivilian(p) end
				if combatOnly and not inCombat(p) then okTeam = false end
				if okTeam and dist <= range then
					table.insert(list, { p = p, d = dist, r = r })
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.d < b.d end)
	return list
end

-- ---------- 杀戮光环 ----------
local auraClock = 0
task.spawn(function()
	while running do
		if Ext.aura then
			local t = os.clock()
			if t - auraClock >= Ext.auraDelay then
				auraClock = t
				safe(function()
					local list = candidates(Ext.auraRange, Ext.auraPolice, Ext.auraCivil, Ext.auraCombat)
					if Ext.auraMulti then
						for _, c in ipairs(list) do hitPlayer(c.p, Ext.bulletPart, Ext.auraDamage) end
					elseif list[1] then
						hitPlayer(list[1].p, Ext.bulletPart, Ext.auraDamage)
					end
				end)
			end
		end
		task.wait(Ext.aura and 0.03 or 0.5)
	end
end)

-- ---------- FOV 圈 ----------
local fovCircle = nil
safe(function()
	if Drawing and Drawing.new then
		fovCircle = Drawing.new("Circle")
		fovCircle.Filled = false
		fovCircle.NumSides = 64
		fovCircle.Visible = false
	end
end)

task.spawn(function()
	while running do
		safe(function()
			local cam = Workspace.CurrentCamera
			if fovCircle and cam then
				fovCircle.Position = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
				fovCircle.Radius = Ext.fovRange
				fovCircle.Thickness = Ext.fovThick
				fovCircle.Color = Color3.fromRGB(240, 240, 245)
				fovCircle.Visible = Ext.showFov and (Ext.aura or Ext.bulletAim)
			end
		end)
		task.wait(0.1)
	end
end)

-- ---------- 子弹追敌（改写 Workspace.Raycast） ----------
local raycastBackup = nil
local function applyBulletAim()
	safe(function()
		if Ext.bulletAim or Ext.npcAim then
			if raycastBackup == nil and type(hookfunction) == "function" then
				raycastBackup = Workspace.Raycast
				hookfunction(Workspace.Raycast, function(self, origin, direction, params)
					local myR = myRoot()
					if myR and origin and direction then
						local best, bestD = nil, Ext.fovDist
						for _, p in ipairs(Players:GetPlayers()) do
							if p ~= LP and p.Character then
								local r = rootOf(p)
								if r then
									local d = (r.Position - origin).Magnitude
									if d <= bestD then best, bestD = r, d end
								end
							end
						end
						if best then
							direction = (best.Position - origin).Unit * direction.Magnitude
						end
					end
					return raycastBackup(self, origin, direction, params)
				end)
			end
		else
			if raycastBackup and type(hookfunction) == "function" then
				hookfunction(Workspace.Raycast, raycastBackup)
				raycastBackup = nil
			end
		end
	end)
end

-- ---------- 逃犯：躲避警察 ----------
task.spawn(function()
	while running do
		if Ext.evade then
			safe(function()
				local myR = myRoot()
				if myR then
					for _, p in ipairs(Players:GetPlayers()) do
						if p ~= LP and isPolice(p) then
							local r = rootOf(p)
							if r and (r.Position - myR.Position).Magnitude <= Ext.evadeRange then
								local dir = (myR.Position - r.Position).Unit
								local target = myR.Position + dir * Ext.evadeTpRange + Vector3.new(0, 3, 0)
								pcall(function() myR.CFrame = CFrame.new(target) end)
								break
							end
						end
					end
				end
			end)
			task.wait(0.6)
		else
			task.wait(1)
		end
	end
end)

-- ---------- 警察功能 ----------
task.spawn(function()
	while running do
		if Ext.cuff or Ext.arrest or Ext.globalTp then
			safe(function()
				local myR = myRoot()
				if myR then
					local list = candidates(300, false, true, Ext.policeCombat)
					for _, c in ipairs(list) do
						if Ext.cuff then invokeFunc("handcuff", c.p, false) end
						if Ext.arrest then invokeFunc("arrest", c.p) end
						if Ext.globalTp and (c.p:GetAttribute("WantedLevel") or 0) > 0 then
							if Ext.cuffTp or Ext.globalTp then
								pcall(function()
									myR.CFrame = CFrame.new(c.r.Position + Vector3.new(0, 0, 3))
								end)
							end
						end
					end
				end
			end)
			task.wait(0.8)
		else
			task.wait(1)
		end
	end
end)

-- ---------- 透视 ----------
local espCache = {}

local function clearEsp()
	for _, rec in pairs(espCache) do
		pcall(function() if rec.bill then rec.bill:Destroy() end end)
		pcall(function() if rec.box then rec.box:Remove() end end)
		pcall(function() if rec.bone then for _, l in ipairs(rec.bone) do l:Remove() end end end)
	end
	espCache = {}
end

local function teamOk(p)
	local name = p.Team and p.Team.Name
	if not name then return true end
	for _, t in ipairs(TEAM_KEYS) do
		if t.key == name then return Ext.espTeams[t.label] ~= false end
	end
	return true
end

local function buildEsp(p)
	-- 远距离时 p.Character 可能为空（被 streaming 剔除），用 Characters 文件夹兜底
	local ch = p.Character
	if not ch then
		local folder = Workspace:FindFirstChild("Characters")
		ch = folder and folder:FindFirstChild(p.Name)
	end
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	if not r then return end
	local bill = mk("BillboardGui", {
		Name = "EXESP",
		AlwaysOnTop = true,
		Enabled = true,
		MaxDistance = 1e6,
		Size = UDim2.fromOffset(150, 40),
		StudsOffset = Vector3.new(0, 3.2, 0),
		Adornee = r,
	}, LP:FindFirstChild("PlayerGui") or ch)
	local lbl = mk("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextStrokeTransparency = 0.3,
		TextColor3 = Color3.fromRGB(235, 235, 240),
	}, bill)

	-- 骨骼线不在这里创建：由刷新循环按需创建（勾选后立刻生效）
	espCache[p] = { bill = bill, lbl = lbl }
end

task.spawn(function()
	while running do
		if Ext.espOn then
			safe(function()
				local myR = myRoot()
				local charsFolder = Workspace:FindFirstChild("Characters")
				for _, p in ipairs(Players:GetPlayers()) do
					if p ~= LP and teamOk(p) then
						if not espCache[p] then buildEsp(p) end
						local rec = espCache[p]
						if rec then
							local ch = p.Character or (charsFolder and charsFolder:FindFirstChild(p.Name))
							local r = ch and ch:FindFirstChild("HumanoidRootPart")
							local hum = ch and ch:FindFirstChildOfClass("Humanoid")
							if rec.bill and r then
								rec.bill.Adornee = r
								local parts = {}
								if Ext.espName then table.insert(parts, p.Name) end
								if Ext.espHp and hum then
									table.insert(parts, "HP " .. math.floor(hum.Health))
								end
								if Ext.espDist and myR and r then
									table.insert(parts, math.floor((r.Position - myR.Position).Magnitude) .. "m")
								end
								local txt = table.concat(parts, "  ")
								if rec.lastText ~= txt then
									rec.lbl.Text = txt
									rec.lastText = txt
								end
								rec.bill.Enabled = true
							end
							-- 骨骼：勾选时立即创建，取消时立即销毁
							if Ext.espBone and Drawing and Drawing.new and not rec.bone then
								local lines = {}
								for i = 1, 12 do
									local ln = Drawing.new("Line")
									ln.Thickness = 1
									ln.Color = Color3.fromRGB(235, 235, 240)
									ln.Transparency = 0.85
									ln.Visible = false
									lines[i] = ln
								end
								rec.bone = lines
							end
							if rec.bone and Ext.espBone then
								local cam = Workspace.CurrentCamera
								local joints = {
									"Head", "UpperTorso", "LowerTorso",
									"LeftUpperArm", "LeftLowerArm", "LeftHand",
									"RightUpperArm", "RightLowerArm", "RightHand",
									"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
									"RightUpperLeg", "RightLowerLeg", "RightFoot",
								}
								local pos = {}
								for _, jn in ipairs(joints) do
									local jp = ch and ch:FindFirstChild(jn)
									local scr = jp and cam and cam:WorldToViewportPoint(jp.Position)
									pos[jn] = scr and Vector2.new(scr.X, scr.Y) or nil
								end
								local pairsList = {
									{ "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
									{ "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" },
									{ "LeftLowerArm", "LeftHand" },
									{ "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" },
									{ "RightLowerArm", "RightHand" },
									{ "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" },
									{ "LeftLowerLeg", "LeftFoot" },
									{ "LowerTorso", "RightUpperLeg" },
								}
								for idx, pr in ipairs(pairsList) do
									local ln = rec.bone[idx]
									local a, b = pos[pr[1]], pos[pr[2]]
									if ln and a and b then
										ln.From = a
										ln.To = b
										ln.Visible = true
									elseif ln then
										ln.Visible = false
									end
								end
							elseif rec.bone then
								for _, ln in ipairs(rec.bone) do ln:Remove() end
								rec.bone = nil
							end

						end
					end
				end
				-- 清理失效的
				for p, rec in pairs(espCache) do
					local c2 = p.Character or (charsFolder and charsFolder:FindFirstChild(p.Name))
					if not c2 or not c2:FindFirstChild("HumanoidRootPart") then
						pcall(function() if rec.bill then rec.bill:Destroy() end end)
						espCache[p] = nil
					end
				end
			end)
			task.wait(0.4)
		else
			if next(espCache) then safe(clearEsp) end
			task.wait(0.8)
		end
	end
end)

-- ---------- 传送 ----------
local function dirOffset(p, dirName, dist)
	local dir = p.CFrame.LookVector
	if dirName == "后面" then dir = -dir
	elseif dirName == "左边" then dir = -p.CFrame.RightVector
	elseif dirName == "右边" then dir = p.CFrame.RightVector end
	return p.Position + dir * dist + Vector3.new(0, 3, 0)
end

local function teleportNearTarget()
	local myR = myRoot()
	if not myR or not Ext.tpTarget then return end
	local tr = rootOf(Ext.tpTarget)
	if not tr then return end
	local pos = dirOffset(tr, Ext.tpDir, Ext.tpDist)
	pcall(function() myR.CFrame = CFrame.new(pos) end)
end

task.spawn(function()
	local orbitA = 0
	while running do
		if Ext.tpLoop then safe(teleportNearTarget) end
		if Ext.orbit and Ext.tpTarget then
			safe(function()
				local myR = myRoot()
				local tr = rootOf(Ext.tpTarget)
				if myR and tr then
					orbitA = orbitA + 0.08
					local off = Vector3.new(math.cos(orbitA), 0, math.sin(orbitA)) * Ext.tpDist
					pcall(function() myR.CFrame = CFrame.new(tr.Position + off + Vector3.new(0, 3, 0)) end)
				end
			end)
		end
		if Ext.watching and Ext.tpTarget then
			safe(function()
				local cam = Workspace.CurrentCamera
				local tr = rootOf(Ext.tpTarget)
				if cam and tr then
					cam.CFrame = CFrame.new(tr.Position + Vector3.new(0, 8, 12), tr.Position)
				end
			end)
		end
		task.wait((Ext.tpLoop or Ext.orbit or Ext.watching) and 0.1 or 0.5)
	end
end)

-- 传送到地点（按名字找地图里的部件）
local function teleportToPlace(keyword)
	safe(function()
		local myR = myRoot()
		if not myR then return end
		local count = 0
		for _, d in ipairs(Workspace:GetDescendants()) do
			count = count + 1
			if count > 6000 then return end     -- 最多看 6000 个对象，防止卡住
			if d:IsA("BasePart") and string.find(string.lower(d.Name), string.lower(keyword)) then
				pcall(function() myR.CFrame = CFrame.new(d.Position + Vector3.new(0, 3, 0)) end)
				return
			end
		end
	end)
end

-- ---------- 商店 ----------
local function buyItem(name)
	safe(function()
		invokeFunc("buyItem", name)
		invokeFunc("purchase", name)
		invokeFunc("shopBuy", name)
	end)
end

local function equipWeapon(name)
	safe(function()
		invokeFunc("equipWeapon", name)
		invokeFunc("buyWeapon", name)
	end)
end

-- ---------- 选择器（单选/多选弹窗） ----------
local pickerOpen = nil

local function closePicker()
	if pickerOpen then
		pcall(function() pickerOpen:Destroy() end)
		pickerOpen = nil
	end
end

local function openPicker(title, options, multi, getSel, onChange)
	closePicker()
	local back = mk("TextButton", {
		Name = "PickerBack",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.5,
		Text = "",
		ZIndex = 90,
	}, panel)
	local rows = #options
	local boxH = math.min(320, 56 + rows * 30)
	local box = mk("Frame", {
		Size = UDim2.fromOffset(240, boxH),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = pal.panel,
		BorderSizePixel = 0,
		ZIndex = 91,
	}, back)
	mk("UICorner", { CornerRadius = UDim.new(0, 10) }, box)
	reg(box, "BackgroundColor3", "panel")

	local t = mk("TextLabel", {
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.fromOffset(12, 10),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = title,
		ZIndex = 92,
	}, box)
	reg(t, "TextColor3", "text")

	local list = mk("ScrollingFrame", {
		Size = UDim2.new(1, -16, 1, -76),
		Position = UDim2.fromOffset(8, 40),
		BackgroundTransparency = 1,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(0, 0, 0, rows * 30),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 92,
	}, box)

	for i, opt in ipairs(options) do
		local row = mk("TextButton", {
			Size = UDim2.new(1, 0, 0, 28),
			Position = UDim2.fromOffset(0, (i - 1) * 30),
			BackgroundColor3 = pal.soft,
			BackgroundTransparency = 0.6,
			Text = "",
			ZIndex = 93,
		}, list)
		mk("UICorner", { CornerRadius = UDim.new(0, 6) }, row)
		reg(row, "BackgroundColor3", "soft")

		local lb = mk("TextLabel", {
			Size = UDim2.new(1, -34, 1, 0),
			Position = UDim2.fromOffset(10, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = opt,
			ZIndex = 94,
		}, row)
		reg(lb, "TextColor3", "text")

		local tick = mk("TextLabel", {
			Size = UDim2.fromOffset(22, 28),
			Position = UDim2.new(1, -26, 0, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			Text = "",
			ZIndex = 94,
		}, row)
		reg(tick, "TextColor3", "accent")

		local function refresh()
			local sel = getSel()
			local on
			if multi then on = sel[opt] ~= false
			else on = (sel == opt) end
			tick.Text = on and "✓" or ""
		end
		refresh()

		row.MouseButton1Click:Connect(function()
			if multi then
				local sel = getSel()
				sel[opt] = (sel[opt] == false)
				refresh()
				if onChange then safe(onChange) end
			else
				if onChange then safe(onChange, opt) end
				closePicker()
			end
		end)
	end

	local done = mk("TextButton", {
		Size = UDim2.new(1, -24, 0, 26),
		Position = UDim2.new(0, 12, 1, -34),
		BackgroundColor3 = pal.accent,
		Text = "完成",
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = pal.bg,
		ZIndex = 93,
	}, box)
	mk("UICorner", { CornerRadius = UDim.new(0, 6) }, done)
	reg(done, "BackgroundColor3", "accent")
	reg(done, "TextColor3", "bg")
	done.MouseButton1Click:Connect(closePicker)
	back.MouseButton1Click:Connect(function() end)

	pickerOpen = back
	return back
end

-- 带选择器的卡片（点卡片打开弹窗）
local function pickerCard(grid, title, desc, options, multi, getSel, onChange)
	local cn, api = card(grid, title, desc, false, function()
		safe(function()
			openPicker(title, options, multi, getSel, onChange)
		end)
	end)
	return cn, api
end

-- ============================================================
-- 下拉行选择器：左标签 + 右侧当前值 + 竖线 + ⌃⌄，整行可点
--   选项列表在行下方展开（覆盖式浮层，不改变页面布局）
-- ============================================================
local selectOpen = nil

function selectClose()
	if selectOpen then
		pcall(function() selectOpen:Destroy() end)
		selectOpen = nil
	end
end

local function selectCard(grid, title, options, multi, getSel, onChange)
	local row = mk("Frame", {
		Name = "SelectRow",
		Size = UDim2.new(0.5, -6, 0, 46),
		BackgroundColor3 = pal.panel,
		BorderSizePixel = 0,
	}, grid)
	mk("UICorner", { CornerRadius = UDim.new(0, 6) }, row)
	local stroke = mk("UIStroke", { Thickness = 1 }, row)
	reg(stroke, "Color", "line")
	stroke.Transparency = 0.6
	reg(row, "BackgroundColor3", "panel")

	local lbl = mk("TextLabel", {
		Size = UDim2.new(1, -120, 0, 18),
		Position = UDim2.new(0, 12, 0.5, -9),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = title,
	}, row)
	reg(lbl, "TextColor3", "text")

	local val = mk("TextLabel", {
		Size = UDim2.new(1, -80, 0, 18),
		Position = UDim2.new(0, 12, 0.5, -9),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
	}, row)
	reg(val, "TextColor3", "sub")

	local div = mk("Frame", {
		Size = UDim2.fromOffset(1, 14),
		Position = UDim2.new(1, -30, 0.5, -7),
		BackgroundColor3 = pal.line,
		BorderSizePixel = 0,
	}, row)
	reg(div, "BackgroundColor3", "line")
	div.BackgroundTransparency = 0.45

	local chev = mk("Frame", {
		Size = UDim2.fromOffset(10, 16),
		Position = UDim2.new(1, -22, 0.5, -8),
		BackgroundTransparency = 1,
	}, row)

	local function chevLine(x, y, rot)
		local f = mk("Frame", {
			Size = UDim2.fromOffset(6, 1),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, y),
			BackgroundColor3 = pal.sub,
			BorderSizePixel = 0,
			Rotation = rot,
		}, chev)
		reg(f, "BackgroundColor3", "sub")
	end
	chevLine(3, 5, -45)
	chevLine(7, 5, 45)
	chevLine(3, 11, 45)
	chevLine(7, 11, -45)

	local function optionList()
		return type(options) == "function" and options() or options
	end

	local function refreshValue()
		local sel = getSel()
		local txt
		if multi then
			local picked = {}
			for _, o in ipairs(optionList() or {}) do
				if sel and sel[o] ~= false then table.insert(picked, o) end
			end
			txt = #picked > 0 and table.concat(picked, ", ") or "未选择"
		else
			txt = tostring(sel or "")
		end
		val.Text = txt
	end
	refreshValue()

	local function openList()
		selectClose()
		local list = optionList()
		if not list or #list == 0 then return end

		local panelPos = panel.AbsolutePosition
		local rowPos = row.AbsolutePosition
		local rowSize = row.AbsoluteSize
		local h = math.min(#list * 26 + 10, 220)

		local box = mk("Frame", {
			Name = "SelectList",
			Size = UDim2.fromOffset(rowSize.X, h),
			Position = UDim2.fromOffset(rowPos.X - panelPos.X,
				rowPos.Y - panelPos.Y + rowSize.Y + 4),
			BackgroundColor3 = pal.panel,
			BorderSizePixel = 0,
			ZIndex = 110,
		}, panel)
		mk("UICorner", { CornerRadius = UDim.new(0, 6) }, box)
		local bs = mk("UIStroke", { Thickness = 1 }, box)
		bs.Color = pal.line
		reg(box, "BackgroundColor3", "panel")
		selectOpen = box

		local scroll = mk("ScrollingFrame", {
			Size = UDim2.new(1, -8, 1, -8),
			Position = UDim2.fromOffset(4, 4),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			CanvasSize = UDim2.new(0, 0, 0, #list * 26),
			ZIndex = 111,
		}, box)

		for i, opt in ipairs(list) do
			local item = mk("TextButton", {
				Size = UDim2.new(1, 0, 0, 26),
				Position = UDim2.fromOffset(0, (i - 1) * 26),
				BackgroundColor3 = pal.soft,
				BackgroundTransparency = 0.75,
				Text = "",
				ZIndex = 112,
			}, scroll)
			mk("UICorner", { CornerRadius = UDim.new(0, 4) }, item)
			reg(item, "BackgroundColor3", "soft")

			local tl = mk("TextLabel", {
				Size = UDim2.new(1, -28, 1, 0),
				Position = UDim2.fromOffset(8, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.Gotham,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = opt,
				ZIndex = 113,
			}, item)
			reg(tl, "TextColor3", "text")

			local tick = mk("TextLabel", {
				Size = UDim2.fromOffset(20, 26),
				Position = UDim2.new(1, -22, 0, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				TextSize = 12,
				Text = "",
				ZIndex = 113,
			}, item)
			reg(tick, "TextColor3", "accent")

			if multi then
				local sel = getSel()
				tick.Text = (sel and sel[opt] ~= false) and "✓" or ""
			end

			item.MouseButton1Click:Connect(function()
				if multi then
					local sel = getSel()
					sel[opt] = (sel[opt] == false)
					tick.Text = sel[opt] and "✓" or ""
					refreshValue()
					if onChange then safe(onChange) end
				else
					if onChange then safe(onChange, opt) end
					refreshValue()
					selectClose()
				end
			end)
		end
	end

	local hit = mk("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 5,
	}, row)
	hit.MouseButton1Click:Connect(function()
		safe(function()
			stroke.Transparency = 0.2
			if selectOpen then
				selectClose()
			else
				openList()
			end
			task.delay(0.2, function()
				safe(function() stroke.Transparency = 0.6 end)
			end)
		end)
	end)

	return {
		refresh = refreshValue,
		close = selectClose,
	}
end

-- ============================================================
-- 7. 一键破解
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
-- 8. 功能循环
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
					hum.WalkSpeed = target
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
	local pm = LP.PlayerScripts:FindFirstChild("PlayerModule")
	if not pm then pm = LP.PlayerScripts:WaitForChild("PlayerModule", 3) end
	if pm then controls = require(pm):GetControls() end
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
			local spd = state.flySpeedValue or 100
			flyVel.Velocity = (dir + Vector3.new(0, up, 0)) * spd
			flyGyro.CFrame = cam.CFrame
		end)
	end)
end

-- ============================================================
-- 提示缓存：每 2 秒扫一次 Workspace，热循环只遍历这个小表
--   原来每 0.1 秒 GetDescendants() 一次，副本多的地图会明显卡
-- ============================================================
local promptCache = {}

local function refreshPromptCache()
	local list = {}
	safe(function()
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("ProximityPrompt") then
				local part = d.Parent
				if part and part:IsA("BasePart") then
					table.insert(list, { prompt = d, part = part })
				end
			end
		end
	end)
	promptCache = list
end

task.spawn(function()
	while running do
		refreshPromptCache()
		task.wait(2)
	end
end)

-- 互动（自动按附近 ProximityPrompt）
task.spawn(function()
	while running do
		if state.interactOn then
			safe(function()
				local _, _, root = getChar()
				if root then
					local best, bd
					for _, rec in ipairs(promptCache) do
						local d, part = rec.prompt, rec.part
						if d.Parent and part.Parent then
							local dist = (part.Position - root.Position).Magnitude
							local reach = math.max(26, (d.MaxActivationDistance or 10) + 8)
							if dist <= reach and (not bd or dist < bd) then
								best, bd = d, dist
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
			border.Color = Color3.fromRGB(235, 235, 240)   -- 固定白色描边
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
	safe(selectClose)          -- 切页时收起未关闭的下拉列表
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
-- 10. 页面装配
-- ============================================================
-- ---- 主页 ----
do
	makeView("home", "主页")
	local v = views.home

	v.section("功能")
	local g = v.grid()

	-- 启用边框
	card(g, "启用边框", "显示面板边框", state.borderOn, function(on)
		state.borderOn = on
		applyBorder()
	end)

	-- 彩虹边框
	card(g, "彩虹边框", "循环渐变色彩", state.rainbowOn, function(on)
		state.rainbowOn = on
		applyBorder()
	end)

	-- 面板按键
	card(g, "面板按键", "启用快捷键", state.bindOn, function(on)
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
	local themeCard = card(g, "切换主题", "当前：" .. (THEME_LABEL[state.theme] or "深色主题"), false, function()
		state.theme = nextThemeName(state.theme)
		if themeCard and themeCard.sub then
			themeCard.sub.Text = "当前：" .. (THEME_LABEL[state.theme] or state.theme)
		end
		safe(applyPalette)
		safe(function() show(curView) end)
		safe(applyBorder)
		safe(function()
			panel.BackgroundColor3 = pal.bg
			nav.BackgroundColor3 = pal.bg
			if navLine then navLine.BackgroundColor3 = pal.line end
			if topbar then topbar.BackgroundColor3 = pal.bg end
			if topbarLine then topbarLine.BackgroundColor3 = pal.line end
			if scroller then scroller.ScrollBarImageColor3 = pal.line end
			if homeBar then homeBar.BackgroundColor3 = pal.accent end
		end)
		if not Guard.quiet then
			print(TAG .. " 主题：" .. tostring(state.theme))
		end
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
		setFloating(not collapsed)
	end)

	bMax.MouseButton1Click:Connect(function()
		zoomed = not zoomed
		safe(function() bMax.Text = zoomed and "▣" or "□" end)
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
	card(g1, "跳跃修改", "开启跳跃高度修改", state.jumpOn, function(on)
		state.jumpOn = on
	end)
	sliderCard(g1, "跳跃高度", 0.1, 10.0, 0.1, state.jump, function(v2)
		state.jump = v2
	end)

	card(g1, "无限跳跃", "", state.infJump, function(on)
		state.infJump = on
	end)
	card(g1, "飞行", "", state.fly, function(on)
		state.fly = on
		if on then safe(flyStart) else safe(flyStop) end
	end)

	sliderCard(g1, "飞行速度(格/秒)", 20, 400, 5, state.flySpeedValue, function(v2)
		state.flySpeedValue = v2
	end)
	card(g1, "穿墙", "", state.noclip, function(on)
		state.noclip = on
	end)

	card(g1, "互动", "", state.interactOn, function(on)
		state.interactOn = on
	end)
	sliderCard(g1, "互动时间(秒)", 0.1, 10.0, 0.1, state.interactSec, function(v2)
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

-- ---- 主要 ----
do
	makeView("main", "主要")
	local v = views.main
	v.section("基础")
	local g = v.grid()

	card(g, "无限体力", "体力锁在 100", Main.stamina, function(on)
		Main.stamina = on
	end)
	card(g, "无限饥饿", "饥饿锁在 100", Main.hunger, function(on)
		Main.hunger = on
	end)
	card(g, "战斗拦截", "屏蔽战斗状态上报", Main.combatBlock, function(on)
		Main.combatBlock = on
		if on then safe(applyCombatHooks) end
	end)
	card(g, "防布娃娃", "不进入布娃娃状态", Main.noRagdoll, function(on)
		Main.noRagdoll = on
		safe(applyMainPatches)
	end)
	card(g, "防摔伤", "屏蔽摔落伤害", Main.noFall, function(on)
		Main.noFall = on
		if on then safe(applyCombatHooks) end
	end)
	card(g, "防监狱拉回", "阻止被拉回监狱", Main.antiPull, function(on)
		Main.antiPull = on
		safe(applyMainPatches)
	end)
	card(g, "防物品减少", "库存不被扣减", Main.itemGuard, function(on)
		Main.itemGuard = on
		safe(applyItemGuard)
	end)
	card(g, "防甩飞", "异常速度自动归零", Main.antiFling, function(on)
		Main.antiFling = on
	end)
	card(g, "无限子弹", "弹药锁定 9999", Main.infAmmo, function(on)
		Main.infAmmo = on
	end)
	card(g, "快速射击", "射速拉到最高", Main.rapidFire, function(on)
		Main.rapidFire = on
	end)
	card(g, "自动捡钱", "自动拾取附近现金", Main.autoMoney, function(on)
		Main.autoMoney = on
	end)
	card(g, "金库刷新提示", "新目标出现时打印", Main.vaultWatch, function(on)
		Main.vaultWatch = on
	end)
	card(g, "显示聊天框", "强制开启聊天", true, function(on)
		setChat(on)
	end)

end


-- ---- 战斗 ----
do
	makeView("combat", "战斗")
	local v = views.combat
	v.section("杀戮光环")
	local g = v.grid()

	card(g, "杀戮光环", "范围自动攻击", Ext.aura, function(on)
		Ext.aura = on
	end)
	card(g, "只攻击警察", "只打警察", Ext.auraPolice, function(on)
		Ext.auraPolice = on
		if on then Ext.auraCivil = false end
	end)
	card(g, "只攻击平民", "只打平民", Ext.auraCivil, function(on)
		Ext.auraCivil = on
		if on then Ext.auraPolice = false end
	end)
	card(g, "战斗检测", "只打战斗状态目标", Ext.auraCombat, function(on)
		Ext.auraCombat = on
	end)
	sliderCard(g, "攻击范围", 20, 400, 5, Ext.auraRange, function(v2)
		Ext.auraRange = v2
	end)
	card(g, "多目标攻击", "同时打多个目标", Ext.auraMulti, function(on)
		Ext.auraMulti = on
	end)
	sliderCard(g, "伤害倍数", 1, 30, 1, Ext.auraDamage, function(v2)
		Ext.auraDamage = v2
	end)

	v.gap(10)
	v.section("子弹")
	local g2 = v.grid()
	card(g2, "子弹追敌", "子弹自动瞄准", Ext.bulletAim, function(on)
		Ext.bulletAim = on
		safe(applyBulletAim)
	end)
	card(g2, "NPC追敌", "连同 NPC 一起瞄", Ext.npcAim, function(on)
		Ext.npcAim = on
		safe(applyBulletAim)
	end)
	card(g2, "显示FOV圈", "屏幕上画准心圈", Ext.showFov, function(on)
		Ext.showFov = on
	end)
	sliderCard(g2, "FOV范围", 50, 600, 10, Ext.fovRange, function(v2)
		Ext.fovRange = v2
	end)
	sliderCard(g2, "FOV圈厚度", 1, 6, 1, Ext.fovThick, function(v2)
		Ext.fovThick = v2
	end)
	sliderCard(g2, "子弹追敌距离", 50, 1000, 25, Ext.fovDist, function(v2)
		Ext.fovDist = v2
	end)
	selectCard(g2, "子弹部位", { "Head", "Torso" }, false,
		function() return Ext.bulletPart end,
		function(opt) Ext.bulletPart = opt end)
end


placeholderView("aimbot", "自瞄")
-- ---- 逃犯 ----
do
	makeView("fugitive", "逃犯")
	local v = views.fugitive
	v.section("躲避")
	local g = v.grid()

	card(g, "躲避警察", "警察靠近自动闪走", Ext.evade, function(on)
		Ext.evade = on
	end)
	sliderCard(g, "检测范围", 30, 400, 10, Ext.evadeRange, function(v2)
		Ext.evadeRange = v2
	end)
	sliderCard(g, "传送范围", 20, 300, 10, Ext.evadeTpRange, function(v2)
		Ext.evadeTpRange = v2
	end)
end


-- ---- 透视 ----
do
	makeView("esp", "透视")
	local v = views.esp
	v.section("显示")
	local g = v.grid()

	card(g, "透视总开关", "开启后下面各项生效", Ext.espOn, function(on)
		Ext.espOn = on
	end)
	card(g, "显示名字", "", Ext.espName, function(on) Ext.espName = on end)
	card(g, "显示距离", "", Ext.espDist, function(on) Ext.espDist = on end)
	card(g, "显示血量", "", Ext.espHp, function(on) Ext.espHp = on end)
	card(g, "显示骨骼", "", Ext.espBone, function(on) Ext.espBone = on end)

	local teamNames = {}
	for _, t in ipairs(TEAM_KEYS) do table.insert(teamNames, t.label) end
	local keyByLabel = {}
	for _, t in ipairs(TEAM_KEYS) do keyByLabel[t.label] = t.key end

	selectCard(g, "透视队伍", teamNames, true,
		function() return Ext.espTeams end,
		function() end)
end


-- ---- 传送 ----
do
	makeView("tp", "传送")
	local v = views.tp
	v.section("玩家传送")
	local g = v.grid()

	local playerNames = {}
	local function refreshNames()
		playerNames = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LP then table.insert(playerNames, p.Name) end
		end
	end
	refreshNames()

	local function playerNames()
		local list = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LP then table.insert(list, p.Name) end
		end
		return list
	end
	local playerCard = selectCard(g, "选择玩家", playerNames, false,
		function() return Ext.tpTarget and Ext.tpTarget.Name or "" end,
		function(name) Ext.tpTarget = Players:FindFirstChild(name) end)

	card(g, "刷新玩家列表", "重新读取在线玩家", false, function()
		refreshNames()
		safe(function() playerCard.refresh() end)
	end)

	selectCard(g, "传送方向", { "前面", "后面", "左边", "右边" }, false,
		function() return Ext.tpDir end,
		function(opt) Ext.tpDir = opt end)

	sliderCard(g, "传送距离", 1, 50, 1, Ext.tpDist, function(v2)
		Ext.tpDist = v2
	end)

	card(g, "持续传送", "每帧贴住目标", Ext.tpLoop, function(on)
		Ext.tpLoop = on
		if on then safe(teleportNearTarget) end
	end)
	card(g, "查看选定玩家", "镜头锁定目标", Ext.watching, function(on)
		Ext.watching = on
	end)
	card(g, "环绕玩家", "围着目标转圈", Ext.orbit, function(on)
		Ext.orbit = on
	end)

	v.gap(10)
	v.section("地点传送")
	local g2 = v.grid()
	selectCard(g2, "传送地点", { "警察局", "医院" }, false,
		function() return Ext.tpPlace end,
		function(opt) Ext.tpPlace = opt end)

	card(g2, "传送", "传送到选中地点", false, function()
		local place = Ext.tpPlace or "警察局"
		if place == "医院" then
			safe(function() teleportToPlace("hospital") end)
			safe(function() teleportToPlace("医院") end)
		else
			safe(function() teleportToPlace("policestation") end)
			safe(function() teleportToPlace("警察局") end)
		end
	end, true)
end


-- ---- 商店 ----
do
	makeView("shop", "商店")
	local v = views.shop
	v.section("黑市物品")
	local g = v.grid()

	for _, name in ipairs(SHOP_ITEMS) do
		Ext.shopSel[name] = true
	end
	selectCard(g, "黑市物品", SHOP_ITEMS, true,
		function() return Ext.shopSel end,
		function() end)

	card(g, "购买选中物品", "按勾选逐个购买", false, function()
		for _, name in ipairs(SHOP_ITEMS) do
			if Ext.shopSel[name] ~= false then buyItem(name) end
		end
	end)

	v.gap(10)
	v.section("武器")
	local g2 = v.grid()
	for _, name in ipairs(WEAPONS) do
		Ext.weaponSel[name] = true
	end
	selectCard(g2, "选择武器", WEAPONS, true,
		function() return Ext.weaponSel end,
		function() end)

	card(g2, "购买选中武器", "按勾选逐个购买", false, function()
		for _, name in ipairs(WEAPONS) do
			if Ext.weaponSel[name] ~= false then equipWeapon(name) end
		end
	end, true)
end


placeholderView("car", "车辆")
-- ---- 游戏功能（警察功能） ----
do
	makeView("game", "游戏功能")
	local v = views.game
	v.section("警察功能")
	local g = v.grid()

	card(g, "自动手铐", "靠近嫌疑人自动上铐", Ext.cuff, function(on)
		Ext.cuff = on
	end)
	card(g, "自动传送", "逮捕后自动跟过去", Ext.cuffTp, function(on)
		Ext.cuffTp = on
	end)
	card(g, "全图传送", "传送到通缉目标身边", Ext.globalTp, function(on)
		Ext.globalTp = on
	end)
	card(g, "自动逮捕", "目标倒地自动逮捕", Ext.arrest, function(on)
		Ext.arrest = on
	end)
	card(g, "战斗检测", "只处理战斗状态目标", Ext.policeCombat, function(on)
		Ext.policeCombat = on
	end)
end


placeholderView("setting", "设置")
placeholderView("safe", "安全模式")
-- ---- 反作弊 ----
do
	makeView("anticheat", "反作弊")
	local v = views.anticheat
	v.section("反作弊对抗")
	local g = v.grid()

	local acCard
	acCard = card(g, "反作弊绕过", "AntiCheatBypass · 未启用", false, function(on)
		if on then
			-- 总开关：把所有子项都打开
			AntiCheatBypass.config.patchAntiCheat = true
			AntiCheatBypass.config.patchRatchet = true
			AntiCheatBypass.config.hookNamecall = true
			AntiCheatBypass.config.hookIndex = true
			AntiCheatBypass.config.selfGuard = true
			local rep = AntiCheatBypass.init()
			Guard.on = true
			if acCard.sub then
				acCard.sub.Text = "AntiCheatBypass · " .. AntiCheatBypass.status()
			end
			if not Guard.quiet and rep then
				print(TAG .. " 反作弊绕过已启用，失败 " .. tostring(#(rep.errors or {})) .. " 步")
			end
		else
			AntiCheatBypass.uninstall()
			Guard.on = false
			if acCard.sub then
				acCard.sub.Text = "AntiCheatBypass · 未启用"
			end
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
function applyLayout(forceW, forceH, keepPos)
	if customSize and not forceW then
		-- 用户手动调过大小，不再按预设覆盖
		return
	end
	local pw, ph, nw
	if forceW then
		pw, ph = forceW, forceH
		nw = math.floor(math.clamp(pw * 0.13, 72, 120))
	else
		pw, ph, nw = calcSizes()
	end
	PANEL_W, PANEL_H, NAV_W = pw, ph, nw

	-- 不再用 UIScale（小数缩放会让文字发虚），直接按整像素定位

	safe(function()
		if panelScale then panelScale.Scale = 1 end
		if not keepPos then
			if zoomed then
				panel.Position = UDim2.fromOffset(0, 0)   -- 全屏：贴左上角
			else
				panel.Position = UDim2.new(0.5, -pw / 2 + PANEL_OFFSET_X, 0.5, -ph / 2 + PANEL_OFFSET_Y)
			end
		end
		if frameBezel then
			local px, py = panel.Position.X, panel.Position.Y
			frameBezel.Size = UDim2.fromOffset(pw + 24, ph + 24)
			frameBezel.Position = UDim2.new(px.Scale, px.Offset - 12, py.Scale, py.Offset - 12)
			frameBezel.Visible = started and not collapsed
		end
		panel.Visible = started
	end)

	-- 收起成悬浮图标时不动布局
	if collapsed then return end

	safe(function()
		panel.Size = UDim2.fromOffset(pw, ph)
		nav.Visible = true
		nav.Size = UDim2.fromOffset(nw, ph)
		if navScroll then
			navScroll.Size = UDim2.new(1, 0, 1, -98)
			navScroll.Position = UDim2.fromOffset(0, 66)
		end
		if navSearch then
			navSearch.Size = UDim2.new(1, -16, 0, 26)
			navSearch.Position = UDim2.fromOffset(8, 32)
		end
		if relayoutNav then safe(relayoutNav) end
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
		-- 顶栏左侧（侧栏右边那块）
		clock.Position = UDim2.fromOffset(12, 6)
		clock.Size = UDim2.fromOffset(86, 18)
		topTitle.Size = UDim2.fromOffset(math.max(50, nw - 16), 28)
		topTitle.Visible = true
		brand.Visible = false
		bMin.Text = "−"
		bMax.Text = zoomed and "▣" or "□"
		bMin.Position = UDim2.new(1, -90, 0, 2)
		bMax.Position = UDim2.new(1, -58, 0, 2)
		bClose.Position = UDim2.new(1, -26, 0, 2)
	end)

	-- 内容太窄就单列
	local contentW = pw - nw - 32
	local oneCol = contentW < 430   -- 窄了自动单列，够宽就双列
	local cellH = MOBILE and 44 or 46

	for _, item in ipairs(gridList) do
		safe(function()
			if oneCol then
				item.lay.CellSize = UDim2.new(1, 0, 0, item.h or cellH)
				item.lay.CellPadding = UDim2.fromOffset(0, 8)
				item.lay.FillDirectionMaxCells = 1
			else
				item.lay.CellSize = UDim2.new(0.5, -4, 0, item.h or cellH)
				item.lay.CellPadding = UDim2.fromOffset(8, 8)
				item.lay.FillDirectionMaxCells = 2
			end
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
					b.label.TextSize = narrow and 14 or (itemH < 26 and 14 or 16)
				end)
			end
			y = y + itemH
		end
	end

	-- 底部版本文字：面板太矮就隐藏，避免压住导航
	safe(function()
		if topbar and footer.Parent ~= topbar then footer.Parent = topbar end
		footer.Visible = true
		footer.Position = UDim2.fromOffset(74, 6)
		footer.Size = UDim2.fromOffset(120, 18)
		footer.TextSize = 11
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

	safe(function()
		clock.TextSize = 12
		-- 按钮占位 92px，状态文字放它左边
		if runLed and runTxt then
			runLed.Position = UDim2.new(1, -168, 0, 11)
			runTxt.Position = UDim2.new(1, -156, 0, 5)
			runTxt.TextSize = MOBILE and 11 or 12
		end
	end)
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
