function dist_sqd(a, b)
  if a == nil or type(a) ~= 'table' then print('dist_sqd: a is null '..require('debug').traceback()); return end
  if b == nil or type(b) ~= 'table' then print('dist_sqd: b is null '..require('debug').traceback()); return end
  if a.x == nil or type(a.x) ~= 'number' then print('dist_sqd: a.x is null '..require('debug').traceback()); return end
  if b.x == nil or type(b.x) ~= 'number' then print('dist_sqd: b.x is null '..require('debug').traceback()); return end
  if a.y == nil or type(a.y) ~= 'number' then print('dist_sqd: a.y is null '..require('debug').traceback()); return end
  if b.y == nil or type(b.y) ~= 'number' then print('dist_sqd: b.y is null '..require('debug').traceback()); return end
	local dx = a.x-b.x
	local dy = a.y-b.y
	return (dx*dx + dy*dy)
end