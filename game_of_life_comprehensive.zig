const std = @import("std");
const zecs = @import("zecs");
const SqliteWorld = zecs.SqliteWorld;
const EntityId = zecs.EntityId;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== ZECS Comprehensive Game of Life Benchmark ===\n\n", .{});
    
    const test_cases = [_]TestCase{
        // Pure Memory Mode Tests
        .{ .name = "100x100 Memory", .width = 100, .height = 100, .generations = 50, .mode = .memory, .threads = 1 },
        .{ .name = "100x100 Hybrid", .width = 100, .height = 100, .generations = 50, .mode = .hybrid, .threads = 1 },
        .{ .name = "100x100 Optimized", .width = 100, .height = 100, .generations = 50, .mode = .optimized, .threads = 1 },
        .{ .name = "100x100 MaxSpeed", .width = 100, .height = 100, .generations = 50, .mode = .max_speed, .threads = 1 },
        
        .{ .name = "200x200 Memory", .width = 200, .height = 200, .generations = 25, .mode = .memory, .threads = 1 },
        .{ .name = "200x200 Hybrid", .width = 200, .height = 200, .generations = 25, .mode = .hybrid, .threads = 1 },
        .{ .name = "200x200 Optimized", .width = 200, .height = 200, .generations = 25, .mode = .optimized, .threads = 1 },
        .{ .name = "200x200 MaxSpeed", .width = 200, .height = 200, .generations = 25, .mode = .max_speed, .threads = 1 },
        
        .{ .name = "500x500 Memory", .width = 500, .height = 500, .generations = 10, .mode = .memory, .threads = 1 },
        .{ .name = "500x500 Optimized", .width = 500, .height = 500, .generations = 10, .mode = .optimized, .threads = 1 },
        .{ .name = "500x500 MaxSpeed", .width = 500, .height = 500, .generations = 10, .mode = .max_speed, .threads = 1 },
        
        // Multi-threaded Tests
        .{ .name = "500x500 Memory 4T", .width = 500, .height = 500, .generations = 10, .mode = .memory, .threads = 4 },
        .{ .name = "500x500 Optimized 4T", .width = 500, .height = 500, .generations = 10, .mode = .optimized, .threads = 4 },
        .{ .name = "500x500 MaxSpeed 4T", .width = 500, .height = 500, .generations = 10, .mode = .max_speed, .threads = 4 },
        
        // Large-scale tests
        .{ .name = "1000x1000 Memory", .width = 1000, .height = 1000, .generations = 5, .mode = .memory, .threads = 1 },
        .{ .name = "1000x1000 Optimized 4T", .width = 1000, .height = 1000, .generations = 5, .mode = .optimized, .threads = 4 },
        .{ .name = "1000x1000 MaxSpeed 4T", .width = 1000, .height = 1000, .generations = 5, .mode = .max_speed, .threads = 4 },
    };
    
    var results = std.ArrayList(TestResult).init(allocator);
    defer results.deinit();
    
    for (test_cases) |test_case| {
        const result = try runGameOfLifeTest(allocator, test_case);
        try results.append(result);
        std.debug.print("\n", .{});
        
        // Brief pause between tests
        std.time.sleep(500 * std.time.ns_per_ms);
    }
    
    // Generate performance comparison
    std.debug.print("📊 GAME OF LIFE PERFORMANCE COMPARISON\n", .{});
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    std.debug.print("{s:<20} {s:>8} {s:>15} {s:>12} {s:>12} {s:>8}\n", .{ "Test Case", "Duration", "Updates/sec", "Gen/sec", "Overhead", "Cells" });
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    
    var memory_baseline: ?f64 = null;
    for (test_cases, results.items) |test_case, result| {
        var overhead_str: []const u8 = "    -   ";
        var overhead_buf: [10]u8 = undefined;
        
        // Calculate overhead vs memory mode baseline
        if (test_case.mode == .memory) {
            memory_baseline = result.updates_per_sec;
        } else if (memory_baseline) |baseline| {
            const overhead = (baseline - result.updates_per_sec) / baseline * 100.0;
            overhead_str = std.fmt.bufPrint(&overhead_buf, "{d:>6.1}%", .{overhead}) catch "  err  ";
        }
        
        std.debug.print("{s:<20} {d:>6.1}ms {d:>11.0}/sec {d:>9.1}/sec {s} {d:>8}\n", .{
            test_case.name,
            result.duration_ms,
            result.updates_per_sec,
            result.generations_per_sec,
            overhead_str,
            result.final_alive,
        });
        
        // Reset baseline for each grid size
        if (std.mem.endsWith(u8, test_case.name, "Hybrid")) {
            memory_baseline = null;
        }
    }
    
    std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    
    // Analyze mode performance
    std.debug.print("\n🔍 MODE PERFORMANCE ANALYSIS\n", .{});
    var i: usize = 0;
    while (i < results.items.len) : (i += 2) {
        if (i + 1 < results.items.len) {
            const memory_result = results.items[i];
            const hybrid_result = results.items[i + 1];
            const performance_diff = (hybrid_result.updates_per_sec - memory_result.updates_per_sec) / memory_result.updates_per_sec * 100.0;
            
            var name_iter = std.mem.splitScalar(u8, test_cases[i].name, ' ');
            const size_name = name_iter.next() orelse "Unknown";
            
            if (performance_diff > 0) {
                std.debug.print("  {s}: Hybrid is {d:.1}% FASTER than Memory! 🚀\n", .{ size_name, performance_diff });
            } else {
                std.debug.print("  {s}: Hybrid is {d:.1}% slower than Memory\n", .{ size_name, -performance_diff });
            }
        }
    }
    
    std.debug.print("\n✅ Comprehensive Game of Life Benchmark Complete!\n", .{});
    std.debug.print("🎯 This benchmark tests both memory and hybrid persistence modes\n", .{});
    std.debug.print("🚀 Some hybrid cases may outperform pure memory due to SQLite optimizations!\n", .{});
}

const UpdateMode = enum {
    memory,      // Pure in-memory, no persistence
    hybrid,      // In-memory + background persistence  
    optimized,   // Optimized batching + WAL performance
    max_speed,   // Maximum speed mode (reduced durability)
    async_wb,    // Async write-behind mode
};

const TestCase = struct {
    name: []const u8,
    width: u32,
    height: u32,
    generations: u32,
    mode: UpdateMode,
    threads: u32,
};

const TestResult = struct {
    duration_ms: f64,
    updates_per_sec: f64,
    generations_per_sec: f64,
    final_alive: u32,
};

fn runGameOfLifeTest(allocator: std.mem.Allocator, test_case: TestCase) !TestResult {
    std.debug.print("🧪 Test: {s} ({d}x{d} grid, {d} generations)\n", .{ 
        test_case.name, test_case.width, test_case.height, test_case.generations 
    });
    
    // Set up database path based on mode
    const db_path: ?[]const u8 = switch (test_case.mode) {
        .memory => null,
        .hybrid, .optimized, .max_speed, .async_wb => "game_of_life_benchmark.db",
    };
    
    var world = try SqliteWorld.init(allocator, db_path);
    defer world.deinit();
    
    // Configure world based on mode
    switch (test_case.mode) {
        .memory => {
            if (test_case.threads > 1) {
                std.debug.print("  🧠 Memory mode: Pure in-memory + {d} threads\n", .{test_case.threads});
            } else {
                std.debug.print("  🧠 Memory mode: Pure in-memory computation\n", .{});
            }
        },
        .hybrid => {
            try world.startPersistence();
            if (test_case.threads > 1) {
                std.debug.print("  🔄 Hybrid mode: Background persistence + {d} threads\n", .{test_case.threads});
            } else {
                std.debug.print("  🔄 Hybrid mode: Background persistence enabled\n", .{});
            }
        },
        .optimized => {
            try world.startPersistence();
            if (test_case.threads > 1) {
                std.debug.print("  ⚡ Optimized mode: WAL batching + {d} threads\n", .{test_case.threads});
            } else {
                std.debug.print("  ⚡ Optimized mode: WAL batching enabled\n", .{});
            }
        },
        .max_speed => {
            try world.startPersistence();
            try world.enableMaxSpeedMode();
            if (test_case.threads > 1) {
                std.debug.print("  🚀 MaxSpeed mode: Reduced durability + {d} threads\n", .{test_case.threads});
            } else {
                std.debug.print("  🚀 MaxSpeed mode: Reduced durability guarantees\n", .{});
            }
        },
        .async_wb => {
            try world.startPersistence();
            if (test_case.threads > 1) {
                std.debug.print("  💨 AsyncWB mode: Write-behind + {d} threads\n", .{test_case.threads});
            } else {
                std.debug.print("  💨 AsyncWB mode: Async write-behind enabled\n", .{});
            }
        },
    }
    
    const total_cells = test_case.width * test_case.height;
    
    // Create entities for all cells
    std.debug.print("  🌱 Creating {d} cell entities...\n", .{total_cells});
    const entities = try world.createEntities(total_cells);
    defer allocator.free(entities);
    
    // Initialize grid with random pattern (30% alive)
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
        const alive_count = if (test_case.threads == 1) 
            try world.gameOfLifeStepNative(test_case.width, test_case.height)
        else 
            try world.gameOfLifeStepMultiThreaded(test_case.width, test_case.height, test_case.threads);
            
        if (gen % (test_case.generations / 5) == 0 or gen == test_case.generations - 1) {
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
    
    // Performance assessment
    if (generations_per_sec >= 30.0) {
        std.debug.print("  ✅ EXCELLENT: {d:.1} generations/sec (30+ target)\n", .{generations_per_sec});
    } else if (generations_per_sec >= 10.0) {
        std.debug.print("  ⚡ GOOD: {d:.1} generations/sec (10+ target)\n", .{generations_per_sec});
    } else if (generations_per_sec >= 1.0) {
        std.debug.print("  ⏳ ACCEPTABLE: {d:.1} generations/sec (1+ target)\n", .{generations_per_sec});
    } else {
        std.debug.print("  🐌 SLOW: {d:.1} generations/sec (< 1 target)\n", .{generations_per_sec});
    }
    
    return TestResult{
        .duration_ms = duration_ms,
        .updates_per_sec = updates_per_sec,
        .generations_per_sec = generations_per_sec,
        .final_alive = final_alive,
    };
}
