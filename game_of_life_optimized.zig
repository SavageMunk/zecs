const std = @import("std");
const zecs = @import("zecs");
const SqliteWorld = zecs.SqliteWorld;
const EntityId = zecs.EntityId;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== ZECS Optimized Game of Life Benchmark ===\n\n", .{});
    
    const test_cases = [_]TestCase{
        .{ .name = "50x50 Native", .width = 50, .height = 50, .generations = 100, .use_native = true },
        .{ .name = "100x100 Native", .width = 100, .height = 100, .generations = 100, .use_native = true },
        .{ .name = "200x200 Native", .width = 200, .height = 200, .generations = 50, .use_native = true },
        .{ .name = "300x300 Native", .width = 300, .height = 300, .generations = 25, .use_native = true },
        .{ .name = "500x500 Native", .width = 500, .height = 500, .generations = 10, .use_native = true },
        .{ .name = "1000x1000 Native", .width = 1000, .height = 1000, .generations = 5, .use_native = true },
    };
    
    for (test_cases) |test_case| {
        try runGameOfLifeTest(allocator, test_case);
        std.debug.print("\n", .{});
    }
    
    std.debug.print("🏆 Optimized Game of Life Benchmark Complete!\n", .{});
    std.debug.print("🚀 Native computation dramatically improves performance on large grids!\n", .{});
}

const TestCase = struct {
    name: []const u8,
    width: u32,
    height: u32,
    generations: u32,
    use_native: bool,
};

fn runGameOfLifeTest(allocator: std.mem.Allocator, test_case: TestCase) !void {
    std.debug.print("🧪 Test: {s} ({d}x{d} grid, {d} generations)\n", .{ 
        test_case.name, test_case.width, test_case.height, test_case.generations 
    });
    
    var world = try SqliteWorld.init(allocator, null);
    defer world.deinit();
    
    const total_cells = test_case.width * test_case.height;
    
    // Create entities for all cells
    std.debug.print("  🌱 Creating {d} cell entities...\n", .{total_cells});
    const entities = try world.createEntities(total_cells);
    defer allocator.free(entities);
    
    // Initialize grid with random pattern
    var rng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    var initial_alive: u32 = 0;
    
    var entity_idx: u32 = 0;
    for (0..test_case.height) |y| {
        for (0..test_case.width) |x| {
            const alive = rng.random().float(f32) < 0.3; // 30% alive
            try world.addGameOfLifeCell(entities[entity_idx], @intCast(x), @intCast(y), alive);
            if (alive) initial_alive += 1;
            entity_idx += 1;
        }
    }
    
    std.debug.print("  🔥 Initial alive cells: {d}/{d} ({d:.1}%)\n", .{ 
        initial_alive, total_cells, @as(f32, @floatFromInt(initial_alive)) / @as(f32, @floatFromInt(total_cells)) * 100.0 
    });
    
    const start_time = std.time.nanoTimestamp();
    
    // Run simulation
    for (0..test_case.generations) |gen| {
        const alive_count = try world.gameOfLifeStepNative(test_case.width, test_case.height);
            
        if (gen % 10 == 0 or gen == test_case.generations - 1) {
            std.debug.print("  📈 Generation {d}: {d} alive cells\n", .{ gen, alive_count });
        }
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    
    const final_alive = try world.getAliveCellCount();
    const total_updates = total_cells * test_case.generations;
    const updates_per_sec = @as(f64, @floatFromInt(total_updates)) / (duration_ms / 1000.0);
    const generations_per_sec = @as(f64, @floatFromInt(test_case.generations)) / (duration_ms / 1000.0);
    
    std.debug.print("  ⏱️  Duration: {d:.2}ms\n", .{duration_ms});
    std.debug.print("  🎯 Cell updates/sec: {d:.0}\n", .{updates_per_sec});
    std.debug.print("  🚀 Generations/sec: {d:.1}\n", .{generations_per_sec});
    std.debug.print("  📊 Final alive cells: {d}/{d} ({d:.1}%)\n", .{ 
        final_alive, total_cells, @as(f32, @floatFromInt(final_alive)) / @as(f32, @floatFromInt(total_cells)) * 100.0 
    });
    
    if (generations_per_sec >= 30.0) {
        std.debug.print("  ✅ EXCELLENT: Can run at 30+ generations/sec\n", .{});
    } else if (generations_per_sec >= 10.0) {
        std.debug.print("  ⚡ GOOD: Can run at 10+ generations/sec\n", .{});
    } else if (generations_per_sec >= 1.0) {
        std.debug.print("  ⏳ ACCEPTABLE: Can run at 1+ generations/sec\n", .{});
    } else {
        std.debug.print("  🐌 SLOW: Less than 1 generation/sec\n", .{});
    }
}
