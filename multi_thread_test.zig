const std = @import("std");
const SqliteWorld = @import("zecs").SqliteWorld;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== Multi-threaded SQLite ECS Test ===\n\n", .{});
    
    // Test 1: Pure memory mode (fastest)
    std.debug.print("🧠 Test 1: Pure Memory Mode\n", .{});
    var memory_world = try SqliteWorld.init(allocator, null);  // No persistence path
    defer memory_world.deinit();
    
    const start_memory = std.time.nanoTimestamp();
    try testPerformance(&memory_world, allocator, "Memory");
    const end_memory = std.time.nanoTimestamp();
    const memory_duration = @as(f64, @floatFromInt(end_memory - start_memory)) / 1_000_000.0;
    
    std.debug.print("Memory mode completed in {d:.2}ms\n\n", .{memory_duration});
    
    // Test 2: Hybrid mode (memory + background persistence)
    std.debug.print("🚀 Test 2: Hybrid Mode (Memory + Background Persistence)\n", .{});

    // Ensure persistent DB is deleted before hybrid test
    std.fs.cwd().deleteFile("persistent_world.db") catch |err| {
        if (err != error.FileNotFound) return err;
    };
    // Create schema before any SqliteWorld opens the DB
    {
        const zsqlite = @import("zsqlite");
        const c = zsqlite.c;
        var db: ?*c.sqlite3 = null;
        if (c.sqlite3_open("persistent_world.db", &db) != c.SQLITE_OK) return error.SQLiteOpenFailed;
        defer _ = c.sqlite3_close(db);

        // Create tables with correct schema
        const entities_sql =
            \\CREATE TABLE IF NOT EXISTS entities (
            \\    id INTEGER PRIMARY KEY,
            \\    created_at INTEGER DEFAULT (unixepoch()),
            \\    active INTEGER DEFAULT 1
            \\);
        ;
        var errmsg: [*c]u8 = null;
        if (c.sqlite3_exec(db, entities_sql, null, null, &errmsg) != c.SQLITE_OK) return error.SQLiteExecFailed;

        const components_sql =
            \\CREATE TABLE IF NOT EXISTS components (
            \\    entity_id INTEGER NOT NULL,
            \\    component_type INTEGER NOT NULL,
            \\    x REAL, y REAL, z REAL,
            \\    dx REAL, dy REAL, dz REAL,
            \\    health_current INTEGER, health_max INTEGER,
            \\    energy_current REAL, energy_max REAL,
            \\    ai_state INTEGER, ai_target INTEGER,
            \\    data BLOB,
            \\    PRIMARY KEY (entity_id, component_type),
            \\    FOREIGN KEY (entity_id) REFERENCES entities(id)
            \\);
        ;
        if (c.sqlite3_exec(db, components_sql, null, null, &errmsg) != c.SQLITE_OK) return error.SQLiteExecFailed;
    }

    var hybrid_world = try SqliteWorld.init(allocator, "persistent_world.db");
    defer hybrid_world.deinit();
    try hybrid_world.startPersistence();
    
    const start_hybrid = std.time.nanoTimestamp();
    try testPerformance(&hybrid_world, allocator, "Hybrid");
    const end_hybrid = std.time.nanoTimestamp();
    const hybrid_duration = @as(f64, @floatFromInt(end_hybrid - start_hybrid)) / 1_000_000.0;
    
    std.debug.print("Hybrid mode completed in {d:.2}ms\n", .{hybrid_duration});
    
    // Wait a bit for background persistence to complete
    std.debug.print("⏳ Waiting for background persistence to complete...\n", .{});
    std.time.sleep(7 * std.time.ns_per_s); // 7 seconds
    
    std.debug.print("\n📊 Performance Comparison:\n", .{});
    std.debug.print("  Memory mode: {d:.2}ms\n", .{memory_duration});
    std.debug.print("  Hybrid mode: {d:.2}ms\n", .{hybrid_duration});
    std.debug.print("  Overhead: {d:.1}%\n", .{(hybrid_duration - memory_duration) / memory_duration * 100.0});
    
    if (hybrid_duration <= memory_duration * 1.1) {
        std.debug.print("  ✅ SUCCESS: Hybrid mode adds <10% overhead!\n", .{});
    } else {
        std.debug.print("  ⚠️  WARNING: Hybrid mode overhead is significant\n", .{});
    }
    
    std.debug.print("\n✅ Multi-threaded ECS test completed!\n", .{});
}

fn testPerformance(world: *SqliteWorld, allocator: std.mem.Allocator, mode: []const u8) !void {
    const entity_count = 1000;
    const simulation_ticks = 30; // 0.5 seconds at 60 FPS
    
    std.debug.print("  Creating {d} entities...\n", .{entity_count});
    const entities = try world.createEntities(entity_count);
    defer allocator.free(entities);
    
    // Add position and velocity components
    for (entities) |entity_id| {
        try world.addPosition(entity_id, 0.0, 0.0);
        try world.addVelocity(entity_id, 1.0, 0.5); // All entities moving
    }
    
    std.debug.print("  Running {d} simulation ticks...\n", .{simulation_ticks});
    const dt = 1.0 / 60.0;
    
    for (0..simulation_ticks) |tick| {
        _ = try world.batchMovementUpdateBlazing(dt);
        if (tick % 10 == 0) {
            std.debug.print("    {s} tick {d}/30\n", .{ mode, tick });
        }
    }
    
    const stats = try world.getStats();
    std.debug.print("  Final stats: {d} entities, {d} components\n", .{ stats.entity_count, stats.component_count });
}
