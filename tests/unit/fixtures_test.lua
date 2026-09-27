-- Fixed format fields and external unzip checks complement the archive roundtrips.
package.path = arg[0]:match('^(.*)/unit/') .. '/helpers/?.lua;' .. package.path
local fixtures = require('fixture_formats')
local png = require('png_pixels')
local function eq(a, b) assert(a == b, ('expected %q, got %q'):format(tostring(b), tostring(a))) end
local n = 0
local function check(fn) fn(); n = n + 1 end
check(function() eq(#fixtures.bmp(32, 'pattern'), 3126) end)
check(function() eq(fixtures.bmp(32, 'pattern'):sub(1, 6), 'BM\054\012\000\000') end)
check(function() eq(fixtures.bmp(32, 'pattern'):sub(55, 60), '\000\000\000\017\000\013') end)
check(function() eq(#fixtures.bmp(64, 'gradient'), 12342) end)
check(function() eq(#fixtures.bmp(3, 'gradient', 2), 78) end)
check(function() eq(fixtures.bmp(3, 'gradient', 2):sub(19,26), '\003\000\000\000\002\000\000\000') end)
check(function() eq(#fixtures.tiff(), 12434) end)
check(function() eq(fixtures.gif(), 'GIF89a\001\000\001\000\128\000\000\255\000\000\000\000\000,\000\000\000\000\001\000\001\000\000\002\002\068\001\000;') end)
check(function() eq(#fixtures.tga(), 12306) end)
check(function() eq(#fixtures.wav(), 88244) end)
check(function() eq(#fixtures.aiff(), 88254) end)
check(function() eq(fixtures.aiff():sub(29, 38), '\064\014\172\068\000\000\000\000\000\000') end)
check(function() eq(#fixtures.fits(), 8640) end)
check(function() eq(fixtures.fits():sub(2881, 2883), '\000\017\034') end)
check(function() eq(#fixtures.nifti(), 4448) end)
check(function() eq(fixtures.nifti():sub(345, 352), 'n+1\000\000\000\000\000') end)
check(function() eq(fixtures.nifti():sub(353, 355), '\000\017\034') end)
check(function() eq(#fixtures.dicom(), 8414) end)
check(function() eq(fixtures.dicom():sub(129, 132), 'DICM') end)
check(function() eq(fixtures.zip({}), 'PK\005\006' .. string.rep('\000', 18)) end)
-- Two rows of three 8-bit grayscale pixels: 10,20,30 and 15,25,35.
local expected = '\010\020\030\015\025\035'
local filters = {
	'\000\010\020\030\000\015\025\035',
	'\001\010\010\010\001\015\010\010',
	'\002\010\020\030\002\005\005\005',
	'\003\010\015\020\003\010\008\008',
	'\004\010\010\010\004\005\005\005',
}
for _, raw in ipairs(filters) do
	check(function() eq(png.unfilter(raw, 3, 2, 1), expected) end)
end
check(function() assert(not pcall(png.unfilter, '\005\010\020\030', 3, 1, 1)) end)
check(function() assert(not pcall(png.unfilter, '\000\010', 3, 1, 1)) end)
check(function() assert(not pcall(png.parse, 'not a PNG')) end)
check(function() local s = fixtures.png('rgba', 8, 8); eq(png.parse(s), png.parse(s)) end)
check(function() assert(png.parse(fixtures.png('rgb')) ~= png.parse(fixtures.png('gray'))) end)
check(function() assert(png.parse(fixtures.png('rgba', 4, 8)) ~= png.parse(fixtures.png('rgba', 8, 4))) end)
check(function() eq(png.unfilter('\001\001\002\003\003\004\005',6,1,3), '\001\002\003\004\006\008') end)
check(function() eq(png.unfilter('\001\250\020',2,1,1), '\250\014') end)
check(function()
	local s = fixtures.png('rgba',8,8)
	assert(not pcall(png.parse, s:sub(1,29)..'bad!'..s:sub(34)))
end)
check(function()
	local s = fixtures.png('rgba',8,8)
	assert(not pcall(png.parse, s:sub(1,-13)))
end)
for _, kind in ipairs({'jpeg','text','flate','encrypted'}) do
	check(function()
		local pdf = require('fixture_pdf')(kind)
		local xref = assert(tonumber(pdf:match('startxref\n(%d+)\n%%%%EOF\n$')))
		eq(pdf:sub(xref+1,xref+5),'xref\n')
		local object = 0
		for offset in pdf:sub(xref+1):gmatch('(%d+) 00000 n \n') do
			object = object+1
			local marker = object..' 0 obj\n'
			eq(pdf:sub(tonumber(offset)+1,tonumber(offset)+#marker),marker)
		end
		eq(object, kind == 'text' and 3 or kind == 'encrypted' and 5 or 4)
	end)
end
print(('Results: %d passed, 0 failed'):format(n))
