--!strict

local Image = {}
Image.__index = Image
Image.ClassName = "Image"

type self = {
	pixels: { number },
	size: Vector2,
}

export type Image = typeof(setmetatable({} :: self, Image))

-- CONSTANTS

local NEIGHBOR_OFFSETS: { { number } } = {
	{ -1, -1 },
	{ 0, -1 },
	{ 1, -1 },
	{ -1, 0 },
	{ 1, 0 },
	{ -1, 1 },
	{ 0, 1 },
	{ 1, 1 },
}

-- Constructors

function Image.new(editableImage: EditableImage): Image
	local self = setmetatable({}, Image)

	self.size = editableImage.Size
	self.pixels = editableImage:ReadPixels(Vector2.zero, self.size)

	return self
end

-- Public Methods

function Image.GetPixelIndex(self: Image, x: number, y: number): number
	return (y - 1) * self.size.X + x
end

function Image.GetXYFromPixelIndex(self: Image, pixelIndex: number): (number, number)
	local y = math.floor((pixelIndex - 1) / self.size.X) + 1
	local x = pixelIndex - ((y - 1) * self.size.X)
	return x, y
end

function Image.GetNeighbors(self: Image, pixelIndex: number): { number }
	local width = self.size.X
	local height = self.size.Y

	local x, y = self:GetXYFromPixelIndex(pixelIndex)

	local neighbors = {}
	for _, offset in NEIGHBOR_OFFSETS do
		local xn = x + offset[1]
		local yn = y + offset[2]

		if xn < 1 or xn > width or yn < 1 or yn > height then
			continue
		end

		table.insert(neighbors, self:GetPixelIndex(xn, yn))
	end

	return neighbors
end

function Image.GetRGBA(self: Image, pixelIndex: number): (number, number, number, number)
	local pixels = self.pixels
	local i = ((pixelIndex - 1) * 4) + 1
	return pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]
end

function Image.SetRGBA(self: Image, pixelIndex: number, r: number, g: number, b: number, a: number)
	local pixels = self.pixels
	local i = ((pixelIndex - 1) * 4) + 1

	pixels[i] = r
	pixels[i + 1] = g
	pixels[i + 2] = b
	pixels[i + 3] = a
end

function Image.Save(self: Image): EditableImage
	local editImage = Instance.new("EditableImage")
	editImage.Size = self.size
	editImage:WritePixels(Vector2.zero, self.size, self.pixels)
	return editImage
end

--

return Image
