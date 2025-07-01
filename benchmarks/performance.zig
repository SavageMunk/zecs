const std = @import("std");
const zecs = @import("zecs");

const World = zecs.World;
const System = zecs.System;
const Position = zecs.components.Position;
const Velocity = zecs.components.Velocity;
const Health = zecs.components.Health;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== ZECS Performance Benchmarks ===\n\n", .{});
    
    // Benchmark 1: Entity creation
    try benchmarkEntityCreation(allocator);
    
    // Benchmark 2: Component addition
    try benchmarkComponentAddition(allocator);
    
    // Benchmark 3: System updates
    try benchmarkSystemUpdates(allocator);
    
    // Benchmark 4: Large world simulation
    try benchmarkLargeWorld(allocator);
    
    std.debug.print("\nAll benchmarks completed!\n", .{});
}

fn benchmarkEntityCreation(allocator: std.mem.Allocator) !void {
    std.debug.print("Benchmark 1: Entity Creation\n", .{});
    
    var world = World.init(allocator);
    defer world.deinit();
    
    const entity_count = 10000;
    const start_time = std.time.nanoTimestamp();
    
    for (0..entity_count) |_| {
        _ = try world.createEntity();
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const entities_per_second = @as(f64, @floatFromInt(entity_count)) / (duration_ms / 1000.0);
    
    std.debug.print("  Created {d} entities in {d:.2}ms\n", .{ entity_count, duration_ms });
    std.debug.print("  Rate: {d:.0} entities/second\n\n", .{entities_per_second});
}

fn benchmarkComponentAddition(allocator: std.mem.Allocator) !void {
    std.debug.print("Benchmark 2: Component Addition\n", .{});
    
    var world = World.init(allocator);
    defer world.deinit();
    
    const entity_count = 5000;
    var entities = std.ArrayList(zecs.EntityId).init(allocator);
    defer entities.deinit();
    
    // Create entities first
    for (0..entity_count) |_| {
        const entity = try world.createEntity();
        try entities.append(entity);
    }
    
    const start_time = std.time.nanoTimestamp();
    
    // Add components to all entities
    for (entities.items) |entity| {
        const position = try Position.init(0.0, 0.0, allocator);
        const velocity = try Velocity.init(0.0, 0.0, allocator);
        const health = try Health.init(100, allocator);
        
        try world.addComponent(entity, &position.component);
        try world.addComponent(entity, &velocity.component);
        try world.addComponent(entity, &health.component);
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const components_added = entity_count * 3;
    const components_per_second = @as(f64, @floatFromInt(components_added)) / (duration_ms / 1000.0);
    
    std.debug.print("  Added {d} components to {d} entities in {d:.2}ms\n", .{ components_added, entity_count, duration_ms });
    std.debug.print("  Rate: {d:.0} components/second\n\n", .{components_per_second});
}

fn benchmarkSystemUpdates(allocator: std.mem.Allocator) !void {
    std.debug.print("Benchmark 3: System Updates\n", .{});
    
    var world = World.init(allocator);
    defer world.deinit();
    
    // Add systems
    try world.addSystem(System.init("movement", zecs.systems.movementSystem));
    try world.addSystem(System.init("health", zecs.systems.healthSystem));
    
    const entity_count = 5000;
    
    // Create entities with components
    for (0..entity_count) |_| {
        const entity = try world.createEntity();
        
        const position = try Position.init(0.0, 0.0, allocator);
        const velocity = try Velocity.init(1.0, 1.0, allocator);
        const health = try Health.init(100, allocator);
        
        try world.addComponent(entity, &position.component);
        try world.addComponent(entity, &velocity.component);
        try world.addComponent(entity, &health.component);
    }
    
    const update_count = 1000;
    const dt = 1.0 / 60.0;
    
    const start_time = std.time.nanoTimestamp();
    
    for (0..update_count) |_| {
        try world.update(dt);
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const updates_per_second = @as(f64, @floatFromInt(update_count)) / (duration_ms / 1000.0);
    
    std.debug.print("  Ran {d} updates on {d} entities in {d:.2}ms\n", .{ update_count, entity_count, duration_ms });
    std.debug.print("  Rate: {d:.0} updates/second\n\n", .{updates_per_second});
}

fn benchmarkLargeWorld(allocator: std.mem.Allocator) !void {
    std.debug.print("Benchmark 4: Large World Simulation\n", .{});
    
    var world = World.init(allocator);
    defer world.deinit();
    
    // Add systems
    try world.addSystem(System.init("movement", zecs.systems.movementSystem));
    try world.addSystem(System.init("health", zecs.systems.healthSystem));
    
    const entity_count = 10000;
    
    // Create large number of entities
    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();
    
    for (0..entity_count) |_| {
        const entity = try world.createEntity();
        
        const position = try Position.init(
            random.float(f32) * 1000.0, 
            random.float(f32) * 1000.0,
            allocator
        );
        const velocity = try Velocity.init(
            (random.float(f32) - 0.5) * 100.0,
            (random.float(f32) - 0.5) * 100.0,
            allocator
        );
        const health = try Health.init(
            50 + @as(i32, @intFromFloat(random.float(f32) * 50.0)),
            allocator
        );
        
        try world.addComponent(entity, &position.component);
        try world.addComponent(entity, &velocity.component);
        try world.addComponent(entity, &health.component);
    }
    
    const simulation_ticks = 600; // 10 seconds at 60 FPS
    const dt = 1.0 / 60.0;
    
    const start_time = std.time.nanoTimestamp();
    
    for (0..simulation_ticks) |_| {
        try world.update(dt);
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const simulation_time = @as(f64, @floatFromInt(simulation_ticks)) * dt;
    const real_time_factor = simulation_time / (duration_ms / 1000.0);
    
    std.debug.print("  Simulated {d:.1}s with {d} entities in {d:.2}ms\n", .{ simulation_time, entity_count, duration_ms });
    std.debug.print("  Real-time factor: {d:.1}x\n", .{real_time_factor});
    
    if (real_time_factor > 1.0) {
        std.debug.print("  ✓ Simulation runs faster than real-time!\n\n", .{});
    } else {
        std.debug.print("  ⚠ Simulation runs slower than real-time\n\n", .{});
    }
}
