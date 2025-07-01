# 🧱 ZECS - Zig Entity Component System
*"The present, in motion."*

A high-performance, production-ready Entity Component System (ECS) framework for Zig, designed for complex simulations, games, and real-time applications. Built to seamlessly integrate with the ZSQLite ecosystem for robust persistence.

## 🎯 Overview

ZECS is a fast, robust ECS library for Zig, supporting both pure in-memory and hybrid (SQLite-backed) operation. It is suitable for real-time games, simulations, and persistent worlds.

## 🚀 Features
- Archetype-based, cache-friendly storage
- Generational entity IDs (safe, fast reuse)
- Bulk entity/component operations
- Multi-threaded system execution
- Async write-behind persistence (via zsqlite)
- Dirty tracking (only changed data is written)
- Batch updates and blazing-fast SQL for persistence
- Time-skipping/event-based simulation
- Real-time performance with minimal persistence overhead

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

## 📋 Example Usage

```zig
const std = @import("std");
const zecs = @import("zecs");

// Define components
const Position = struct { x: f32, y: f32 };
const Velocity = struct { dx: f32, dy: f32 };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // In-memory world (no persistence)
    var world = try zecs.SqliteWorld.init(allocator, null);
    // For persistent world, use: var world = try zecs.SqliteWorld.init(allocator, "my_world.db");
    defer world.deinit();

    // Create entities
    const entities = try world.createEntities(100);
    defer allocator.free(entities);

    // Add components
    for (entities) |entity| {
        try world.addPosition(entity, 0.0, 0.0);
        try world.addVelocity(entity, 1.0, 0.5);
    }

    // Run a simple system loop (e.g., movement)
    const dt = 1.0 / 60.0;
    for (0..60) |_| {
        _ = try world.batchMovementUpdateBlazing(dt);
    }

    // (Optional) Start persistence if using a DB
    // try world.startPersistence();
}
```

## 🔧 Building

```bash
zig build          # Build the library
zig build test     # Run tests
zig build bench    # Run benchmarks
zig build examples # Build examples
```

## 📊 Performance

See `PERFORMANCE_REPORT.md` for detailed benchmarks and technical implementation notes.

## 🤝 Integration

ZECS is designed to work seamlessly with:
- **zsqlite** - Persistent storage and historical data
- **zai** (future) - AI behavior trees and decision making
- **zgrid** (future) - Spatial world management

## 📄 License
MIT License
