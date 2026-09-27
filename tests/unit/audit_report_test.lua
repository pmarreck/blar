package.path = arg[0]:match('^(.*)/unit/') .. '/helpers/?.lua;' .. package.path
local report = require('audit_report')
local csv = 'format,generator,path,size,archive_size,byte_identical,residual_bytes,residual_ratio,time_ms\r\n'
	..'png,zlib,"a, ""quote""\nnext.png",100,80,true,,,10\r\n'
	..'zip,office,b.docx,100,80,false,2,0.0200,20\r\n'
	..'zip,office,c.docx,100,80,false,4,0.0400,20\r\n'
	..'pdf,jpeg,d.pdf,100,,FAIL_CREATE,,,,\r\n'
local rows = report.parse(csv)
assert(#rows == 4 and rows[1].path == 'a, "quote"\nnext.png')
assert(not pcall(report.parse, 'a,b\n"unclosed,b'))
local md = report.render(rows, 'test')
assert(md:find('Byte-identical: **1 / 4 (25.0%)**',1,true))
assert(md:find('| zip | office | 2 | 0/2 (0%) | 4 | 0.0400 | difz backstop: feasible |',1,true))
assert(md:find('`pdf/jpeg/d.pdf`',1,true))
assert(md:find('Failed (create/extract error): 1',1,true))
local empty = report.render({}, 'empty')
assert(empty:find('0 / 0 (0.0%)',1,true))
print('Results: 7 passed, 0 failed')
