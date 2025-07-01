# 🧱 ZECS - Zig Entity Component System
*"The present, in motion."*

A high-performance, feature-rich Entity Component System (ECS) framework for Zig, designed for complex simulations, games, and real-time applications. Built to seamlessly integrate with the ZSQLite ecosystem.

## 🎯 Vision

ZECS is the **runtime engine** that operates on data stored in zsqlite. While zsqlite handles persistence and historical data, zecs manages live entities, their behaviors, and real-time interactions.

## 🚀 Core Features (Planned)

### �️ Architecture
- **Archetype-based storage** - Cache-friendly component storage for maximum performance
- **Sparse set entities** - O(1) entity operations with efficient iteration
- **Component pools** - Pre-allocated memory pools to reduce allocations
- **Query optimization** - Smart query caching and batching
- **Multi-threaded systems** - Parallel system execution support

### 🆔 Entity Management
- **Generational entities** - Prevent use-after-free with versioned entity IDs
- **Entity templates** - Predefined entity archetypes for quick spawning
- **Bulk operations** - Create/destroy thousands of entities efficiently
- **Entity relationships** - Parent-child hierarchies and entity references
- **Entity pools** - Reuse entity IDs to minimize memory fragmentation

### 🧩 Component System
- **Zero-cost abstractions** - Compile-time component type checking
- **Component serialization** - Automatic serialization for zsqlite integration
- **Component validation** - Runtime integrity checks and constraints
- **Component events** - Lifecycle hooks (on_add, on_remove, on_update)
- **Component queries** - Advanced filtering and selection

### ⚙️ System Framework
- **System dependencies** - Automatic system ordering and dependency resolution
- **System priorities** - Control execution order with priority levels
- **System groups** - Organize systems into logical groups
- **Conditional systems** - Enable/disable systems based on world state
- **System profiling** - Built-in performance monitoring

### 🧠 Advanced Features
- **State machines** - Built-in FSM support for complex entity behaviors
- **Event system** - Pub/sub messaging between systems and entities
- **Resource management** - Global resources accessible to all systems
- **Time management** - Delta time, fixed timestep, and time scaling
- **Spatial partitioning** - Built-in spatial indexing for position-based queries

### 🗃️ ZSQLite Integration
- **Persistent entities** - Save/load entity states to/from database
- **Incremental saves** - Only save changed components
- **World snapshots** - Create complete world state backups
- **Historical queries** - Query past states and changes
- **Migration system** - Handle schema changes gracefully

## 📋 API Reference (Planned)

### World Management
```zig
// World creation and lifecycle
var world = World.init(allocator);
defer world.deinit();

// Database integration
try world.connectDatabase("simulation.db");
try world.loadFromDatabase();
try world.saveToDatabase();

// Performance monitoring
const stats = world.getPerformanceStats();
world.enableProfiling(true);
```

### Entity Operations
```zig
// Entity creation
const entity = try world.createEntity();
const entity_from_template = try world.createEntityFromTemplate("npc_template");

// Bulk operations
const entities = try world.createEntities(1000);
world.destroyEntities(entities);

// Entity queries
const living_entities = try world.query(.{Health, Position}, .{Dead});
```

### Component Management
```zig
// Component registration
world.registerComponent(Position);
world.registerComponent(Velocity);
world.registerComponent(Health);

// Component operations
try world.addComponent(entity, Position{.x = 10, .y = 20});
const pos = world.getComponent(entity, Position);
world.removeComponent(entity, Position);

// Component events
world.onComponentAdded(Position, onPositionAdded);
world.onComponentRemoved(Health, onHealthRemoved);
```

### System Definition
```zig
// System registration
const MovementSystem = System.init(.{
    .name = "movement",
    .query = .{Position, Velocity},
    .exclude = .{Dead},
    .update = movementUpdate,
    .priority = 10,
});

world.addSystem(MovementSystem);

// System groups
const PhysicsGroup = SystemGroup.init(.{
    .name = "physics",
    .systems = .{MovementSystem, CollisionSystem},
});

world.addSystemGroup(PhysicsGroup);
```

### Advanced Queries
```zig
// Complex queries
const query = world.query(.{
    .with = .{Position, Health},
    .without = .{Dead, Invisible},
    .where = |entity| world.getComponent(entity, Health).?.value > 0,
});

// Spatial queries
const nearby = world.queryInRadius(Position{.x = 100, .y = 100}, 50.0);
const in_area = world.queryInBounds(min_pos, max_pos);
```

## 🏃‍♂️ Performance Targets

- **10,000+ entities** at 60fps with complex logic
- **Sub-millisecond** system execution for simple operations
- **Memory efficiency** - Minimal allocations during runtime
- **Cache-friendly** data access patterns
- **Scalable** architecture for massive simulations

## 🧪 Example Usage

### Basic Simulation
```zig
const std = @import("std");
const zecs = @import("zecs");

// Define components
const Position = struct { x: f32, y: f32, z: f32 };
const Velocity = struct { dx: f32, dy: f32, dz: f32 };
const Health = struct { current: i32, max: i32 };
const AI = struct { state: AIState, target: ?EntityId };

// Define systems
fn movementSystem(world: *World, dt: f32) !void {
    var query = world.query(.{Position, Velocity});
    while (query.next()) |entity| {
        const pos = world.getComponentMut(entity, Position);
        const vel = world.getComponent(entity, Velocity);
        
        pos.x += vel.dx * dt;
        pos.y += vel.dy * dt;
        pos.z += vel.dz * dt;
    }
}

fn aiSystem(world: *World, dt: f32) !void {
    var query = world.query(.{AI, Position});
    while (query.next()) |entity| {
        const ai = world.getComponentMut(entity, AI);
        const pos = world.getComponent(entity, Position);
        
        // AI logic here
        switch (ai.state) {
            .hunting => updateHunting(world, entity, ai, pos),
            .fleeing => updateFleeing(world, entity, ai, pos),
            .idle => updateIdle(world, entity, ai, pos),
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create world with database integration
    var world = zecs.World.init(allocator);
    defer world.deinit();
    
    try world.connectDatabase("ecosystem.db");
    
    // Register components
    world.registerComponent(Position);
    world.registerComponent(Velocity);
    world.registerComponent(Health);
    world.registerComponent(AI);
    
    // Add systems
    world.addSystem(movementSystem, .{.priority = 10});
    world.addSystem(aiSystem, .{.priority = 5});
    
    // Create entities
    for (0..1000) |_| {
        const entity = try world.createEntity();
        try world.addComponent(entity, Position{
            .x = randomFloat(-100, 100),
            .y = randomFloat(-100, 100),
            .z = 0,
        });
        try world.addComponent(entity, Velocity{
            .dx = randomFloat(-5, 5),
            .dy = randomFloat(-5, 5),
            .dz = 0,
        });
        try world.addComponent(entity, Health{.current = 100, .max = 100});
        try world.addComponent(entity, AI{.state = .idle, .target = null});
    }
    
    // Main simulation loop
    var timer = std.time.Timer.start() catch unreachable;
    while (true) {
        const dt = @as(f32, @floatFromInt(timer.lap())) / std.time.ns_per_s;
        
        // Update all systems
        try world.update(dt);
        
        // Save periodically
        if (world.getTick() % 300 == 0) { // Every 5 seconds at 60fps
            try world.saveToDatabase();
        }
        
        // Maintain 60fps
        std.time.sleep(16_666_667); // ~60fps
    }
}
```

## 🏗️ Development Roadmap

### Phase 1: Core Architecture ✅
- [x] Basic entity management
- [x] Component system foundation
- [x] Simple system execution
- [x] Basic tests

### Phase 2: Performance Optimization 🚧
- [ ] Archetype-based storage
- [ ] Component pools
- [ ] Query optimization
- [ ] Memory profiling

### Phase 3: Advanced Features 📋
- [ ] Multi-threaded systems
- [ ] Event system
- [ ] State machines
- [ ] Spatial partitioning

### Phase 4: ZSQLite Integration 📋
- [ ] Component serialization
- [ ] Database persistence
- [ ] World snapshots
- [ ] Migration system

### Phase 5: Developer Experience 📋
- [ ] Comprehensive documentation
- [ ] Example projects
- [ ] Performance benchmarks
- [ ] Debug tools

## 🤝 Integration with ZSQLite Ecosystem

ZECS is designed to work seamlessly with:
- **zsqlite** - Persistent storage and historical data
- **zai** (future) - AI behavior trees and decision making
- **zgrid** (future) - Spatial world management

## 🔧 Building

```bash
# Build the library
zig build

# Run tests
zig build test

# Run benchmarks
zig build bench

# Build examples
zig build examples
```

## 🧪 Test & Demo Types

ZECS includes a variety of tests and demos to validate performance, persistence, and multi-threading:

- **Memory-Only Tests**: Run the ECS entirely in memory, with no persistence. Fastest mode, no zsqlite required.
- **Hybrid/Persistent Tests**: Use SQLite-backed persistence (via zsqlite) for all entity/component data. Demonstrates async write-behind and dirty tracking. Requires zsqlite.
- **Multi-Threaded Tests**: Stress-test the ECS with concurrent system execution and background persistence. Validates thread safety and async DB writes.
- **Performance Demos**: Run large-scale simulations (e.g., 5,000+ entities) and print real-time stats. See `comprehensive_demo.zig` for a full comparison of memory vs. persistent modes.
- **Time-Skip/Event-Based Tests**: Efficiently simulate off-screen or inactive entities in bulk. See `game_of_life_timeskip.zig` for an example.

Run all tests with:
```sh
zig build test
```
Run the main performance demo with:
```sh
zig build run
```

## 🗃️ How zsqlite is Used

- **zsqlite** is only required for persistent/hybrid modes. Memory-only mode does not require it.
- ZECS uses zsqlite for:
  - Persistent storage of entities and components
  - Async write-behind (background DB writes)
  - Dirty tracking (only changed data is written)
  - World snapshots and historical queries (planned)
- The zsqlite dependency is managed via `build.zig.zon` and is not checked into the repo.

## ⚡ Speed & Performance Mechanisms

ZECS achieves high performance through:
- **Archetype-based storage**: Cache-friendly, fast iteration over entities with the same component set
- **Batch updates**: Systems can update thousands of entities in a single pass
- **Async write-behind**: Persistence is handled in the background, minimizing simulation stalls
- **Dirty tracking**: Only changed components are written to disk
- **Multi-threading**: Systems and persistence can run in parallel (see `multi_thread_test.zig`)
- **Time-skipping**: Efficiently simulates inactive entities in bulk (see `game_of_life_timeskip.zig`)

See the `benchmarks/` and `examples/` folders for more details and usage patterns.
