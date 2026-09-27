-- Small deterministic fixtures ported from the integration suites.
local b = require('fixture_binary')
local le, be, char = b.le, b.be, string.char
local M = {}
local function pixels(w, h, pixel)
	local out = {}
	for y = 0, h - 1 do
		for x = 0, w - 1 do out[#out + 1] = pixel(x, y) end
	end
	return table.concat(out)
end
local function gradient(x, y) return char(x * 4 % 256, y * 4 % 256, (x + y) * 2 % 256) end
function M.bmp(width, pattern, height)
	width = tonumber(width) or 32
	height = tonumber(height) or width
	local stride = math.ceil(width * 3 / 4) * 4
	local rows = {}
	for y = 0, height - 1 do
		rows[#rows + 1] = pixels(width, 1, function(x)
			if pattern == 'pattern' then return char(x * 17 % 256, y * 23 % 256, (x + y) * 13 % 256) end
			return gradient(x, y)
		end) .. string.rep('\0', stride - width * 3)
	end
	local data = table.concat(rows)
	return 'BM' .. le(54 + #data, 4) .. le(0, 4) .. le(54, 4)
		.. le(40, 4) .. le(width, 4) .. le(height, 4) .. le(1, 2) .. le(24, 2)
		.. le(0, 4) .. le(#data, 4) .. le(2835, 4) .. le(2835, 4) .. le(0, 8) .. data
end
function M.tiff()
	local entries = {
		{256,4,64}, {257,4,64}, {258,3,8}, {259,3,1}, {262,3,2}, {273,4,146},
		{277,3,3}, {278,4,64}, {279,4,12288}, {284,3,1}, {296,3,2},
	}
	local out = {'II', le(42, 2), le(8, 4), le(#entries, 2)}
	for _, e in ipairs(entries) do out[#out + 1] = le(e[1],2) .. le(e[2],2) .. le(1,4) .. le(e[3],4) end
	out[#out + 1] = le(0,4) .. pixels(64,64,gradient)
	return table.concat(out)
end
function M.gif()
	return 'GIF89a' .. le(1,2) .. le(1,2) .. char(128,0,0,255,0,0,0,0,0)
		.. ',' .. le(0,4) .. le(1,2) .. le(1,2) .. char(0,2,2,0x44,1,0,0x3b)
end
function M.tga()
	return char(0,0,2) .. string.rep('\0',9) .. le(64,2) .. le(64,2) .. char(24,0) .. pixels(64,64,gradient)
end
local function pcm(big_endian)
	local samples = {}
	local pi = big_endian and 3.14159265 or math.pi
	for s = 0, 22049 do
		for c = 0, 1 do
			local value = 16384 * math.sin(2 * pi * (440 + c * 220) * s / 44100)
			value = value < 0 and math.ceil(value) or math.floor(value)
			samples[#samples + 1] = (big_endian and be or le)(value, 2)
		end
	end
	return table.concat(samples)
end
function M.wav()
	local data = pcm(false)
	return 'RIFF' .. le(36 + #data,4) .. 'WAVEfmt ' .. le(16,4) .. le(1,2) .. le(2,2)
		.. le(44100,4) .. le(176400,4) .. le(4,2) .. le(16,2) .. 'data' .. le(#data,4) .. data
end
function M.aiff()
	local data = pcm(true)
	return 'FORM' .. be(46 + #data,4) .. 'AIFFCOMM' .. be(18,4) .. be(2,2) .. be(22050,4)
		.. be(16,2) .. be(16398,2) .. be(2890137600,4) .. be(0,4)
		.. 'SSND' .. be(8 + #data,4) .. be(0,8) .. data
end
function M.fits()
	local header = {}
	for _, item in ipairs({{'SIMPLE','T'}, {'BITPIX',8}, {'NAXIS',2}, {'NAXIS1',64}, {'NAXIS2',64}}) do
		header[#header + 1] = ('%-8s= %20s%s'):format(item[1], item[2], string.rep(' ',50))
	end
	header[#header + 1] = 'END' .. string.rep(' ',77)
	local h = table.concat(header)
	return h .. string.rep(' ',2880 - #h) .. pixels(64,64,function(x,y) return char((x*17+y*23)%256) end)
		.. string.rep(' ',5760-4096)
end
function M.nifti()
	local header = string.rep('\0',352)
	local function put(offset, bytes) header = header:sub(1,offset) .. bytes .. header:sub(offset+#bytes+1) end
	put(0,le(348,4)); put(40,le(3,2)..le(32,2)..le(32,2)..le(4,2))
	put(70,le(2,2)..le(8,2)); put(108,b.float(352)); put(344,'n+1\0')
	return header .. pixels(4096,1,function(i) return char(i*17%256) end)
end
function M.dicom()
	local out = {string.rep('\0',128), 'DICM'}
	local function tag(group, element, vr, value)
		out[#out+1] = le(group,2)..le(element,2)..vr..le(#value,2)..value
	end
	tag(2,16,'UI','1.2.840.10008.1.2.1\0')
	for _, v in ipairs({{2,1},{16,64},{17,64},{256,16},{257,16}}) do tag(40,v[1],'US',le(v[2],2)) end
	out[#out+1] = le(0x7fe0,2)..le(16,2)..'OW'..le(0,2)..le(8192,4)
	out[#out+1] = pixels(64,64,function(x,y) return le((x*137+y*53)%65536,2) end)
	return table.concat(out)
end
function M.zip(args)
	local records, directory, offset = {}, {}, 0
	for i = 1, #args, 2 do
		local name, data = args[i], args[i+1] or ''
		local folder = name:sub(-1) == '/'
		if folder then data = '' end
		local method = folder and 0 or 8
		local encoded = folder and data or b.compress(data):sub(3,-5)
		local crc = b.crc(data)
		local flags = name:find('[\128-\255]') and 2048 or 0
		-- Fixed DOS timestamp: 1980-01-01 00:00:00.
		local common = le(20,2)..le(flags,2)..le(method,2)..le(0,2)..le(33,2)..le(crc,4)
			..le(#encoded,4)..le(#data,4)..le(#name,2)..le(0,2)
		local record = 'PK\003\004'..common..name..encoded
		records[#records+1] = record
		directory[#directory+1] = 'PK\001\002'..le(788,2)..common..le(0,2)..le(0,2)..le(0,2)
			..le(folder and (493*65536+16) or 384*65536,4)..le(offset,4)..name
		offset = offset + #record
	end
	local central = table.concat(directory)
	return table.concat(records)..central..'PK\005\006'..le(0,4)..le(#records,2)..le(#records,2)
		..le(#central,4)..le(offset,4)..le(0,2)
end
local function chunk(kind, data) return be(#data,4)..kind..data..be(b.crc(kind..data),4) end
function M.png(kind, width, height)
	local w, h = tonumber(width) or (kind == 'rgba' and 128 or 64), tonumber(height) or (kind == 'rgba' and 128 or 64)
	local color = ({rgba=6,rgb=2,gray=0,text=6})[kind]
	assert(color, 'unknown PNG fixture')
	local rows = {}
	for y = 0, h-1 do
		rows[#rows+1] = '\0'..pixels(w,1,function(x)
			if kind == 'rgba' then return char((x*7+y*3)%256,(x*3+y*7)%256,(x+y)%256,255) end
			if kind == 'rgb' then return char(x*5%256,y*5%256,128) end
			if kind == 'gray' then return char((x*4+y*4)%256) end
			return char(x*4%256,y*4%256,128,200)
		end)
	end
	return '\137PNG\r\n\26\n'..chunk('IHDR',be(w,4)..be(h,4)..char(8,color,0,0,0))
		..(kind == 'text' and chunk('tEXt','Author\0BlarTestSuite') or '')
		..chunk('IDAT',b.compress(table.concat(rows)))..chunk('IEND','')
end
return M
