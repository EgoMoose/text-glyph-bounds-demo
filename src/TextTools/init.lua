--!strict

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local AssetService = game:GetService("AssetService")
local CaptureService = game:GetService("CaptureService")
local UserInputService = game:GetService("UserInputService")

local Image = require(script:WaitForChild("Image"))
local InstanceConverter = require(script:WaitForChild("InstanceConverter"))

local Promise = require(script.Parent:WaitForChild("Promise"))

type Image = Image.Image

export type TextGuiObject = TextBox | TextLabel | TextButton

export type GlyphBBox = {
	rect: Rect,
	children: { Rect },
}

local CAPTURE_SCALE = 1.25

local module = {}

-- Private

local function getTopbarHeight(): number
	local insetTL, _insetBR = GuiService:GetGuiInset()
	return insetTL.Y
end

local function checkCanRender(textFrame: TextGuiObject): (boolean, string?)
	local topbarHeight = getTopbarHeight()
	local absTextFrameSize = textFrame.AbsoluteSize
	local viewportSize = workspace.CurrentCamera.ViewportSize

	if absTextFrameSize.X > viewportSize.X or (absTextFrameSize.Y + topbarHeight) > viewportSize.Y then
		return false, "Text can't all fit in the viewport."
	end

	if absTextFrameSize.X > 1024 or absTextFrameSize.Y > 1024 then
		return false, "Text bounds is greater than (1024 x 1024)"
	end

	return true
end

local function getScreenGuiForCapture(textFrame: TextGuiObject)
	local textFrameAbsSize = textFrame.AbsoluteSize

	local screen = Instance.new("ScreenGui")
	screen.Name = "TextToImage"
	screen.DisplayOrder = 100

	local text = ""
	for i, graphmeme in module.graphemes(textFrame.Text) do
		if i % 2 == 0 then
			graphmeme = ('<font color="#0000FF">%s</font>'):format(graphmeme)
		end
		text = text .. graphmeme
	end

	local label = module.toTextLabel(textFrame)
	label.Size = UDim2.fromOffset(textFrameAbsSize.X, textFrameAbsSize.Y)
	label.BackgroundTransparency = 0
	label.BorderSizePixel = 0
	label.BackgroundColor3 = Color3.new(1, 0, 0)
	label.RichText = true
	label.Text = text
	label.TextColor3 = Color3.new(0, 1, 0)
	label.Parent = screen

	return screen, label
end

local function screenshot(callback: (string) -> ())
	-- stylua: ignore
	return Promise.new(function(resolve)
		UserInputService.MouseIconEnabled = false
		CaptureService:CaptureScreenshot(function(content: string)
			resolve(content)
		end)
	end):andThen(function(content)
		UserInputService.MouseIconEnabled = true
		callback(content)
	end):expect()
end

local function getTextRect(textFrame: TextGuiObject)
	local anchorX = 1
	if textFrame.TextXAlignment == Enum.TextXAlignment.Left then
		anchorX = 0
	elseif textFrame.TextXAlignment == Enum.TextXAlignment.Center then
		anchorX = 0.5
	end

	local anchorY = 1
	if textFrame.TextYAlignment == Enum.TextYAlignment.Top then
		anchorY = 0
	elseif textFrame.TextYAlignment == Enum.TextYAlignment.Center then
		anchorY = 0.5
	end

	local anchor = Vector2.new(anchorX, anchorY)

	local textBounds = textFrame.TextBounds
	local textFrameAbsSize = textFrame.AbsoluteSize

	local tlc = (textFrameAbsSize - textBounds) * anchor
	return Rect.new(tlc, tlc + textBounds)
end

local function getSortedBboxes(bboxGroups: { [string]: { Rect } }, textSize: number, textRect: Rect)
	local bboxes: { GlyphBBox } = {}

	for _name, bboxGroup in bboxGroups do
		local bboxesByLines = {}
		for _, bbox in bboxGroup do
			local lineIndex = math.floor((bbox.Min.Y - textRect.Min.Y) / textSize) + 1

			if not bboxesByLines[lineIndex] then
				bboxesByLines[lineIndex] = {}
			end

			table.insert(bboxesByLines[lineIndex], bbox)
		end

		for _lineIndex, lineGroup in bboxesByLines do
			while #lineGroup > 0 do
				local bbox = table.remove(lineGroup) :: Rect
				local overlapping = { bbox }

				for i = #lineGroup, 1, -1 do
					local rect = lineGroup[i]
					if bbox.Max.X >= rect.Min.X and bbox.Min.X <= rect.Max.X then
						-- they do overlap
						table.insert(overlapping, rect)
						table.remove(lineGroup, i)
					end
				end

				local minX = math.huge
				local minY = math.huge
				local maxX = -math.huge
				local maxY = -math.huge

				for _, rect in overlapping do
					minX = math.min(minX, rect.Min.X)
					minY = math.min(minY, rect.Min.Y)
					maxX = math.max(maxX, rect.Max.X)
					maxY = math.max(maxY, rect.Max.Y)
				end

				table.insert(bboxes, {
					rect = Rect.new(minX, minY, maxX, maxY),
					children = overlapping,
				})
			end
		end
	end

	table.sort(bboxes, function(a, b)
		local lineIndexA = math.floor((a.rect.Min.Y - textRect.Min.Y) / textSize) + 1
		local lineIndexB = math.floor((b.rect.Min.Y - textRect.Min.Y) / textSize) + 1

		if lineIndexA == lineIndexB then
			return a.rect.Min.X < b.rect.Min.X
		end

		return lineIndexA < lineIndexB
	end)

	return bboxes
end

local function getGlyphBounds(image: Image, textSize: number, textRect: Rect)
	local visited = {}
	local bboxGroups: { [string]: { Rect } } = {
		green = {},
		blue = {},
	}

	local function isRedChannelDominant(r: number, g: number, b: number, _a: number)
		return r > 0 and g == 0 and b == 0
	end

	for h = 1, image.size.Y do
		for w = 1, image.size.X do
			local found = 0

			local minX = math.huge
			local minY = math.huge
			local maxX = -math.huge
			local maxY = -math.huge

			local pixelIndex = image:GetPixelIndex(w, h)
			local rgba = { image:GetRGBA(pixelIndex) }

			local isGreen = rgba[2] > rgba[3]
			local function isSameChannel(_r: number, g: number, b: number, _a: number)
				return if isGreen then b == 0 else g == 0
			end

			local queue = { pixelIndex }

			while #queue > 0 do
				local poppedIndex = table.remove(queue) :: number

				if not visited[poppedIndex] then
					visited[poppedIndex] = true

					local r, g, b, a = image:GetRGBA(poppedIndex)
					if not isRedChannelDominant(r, g, b, a) and isSameChannel(r, g, b, a) then
						found = found + 1

						local x, y = image:GetXYFromPixelIndex(poppedIndex)

						-- in EditableImages the (x, y) represents the bottom right corner of the pixel
						-- when considering the min, we actually want the top left corner of the pixel
						minX = math.min(minX, x - 1)
						minY = math.min(minY, y - 1)
						maxX = math.max(maxX, x)
						maxY = math.max(maxY, y)

						for _, neighbor in image:GetNeighbors(poppedIndex) do
							if not visited[neighbor] then
								table.insert(queue, neighbor)
							end
						end
					end
				end
			end

			if found > 0 then
				if found == 1 then
					print(rgba)
				end

				local bboxGroup = if isGreen then bboxGroups.green else bboxGroups.blue
				table.insert(bboxGroup, Rect.new(minX, minY, maxX, maxY))
			end
		end
	end

	return getSortedBboxes(bboxGroups, textSize, textRect)
end

local function rgbChannelsToAlphaWhite(image: Image)
	for h = 1, image.size.Y do
		for w = 1, image.size.X do
			local pixelIndex = image:GetPixelIndex(w, h)
			local r, g, b = image:GetRGBA(pixelIndex)

			if r == 1 then
				image:SetRGBA(pixelIndex, 1, 1, 1, 0)
			else
				image:SetRGBA(pixelIndex, 1, 1, 1, g + b)
			end
		end
	end
end

-- Public

function module.graphemes(text: string): { string }
	local graphemes = {}
	for i, j in utf8.graphemes(text) do
		table.insert(graphemes, text:sub(i, j))
	end
	return graphemes
end

function module.toTextLabel(textFrame: TextGuiObject): TextLabel
	assert(
		(textFrame:IsA("TextLabel") or textFrame:IsA("TextBox") or textFrame:IsA("TextButton")),
		("%s cannot be converted to a TextLabel"):format(textFrame.ClassName)
	)

	return InstanceConverter(textFrame, "TextLabel")
end

function module.convert(textFrame: TextGuiObject, glyphBboxes: boolean?): (EditableImage, { GlyphBBox })
	assert(textFrame.FontFace.Family ~= Font.fromEnum(Enum.Font.Legacy).Family, "Legacy font is not supported")
	assert(textFrame.RichText == true, "RichText property must be enabled.")
	assert(textFrame.TextScaled == false, "TextScale property must be disabled.")
	assert(textFrame.TextStrokeTransparency == 1, "TextStroke is currently not supported.")
	assert(textFrame.ClipsDescendants, "ClipsDescendants == false is currently not supported.")

	assert(checkCanRender(textFrame))

	local textSize = textFrame.TextSize
	local textRect = getTextRect(textFrame)
	local textFrameAbsSize = textFrame.AbsoluteSize

	local screen = getScreenGuiForCapture(textFrame)
	screen.Parent = Players.LocalPlayer.PlayerGui

	-- some fonts take a frame to load in
	RunService.RenderStepped:Wait()

	local result: EditableImage
	screenshot(function(content: string)
		local topbarHeight = getTopbarHeight()
		local inset = Vector2.new(0, math.floor(topbarHeight * CAPTURE_SCALE) + 1)

		local editImage = AssetService:CreateEditableImageAsync(content)
		local captureSize = editImage.Size

		local function clamp(v: Vector2)
			-- stylua: ignore
			return Vector2.new(
				math.clamp(v.X, 0, captureSize.X), 
				math.clamp(v.Y, 0, captureSize.Y)
			)
		end

		editImage:Crop(clamp(inset), clamp(inset + (textFrameAbsSize * CAPTURE_SCALE)))
		editImage:Resize(textFrameAbsSize)

		result = editImage
	end)

	screen:Destroy()

	local image = Image.new(result)
	local bboxes: { GlyphBBox } = {}

	if glyphBboxes then
		bboxes = getGlyphBounds(image, textSize, textRect)
	end

	rgbChannelsToAlphaWhite(image)

	return image:Save(), bboxes
end

return module
