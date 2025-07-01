# ZECS + ZSQLite Integration Plan

## 🎯 Integration Goals

Transform ZECS from a runtime-only ECS into a **persistent simulation engine** that can save, load, and query historical world states using ZSQLite as the storage backend.

## 🏗️ Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│     ZECS        │    │   Integration   │    │    ZSQLite      │
│   (Runtime)     │◄──►│     Layer       │◄──►│  (Persistence)  │
├─────────────────┤    ├─────────────────┤    ├─────────────────┤
│ • Entities      │    │ • Serialization │    │ • Entity Tables │
│ • Components    │    │ • Sync Manager  │    │ • Component DB  │
│ • Systems       │    │ • Schema Mgmt   │    │ • History Log   │
│ • Queries       │    │ • Change Track  │    │ • Snapshots     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🔗 Integration Components

### 1. Database Schema (ZSQLite Side)

```sql
-- Core entity tracking
CREATE TABLE zecs_entities (
    id INTEGER PRIMARY KEY,
    generation INTEGER NOT NULL DEFAULT 1,
    archetype_id INTEGER,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Component storage with versioning
CREATE TABLE zecs_components (
    entity_id INTEGER NOT NULL,
    component_type TEXT NOT NULL,
    component_data BLOB NOT NULL,
    version INTEGER DEFAULT 1,
    checksum TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (entity_id, component_type),
    FOREIGN KEY (entity_id) REFERENCES zecs_entities(id)
);

-- Change tracking for incremental saves
CREATE TABLE zecs_changes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_id INTEGER NOT NULL,
    component_type TEXT,
    action TEXT NOT NULL, -- 'entity_created', 'entity_destroyed', 'component_added', 'component_updated', 'component_removed'
    old_data BLOB,
    new_data BLOB,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    session_id TEXT NOT NULL
);

-- World snapshots for full state backups
CREATE TABLE zecs_snapshots (
    name TEXT PRIMARY KEY,
    description TEXT,
    world_tick INTEGER NOT NULL,
    entity_count INTEGER NOT NULL,
    component_count INTEGER NOT NULL,
    compressed_data BLOB NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- System execution logs for debugging
CREATE TABLE zecs_system_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    system_name TEXT NOT NULL,
    execution_time_ns INTEGER NOT NULL,
    entities_processed INTEGER DEFAULT 0,
    tick INTEGER NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Archetype definitions for optimization
CREATE TABLE zecs_archetypes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    component_signature TEXT NOT NULL UNIQUE,
    entity_count INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### 2. Serialization System (ZECS Side)

```zig
/// Component serialization interface
pub const ComponentSerializer = struct {
    const Self = @This();
    
    serialize_fn: *const fn(*const anyopaque, Allocator) ![]u8,
    deserialize_fn: *const fn([]const u8, Allocator) !*anyopaque,
    type_name: []const u8,
    type_id: u32,
    version: u32,
    
    pub fn serialize(self: Self, component: *const anyopaque, allocator: Allocator) ![]u8 {
        return self.serialize_fn(component, allocator);
    }
    
    pub fn deserialize(self: Self, data: []const u8, allocator: Allocator) !*anyopaque {
        return self.deserialize_fn(data, allocator);
    }
};

/// Auto-generate serializers for simple structs
pub fn AutoSerializer(comptime T: type) ComponentSerializer {
    const SerializerImpl = struct {
        fn serialize(component: *const anyopaque, allocator: Allocator) ![]u8 {
            const typed_component: *const T = @ptrCast(@alignCast(component));
            
            // Use std.json for simple serialization
            var json_string = std.ArrayList(u8).init(allocator);
            try std.json.stringify(typed_component.*, .{}, json_string.writer());
            return json_string.toOwnedSlice();
        }
        
        fn deserialize(data: []const u8, allocator: Allocator) !*anyopaque {
            const parsed = try std.json.parseFromSlice(T, allocator, data, .{});
            const component = try allocator.create(T);
            component.* = parsed.value;
            return @ptrCast(component);
        }
    };
    
    return ComponentSerializer{
        .serialize_fn = SerializerImpl.serialize,
        .deserialize_fn = SerializerImpl.deserialize,
        .type_name = @typeName(T),
        .type_id = comptime typeId(T),
        .version = 1,
    };
}

/// Binary serialization for performance-critical components
pub fn BinarySerializer(comptime T: type) ComponentSerializer {
    const SerializerImpl = struct {
        fn serialize(component: *const anyopaque, allocator: Allocator) ![]u8 {
            const typed_component: *const T = @ptrCast(@alignCast(component));
            const size = @sizeOf(T);
            const data = try allocator.alloc(u8, size);
            @memcpy(data, std.mem.asBytes(typed_component));
            return data;
        }
        
        fn deserialize(data: []const u8, allocator: Allocator) !*anyopaque {
            if (data.len != @sizeOf(T)) return error.InvalidDataSize;
            const component = try allocator.create(T);
            @memcpy(std.mem.asBytes(component), data);
            return @ptrCast(component);
        }
    };
    
    return ComponentSerializer{
        .serialize_fn = SerializerImpl.serialize,
        .deserialize_fn = SerializerImpl.deserialize,
        .type_name = @typeName(T),
        .type_id = comptime typeId(T),
        .version = 1,
    };
}
```

### 3. Persistence Manager (Integration Layer)

```zig
/// Manages synchronization between ZECS and ZSQLite
pub const PersistenceManager = struct {
    const Self = @This();
    
    allocator: Allocator,
    db: *zsqlite.Database,
    world: *World,
    serializers: HashMap(u32, ComponentSerializer),
    change_tracker: ChangeTracker,
    session_id: []const u8,
    
    pub fn init(allocator: Allocator, db: *zsqlite.Database, world: *World) !Self {
        var self = Self{
            .allocator = allocator,
            .db = db,
            .world = world,
            .serializers = HashMap(u32, ComponentSerializer).init(allocator),
            .change_tracker = ChangeTracker.init(allocator),
            .session_id = try generateSessionId(allocator),
        };
        
        // Setup database schema
        try self.setupSchema();
        
        // Register default serializers
        try self.registerDefaultSerializers();
        
        return self;
    }
    
    /// Register a component type for persistence
    pub fn registerComponent(self: *Self, comptime T: type, serializer: ComponentSerializer) !void {
        const type_id = comptime typeId(T);
        try self.serializers.put(type_id, serializer);
        
        // Subscribe to component events
        self.world.onComponentAdded(T, onComponentAdded);
        self.world.onComponentRemoved(T, onComponentRemoved);
        self.world.onComponentUpdated(T, onComponentUpdated);
    }
    
    /// Save all changes to database
    pub fn saveChanges(self: *Self) !void {
        const changes = self.change_tracker.getChanges();
        defer self.change_tracker.clearChanges();
        
        try self.db.begin();
        defer self.db.commit() catch |err| {
            self.db.rollback() catch {};
            return err;
        };
        
        for (changes) |change| {
            try self.applyChange(change);
        }
    }
    
    /// Load world state from database
    pub fn loadWorld(self: *Self) !void {
        // Clear current world
        self.world.clear();
        
        // Load entities
        const entities_query = try self.db.prepare("SELECT id, generation FROM zecs_entities WHERE is_active = TRUE");
        defer entities_query.deinit();
        
        while (try entities_query.step()) {
            const entity_id = entities_query.columnInt(0);
            const generation = entities_query.columnInt(1);
            
            // Recreate entity with specific ID and generation
            try self.world.createEntityWithId(entity_id, generation);
            
            // Load components for this entity
            try self.loadEntityComponents(entity_id);
        }
    }
    
    /// Create a world snapshot
    pub fn createSnapshot(self: *Self, name: []const u8, description: []const u8) !void {
        const snapshot_data = try self.serializeWorld();
        defer self.allocator.free(snapshot_data);
        
        const compressed_data = try compress(snapshot_data, self.allocator);
        defer self.allocator.free(compressed_data);
        
        const insert_query = try self.db.prepare(
            "INSERT INTO zecs_snapshots (name, description, world_tick, entity_count, component_count, compressed_data) VALUES (?, ?, ?, ?, ?, ?)"
        );
        defer insert_query.deinit();
        
        try insert_query.bind(1, name);
        try insert_query.bind(2, description);
        try insert_query.bind(3, self.world.getTick());
        try insert_query.bind(4, self.world.getEntityCount());
        try insert_query.bind(5, self.world.getComponentCount());
        try insert_query.bind(6, compressed_data);
        
        try insert_query.step();
    }
    
    /// Load from a snapshot
    pub fn loadSnapshot(self: *Self, name: []const u8) !void {
        const query = try self.db.prepare("SELECT compressed_data FROM zecs_snapshots WHERE name = ?");
        defer query.deinit();
        
        try query.bind(1, name);
        
        if (!try query.step()) {
            return error.SnapshotNotFound;
        }
        
        const compressed_data = query.columnBlob(0);
        const snapshot_data = try decompress(compressed_data, self.allocator);
        defer self.allocator.free(snapshot_data);
        
        try self.deserializeWorld(snapshot_data);
    }
    
    /// Get historical component data
    pub fn getComponentHistory(self: *Self, entity_id: EntityId, comptime T: type, since: ?i64) ![]ComponentSnapshot(T) {
        const type_name = @typeName(T);
        
        var query_sql = std.ArrayList(u8).init(self.allocator);
        defer query_sql.deinit();
        
        try query_sql.appendSlice("SELECT new_data, timestamp FROM zecs_changes WHERE entity_id = ? AND component_type = ?");
        if (since) |timestamp| {
            try query_sql.appendSlice(" AND timestamp > ?");
        }
        try query_sql.appendSlice(" ORDER BY timestamp ASC");
        
        const query = try self.db.prepare(query_sql.items);
        defer query.deinit();
        
        try query.bind(1, entity_id);
        try query.bind(2, type_name);
        if (since) |timestamp| {
            try query.bind(3, timestamp);
        }
        
        var snapshots = std.ArrayList(ComponentSnapshot(T)).init(self.allocator);
        
        while (try query.step()) {
            const data = query.columnBlob(0);
            const timestamp = query.columnInt64(1);
            
            if (self.serializers.get(comptime typeId(T))) |serializer| {
                const component_ptr = try serializer.deserialize(data, self.allocator);
                const component: *T = @ptrCast(@alignCast(component_ptr));
                
                try snapshots.append(ComponentSnapshot(T){
                    .component = component.*,
                    .timestamp = timestamp,
                });
            }
        }
        
        return snapshots.toOwnedSlice();
    }
    
    // Private helper methods...
    fn setupSchema(self: *Self) !void {
        // Execute schema creation SQL
    }
    
    fn registerDefaultSerializers(self: *Self) !void {
        // Register serializers for built-in components
    }
    
    fn applyChange(self: *Self, change: Change) !void {
        // Apply individual change to database
    }
    
    fn loadEntityComponents(self: *Self, entity_id: EntityId) !void {
        // Load all components for a specific entity
    }
    
    fn serializeWorld(self: *Self) ![]u8 {
        // Serialize entire world state
    }
    
    fn deserializeWorld(self: *Self, data: []const u8) !void {
        // Deserialize world state from data
    }
};
```

### 4. Change Tracking System

```zig
/// Tracks all changes to entities and components
pub const ChangeTracker = struct {
    const Self = @This();
    
    changes: ArrayList(Change),
    entity_checksums: HashMap(EntityId, u64),
    
    pub const Change = struct {
        entity_id: EntityId,
        component_type: ?u32,
        action: Action,
        old_data: ?[]u8,
        new_data: ?[]u8,
        timestamp: i64,
        
        pub const Action = enum {
            entity_created,
            entity_destroyed,
            component_added,
            component_updated,
            component_removed,
        };
    };
    
    pub fn init(allocator: Allocator) Self {
        return Self{
            .changes = ArrayList(Change).init(allocator),
            .entity_checksums = HashMap(EntityId, u64).init(allocator),
        };
    }
    
    pub fn trackEntityCreated(self: *Self, entity_id: EntityId) !void {
        try self.changes.append(Change{
            .entity_id = entity_id,
            .component_type = null,
            .action = .entity_created,
            .old_data = null,
            .new_data = null,
            .timestamp = std.time.timestamp(),
        });
    }
    
    pub fn trackComponentAdded(self: *Self, entity_id: EntityId, component_type: u32, data: []const u8) !void {
        const owned_data = try self.changes.allocator.dupe(u8, data);
        try self.changes.append(Change{
            .entity_id = entity_id,
            .component_type = component_type,
            .action = .component_added,
            .old_data = null,
            .new_data = owned_data,
            .timestamp = std.time.timestamp(),
        });
    }
    
    pub fn trackComponentUpdated(self: *Self, entity_id: EntityId, component_type: u32, old_data: []const u8, new_data: []const u8) !void {
        const owned_old = try self.changes.allocator.dupe(u8, old_data);
        const owned_new = try self.changes.allocator.dupe(u8, new_data);
        try self.changes.append(Change{
            .entity_id = entity_id,
            .component_type = component_type,
            .action = .component_updated,
            .old_data = owned_old,
            .new_data = owned_new,
            .timestamp = std.time.timestamp(),
        });
    }
    
    pub fn getChanges(self: *Self) []const Change {
        return self.changes.items;
    }
    
    pub fn clearChanges(self: *Self) void {
        for (self.changes.items) |change| {
            if (change.old_data) |data| self.changes.allocator.free(data);
            if (change.new_data) |data| self.changes.allocator.free(data);
        }
        self.changes.clearRetainingCapacity();
    }
};
```

### 5. Integration API (World Extensions)

```zig
/// Extended World with persistence capabilities
pub const PersistentWorld = struct {
    const Self = @This();
    
    world: World,
    persistence: PersistenceManager,
    auto_save_interval: ?u64, // ticks between auto-saves
    last_save_tick: u64,
    
    pub fn init(allocator: Allocator, db_path: []const u8) !Self {
        // Initialize database
        var db = try zsqlite.Database.init(allocator);
        try db.open(db_path);
        
        // Initialize world
        var world = World.init(allocator);
        
        // Initialize persistence manager
        var persistence = try PersistenceManager.init(allocator, &db, &world);
        
        return Self{
            .world = world,
            .persistence = persistence,
            .auto_save_interval = null,
            .last_save_tick = 0,
        };
    }
    
    /// Enable automatic saving every N ticks
    pub fn enableAutoSave(self: *Self, interval_ticks: u64) void {
        self.auto_save_interval = interval_ticks;
    }
    
    /// Update world and handle auto-save
    pub fn update(self: *Self, dt: f32) !void {
        try self.world.update(dt);
        
        // Check if we need to auto-save
        if (self.auto_save_interval) |interval| {
            const current_tick = self.world.getTick();
            if (current_tick - self.last_save_tick >= interval) {
                try self.persistence.saveChanges();
                self.last_save_tick = current_tick;
            }
        }
    }
    
    /// Register a component type for persistence
    pub fn registerPersistentComponent(self: *Self, comptime T: type) !void {
        // Register with world
        self.world.registerComponent(T);
        
        // Register with persistence (auto-detect serialization method)
        const serializer = if (isSimpleStruct(T)) 
            AutoSerializer(T) 
        else 
            BinarySerializer(T);
            
        try self.persistence.registerComponent(T, serializer);
    }
    
    /// Manual save
    pub fn save(self: *Self) !void {
        try self.persistence.saveChanges();
        self.last_save_tick = self.world.getTick();
    }
    
    /// Load world state
    pub fn load(self: *Self) !void {
        try self.persistence.loadWorld();
    }
    
    /// Create snapshot
    pub fn snapshot(self: *Self, name: []const u8, description: []const u8) !void {
        try self.persistence.createSnapshot(name, description);
    }
    
    /// Load from snapshot
    pub fn loadSnapshot(self: *Self, name: []const u8) !void {
        try self.persistence.loadSnapshot(name);
    }
    
    /// Query historical component data
    pub fn getHistory(self: *Self, entity_id: EntityId, comptime T: type, since: ?i64) ![]ComponentSnapshot(T) {
        return self.persistence.getComponentHistory(entity_id, T, since);
    }
    
    // Delegate all other World methods...
    pub usingnamespace @This().world;
};
```

## 🚀 Usage Examples

### Basic Persistent World
```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create persistent world
    var world = try PersistentWorld.init(allocator, "simulation.db");
    defer world.deinit();
    
    // Register persistent components
    try world.registerPersistentComponent(Position);
    try world.registerPersistentComponent(Velocity);
    try world.registerPersistentComponent(Health);
    
    // Enable auto-save every 5 seconds (300 ticks at 60fps)
    world.enableAutoSave(300);
    
    // Try to load existing world, or create new one
    world.load() catch |err| switch (err) {
        error.NoExistingWorld => {
            std.log.info("Creating new world...");
            try createInitialWorld(&world);
        },
        else => return err,
    };
    
    // Main simulation loop
    var timer = std.time.Timer.start() catch unreachable;
    while (true) {
        const dt = @as(f32, @floatFromInt(timer.lap())) / std.time.ns_per_s;
        
        try world.update(dt);
        
        // Create daily snapshots
        if (world.getTick() % (60 * 60 * 24) == 0) { // Every 24 in-game hours
            const snapshot_name = try std.fmt.allocPrint(allocator, "day_{d}", .{world.getTick() / (60 * 60 * 24)});
            defer allocator.free(snapshot_name);
            
            try world.snapshot(snapshot_name, "Daily automatic snapshot");
        }
        
        std.time.sleep(16_666_667); // 60fps
    }
}
```

### Historical Analysis
```zig
pub fn analyzeEntityHistory(world: *PersistentWorld, entity_id: EntityId) !void {
    // Get position history for the last hour
    const one_hour_ago = std.time.timestamp() - 3600;
    const position_history = try world.getHistory(entity_id, Position, one_hour_ago);
    defer world.persistence.allocator.free(position_history);
    
    std.log.info("Entity {d} position history:", .{entity_id});
    for (position_history) |snapshot| {
        std.log.info("  Time: {d}, Position: ({d:.2}, {d:.2})", .{
            snapshot.timestamp, 
            snapshot.component.x, 
            snapshot.component.y
        });
    }
    
    // Calculate total distance traveled
    var total_distance: f32 = 0;
    for (position_history[1..], position_history[0..position_history.len-1]) |curr, prev| {
        const dx = curr.component.x - prev.component.x;
        const dy = curr.component.y - prev.component.y;
        total_distance += @sqrt(dx*dx + dy*dy);
    }
    
    std.log.info("Total distance traveled: {d:.2}", .{total_distance});
}
```

This integration plan creates a seamless bridge between ZECS's runtime performance and ZSQLite's persistent storage, enabling complex simulations that can save/load state, create snapshots, and perform historical analysis! 🚀
