-- PNG oracle independent of blar: validate chunks, inflate, and undo row filters.
local b = require('fixture_binary')
local M = {}
local function paeth(a, c, d)
	local p = a+c-d
	local da, dc, dd = math.abs(p-a), math.abs(p-c), math.abs(p-d)
	if da <= dc and da <= dd then return a end
	return dc <= dd and c or d
end
function M.unfilter(raw, row_bytes, height, bpp)
	assert(#raw == (row_bytes+1)*height, 'wrong PNG scanline size')
	local previous, rows, pos = {}, {}, 1
	for _ = 1, height do
		local filter = raw:byte(pos); pos = pos+1
		assert(filter <= 4, 'unknown PNG filter')
		local row, bytes = {}, {}
		for x = 1, row_bytes do
			local left, up, corner = row[x-bpp] or 0, previous[x] or 0, previous[x-bpp] or 0
			local predictor = 0
			if filter == 1 then predictor = left
			elseif filter == 2 then predictor = up
			elseif filter == 3 then predictor = math.floor((left+up)/2)
			elseif filter == 4 then predictor = paeth(left,up,corner) end
			row[x] = (raw:byte(pos)+predictor)%256; pos = pos+1
			bytes[x] = string.char(row[x])
		end
		previous = row; rows[#rows+1] = table.concat(bytes)
	end
	return table.concat(rows)
end
local function u32(s, p)
	local a,c,d,e = s:byte(p,p+3)
	assert(e, 'truncated PNG integer')
	return ((a*256+c)*256+d)*256+e
end
function M.parse(data)
	assert(data:sub(1,8) == '\137PNG\r\n\26\n', 'invalid PNG signature')
	local pos, header, parts, ended = 9, nil, {}, false
	while pos <= #data do
		local length = u32(data,pos)
		local kind, payload = data:sub(pos+4,pos+7), data:sub(pos+8,pos+7+length)
		assert(#payload == length and b.crc(kind..payload) == u32(data,pos+8+length), 'invalid PNG chunk')
		if kind == 'IHDR' then
			assert(not header and pos == 9 and length == 13, 'invalid PNG header'); header = payload
		elseif kind == 'IDAT' then parts[#parts+1] = payload
		elseif kind == 'IEND' then
			assert(length == 0 and pos+12 == #data+1, 'invalid PNG end'); ended = true; break
		end
		pos = pos+12+length
	end
	assert(header and ended, 'incomplete PNG')
	local width, height, depth, color = u32(header,1), u32(header,5), header:byte(9), header:byte(10)
	local channels = ({[0]=1,[2]=3,[4]=2,[6]=4})[color]
	assert(channels and (depth == 8 or depth == 16) and header:sub(11) == '\0\0\0', 'unsupported fixture PNG')
	assert(width > 0 and height > 0, 'empty PNG')
	local bpp = channels*depth/8
	local raw = b.decompress(table.concat(parts),(width*bpp+1)*height)
	return header .. M.unfilter(raw,width*bpp,height,bpp)
end
return M
