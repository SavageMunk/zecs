const std = @import("std");
const zecs = @import("zecs");
const SqliteWorld = zecs.SqliteWorld;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== Simple Hot Entity Test ===\n", .{});
    
    // Create SQLite world
    var sqlite_world = try SqliteWorld.init(allocator, ":memory:");
    defer sqlite_world.deinit();
    
    // Create 1000 entities with 20% moving
    const entity_count = 1000;
    var entities = try sqlite_world.batchCreateEntities(entity_count);
    defer entities.deinit();
    
    var positions = try allocator.alloc([2]f32, entity_count);
    var velocities = try allocator.alloc([2]f32, entity_count);
    defer allocator.free(positions);
    defer allocator.free(velocities);
    
    for (0..entity_count) |i| {
        positions[i] = [2]f32{ 0.0, 0.0 };
        // Only 20% moving
        if (i < entity_count / 5) {
            velocities[i] = [2]f32{ 1.0, 1.0 };
        } else {
            velocities[i] = [2]f32{ 0.0, 0.0 };
        }
    }
    
    try sqlite_world.batchAddPositionVelocity(entities.items, positions, velocities);
    
    const dt = 1.0 / 60.0;
    const test_updates = 10;
    
    // Test hot entity tracking
    std.debug.print("Testing hot entity updates...\n", .{});
    const start_time = std.time.nanoTimestamp();
    
    for (0..test_updates) |_| {
        const updated = try sqlite_world.batchMovementUpdateHot(dt);
        std.debug.print("  Updated {d} entities\n", .{updated});
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    
    std.debug.print("Completed {d} hot updates in {d:.2}ms\n", .{ test_updates, duration_ms });
    std.debug.print("Rate: {d:.0} updates/second\n", .{@as(f64, @floatFromInt(test_updates)) / (duration_ms / 1000.0)});
}
