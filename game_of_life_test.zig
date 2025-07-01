const std = @import("std");
const zecs = @import("zecs");
const SqliteWorld = zecs.SqliteWorld;
const EntityId = zecs.EntityId;
const c = @import("zsqlite").c;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== ZECS Game of Life Test (10x10) ===\n\n", .{});
    
    var world = try SqliteWorld.init(allocator, null);
    defer world.deinit();
    
    const width: u32 = 10;
    const height: u32 = 10;
    const total_cells = width * height;
    
    // Create entities for all cells
    std.debug.print("🌱 Creating {d} cell entities...\n", .{total_cells});
    const entities = try world.createEntities(total_cells);
    defer allocator.free(entities);
    
    // Initialize grid with a simple pattern (glider)
    var entity_idx: u32 = 0;
    for (0..height) |y| {
        for (0..width) |x| {
            // Create a glider pattern at position (1,1)
            const alive = (x == 1 and y == 2) or (x == 2 and y == 3) or (x == 3 and y == 1) or (x == 3 and y == 2) or (x == 3 and y == 3);
            try world.addGameOfLifeCell(entities[entity_idx], @intCast(x), @intCast(y), alive);
            entity_idx += 1;
        }
    }
    
    // Print initial state
    try printGrid(&world, width, height);
    
    // Run a few generations
    for (0..5) |gen| {
        const alive_count = try world.gameOfLifeStepNative(width, height);
        std.debug.print("\n📈 Generation {d}: {d} alive cells\n", .{ gen + 1, alive_count });
        try printGrid(&world, width, height);
    }
    
    std.debug.print("\n✅ Game of Life test complete!\n", .{});
}

fn printGrid(world: *SqliteWorld, width: u32, height: u32) !void {
    // Read current state
    const read_sql = 
        \\SELECT x, y, health_current 
        \\FROM components 
        \\WHERE component_type = 3
        \\ORDER BY y, x;
    ;
    
    var stmt: ?*c.sqlite3_stmt = null;
    var rc = c.sqlite3_prepare_v2(world.db, read_sql, -1, &stmt, null);
    if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);
    
    // Create grid
    var grid = try world.allocator.alloc(bool, width * height);
    defer world.allocator.free(grid);
    @memset(grid, false);
    
    while (true) {
        rc = c.sqlite3_step(stmt);
        if (rc == c.SQLITE_DONE) break;
        if (rc != c.SQLITE_ROW) return error.SQLiteStepFailed;
        
        const x = @as(u32, @intFromFloat(c.sqlite3_column_double(stmt, 0)));
        const y = @as(u32, @intFromFloat(c.sqlite3_column_double(stmt, 1)));
        const alive = c.sqlite3_column_int(stmt, 2) == 1;
        
        if (x < width and y < height) {
            const idx = y * width + x;
            grid[idx] = alive;
        }
    }
    
    // Print grid
    for (0..height) |y| {
        for (0..width) |x| {
            const idx = y * width + x;
            std.debug.print("{s}", .{if (grid[idx]) "█" else "·"});
        }
        std.debug.print("\n", .{});
    }
}
