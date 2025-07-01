const std = @import("std");
const zecs = @import("zecs");
const SqliteWorld = zecs.SqliteWorld;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== SQLite ECS Performance Benchmarks ===\n\n", .{});
    
    // Create SQLite world
    var sqlite_world = try SqliteWorld.init(allocator, ":memory:");
    defer sqlite_world.deinit();
    
    // Benchmark 1: Entity creation
    try benchmarkSqliteEntityCreation(&sqlite_world);
    
    // Benchmark 2: Component addition
    try benchmarkSqliteComponentAddition(&sqlite_world, allocator);
    
    // Benchmark 3: Batch system updates
    try benchmarkSqliteBatchUpdates(&sqlite_world);
    
    // Benchmark 4: Large world simulation
    try benchmarkSqliteLargeWorld(&sqlite_world, allocator);
    
    std.debug.print("\nAll SQLite benchmarks completed!\n", .{});
}

fn benchmarkSqliteEntityCreation(world: *SqliteWorld) !void {
    std.debug.print("SQLite Benchmark 1: Batch Entity Creation\n", .{});
    
    const entity_count = 10000;
    const start_time = std.time.nanoTimestamp();
    
    // Use new batch method
    var entities = try world.batchCreateEntities(entity_count);
    defer entities.deinit();
    
    const end_time = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const entities_per_second = @as(f64, @floatFromInt(entity_count)) / (duration_ms / 1000.0);
    
    std.debug.print("  Created {d} entities in {d:.2}ms\n", .{ entity_count, duration_ms });
    std.debug.print("  Rate: {d:.0} entities/second\n\n", .{entities_per_second});
}

fn benchmarkSqliteComponentAddition(world: *SqliteWorld, allocator: std.mem.Allocator) !void {
    std.debug.print("SQLite Benchmark 2: Batch Component Addition\n", .{});
    
    const entity_count = 5000;
    
    // Create entities
    var entities = try world.batchCreateEntities(entity_count);
    defer entities.deinit();
    
    // Prepare component data
    var positions = try allocator.alloc([2]f32, entity_count);
    var velocities = try allocator.alloc([2]f32, entity_count);
    defer allocator.free(positions);
    defer allocator.free(velocities);
    
    for (0..entity_count) |i| {
        positions[i] = [2]f32{ 0.0, 0.0 };
        velocities[i] = [2]f32{ 1.0, 1.0 };
    }
    
    const start_time = std.time.nanoTimestamp();
    
    // Use batch method
    try world.batchAddPositionVelocity(entities.items, positions, velocities);
    
    const end_time = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const components_added = entity_count * 2; // Position + Velocity
    const components_per_second = @as(f64, @floatFromInt(components_added)) / (duration_ms / 1000.0);
    
    std.debug.print("  Added {d} components to {d} entities in {d:.2}ms\n", .{ components_added, entity_count, duration_ms });
    std.debug.print("  Rate: {d:.0} components/second\n\n", .{components_per_second});
}

fn benchmarkSqliteBatchUpdates(world: *SqliteWorld) !void {
    std.debug.print("SQLite Benchmark 3: HOT ENTITY vs FULL UPDATE COMPARISON\n", .{});
    
    const entity_count = 5000;
    
    // Create entities and components using batch methods
    var entities = try world.batchCreateEntities(entity_count);
    defer entities.deinit();
    
    var positions = try world.allocator.alloc([2]f32, entity_count);
    var velocities = try world.allocator.alloc([2]f32, entity_count);
    defer world.allocator.free(positions);
    defer world.allocator.free(velocities);
    
    for (0..entity_count) |i| {
        positions[i] = [2]f32{ 0.0, 0.0 };
        // Only 20% of entities are actually moving (realistic game scenario)
        if (i < entity_count / 5) {
            velocities[i] = [2]f32{ 1.0, 1.0 };
        } else {
            velocities[i] = [2]f32{ 0.0, 0.0 }; // Stationary
        }
    }
    
    try world.batchAddPositionVelocity(entities.items, positions, velocities);
    
    // DEBUG: Check what entities are actually moving
    var moving_query = try world.batchQueryMovementEntities();
    defer moving_query.deinit();
    std.debug.print("  DEBUG: {d} entities have non-zero velocity\n", .{moving_query.items.len});
    
    const update_count = 10; // Reduced for debugging
    const dt = 1.0 / 60.0;
    
    std.debug.print("  Setup: {d} entities, {d}% moving, dt={d:.6}\n", .{ entity_count, entity_count / 5 * 100 / entity_count, dt });
    
    // TEST 1: Native calculation approach (full update)
    std.debug.print("  Testing NATIVE calculation (full update)...\n", .{});
    const start_time1 = std.time.nanoTimestamp();
    
    for (0..update_count) |_| {
        _ = try world.batchMovementUpdateNative(dt);
    }
    
    const end_time1 = std.time.nanoTimestamp();
    const duration_ns1 = @as(u64, @intCast(end_time1 - start_time1));
    const duration_ms1 = @as(f64, @floatFromInt(duration_ns1)) / 1_000_000.0;
    const updates_per_second1 = @as(f64, @floatFromInt(update_count)) / (duration_ms1 / 1000.0);
    
    std.debug.print("    Native: {d} updates in {d:.2}ms = {d:.0} updates/sec\n", .{ update_count, duration_ms1, updates_per_second1 });
    
    // TEST 2: Single-statement REPLACE approach (full update)
    std.debug.print("  Testing SINGLE-STATEMENT REPLACE (full update)...\n", .{});
    const start_time2 = std.time.nanoTimestamp();
    
    for (0..update_count) |_| {
        _ = try world.batchMovementUpdateReplace(dt);
    }
    
    const end_time2 = std.time.nanoTimestamp();
    const duration_ns2 = @as(u64, @intCast(end_time2 - start_time2));
    const duration_ms2 = @as(f64, @floatFromInt(duration_ns2)) / 1_000_000.0;
    const updates_per_second2 = @as(f64, @floatFromInt(update_count)) / (duration_ms2 / 1000.0);
    
    std.debug.print("    Replace: {d} updates in {d:.2}ms = {d:.0} updates/sec\n", .{ update_count, duration_ms2, updates_per_second2 });
    
    // TEST 3: BLAZING FAST approach (no JOIN needed!)
    std.debug.print("  Testing BLAZING FAST (no JOIN, direct update)...\n", .{});
    const start_time3 = std.time.nanoTimestamp();
    
    for (0..update_count) |_| {
        _ = try world.batchMovementUpdateBlazing(dt);
    }
    
    const end_time3 = std.time.nanoTimestamp();
    const duration_ns3 = @as(u64, @intCast(end_time3 - start_time3));
    const duration_ms3 = @as(f64, @floatFromInt(duration_ns3)) / 1_000_000.0;
    const updates_per_second3 = @as(f64, @floatFromInt(update_count)) / (duration_ms3 / 1000.0);
    
    std.debug.print("    Blazing Fast: {d} updates in {d:.2}ms = {d:.0} updates/sec\n", .{ update_count, duration_ms3, updates_per_second3 });
    
    // TEST 4: OPTIMIZED approach (single SQL + moving entities only)
    std.debug.print("  Testing OPTIMIZED SQL (single statement + moving entities only)...\n", .{});
    const start_time4 = std.time.nanoTimestamp();
    
    for (0..update_count) |_| {
        _ = try world.batchMovementUpdateOptimized(dt);
    }
    
    const end_time4 = std.time.nanoTimestamp();
    const duration_ns4 = @as(u64, @intCast(end_time4 - start_time4));
    const duration_ms4 = @as(f64, @floatFromInt(duration_ns4)) / 1_000_000.0;
    const updates_per_second4 = @as(f64, @floatFromInt(update_count)) / (duration_ms4 / 1000.0);
    
    std.debug.print("    Optimized: {d} updates in {d:.2}ms = {d:.0} updates/sec\n", .{ update_count, duration_ms4, updates_per_second4 });
    
    // Find the winner
    const best_rate = @max(@max(@max(updates_per_second1, updates_per_second2), updates_per_second3), updates_per_second4);
    
    if (updates_per_second4 == best_rate) {
        const speedup_vs_native = updates_per_second4 / updates_per_second1;
        const speedup_vs_replace = updates_per_second4 / updates_per_second2;
        std.debug.print("  🚀 OPTIMIZED WINS! {d:.1}x faster than Native, {d:.1}x faster than Replace!\n\n", .{ speedup_vs_native, speedup_vs_replace });
    } else if (updates_per_second3 == best_rate) {
        const speedup_vs_native = updates_per_second3 / updates_per_second1;
        const speedup_vs_replace = updates_per_second3 / updates_per_second2;
        std.debug.print("  🚀 HOT ENTITY WINS! {d:.1}x faster than Native, {d:.1}x faster than Replace!\n\n", .{ speedup_vs_native, speedup_vs_replace });
    } else if (updates_per_second1 == best_rate) {
        std.debug.print("  🤔 Native is still fastest\n\n", .{});
    } else {
        std.debug.print("  🤔 Replace is fastest\n\n", .{});
    }
}

fn benchmarkSqliteLargeWorld(world: *SqliteWorld, allocator: std.mem.Allocator) !void {
    std.debug.print("SQLite Benchmark 4: Large World Simulation\n", .{});
    
    // Clear all data to start fresh for this benchmark
    try world.execSql("DELETE FROM components;");
    try world.execSql("DELETE FROM entities;");
    std.debug.print("  Cleared database for fresh start\n", .{});
    
    const entity_count = 10000;
    const entities = try world.createEntities(entity_count);
    defer allocator.free(entities);
    
    // Create large number of entities with random data
    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();
    
    var moving_count: u32 = 0;
    
    try world.execSql("BEGIN TRANSACTION;");
    for (entities) |entity_id| {
        const x = random.float(f32) * 1000.0;
        const y = random.float(f32) * 1000.0;
        
        // Make only 60% of entities moving (like in benchmark 3)
        var dx: f32 = 0.0;
        var dy: f32 = 0.0;
        if (random.float(f32) < 0.6) {
            dx = (random.float(f32) - 0.5) * 100.0;
            dy = (random.float(f32) - 0.5) * 100.0;
            moving_count += 1;
        }
        
        const health = 50 + @as(i32, @intFromFloat(random.float(f32) * 50.0));
        
        try world.addPosition(entity_id, x, y);
        try world.addVelocity(entity_id, dx, dy);
        try world.addHealth(entity_id, health, 100);
    }
    try world.execSql("COMMIT;");
    
    std.debug.print("  Created {d} entities, {d} moving ({d:.1}%)\n", .{ entity_count, moving_count, @as(f64, @floatFromInt(moving_count)) / @as(f64, @floatFromInt(entity_count)) * 100.0 });
    
    const simulation_ticks = 60; // 1 second at 60 FPS (reduced for debugging)
    const dt = 1.0 / 60.0;
    
    const start_time = std.time.nanoTimestamp();
    
    for (0..simulation_ticks) |_| {
        try world.batchMovementSystemBlazing(dt);
        // Skip health system for now to focus on movement optimization
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const simulation_time = @as(f64, @floatFromInt(simulation_ticks)) * dt;
    const real_time_factor = simulation_time / (duration_ms / 1000.0);
    
    std.debug.print("  Simulated {d:.1}s with {d} entities in {d:.2}ms\n", .{ simulation_time, entity_count, duration_ms });
    std.debug.print("  Real-time factor: {d:.1}x\n", .{real_time_factor});
    
    if (real_time_factor > 1.0) {
        std.debug.print("  ✓ SQLite simulation runs faster than real-time!\n", .{});
    } else {
        std.debug.print("  ⚠ SQLite simulation runs slower than real-time\n", .{});
    }
    
    // Show final statistics
    const stats = try world.getStats();
    std.debug.print("  Final entities: {d}\n", .{stats.entity_count});
    std.debug.print("  Final components: {d}\n", .{stats.component_count});
    std.debug.print("  Cache hit ratio: {d:.1}%\n\n", .{
        if (stats.cache_hits + stats.cache_misses > 0) 
            @as(f64, @floatFromInt(stats.cache_hits)) / @as(f64, @floatFromInt(stats.cache_hits + stats.cache_misses)) * 100.0
        else 
            0.0
    });
}
