const std = @import("std");
const zecs = @import("zecs");

const World = zecs.World;
const System = zecs.System;
const Position = zecs.components.Position;
const Velocity = zecs.components.Velocity;
const Health = zecs.components.Health;
const AI = zecs.components.AI;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create world
    var world = World.init(allocator);
    defer world.deinit();
    
    std.debug.print("=== ZECS Ecosystem Simulation ===\n\n", .{});
    
    // Add systems
    try world.addSystem(System.init("movement", zecs.systems.movementSystem));
    try world.addSystem(System.init("ai", zecs.systems.aiSystem));
    try world.addSystem(System.init("health", zecs.systems.healthSystem));
    
    // Create a larger ecosystem
    var prng = std.Random.DefaultPrng.init(12345);
    const random = prng.random();
    
    // Create 10 predators
    for (0..10) |_| {
        const x = random.float(f32) * 200.0;
        const y = random.float(f32) * 200.0;
        try createPredator(&world, x, y);
    }
    
    // Create 30 prey
    for (0..30) |_| {
        const x = random.float(f32) * 200.0;
        const y = random.float(f32) * 200.0;
        try createPrey(&world, x, y);
    }
    
    // Create 5 scavengers
    for (0..5) |_| {
        const x = random.float(f32) * 200.0;
        const y = random.float(f32) * 200.0;
        try createScavenger(&world, x, y);
    }
    
    std.debug.print("Created ecosystem with {} entities\n", .{world.getEntityCount()});
    
    // Run simulation
    const simulation_time = 30.0; // 30 seconds
    const dt = 1.0 / 60.0; // 60 FPS
    var elapsed_time: f32 = 0.0;
    var tick: u32 = 0;
    
    std.debug.print("\nRunning ecosystem simulation...\n", .{});
    
    while (elapsed_time < simulation_time) {
        // Update all systems
        try world.update(dt);
        
        elapsed_time += dt;
        tick += 1;
        
        // Print status every 5 seconds
        if (@mod(tick, 300) == 0) {
            const seconds = @floor(elapsed_time);
            std.debug.print("Time: {d:.0}s - Entities: {d} - Tick: {d}\n", .{
                seconds, world.getEntityCount(), tick
            });
        }
    }
    
    // Final status
    std.debug.print("\nEcosystem simulation complete!\n", .{});
    std.debug.print("Total time: {d:.1}s\n", .{elapsed_time});
    std.debug.print("Total ticks: {d}\n", .{tick});
    std.debug.print("Final entities: {d}\n", .{world.getEntityCount()});
}

fn createPredator(world: *World, x: f32, y: f32) !void {
    const entity = try world.createEntity();
    const allocator = world.allocator;
    
    // Position
    const position = try Position.init(x, y, allocator);
    const velocity = try Velocity.init(0.0, 0.0, allocator);
    const health = try Health.init(100, allocator);
    const ai = try AI.init(.chasing, allocator);
    
    try world.addComponent(entity, &position.component);
    try world.addComponent(entity, &velocity.component);
    try world.addComponent(entity, &health.component);
    try world.addComponent(entity, &ai.component);
}

fn createPrey(world: *World, x: f32, y: f32) !void {
    const entity = try world.createEntity();
    const allocator = world.allocator;
    
    // Position
    const position = try Position.init(x, y, allocator);
    const velocity = try Velocity.init(0.0, 0.0, allocator);
    const health = try Health.init(60, allocator);
    const ai = try AI.init(.fleeing, allocator);
    
    try world.addComponent(entity, &position.component);
    try world.addComponent(entity, &velocity.component);
    try world.addComponent(entity, &health.component);
    try world.addComponent(entity, &ai.component);
}

fn createScavenger(world: *World, x: f32, y: f32) !void {
    const entity = try world.createEntity();
    const allocator = world.allocator;
    
    // Position
    const position = try Position.init(x, y, allocator);
    const velocity = try Velocity.init(0.0, 0.0, allocator);
    const health = try Health.init(80, allocator);
    const ai = try AI.init(.wandering, allocator);
    
    try world.addComponent(entity, &position.component);
    try world.addComponent(entity, &velocity.component);
    try world.addComponent(entity, &health.component);
    try world.addComponent(entity, &ai.component);
}
