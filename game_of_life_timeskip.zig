const std = @import("std");
const zecs = @import("zecs");
const SqliteWorld = zecs.SqliteWorld;
const TimeSkipComponent = @import("src/systems/time_skip.zig").TimeSkipComponent;
const EntityId = zecs.EntityId;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== ZECS Game of Life Benchmark with TimeSkip ===\n\n", .{});

    const width = 1000;
    const height = 1000;
    const generations = 10;
    const active_window = 100; // Only a 100x100 region is 'active' per tick
    const total_cells = width * height;

    var world = try SqliteWorld.init(allocator, null);
    defer world.deinit();

    // Create entities and attach TimeSkipComponent
    const entities = try world.createEntities(total_cells);
    defer allocator.free(entities);
    var time_skips = try allocator.alloc(TimeSkipComponent, total_cells);
    defer allocator.free(time_skips);

    var rng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    var entity_idx: usize = 0;
    for (0..height) |y| {
        for (0..width) |x| {
            const alive = rng.random().float(f32) < 0.3;
            try world.addGameOfLifeCell(entities[entity_idx], @intCast(x), @intCast(y), alive);
            time_skips[entity_idx] = TimeSkipComponent.init(0); // Start at tick 0
            entity_idx += 1;
        }
    }

    const start_time = std.time.nanoTimestamp();
    var now: i64 = 0;

    for (0..generations) |gen| {
        // Move the active window (simulate a camera moving)
        const wx = (gen * 50) % (width - active_window);
        const wy = (gen * 50) % (height - active_window);

        var active_count: usize = 0;
        var skipped_count: usize = 0;
        // Mark active region
        for (0..height) |y| {
            for (0..width) |x| {
                const idx = y * width + x;
                const is_active = x >= wx and x < wx + active_window and y >= wy and y < wy + active_window;
                if (is_active) {
                    time_skips[idx].last_update_time = now;
                    active_count += 1;
                } else {
                    const elapsed = now - time_skips[idx].last_update_time;
                    if (elapsed > 0) {
                        time_skips[idx].simulateFor(elapsed);
                        time_skips[idx].last_update_time = now;
                        skipped_count += 1;
                    }
                }
            }
        }
        // Print progress and speed at intervals
        const print_interval = @max(1, generations / 10);
        if (gen % print_interval == 0 or gen == generations - 1) {
            const elapsed_ms = (@as(f64, @floatFromInt(std.time.nanoTimestamp() - start_time)) / 1_000_000.0);
            const speed = if (elapsed_ms > 0) @as(f64, @floatFromInt(gen + 1)) / (elapsed_ms / 1000.0) else 0.0;
            std.debug.print("  Gen {d}/{d}: Active window at ({d},{d}) | Active: {d} | Skipped: {d} | Elapsed: {d:.2}ms | Speed: {d:.2} gen/sec\n",
                .{gen + 1, generations, wx, wy, active_count, skipped_count, elapsed_ms, speed});
        }
        now += 1;
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    std.debug.print("\n⏱️  Duration: {d:.2}ms for {d} generations on {d}x{d} grid (TimeSkip)\n", .{duration_ms, generations, width, height});
}
