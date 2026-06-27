class_name ChunkWorker
extends RefCounted

enum TaskType {
	LOAD,
	LOD_UPDATE,
}

var _thread: Thread = null
var _semaphore: Semaphore = Semaphore.new()
var _mutex: Mutex = Mutex.new()
var _queue: Array[Dictionary] = []
var _completed: Array[Dictionary] = []
var _running: bool = false


func start() -> void:
	if _running:
		return
	_running = true
	_thread = Thread.new()
	_thread.start(_worker_loop)


func stop() -> void:
	if not _running:
		return
	_running = false
	_semaphore.post()
	if _thread and _thread.is_alive():
		_thread.wait_to_finish()
	_thread = null


func push_task(task_type: int, chunk_pos: Vector2i, chunk_data: ChunkData, lod: int, needs_collision: bool) -> void:
	_mutex.lock()
	_queue.append({
		"type": task_type,
		"chunk_pos": chunk_pos,
		"chunk_data": chunk_data,
		"lod": lod,
		"needs_collision": needs_collision,
	})
	_mutex.unlock()
	_semaphore.post()


func pop_completed() -> Array[Dictionary]:
	_mutex.lock()
	var results: Array[Dictionary] = _completed.duplicate()
	_completed.clear()
	_mutex.unlock()
	return results


func _worker_loop() -> void:
	while _running:
		_semaphore.wait()
		if not _running:
			break
		while true:
			var task: Dictionary = _dequeue_task()
			if task.is_empty():
				break
			var result: Dictionary = _process_task(task)
			if result.is_empty():
				continue
			_mutex.lock()
			_completed.append(result)
			_mutex.unlock()


func _dequeue_task() -> Dictionary:
	_mutex.lock()
	if _queue.is_empty():
		_mutex.unlock()
		return {}
	var task: Dictionary = _queue.pop_front()
	_mutex.unlock()
	return task


func _process_task(task: Dictionary) -> Dictionary:
	var chunk_data: ChunkData = task["chunk_data"]
	if chunk_data == null or chunk_data.heightmap.is_empty():
		return {}
	var t0: int = Time.get_ticks_usec()
	var lod: int = task["lod"]
	var mesh: ArrayMesh = TerrainMeshBuilder.build_chunk_mesh(chunk_data, lod)
	var mesh_usec: int = Time.get_ticks_usec() - t0
	var shape: ConcavePolygonShape3D = null
	var shape_usec: int = 0
	if task["needs_collision"]:
		var ts0: int = Time.get_ticks_usec()
		shape = CollisionGenerator.build_collision_shape(chunk_data)
		shape_usec = Time.get_ticks_usec() - ts0
	var total_usec: int = Time.get_ticks_usec() - t0
	return {
		"type": task["type"],
		"chunk_pos": task["chunk_pos"],
		"lod": lod,
		"mesh": mesh,
		"shape": shape,
		"needs_collision": task["needs_collision"],
		"build_usec": total_usec,
		"mesh_usec": mesh_usec,
		"shape_usec": shape_usec,
	}
