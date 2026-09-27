-- CSV audit aggregation, including quoted commas, quotes, and multiline paths.
local M = {}
function M.parse(csv)
	local rows, row, field, quoted, closed, i = {}, {}, {}, false, false, 1
	local function finish_field() row[#row+1] = table.concat(field); field = {}; closed = false end
	while i <= #csv do
		local c = csv:sub(i,i)
		if quoted then
			if c == '"' then
				if csv:sub(i+1,i+1) == '"' then field[#field+1] = '"'; i = i+1
				else quoted = false; closed = true end
			else field[#field+1] = c end
		elseif c == '"' and #field == 0 and not closed then quoted = true
		elseif c == ',' then finish_field()
		elseif c == '\n' or c == '\r' then
			finish_field(); rows[#rows+1] = row; row = {}
			if c == '\r' and csv:sub(i+1,i+1) == '\n' then i = i+1 end
		else assert(not closed and c ~= '"', 'invalid CSV quoting'); field[#field+1] = c end
		i = i+1
	end
	assert(not quoted, 'unclosed CSV quote')
	if #field > 0 or #row > 0 or closed then finish_field(); rows[#rows+1] = row end
	local header, records = rows[1] or {}, {}
	for index = 2, #rows do
		local record = {}
		for col, name in ipairs(header) do record[name] = rows[index][col] or '' end
		records[#records+1] = record
	end
	return records
end
local function median(rows, key)
	local numbers = {}
	for _, r in ipairs(rows) do
		local value = tonumber(r[key])
		if value then numbers[#numbers+1] = value end
	end
	table.sort(numbers)
	-- Preserve the former report's upper-middle value for even-size groups.
	return numbers[math.floor(#numbers/2)+1]
end
function M.render(records, title)
	local out, groups, order, failures, identical, diverged = {}, {}, {}, {}, 0, 0
	local function write(fmt, ...) out[#out+1] = fmt:format(...) end
	for _, r in ipairs(records) do
		if r.byte_identical == 'true' then identical = identical+1 end
		if r.byte_identical == 'false' then diverged = diverged+1 end
		if r.byte_identical:match('^FAIL') then failures[#failures+1] = r end
		local key = r.format..'\0'..r.generator
		if not groups[key] then groups[key] = {}; order[#order+1] = key end
		groups[key][#groups[key]+1] = r
	end
	write('# blar byte-identity audit — %s\n\nTotal files audited: **%d**\n\n',title,#records)
	write('- Byte-identical: **%d / %d (%.1f%%)**\n',identical,#records,100*identical/math.max(1,#records))
	write('- Diverged (content-only): %d\n- Failed (create/extract error): %d\n\n',diverged,#failures)
	write('## Per-format breakdown\n\n| Format | Generator | N | Byte-identical | Median residual | Median ratio | Notes |\n')
	write('|---|---|---|---|---|---|---|\n')
	table.sort(order)
	for _, key in ipairs(order) do
		local rows, count = groups[key], 0
		for _, r in ipairs(rows) do if r.byte_identical == 'true' then count = count+1 end end
		local residual, ratio = median(rows,'residual_bytes'), median(rows,'residual_ratio')
		local note = ''
		if ratio then
			if ratio < 0.01 then note = 'difz backstop: tiny patch — viable'
			elseif ratio < 0.5 then note = 'difz backstop: feasible'
			else note = 'difz backstop: patch too large; raw-store wins' end
		end
		write('| %s | %s | %d | %d/%d (%.0f%%) | %s | %s | %s |\n', rows[1].format, rows[1].generator,
			#rows,count,#rows,100*count/#rows,residual and tostring(residual) or '',ratio and ('%.4f'):format(ratio) or '',note)
	end
	write('\n## Failures\n\n')
	if #failures == 0 then write('(none)\n') end
	for i = 1, math.min(50,#failures) do
		local r = failures[i]; write('- `%s/%s/%s` — %s\n',r.format,r.generator,r.path,r.byte_identical)
	end
	if #failures > 50 then write('- ... and %d more\n',#failures-50) end
	return table.concat(out)
end
return M
