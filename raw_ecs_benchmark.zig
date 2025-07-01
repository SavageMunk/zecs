const std = @import("std");
const zecs = @import("zecs");
const SqliteWorld = zecs.SqliteWorld;
const EntityId = zecs.EntityId;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== ZECS Raw ECS Performance Benchmark ===\n", .{});
    std.debug.print("Testing all optimized batch operations for maximum throughput\n\n", .{});
    
    // Test 1: Raw entity creation performance
    try benchmarkEntityCreation(allocator);
    
    // Test 2: Raw component addition performance
    try benchmarkComponentAddition(allocator);
    
    // Test 3: Different movement update methods
    try benchmarkMovementMethods(allocator);
    
    // Test 4: Batch operations scaling test
    try benchmarkBatchScaling(allocator);
    
    // Test 5: Max speed mode vs normal mode
    try benchmarkMaxSpeedMode(allocator);
    
    // Test 6: Pure read/write throughput (like raw SQLite test)
    try benchmarkRawThroughput(allocator);
    
    std.debug.print("🎯 All ECS benchmarks completed!\n", .{});
}

fn benchmarkEntityCreation(allocator: std.mem.Allocator) !void {
    std.debug.print("📦 Test 1: Entity Creation Performance\n", .{});
    
    var world = try SqliteWorld.init(allocator, null);
    defer world.deinit();
    
    const entity_counts = [_]u32{ 1000, 5000, 10000, 25000, 50000 };
    
    for (entity_counts) |count| {
        // Single entity creation
        {
            var world_single = try SqliteWorld.init(allocator, null);
            defer world_single.deinit();
            
            const start_time = std.time.nanoTimestamp();
            
            for (0..count) |_| {
                _ = try world_single.createEntity();
            }
            
            const end_time = std.time.nanoTimestamp();
            const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
            const entities_per_second = @as(f64, @floatFromInt(count)) / (duration_ms / 1000.0);
            
            std.debug.print("  Single: {d:>6} entities in {d:>8.2}ms -> {d:>10.0} entities/sec\n", 
                .{ count, duration_ms, entities_per_second });
        }
        
        // Batch entity creation
        {
            var world_batch = try SqliteWorld.init(allocator, null);
            defer world_batch.deinit();
            
            const start_time = std.time.nanoTimestamp();
            
            var entities = try world_batch.batchCreateEntities(count);
            defer entities.deinit();
            
            const end_time = std.time.nanoTimestamp();
            const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
            const entities_per_second = @as(f64, @floatFromInt(count)) / (duration_ms / 1000.0);
            
            std.debug.print("  Batch:  {d:>6} entities in {d:>8.2}ms -> {d:>10.0} entities/sec\n", 
                .{ count, duration_ms, entities_per_second });
        }
        std.debug.print("\n", .{});
    }
}

fn benchmarkComponentAddition(allocator: std.mem.Allocator) !void {
    std.debug.print("⚡ Test 2: Component Addition Performance\n", .{});
    
    const entity_count = 10000;
    
    // Single component addition
    {
        var world = try SqliteWorld.init(allocator, null);
        defer world.deinit();
        
        var entities = try world.batchCreateEntities(entity_count);
        defer entities.deinit();
        
        const start_time = std.time.nanoTimestamp();
        
        for (entities.items) |entity_id| {
            try world.addPosition(entity_id, 100.0, 200.0);
            try world.addVelocity(entity_id, 1.0, 2.0);
            try world.addHealth(entity_id, 100, 100);
        }
        
        const end_time = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
        const components_added = entity_count * 3;
        const components_per_second = @as(f64, @floatFromInt(components_added)) / (duration_ms / 1000.0);
        
        std.debug.print("  Single: {d} components in {d:.2}ms -> {d:.0} components/sec\n", 
            .{ components_added, duration_ms, components_per_second });
    }
    
    // Batch component addition
    {
        var world = try SqliteWorld.init(allocator, null);
        defer world.deinit();
        
        var entities = try world.batchCreateEntities(entity_count);
        defer entities.deinit();
        
        // Prepare batch data
        var positions = try allocator.alloc([2]f32, entity_count);
        defer allocator.free(positions);
        var velocities = try allocator.alloc([2]f32, entity_count);
        defer allocator.free(velocities);
        
        var prng = std.Random.DefaultPrng.init(42);
        const random = prng.random();
        
        for (0..entity_count) |i| {
            positions[i] = [2]f32{ random.float(f32) * 1000.0, random.float(f32) * 1000.0 };
            velocities[i] = [2]f32{ (random.float(f32) - 0.5) * 100.0, (random.float(f32) - 0.5) * 100.0 };
        }
        
        const start_time = std.time.nanoTimestamp();
        
        try world.batchAddPositionVelocity(entities.items, positions, velocities);
        
        // Add health components individually (no batch method yet)
        for (entities.items) |entity_id| {
            try world.addHealth(entity_id, 100, 100);
        }
        
        const end_time = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
        const components_added = entity_count * 3;
        const components_per_second = @as(f64, @floatFromInt(components_added)) / (duration_ms / 1000.0);
        
        std.debug.print("  Batch:  {d} components in {d:.2}ms -> {d:.0} components/sec\n", 
            .{ components_added, duration_ms, components_per_second });
    }
    std.debug.print("\n", .{});
}

fn benchmarkMovementMethods(allocator: std.mem.Allocator) !void {
    std.debug.print("🚀 Test 3: Movement Update Methods Comparison\n", .{});
    
    const entity_count = 6000; // Same as raw SQLite test
    const ticks = 60; // 1 second at 60 FPS
    const dt = 1.0 / 60.0;
    
    const methods = [_]struct { name: []const u8, func: []const u8 }{
        .{ .name = "Optimized     ", .func = "batchMovementUpdateOptimized" },
        .{ .name = "Ultra         ", .func = "batchMovementUpdateUltra" },
        .{ .name = "Blazing       ", .func = "batchMovementUpdateBlazing" },
        .{ .name = "Native        ", .func = "batchMovementUpdateNative" },
        .{ .name = "Replace       ", .func = "batchMovementUpdateReplace" },
    };
    
    for (methods) |method| {
        var world = try SqliteWorld.init(allocator, null);
        defer world.deinit();
        
        // Create entities with position and velocity
        var entities = try world.batchCreateEntities(entity_count);
        defer entities.deinit();
        
        var positions = try allocator.alloc([2]f32, entity_count);
        defer allocator.free(positions);
        var velocities = try allocator.alloc([2]f32, entity_count);
        defer allocator.free(velocities);
        
        var prng = std.Random.DefaultPrng.init(42);
        const random = prng.random();
        
        for (0..entity_count) |i| {
            positions[i] = [2]f32{ random.float(f32) * 1000.0, random.float(f32) * 1000.0 };
            velocities[i] = [2]f32{ (random.float(f32) - 0.5) * 100.0, (random.float(f32) - 0.5) * 100.0 };
        }
        
        try world.batchAddPositionVelocity(entities.items, positions, velocities);
        
        var total_updates: u32 = 0;
        const start_time = std.time.nanoTimestamp();
        
        for (0..ticks) |_| {
            const updates = if (std.mem.eql(u8, method.func, "batchMovementUpdateOptimized"))
                try world.batchMovementUpdateOptimized(dt)
            else if (std.mem.eql(u8, method.func, "batchMovementUpdateUltra"))
                try world.batchMovementUpdateUltra(dt)
            else if (std.mem.eql(u8, method.func, "batchMovementUpdateBlazing"))
                try world.batchMovementUpdateBlazing(dt)
            else if (std.mem.eql(u8, method.func, "batchMovementUpdateNative"))
                try world.batchMovementUpdateNative(dt)
            else if (std.mem.eql(u8, method.func, "batchMovementUpdateReplace"))
                try world.batchMovementUpdateReplace(dt)
            else 0;
            
            total_updates += updates;
        }
        
        const end_time = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
        const updates_per_second = @as(f64, @floatFromInt(total_updates)) / (duration_ms / 1000.0);
        
        std.debug.print("  {s}: {d:>6} updates in {d:>8.2}ms -> {d:>10.0} updates/sec\n", 
            .{ method.name, total_updates, duration_ms, updates_per_second });
    }
    std.debug.print("\n", .{});
}

fn benchmarkBatchScaling(allocator: std.mem.Allocator) !void {
    std.debug.print("📈 Test 4: Batch Operations Scaling\n", .{});
    
    const entity_counts = [_]u32{ 1000, 5000, 10000, 25000, 50000 };
    const dt = 1.0 / 60.0;
    
    for (entity_counts) |count| {
        var world = try SqliteWorld.init(allocator, null);
        defer world.deinit();
        
        // Setup entities
        var entities = try world.batchCreateEntities(count);
        defer entities.deinit();
        
        var positions = try allocator.alloc([2]f32, count);
        defer allocator.free(positions);
        var velocities = try allocator.alloc([2]f32, count);
        defer allocator.free(velocities);
        
        var prng = std.Random.DefaultPrng.init(42);
        const random = prng.random();
        
        for (0..count) |i| {
            positions[i] = [2]f32{ random.float(f32) * 1000.0, random.float(f32) * 1000.0 };
            velocities[i] = [2]f32{ (random.float(f32) - 0.5) * 100.0, (random.float(f32) - 0.5) * 100.0 };
        }
        
        try world.batchAddPositionVelocity(entities.items, positions, velocities);
        
        // Test blazing fast method
        const start_time = std.time.nanoTimestamp();
        const updates = try world.batchMovementUpdateBlazing(dt);
        const end_time = std.time.nanoTimestamp();
        
        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
        const updates_per_second = @as(f64, @floatFromInt(updates)) / (duration_ms / 1000.0);
        
        std.debug.print("  {d:>6} entities -> {d:>6} updates in {d:>8.2}ms -> {d:>10.0} updates/sec\n", 
            .{ count, updates, duration_ms, updates_per_second });
    }
    std.debug.print("\n", .{});
}

fn benchmarkMaxSpeedMode(allocator: std.mem.Allocator) !void {
    std.debug.print("⚡ Test 5: Max Speed Mode vs Normal Mode\n", .{});
    
    const entity_count = 10000;
    const ticks = 30;
    const dt = 1.0 / 60.0;
    
    // Normal mode
    {
        var world = try SqliteWorld.init(allocator, null);
        defer world.deinit();
        
        // Setup entities
        var entities = try world.batchCreateEntities(entity_count);
        defer entities.deinit();
        
        var positions = try allocator.alloc([2]f32, entity_count);
        defer allocator.free(positions);
        var velocities = try allocator.alloc([2]f32, entity_count);
        defer allocator.free(velocities);
        
        var prng = std.Random.DefaultPrng.init(42);
        const random = prng.random();
        
        for (0..entity_count) |i| {
            positions[i] = [2]f32{ random.float(f32) * 1000.0, random.float(f32) * 1000.0 };
            velocities[i] = [2]f32{ (random.float(f32) - 0.5) * 100.0, (random.float(f32) - 0.5) * 100.0 };
        }
        
        try world.batchAddPositionVelocity(entities.items, positions, velocities);
        
        var total_updates: u32 = 0;
        const start_time = std.time.nanoTimestamp();
        
        for (0..ticks) |_| {
            total_updates += try world.batchMovementUpdateBlazing(dt);
        }
        
        const end_time = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
        const updates_per_second = @as(f64, @floatFromInt(total_updates)) / (duration_ms / 1000.0);
        
        std.debug.print("  Normal:   {d:>6} updates in {d:>8.2}ms -> {d:>10.0} updates/sec\n", 
            .{ total_updates, duration_ms, updates_per_second });
    }
    
    // Max speed mode
    {
        var world = try SqliteWorld.init(allocator, null);
        defer world.deinit();
        
        try world.enableMaxSpeedMode();
        
        // Setup entities
        var entities = try world.batchCreateEntities(entity_count);
        defer entities.deinit();
        
        var positions = try allocator.alloc([2]f32, entity_count);
        defer allocator.free(positions);
        var velocities = try allocator.alloc([2]f32, entity_count);
        defer allocator.free(velocities);
        
        var prng = std.Random.DefaultPrng.init(42);
        const random = prng.random();
        
        for (0..entity_count) |i| {
            positions[i] = [2]f32{ random.float(f32) * 1000.0, random.float(f32) * 1000.0 };
            velocities[i] = [2]f32{ (random.float(f32) - 0.5) * 100.0, (random.float(f32) - 0.5) * 100.0 };
        }
        
        try world.batchAddPositionVelocity(entities.items, positions, velocities);
        
        var total_updates: u32 = 0;
        const start_time = std.time.nanoTimestamp();
        
        for (0..ticks) |_| {
            total_updates += try world.batchMovementUpdateBlazing(dt);
        }
        
        const end_time = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
        const updates_per_second = @as(f64, @floatFromInt(total_updates)) / (duration_ms / 1000.0);
        
        std.debug.print("  MaxSpeed: {d:>6} updates in {d:>8.2}ms -> {d:>10.0} updates/sec\n", 
            .{ total_updates, duration_ms, updates_per_second });
    }
    std.debug.print("\n", .{});
}

fn benchmarkRawThroughput(allocator: std.mem.Allocator) !void {
    std.debug.print("🔥 Test 6: Raw Read/Write Throughput (vs Raw SQLite)\n", .{});
    
    const entity_count = 6000;
    const ticks = 60;
    const dt = 1.0 / 60.0;
    
    var world = try SqliteWorld.init(allocator, null);
    defer world.deinit();
    
    // Setup entities with components
    var entities = try world.batchCreateEntities(entity_count);
    defer entities.deinit();
    
    var positions = try allocator.alloc([2]f32, entity_count);
    defer allocator.free(positions);
    var velocities = try allocator.alloc([2]f32, entity_count);
    defer allocator.free(velocities);
    
    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();
    
    for (0..entity_count) |i| {
        positions[i] = [2]f32{ random.float(f32) * 1000.0, random.float(f32) * 1000.0 };
        velocities[i] = [2]f32{ (random.float(f32) - 0.5) * 100.0, (random.float(f32) - 0.5) * 100.0 };
    }
    
    try world.batchAddPositionVelocity(entities.items, positions, velocities);
    
    std.debug.print("  Setup complete: {d} entities with position+velocity components\n", .{entity_count});
    
    // Test read throughput
    {
        const start_time = std.time.nanoTimestamp();
        var total_reads: u32 = 0;
        
        for (0..ticks) |_| {
            var movement_data = try world.batchQueryMovementEntities();
            defer movement_data.deinit();
            total_reads += @intCast(movement_data.items.len);
        }
        
        const end_time = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
        const reads_per_second = @as(f64, @floatFromInt(total_reads)) / (duration_ms / 1000.0);
        
        std.debug.print("  Read:     {d:>6} reads  in {d:>8.2}ms -> {d:>10.0} reads/sec\n", 
            .{ total_reads, duration_ms, reads_per_second });
    }
    
    // Test write throughput (blazing method)
    {
        const start_time = std.time.nanoTimestamp();
        var total_writes: u32 = 0;
        
        for (0..ticks) |_| {
            total_writes += try world.batchMovementUpdateBlazing(dt);
        }
        
        const end_time = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
        const writes_per_second = @as(f64, @floatFromInt(total_writes)) / (duration_ms / 1000.0);
        
        std.debug.print("  Write:    {d:>6} writes in {d:>8.2}ms -> {d:>10.0} writes/sec\n", 
            .{ total_writes, duration_ms, writes_per_second });
    }
    
    // Test combined read+compute+write throughput (native method)
    {
        const start_time = std.time.nanoTimestamp();
        var total_operations: u32 = 0;
        
        for (0..ticks) |_| {
            total_operations += try world.batchMovementUpdateNative(dt);
        }
        
        const end_time = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
        const operations_per_second = @as(f64, @floatFromInt(total_operations)) / (duration_ms / 1000.0);
        
        std.debug.print("  R+C+W:    {d:>6} ops   in {d:>8.2}ms -> {d:>10.0} ops/sec\n", 
            .{ total_operations, duration_ms, operations_per_second });
    }
    
    std.debug.print("\n  🎯 Target: 1.5M+ reads/sec, 2M+ writes/sec (raw SQLite baseline)\n", .{});
}
