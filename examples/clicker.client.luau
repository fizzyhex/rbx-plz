--[[
	clicker.client.luau

	Draws an array of buttons, with a bar next to each that fills as you click.
]]

local Players = game:GetService("Players")
local plz = require("../plz")

local pen = plz.pen()

local BORDER_SIZE = 2

local gui_prefab = Instance.new("ScreenGui")
gui_prefab.ResetOnSpawn = false
gui_prefab.Name = "plz click"

local box_prefab = Instance.new("Frame")
box_prefab.BorderSizePixel = BORDER_SIZE

local button_prefab = Instance.new("TextButton")
button_prefab.BorderSizePixel = BORDER_SIZE

local label_prefab = Instance.new("TextLabel")
label_prefab.BackgroundTransparency = 1

local Button = plz.allocate(button_prefab)
local ScreenGui = plz.allocate(gui_prefab)
local Box = plz.allocate(box_prefab)
local Label = plz.allocate(label_prefab)

local BUTTONS = 8
local btn_clicks = table.create(BUTTONS, 0)
local updates = 0

while true do
	local gui = pen:node(ScreenGui)
	gui.Parent = Players.LocalPlayer.PlayerGui

	for i = 1, BUTTONS do
		const height = 30

		local outline_color = Color3.fromHSV(math.abs(math.sin(i + os.clock() / 5)), 1, 1)

		local btn = pen:node(Button)
		btn.Name = `btn {i}`
		btn.Text = `Clicks: {btn_clicks[i]}`
		btn.BorderColor3 = outline_color
		btn.Size = UDim2.fromOffset(200, height)
		btn.Position = UDim2.fromOffset(8, (height + BORDER_SIZE + 12) * i)
		btn.Parent = gui

		plz.event(btn, button_prefab.MouseButton1Click, function()
			btn_clicks[i] += 1
		end)

		plz.event(btn, button_prefab.ChildAdded, function(child: Instance)			
			print(`hi {child}!`)
		end)

		for i = 1, btn_clicks[i] do
			local bar = pen:node(Box)
			bar.Parent = btn
			bar.Name = `Bar {i}`
			bar.Size = UDim2.fromOffset(12, height)
			bar.Position = UDim2.new(1, (12 + BORDER_SIZE + 4) * i, 0, 0)
			bar.BackgroundColor3 = outline_color
			bar.Transparency = math.abs(math.sin(os.clock() + i)) ^ 0.9
		end
	end

	local label = pen:node(Label)
	label.Parent = gui
	label.Name = "updates"
	label.Size = UDim2.fromOffset(200, 30)
	label.Position = UDim2.fromOffset(8, 8)
	label.Text = `Updates: {updates}`

	updates = pen:render()

	task.wait(1 / 20)
end
