-- Binary primitives for deterministic test inputs. No archive implementation imports.
local ffi = require('ffi')
ffi.cdef[[
unsigned long compressBound(unsigned long);
int compress2(unsigned char *, unsigned long *, const unsigned char *, unsigned long, int);
int uncompress(unsigned char *, unsigned long *, const unsigned char *, unsigned long);
unsigned long crc32(unsigned long, const unsigned char *, unsigned int);
]]
local z = ffi.load(os.getenv('BLAR_TEST_ZLIB') or 'z')
local M = {}
function M.le(n, size)
	local bytes = {}
	for i = 1, size do bytes[i] = string.char(n % 256); n = math.floor(n / 256) end
	return table.concat(bytes)
end
function M.be(n, size) return M.le(n, size):reverse() end
function M.float(n)
	local value = ffi.new('float[1]', n)
	local bytes = ffi.string(value, 4)
	return ffi.abi('le') and bytes or bytes:reverse()
end
function M.crc(data) return tonumber(z.crc32(0, data, #data)) end
function M.compress(data)
	local size = ffi.new('unsigned long[1]', z.compressBound(#data))
	local buf = ffi.new('unsigned char[?]', size[0])
	assert(z.compress2(buf, size, data, #data, 6) == 0, 'zlib compression failed')
	return ffi.string(buf, size[0])
end
function M.decompress(data, expected)
	assert(expected > 0 and expected <= 64 * 1024 * 1024, 'invalid fixture image size')
	local size = ffi.new('unsigned long[1]', expected)
	local buf = ffi.new('unsigned char[?]', expected)
	assert(z.uncompress(buf, size, data, #data) == 0 and tonumber(size[0]) == expected, 'invalid PNG payload')
	return ffi.string(buf, size[0])
end
function M.read(path)
	local f = assert(io.open(path, 'rb'))
	local data = assert(f:read('*a')); assert(f:close()); return data
end
function M.write(path, data)
	local f = assert(io.open(path, 'wb'))
	assert(f:write(data)); assert(f:close())
end
return M
