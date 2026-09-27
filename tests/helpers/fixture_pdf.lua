local b = require('fixture_binary')
local jpeg = require('fixture_jpeg')
return function(kind, count)
	count = kind == 'text' and 0 or tonumber(count) or 1
	local objects = {
		'<< /Type /Catalog /Pages 2 0 R >>',
		'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
	}
	local page = '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792]'
	if kind == 'text' then objects[3] = page..' >>'
	else
		local refs = {}
		for i = 0, count-1 do refs[#refs+1] = ('/Im%d %d 0 R'):format(i,4+i) end
		objects[3] = page..' /Resources << /XObject << '..table.concat(refs,' ')..' >> >> >>'
	end
	for _ = 1, count do
		local stream = kind == 'flate' and b.compress(string.rep('\255\0\0',64)) or jpeg
		local filter = kind == 'flate' and 'FlateDecode' or 'DCTDecode'
		objects[#objects+1] = '<< /Type /XObject /Subtype /Image /Width 8 /Height 8'
			..' /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /'..filter..' /Length '..#stream..' >>'
			..'\nstream\n'..stream..'\nendstream'
	end
	if kind == 'encrypted' then objects[#objects+1] = '<< /Filter /Standard /V 1 /R 2 /O (fake) /U (fake) /P -44 >>' end
	local out, offsets, size = {'%PDF-1.4\n'}, {}, 9
	for i, obj in ipairs(objects) do
		offsets[i] = size
		local record = i..' 0 obj\n'..obj..'\nendobj\n'
		out[#out+1] = record; size = size+#record
	end
	out[#out+1] = 'xref\n0 '..(#objects+1)..'\n0000000000 65535 f \n'
	for _, offset in ipairs(offsets) do out[#out+1] = ('%010d 00000 n \n'):format(offset) end
	out[#out+1] = 'trailer\n<< /Size '..(#objects+1)..' /Root 1 0 R'
		..(kind == 'encrypted' and ' /Encrypt 5 0 R' or '')..' >>\nstartxref\n'..size..'\n%%EOF\n'
	return table.concat(out)
end
