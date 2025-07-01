const std = @import("std");
const zecs = @import("zecs");
const SqliteWorld = zecs.SqliteWorld;
const EntityId = zecs.EntityId;

const GameOfLifeConfig = struct {
    width: u32,
    height: u32,
    generations: u32,
    initial_density: f32 = 0.3, // 30% of cells start alive
    print_every: u32 = 10,
    use_persistence: bool = false,
};

const CellState = enum(u8) {
    dead = 0,
    alive = 1,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== ZECS Game of Life Benchmark ===\n\n", .{});
    
    // Test different scales
    const test_cases = [_]GameOfLifeConfig{
        .{ .width = 50, .height = 50, .generations = 100, .use_persistence = false },     // Small: 2,500 cells
        .{ .width = 50, .height = 50, .generations = 100, .use_persistence = true },      // Small with persistence
        .{ .width = 100, .height = 100, .generations = 100, .use_persistence = false },  // Medium: 10,000 cells
        .{ .width = 100, .height = 100, .generations = 100, .use_persistence = true },   // Medium with persistence
        .{ .width = 200, .height = 200, .generations = 50, .use_persistence = false },   // Large: 40,000 cells
        .{ .width = 300, .height = 300, .generations = 25, .use_persistence = false },   // Huge: 90,000 cells
        .{ .width = 500, .height = 500, .generations = 10, .use_persistence = false },   // Massive: 250,000 cells
    };
    
    for (test_cases, 0..) |config, i| {
        const mode = if (config.use_persistence) "Hybrid" else "Memory";
        std.debug.print("🧪 Test {d}: {s} - {d}x{d} grid ({d} cells, {d} generations)\n", .{
            i + 1, mode, config.width, config.height, config.width * config.height, config.generations
        });
        
        const result = try runGameOfLife(allocator, config);
        
        const cells_per_sec = @as(f64, @floatFromInt(config.width * config.height * config.generations)) / (result.duration_ms / 1000.0);
        const generations_per_sec = @as(f64, @floatFromInt(config.generations)) / (result.duration_ms / 1000.0);
        
        std.debug.print("  ⏱️  Duration: {d:.2}ms\n", .{result.duration_ms});
        std.debug.print("  🎯 Cell updates/sec: {d:.0}\n", .{cells_per_sec});
        std.debug.print("  🚀 Generations/sec: {d:.1}\n", .{generations_per_sec});
        std.debug.print("  📊 Final alive cells: {d}/{d} ({d:.1}%)\n", .{
            result.final_alive, config.width * config.height,
            @as(f64, @floatFromInt(result.final_alive)) / @as(f64, @floatFromInt(config.width * config.height)) * 100.0
        });
        
        if (generations_per_sec >= 60.0) {
            std.debug.print("  ✅ REAL-TIME: Can run at 60+ generations/sec!\n", .{});
        } else if (generations_per_sec >= 30.0) {
            std.debug.print("  ✅ SMOOTH: Can run at 30+ generations/sec\n", .{});
        } else if (generations_per_sec >= 10.0) {
            std.debug.print("  ⚡ GOOD: Can run at 10+ generations/sec\n", .{});
        } else {
            std.debug.print("  ⏳ SLOW: Only {d:.1} generations/sec\n", .{generations_per_sec});
        }
        
        std.debug.print("\n", .{});
        
        // Brief pause between tests
        std.time.sleep(500 * std.time.ns_per_ms);
    }
    
    std.debug.print("🏆 ZECS Game of Life Benchmark Complete!\n", .{});
    std.debug.print("This demonstrates our ECS can handle massive simultaneous entity updates.\n", .{});
}

const GameOfLifeResult = struct {
    duration_ms: f64,
    final_alive: u32,
    generations_completed: u32,
};

fn runGameOfLife(allocator: std.mem.Allocator, config: GameOfLifeConfig) !GameOfLifeResult {
    const db_path: ?[]const u8 = if (config.use_persistence) "game_of_life.db" else null;
    
    var world = try SqliteWorld.init(allocator, db_path);
    defer world.deinit();
    
    if (config.use_persistence) {
        try world.startPersistence();
    }
    
    const start_time = std.time.nanoTimestamp();
    
    // Initialize the grid
    std.debug.print("  🌱 Initializing {d}x{d} grid...\n", .{ config.width, config.height });
    const total_cells = config.width * config.height;
    const entities = try world.createEntities(total_cells);
    defer allocator.free(entities);
    
    // Create a lookup table for entity IDs by grid position
    var grid = try allocator.alloc(EntityId, total_cells);
    defer allocator.free(grid);
    
    // Initialize cells with random life
    var rng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    var initial_alive: u32 = 0;
    
    for (0..config.height) |y| {
        for (0..config.width) |x| {
            const idx = y * config.width + x;
            const entity_id = entities[idx];
            grid[idx] = entity_id;
            
            // Add position component (x, y coordinates)
            try world.addPosition(entity_id, @floatFromInt(x), @floatFromInt(y));
            
            // Add health component to represent cell state (0 = dead, 1 = alive)
            const is_alive = rng.random().float(f32) < config.initial_density;
            const state: i32 = if (is_alive) 1 else 0;
            try world.addHealth(entity_id, state, 1); // current = state, max = 1
            
            if (is_alive) initial_alive += 1;
        }
    }
    
    std.debug.print("  🔥 Initial alive cells: {d}/{d} ({d:.1}%)\n", .{
        initial_alive, total_cells,
        @as(f64, @floatFromInt(initial_alive)) / @as(f64, @floatFromInt(total_cells)) * 100.0
    });
    
    // Run Game of Life generations
    var generation: u32 = 0;
    while (generation < config.generations) : (generation += 1) {
        try runGameOfLifeGeneration(&world, allocator, grid, config.width, config.height);
        
        if (generation % config.print_every == 0) {
            const alive_count = try countAliveCells(&world);
            std.debug.print("  📈 Generation {d}: {d} alive cells\n", .{ generation, alive_count });
        }
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration_ns = end_time - start_time;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    
    const final_alive = try countAliveCells(&world);
    
    return GameOfLifeResult{
        .duration_ms = duration_ms,
        .final_alive = final_alive,
        .generations_completed = generation,
    };
}

fn runGameOfLifeGeneration(
    world: *SqliteWorld,
    allocator: std.mem.Allocator,
    grid: []const EntityId,
    width: u32,
    height: u32,
) !void {
    // Step 1: Count neighbors for all cells
    var neighbor_counts = try allocator.alloc(u8, grid.len);
    defer allocator.free(neighbor_counts);
    
    // Get current cell states
    var cell_states = try getCellStates(world, allocator);
    defer cell_states.deinit();
    
    // Count neighbors for each cell
    for (0..height) |y| {
        for (0..width) |x| {
            const idx = y * width + x;
            var neighbors: u8 = 0;
            
            // Check all 8 neighbors
            for (0..3) |dy| {
                for (0..3) |dx| {
                    if (dx == 1 and dy == 1) continue; // Skip self
                    
                    const ny = @as(i32, @intCast(y)) + @as(i32, @intCast(dy)) - 1;
                    const nx = @as(i32, @intCast(x)) + @as(i32, @intCast(dx)) - 1;
                    
                    if (ny >= 0 and ny < height and nx >= 0 and nx < width) {
                        const neighbor_idx = @as(usize, @intCast(ny)) * width + @as(usize, @intCast(nx));
                        const neighbor_entity = grid[neighbor_idx];
                        
                        if (cell_states.get(neighbor_entity)) |state| {
                            if (state == 1) neighbors += 1;
                        }
                    }
                }
            }
            
            neighbor_counts[idx] = neighbors;
        }
    }
    
    // Step 2: Apply Game of Life rules and batch update
    var updates = std.ArrayList(CellUpdate).init(allocator);
    defer updates.deinit();
    
    for (0..grid.len) |idx| {
        const entity_id = grid[idx];
        const current_state = cell_states.get(entity_id) orelse 0;
        const neighbors = neighbor_counts[idx];
        
        // Game of Life rules:
        // 1. Live cell with 2-3 neighbors survives
        // 2. Dead cell with exactly 3 neighbors becomes alive
        // 3. All other cells die or stay dead
        const new_state: i32 = switch (current_state) {
            1 => if (neighbors == 2 or neighbors == 3) 1 else 0, // Alive cell
            0 => if (neighbors == 3) 1 else 0,                   // Dead cell
            else => 0,
        };
        
        if (new_state != current_state) {
            try updates.append(.{ .entity_id = entity_id, .new_state = new_state });
        }
    }
    
    // Step 3: Batch update all changed cells
    try batchUpdateCellStates(world, updates.items);
}

const CellUpdate = struct {
    entity_id: EntityId,
    new_state: i32,
};

fn getCellStates(world: *SqliteWorld, allocator: std.mem.Allocator) !std.AutoHashMap(EntityId, i32) {
    var states = std.AutoHashMap(EntityId, i32).init(allocator);
    
    const query_sql = 
        \\SELECT entity_id, health_current
        \\FROM components
        \\WHERE component_type = 3;
    ;
    
    const zsqlite = @import("zsqlite");
    var stmt: ?*zsqlite.c.sqlite3_stmt = null;
    var rc = zsqlite.c.sqlite3_prepare_v2(world.db, query_sql, -1, &stmt, null);
    if (rc != zsqlite.c.SQLITE_OK) return error.SQLitePrepareFailed;
    defer _ = zsqlite.c.sqlite3_finalize(stmt);
    
    while (true) {
        rc = zsqlite.c.sqlite3_step(stmt);
        if (rc == zsqlite.c.SQLITE_DONE) break;
        if (rc != zsqlite.c.SQLITE_ROW) return error.SQLiteStepFailed;
        
        const entity_id = @as(EntityId, @intCast(zsqlite.c.sqlite3_column_int64(stmt, 0)));
        const state = @as(i32, @intCast(zsqlite.c.sqlite3_column_int(stmt, 1)));
        
        try states.put(entity_id, state);
    }
    
    return states;
}

fn batchUpdateCellStates(world: *SqliteWorld, updates: []const CellUpdate) !void {
    if (updates.len == 0) return;
    
    // Use a transaction for batch updates
    try world.execSql("BEGIN TRANSACTION;");
    
    const update_sql = 
        \\UPDATE components 
        \\SET health_current = ? 
        \\WHERE entity_id = ? AND component_type = 3;
    ;
    
    const zsqlite = @import("zsqlite");
    var stmt: ?*zsqlite.c.sqlite3_stmt = null;
    var rc = zsqlite.c.sqlite3_prepare_v2(world.db, update_sql, -1, &stmt, null);
    if (rc != zsqlite.c.SQLITE_OK) return error.SQLitePrepareFailed;
    defer _ = zsqlite.c.sqlite3_finalize(stmt);
    
    for (updates) |update| {
        rc = zsqlite.c.sqlite3_bind_int(stmt, 1, update.new_state);
        if (rc != zsqlite.c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = zsqlite.c.sqlite3_bind_int64(stmt, 2, update.entity_id);
        if (rc != zsqlite.c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = zsqlite.c.sqlite3_step(stmt);
        if (rc != zsqlite.c.SQLITE_DONE) return error.SQLiteStepFailed;
        
        _ = zsqlite.c.sqlite3_reset(stmt);
    }
    
    try world.execSql("COMMIT;");
}

fn countAliveCells(world: *SqliteWorld) !u32 {
    const count_sql = 
        \\SELECT COUNT(*) 
        \\FROM components 
        \\WHERE component_type = 3 AND health_current = 1;
    ;
    
    const zsqlite = @import("zsqlite");
    var stmt: ?*zsqlite.c.sqlite3_stmt = null;
    var rc = zsqlite.c.sqlite3_prepare_v2(world.db, count_sql, -1, &stmt, null);
    if (rc != zsqlite.c.SQLITE_OK) return error.SQLitePrepareFailed;
    defer _ = zsqlite.c.sqlite3_finalize(stmt);
    
    rc = zsqlite.c.sqlite3_step(stmt);
    if (rc != zsqlite.c.SQLITE_ROW) return error.SQLiteStepFailed;
    
    return @as(u32, @intCast(zsqlite.c.sqlite3_column_int64(stmt, 0)));
}
