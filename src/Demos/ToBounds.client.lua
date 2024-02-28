--!strict

local Packages = game.ReplicatedStorage.Packages
local TextTools = require(Packages.TextTools)

local screen = script.Parent.Parent
local frame = screen.Frame
local textBox = frame.TextBox

local function getGraphemesGlyphsAndImage(textFrame: TextTools.TextGuiObject)
	local graphemes = TextTools.graphemes(textFrame.ContentText)
	local image, bboxes = TextTools.convert(textFrame, true)

	local glyphs = {}
	local bboxIndex = 0

	for i, grapheme in graphemes do
		if grapheme:gsub("%s+", "") ~= "" then
			bboxIndex = bboxIndex + 1

			glyphs[i] = bboxes[bboxIndex]
		end
	end

	return graphemes, glyphs, image
end

local function getBreakdown(textFrame: TextTools.TextGuiObject)
	local textFrameAbsSize = textFrame.AbsoluteSize
	local graphemes, glyphs, image = getGraphemesGlyphsAndImage(textFrame)

	local container = Instance.new("Frame")
	container.Name = "Breakdown"
	container.BackgroundTransparency = 1
	container.Size = UDim2.fromScale(1, 1)
	container.Parent = textFrame

	local labelTemplate = TextTools.toTextLabel(textFrame)
	labelTemplate.RichText = true

	for i, grapheme in graphemes do
		local glyph = glyphs[i]

		if glyph then
			local bounds = Instance.new("Frame")
			bounds.Name = tostring(i)
			bounds.Size = UDim2.fromOffset(glyph.rect.Width, glyph.rect.Height)
			bounds.Position = UDim2.fromOffset(glyph.rect.Min.X, glyph.rect.Min.Y)
			bounds.BackgroundTransparency = 1
			bounds.BorderSizePixel = 0
			bounds.Parent = container

			local label = labelTemplate:Clone()

			label.Text = ('<font transparency="1">%s</font>%s<font transparency="1">%s</font>'):format(
				table.concat(graphemes, "", 1, i - 1),
				grapheme,
				table.concat(graphemes, "", i + 1)
			)

			label.Size = UDim2.fromOffset(textFrameAbsSize.X, textFrameAbsSize.Y)
			label.Position = UDim2.fromOffset(-glyph.rect.Min.X, -glyph.rect.Min.Y)
			label.Parent = bounds
		end
	end

	labelTemplate:Destroy()

	return container, image
end

textBox.TextEditable = false

local container = getBreakdown(textBox)
container.Parent = frame
textBox.Visible = false

local random = Random.new()
for _, glyphFrame in container:GetChildren() do
	if glyphFrame:IsA("Frame") then
		local index = random:NextInteger(1, 3)
		local rotations = { -random:NextInteger(3, 6), 0, random:NextInteger(3, 6) }

		task.spawn(function()
			while true do
				index = (index % #rotations) + 1
				glyphFrame.Rotation = rotations[index]
				task.wait(0.05)
			end
		end)
	end
end
