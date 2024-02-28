--!strict

local Packages = game.ReplicatedStorage.Packages
local TextTools = require(Packages.TextTools)

local screen = script.Parent.Parent
local frame = screen.Frame
local textBox = frame.TextBox

local cylinder = workspace.Cylinder

local decal = Instance.new("Decal")
decal.Face = Enum.NormalId.Top
decal.Parent = cylinder

local button = Instance.new("TextButton")
button.Text = "Submit"
button.TextSize = 22
button.FontFace = Font.fromEnum(Enum.Font.GothamBold)
button.BackgroundColor3 = Color3.new(1, 1, 1)
button.AnchorPoint = Vector2.new(0.5, 0)
button.Position = UDim2.new(0.5, 0, 1, 20)
button.Size = UDim2.fromOffset(200, 50)
button.Parent = frame

local function render()
	decal:ClearAllChildren()
	decal.Color3 = textBox.TextColor3

	local image = TextTools.convert(textBox, false)
	image.Parent = decal
end

render()
button.Activated:Connect(function()
	render()
end)
