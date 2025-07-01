const std = @import("std");
const zecs = @import("zecs");

// Import what we need
const World = zecs.World;
const Position = zecs.Position;
const Velocity = zecs.Velocity;
const Health = zecs.Health;
const AI = zecs.AI;
const AIState = zecs.components.gameplay.AIState;
const System = zecs.System;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create world
    var world = World.init(allocator);
    defer world.deinit();
    
    std.debug.print("=== ZECS Library Demo ===\n\n", .{});
    
    // Add systems to the world
    try world.addSystem(System.init("movement", zecs.movementSystem));
    try world.addSystem(System.init("velocity", zecs.systems.velocitySystem));
    try world.addSystem(System.init("health", zecs.systems.healthSystem));
    try world.addSystem(System.init("ai", zecs.systems.aiSystem));
    try world.addSystem(System.init("wandering", zecs.systems.wanderingSystem));
    
    std.debug.print("Added {} systems to world\n", .{world.getSystemCount()});
    
    // Create some entities with different behaviors
    try createPredator(&world, 50, 50, allocator);
    try createPrey(&world, 20, 80, allocator);
    try createPrey(&world, 80, 20, allocator);
    try createWanderer(&world, 0, 0, allocator);
    try createWanderer(&world, 100, 100, allocator);
    
    std.debug.print("Created {} entities\n", .{world.getEntityCount()});
    
    // Run simulation for several seconds
    std.debug.print("\nRunning simulation...\n", .{});
    const start_time = std.time.milliTimestamp();
    var last_print = start_time;
    
    while (true) {
        const current_time = std.time.milliTimestamp();
        const dt = 0.016; // 60 FPS
        
        // Update all systems
        try world.update(dt);
        
        // Print status every second
        if (current_time - last_print >= 1000) {
            const runtime = @as(f32, @floatFromInt(current_time - start_time)) / 1000.0;
            std.debug.print("Time: {d:.1}s - Entities: {d} - Tick: {d}\n", .{
                runtime,
                world.getEntityCount(),
                world.getTick(),
            });
            last_print = current_time;
            
            // Stop after 10 seconds
            if (runtime >= 10.0) break;
        }
        
        // Maintain 60 FPS
        std.time.sleep(16_666_667);
    }
    
    std.debug.print("\nSimulation complete!\n", .{});
    world.debugPrint();
}

fn createPredator(world: *World, x: f32, y: f32, allocator: std.mem.Allocator) !void {
    const entity = try world.createEntity();
    
    const position = try Position.init(x, y, allocator);
    const velocity = try Velocity.init(0, 0, allocator);
    const health = try Health.initWithRegen(150, 1.0, allocator); // 150 HP, 1 HP/sec regen
    const ai = try AI.init(.idle, allocator);
    
    try world.addComponent(entity, &position.component);
    try world.addComponent(entity, &velocity.component);
    try world.addComponent(entity, &health.component);
    try world.addComponent(entity, &ai.component);
    
    std.debug.print("Created predator at ({d:.1}, {d:.1})\n", .{ x, y });
}

fn createPrey(world: *World, x: f32, y: f32, allocator: std.mem.Allocator) !void {
    const entity = try world.createEntity();
    
    const position = try Position.init(x, y, allocator);
    const velocity = try Velocity.init(0, 0, allocator);
    const health = try Health.initWithRegen(75, 0.5, allocator); // 75 HP, 0.5 HP/sec regen
    const ai = try AI.init(.wandering, allocator); // Start wandering
    
    try world.addComponent(entity, &position.component);
    try world.addComponent(entity, &velocity.component);
    try world.addComponent(entity, &health.component);
    try world.addComponent(entity, &ai.component);
    
    std.debug.print("Created prey at ({d:.1}, {d:.1})\n", .{ x, y });
}

fn createWanderer(world: *World, x: f32, y: f32, allocator: std.mem.Allocator) !void {
    const entity = try world.createEntity();
    
    const position = try Position.init(x, y, allocator);
    const velocity = try Velocity.init(0, 0, allocator);
    const ai = try AI.init(.wandering, allocator);
    
    try world.addComponent(entity, &position.component);
    try world.addComponent(entity, &velocity.component);
    try world.addComponent(entity, &ai.component);
    
    std.debug.print("Created wanderer at ({d:.1}, {d:.1})\n", .{ x, y });
}
