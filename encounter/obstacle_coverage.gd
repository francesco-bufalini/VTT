extends RefCounted

# Exact union of XZ rectangles; overlapping obstacles are counted only once.
static func fraction(sweep: AABB, obstacles: Array[AABB], minimum_height: float) -> float:
	var rectangles: Array[Rect2] = []
	var xs: Array[float] = []
	for box in obstacles:
		if box.size.y < minimum_height or not sweep.intersects(box):
			continue
		var overlap := sweep.intersection(box)
		var rect := Rect2(overlap.position.x, overlap.position.z, overlap.size.x, overlap.size.z)
		if rect.has_area():
			rectangles.append(rect)
			xs.append(rect.position.x)
			xs.append(rect.end.x)
	xs.sort()
	var area: float = 0
	for index in range(1, xs.size()):
		var width := xs[index] - xs[index - 1]
		if width <= 0:
			continue
		var intervals: Array[Vector2] = []
		for rect in rectangles:
			if rect.position.x < xs[index] and rect.end.x > xs[index - 1]:
				intervals.append(Vector2(rect.position.y, rect.end.y))
		intervals.sort_custom(func(a: Vector2, b: Vector2): return a.x < b.x)
		var end: float = -INF
		var length: float = 0
		for interval in intervals:
			length += maxf(0, interval.y - maxf(end, interval.x))
			end = maxf(end, interval.y)
		area += width * length
	return area / (sweep.size.x * sweep.size.z)
