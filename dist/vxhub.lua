--[[
	VX 手机启动器（带错误显示）
	用法：执行器新建脚本 -> 全选删掉 -> 粘贴本文件 -> 运行
	无论成功还是失败，屏幕上都会弹出一个框告诉你情况，截图发我即可
]]

local MIRRORS = {
	-- gh-proxy 直通 GitHub，不走缓存。改了脚本想立刻看到效果用它
	"https://gh-proxy.com/https://raw.githubusercontent.com/Baozi733/vx-hub/refs/heads/main/dist/vxhub.lua",
	"https://ghproxy.net/https://raw.githubusercontent.com/Baozi733/vx-hub/refs/heads/main/dist/vxhub.lua",
	-- jsDelivr 有 12 小时缓存，作为备用
	"https://fastly.jsdelivr.net/gh/Baozi733/vx-hub@main/dist/vxhub.lua",
	"https://gcore.jsdelivr.net/gh/Baozi733/vx-hub@main/dist/vxhub.lua",
}

-- ============ 结果面板 ============
local function show(title, body, color)
	local gui = Instance.new("ScreenGui")
	gui.Name = "VXLaunch"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 9999
	local ok = pcall(function() gui.Parent = game:GetService("CoreGui") end)
	if not ok then
		pcall(function() gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui") end)
	end

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0.92, 0, 0.7, 0)
	frame.Position = UDim2.new(0.04, 0, 0.12, 0)
	frame.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
	frame.BackgroundTransparency = 0.02
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = frame

	local head = Instance.new("TextLabel")
	head.Size = UDim2.new(1, -20, 0, 34)
	head.Position = UDim2.new(0, 10, 0, 8)
	head.BackgroundTransparency = 1
	head.Font = Enum.Font.GothamBold
	head.TextSize = 18
	head.TextColor3 = color or Color3.fromRGB(120, 220, 150)
	head.TextXAlignment = Enum.TextXAlignment.Left
	head.Text = title
	head.Parent = frame

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -20, 1, -104)
	scroll.Position = UDim2.new(0, 10, 0, 44)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = frame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -8, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = 13
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextColor3 = Color3.fromRGB(225, 230, 240)
	label.Text = body
	label.Parent = scroll

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -20, 0, 42)
	btn.Position = UDim2.new(0, 10, 1, -52)
	btn.BackgroundColor3 = Color3.fromRGB(60, 130, 255)
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 16
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Text = "关闭"
	btn.Parent = frame
	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(0, 8)
	c2.Parent = btn
	btn.MouseButton1Click:Connect(function() gui:Destroy() end)
end

-- ============ 拉取 ============
local src, used
for _, url in ipairs(MIRRORS) do
	local ok, body = pcall(function() return game:HttpGet(url, true) end)
	if ok and type(body) == "string" and #body > 1000 then
		src, used = body, url
		break
	end
end

if not src then
	show("拉取失败", "所有线路都没拿到文件。\n检查手机网络，或换个时间再试。", Color3.fromRGB(255, 120, 120))
	return
end

-- 版本检查：新版至少 66000 字节，拿到小的说明 GitHub 上还是旧文件
if #src < 66000 then
	show("服务器上还是旧版文件",
		string.format(
			"拿到的文件只有 %d 字节。\n新版应该是 66272 字节。\n\n"
			.. "说明 GitHub 上还没覆盖成功，\n去把新的 dist/vxhub.lua 传上去再来。",
			#src
		),
		Color3.fromRGB(255, 170, 90))
	return
end

-- ============ 编译 ============
local chunk, cerr = loadstring(src)
if not chunk then
	show("编译失败（文件可能传坏了）", "来源: " .. used .. "\n大小: " .. #src .. " 字节\n\n" .. tostring(cerr),
		Color3.fromRGB(255, 120, 120))
	return
end

-- ============ 运行 ============
local ok, err = xpcall(chunk, function(e)
	local tb = ""
	pcall(function() tb = debug.traceback() end)
	return tostring(e) .. "\n\n" .. tb
end)

if ok then
	show("启动成功",
		"脚本已运行。\n\n"
		.. "如果屏幕上没看到菜单窗口：\n"
		.. "1. 找屏幕左边那个写着 VX HUB 的小按钮，点它\n"
		.. "2. 如果按钮也没有，说明菜单跑到屏幕外面了，把这张图发我\n\n"
		.. "来源: " .. used .. "\n大小: " .. #src .. " 字节",
		Color3.fromRGB(120, 220, 150))
else
	show("运行出错（这就是原因）",
		tostring(err) .. "\n\n来源: " .. used .. "\n大小: " .. #src .. " 字节",
		Color3.fromRGB(255, 120, 120))
end
