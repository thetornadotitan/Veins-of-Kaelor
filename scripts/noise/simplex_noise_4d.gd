@tool
class_name SimplexNoise4D
extends RefCounted

const F4: float = 0.30901699437494745850
const G4: float = 0.13819660112578017589

var _perm: PackedByteArray

var _grad_x: PackedFloat32Array
var _grad_y: PackedFloat32Array
var _grad_z: PackedFloat32Array
var _grad_w: PackedFloat32Array


func _init(p_seed: int = 0) -> void:
	_perm = _generate_permutation(p_seed)
	_build_gradient_table()


func noise_4d(x: float, y: float, z: float, w: float) -> float:
	var s: float = (x + y + z + w) * F4
	var i: int = _fastfloor(x + s)
	var j: int = _fastfloor(y + s)
	var k: int = _fastfloor(z + s)
	var l: int = _fastfloor(w + s)
	var t: float = (i + j + k + l) * G4
	var x0: float = x - (i - t)
	var y0: float = y - (j - t)
	var z0: float = z - (k - t)
	var w0: float = w - (l - t)

	var rank_x: int = 0
	var rank_y: int = 0
	var rank_z: int = 0
	var rank_w: int = 0
	if x0 > y0:
		rank_x += 1
	else:
		rank_y += 1
	if x0 > z0:
		rank_x += 1
	else:
		rank_z += 1
	if x0 > w0:
		rank_x += 1
	else:
		rank_w += 1
	if y0 > z0:
		rank_y += 1
	else:
		rank_z += 1
	if y0 > w0:
		rank_y += 1
	else:
		rank_w += 1
	if z0 > w0:
		rank_z += 1
	else:
		rank_w += 1

	var i1: int = 0; var j1: int = 0; var k1: int = 0; var l1: int = 0
	var i2: int = 0; var j2: int = 0; var k2: int = 0; var l2: int = 0
	var i3: int = 0; var j3: int = 0; var k3: int = 0; var l3: int = 0

	if rank_x >= 3:
		i1 = 1
	if rank_y >= 3:
		j1 = 1
	if rank_z >= 3:
		k1 = 1
	if rank_w >= 3:
		l1 = 1
	if rank_x >= 2:
		i2 = 1
	if rank_y >= 2:
		j2 = 1
	if rank_z >= 2:
		k2 = 1
	if rank_w >= 2:
		l2 = 1
	if rank_x >= 1:
		i3 = 1
	if rank_y >= 1:
		j3 = 1
	if rank_z >= 1:
		k3 = 1
	if rank_w >= 1:
		l3 = 1

	var x1: float = x0 - i1 + G4
	var y1: float = y0 - j1 + G4
	var z1: float = z0 - k1 + G4
	var w1: float = w0 - l1 + G4
	var x2: float = x0 - i2 + 2.0 * G4
	var y2: float = y0 - j2 + 2.0 * G4
	var z2: float = z0 - k2 + 2.0 * G4
	var w2: float = w0 - l2 + 2.0 * G4
	var x3: float = x0 - i3 + 3.0 * G4
	var y3: float = y0 - j3 + 3.0 * G4
	var z3: float = z0 - k3 + 3.0 * G4
	var w3: float = w0 - l3 + 3.0 * G4
	var x4: float = x0 - 1.0 + 4.0 * G4
	var y4: float = y0 - 1.0 + 4.0 * G4
	var z4: float = z0 - 1.0 + 4.0 * G4
	var w4: float = w0 - 1.0 + 4.0 * G4

	var ii: int = i & 255
	var jj: int = j & 255
	var kk: int = k & 255
	var ll: int = l & 255

	var n0: float = 0.0
	var n1: float = 0.0
	var n2: float = 0.0
	var n3: float = 0.0
	var n4: float = 0.0

	var t0: float = 0.6 - x0 * x0 - y0 * y0 - z0 * z0 - w0 * w0
	if t0 > 0.0:
		t0 *= t0
		var gi: int = _perm[ii + _perm[jj + _perm[kk + _perm[ll]]]] & 31
		n0 = t0 * t0 * (_grad_x[gi] * x0 + _grad_y[gi] * y0 + _grad_z[gi] * z0 + _grad_w[gi] * w0)

	var t1: float = 0.6 - x1 * x1 - y1 * y1 - z1 * z1 - w1 * w1
	if t1 > 0.0:
		t1 *= t1
		var gi: int = _perm[ii + i1 + _perm[jj + j1 + _perm[kk + k1 + _perm[ll + l1]]]] & 31
		n1 = t1 * t1 * (_grad_x[gi] * x1 + _grad_y[gi] * y1 + _grad_z[gi] * z1 + _grad_w[gi] * w1)

	var t2: float = 0.6 - x2 * x2 - y2 * y2 - z2 * z2 - w2 * w2
	if t2 > 0.0:
		t2 *= t2
		var gi: int = _perm[ii + i2 + _perm[jj + j2 + _perm[kk + k2 + _perm[ll + l2]]]] & 31
		n2 = t2 * t2 * (_grad_x[gi] * x2 + _grad_y[gi] * y2 + _grad_z[gi] * z2 + _grad_w[gi] * w2)

	var t3: float = 0.6 - x3 * x3 - y3 * y3 - z3 * z3 - w3 * w3
	if t3 > 0.0:
		t3 *= t3
		var gi: int = _perm[ii + i3 + _perm[jj + j3 + _perm[kk + k3 + _perm[ll + l3]]]] & 31
		n3 = t3 * t3 * (_grad_x[gi] * x3 + _grad_y[gi] * y3 + _grad_z[gi] * z3 + _grad_w[gi] * w3)

	var t4: float = 0.6 - x4 * x4 - y4 * y4 - z4 * z4 - w4 * w4
	if t4 > 0.0:
		t4 *= t4
		var gi: int = _perm[ii + 1 + _perm[jj + 1 + _perm[kk + 1 + _perm[ll + 1]]]] & 31
		n4 = t4 * t4 * (_grad_x[gi] * x4 + _grad_y[gi] * y4 + _grad_z[gi] * z4 + _grad_w[gi] * w4)

	return 27.0 * (n0 + n1 + n2 + n3 + n4)


func noise_4d_fbm(x: float, y: float, z: float, w: float, octaves: int, frequency: float, persistence: float, lacunarity: float) -> float:
	var output: float = 0.0
	var denom: float = 0.0
	var amp: float = 1.0
	var freq: float = frequency
	for _i: int in range(octaves):
		output += amp * noise_4d(x * freq, y * freq, z * freq, w * freq)
		denom += amp
		freq *= lacunarity
		amp *= persistence
	return output / denom


func noise_4d_ridged_fbm(x: float, y: float, z: float, w: float, octaves: int, frequency: float, persistence: float, lacunarity: float) -> float:
	var output: float = 0.0
	var denom: float = 0.0
	var amp: float = 1.0
	var freq: float = frequency
	var weight: float = 1.0
	for _i: int in range(octaves):
		var n: float = 1.0 - absf(noise_4d(x * freq, y * freq, z * freq, w * freq))
		n = n * n
		n *= weight
		weight = clampf(n * 2.0, 0.0, 1.0)
		output += n * amp
		denom += amp
		freq *= lacunarity
		amp *= persistence
	return output / denom


static func _static_smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t: float = clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _fastfloor(x: float) -> int:
	var i: int = int(x)
	return i - 1 if x < float(i) else i


func _build_gradient_table() -> void:
	var s: float = 1.0 / sqrt(2.0)
	var grad_data: Array = [
		[1,1,0,0],[-1,1,0,0],[1,-1,0,0],[-1,-1,0,0],
		[1,0,1,0],[-1,0,1,0],[1,0,-1,0],[-1,0,-1,0],
		[0,1,1,0],[0,-1,1,0],[0,1,-1,0],[0,-1,-1,0],
		[1,0,0,1],[-1,0,0,1],[1,0,0,-1],[-1,0,0,-1],
		[0,1,0,1],[0,-1,0,1],[0,1,0,-1],[0,-1,0,-1],
		[0,0,1,1],[0,0,-1,1],[0,0,1,-1],[0,0,-1,-1],
		[1,1,0,0],[-1,1,0,0],[0,0,1,-1],[0,0,-1,-1],
		[0,1,-1,0],[0,-1,1,0],[1,0,0,-1],[-1,0,0,1],
	]
	_grad_x = PackedFloat32Array()
	_grad_y = PackedFloat32Array()
	_grad_z = PackedFloat32Array()
	_grad_w = PackedFloat32Array()
	_grad_x.resize(32)
	_grad_y.resize(32)
	_grad_z.resize(32)
	_grad_w.resize(32)
	for i: int in range(32):
		_grad_x[i] = float(grad_data[i][0]) * s
		_grad_y[i] = float(grad_data[i][1]) * s
		_grad_z[i] = float(grad_data[i][2]) * s
		_grad_w[i] = float(grad_data[i][3]) * s


func _generate_permutation(p_seed: int) -> PackedByteArray:
	var p := PackedByteArray()
	p.resize(256)
	for i: int in range(256):
		p[i] = i
	var state: int = p_seed & 0xFFFFFFFF
	for i: int in range(255, 0, -1):
		state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
		var j: int = state % (i + 1)
		var tmp: int = p[i]
		p[i] = p[j]
		p[j] = tmp
	var perm := PackedByteArray()
	perm.resize(512)
	for i: int in range(256):
		perm[i] = p[i]
		perm[256 + i] = p[i]
	return perm
