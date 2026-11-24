--[[
    EX HUD 卡密加载器
    ------------------------------------------------------------
    用法（客户端只需要这一行）：
      loadstring(game:HttpGet("加载器地址"))("卡密")

    流程：
      1. 拿卡密 + 设备号
      2. 请求网关 /vx?key=..&hwid=..
      3. 网关校验通过才返回脚本源码
      4. 本地执行源码

    没有卡密 / 卡密错 / 过期 / 被封 / 设备不符 → 只返回错误注释，拿不到脚本
]]

local GATE = "https://exhud-auth.guangdong-77.workers.dev"

-- ============================================================
-- 1. 设备号（尽量稳定，换设备会触发重新绑定）
-- ============================================================
local function getHwid()
    local ok, id

    ok, id = pcall(function() return gethwid and gethwid() end)
    if ok and type(id) == "string" and #id > 6 then return id end

    ok, id = pcall(function() return game:GetService("RbxAnalyticsService"):GetClientId() end)
    if ok and type(id) == "string" and #id > 6 then return id end

    -- 退化方案：本地存一个随机串
    local file = "EXHUD_hwid.txt"
    ok, id = pcall(function() return readfile(file) end)
    if ok and type(id) == "string" and #id > 6 then return id end

    local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
    local s = ""
    for _ = 1, 32 do
        local i = math.random(1, #chars)
        s = s .. chars:sub(i, i)
    end
    pcall(function() writefile(file, s) end)
    return s
end

-- ============================================================
-- 2. 小提示框（卡密错误时显示，不用打开控制台）
-- ============================================================
local function toast(msg)
    pcall(function()
        local parent = (gethui and gethui()) or game:GetService("CoreGui")
        local gui = Instance.new("ScreenGui")
        gui.Name = "EXHUD_MSG"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.Parent = parent

        local box = Instance.new("Frame")
        box.Size = UDim2.fromOffset(360, 70)
        box.Position = UDim2.new(0.5, -180, 0, 60)
        box.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
        box.BorderSizePixel = 0
        box.Parent = gui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 10)
        corner.Parent = box

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(239, 68, 68)
        stroke.Thickness = 1.5
        stroke.Parent = box

        local txt = Instance.new("TextLabel")
        txt.Size = UDim2.new(1, -20, 1, -10)
        txt.Position = UDim2.fromOffset(10, 5)
        txt.BackgroundTransparency = 1
        txt.Font = Enum.Font.GothamMedium
        txt.TextSize = 14
        txt.TextWrapped = true
        txt.TextColor3 = Color3.fromRGB(240, 240, 245)
        txt.Text = msg
        txt.Parent = box

        task.delay(4, function()
            pcall(function() gui:Destroy() end)
        end)
    end)
end

-- ============================================================
-- 3. 主流程
-- ============================================================
local key = ...

-- 没传卡密就从本地记录里取
if type(key) ~= "string" or key == "" then
    local ok, saved = pcall(function() return readfile("EXHUD_key.txt") end)
    if ok and type(saved) == "string" then
        key = saved:gsub("%s", "")
    end
end

if type(key) ~= "string" or key == "" then
    toast("没有输入卡密。\n用法：loadstring(...)(\"你的卡密\")")
    return
end

key = key:gsub("%s", ""):upper()
pcall(function() writefile("EXHUD_key.txt", key) end)

local hwid = getHwid()
local url = GATE .. "/vx?key=" .. key .. "&hwid=" .. hwid

local okFetch, body = pcall(function()
    return game:HttpGet(url, true)
end)

if not okFetch or type(body) ~= "string" or #body < 200 then
    toast("网络请求失败，请检查网络后重试")
    return
end

-- 网关返回错误时是这个格式：--[[VXERR:code|message]]
local errCode, errMsg = body:match("^%-%-%[%[VXERR:([^|]+)|([^%]]+)%]%]")
if errCode then
    local map = {
        invalid = "卡密不存在",
        expired = "卡密已到期",
        banned = "卡密已被封禁",
        device_mismatch = "该卡密已绑定其他设备",
        no_hwid = "无法识别设备",
        upstream = "脚本源异常",
    }
    toast("验证失败：" .. (map[errCode] or errMsg or errCode))
    return
end

-- 执行脚本
local fn, loadErr = loadstring(body)
if not fn then
    toast("脚本加载失败：" .. tostring(loadErr))
    return
end

local okRun, runErr = pcall(fn, "")
if not okRun then
    warn("[EX HUD] 运行出错：" .. tostring(runErr))
end
