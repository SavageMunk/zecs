const std = @import("std");
const zsqlite = @import("zsqlite");
const c = zsqlite.c;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const EntityId = @import("entity.zig").EntityId;

/// SQLite-powered ECS World for high-performance batch operations
pub const SqliteWorld = struct {
    const Self = @This();
    
    db: ?*c.sqlite3,
    allocator: Allocator,
    
    // Prepared statements for performance
    insert_entity_stmt: ?*c.sqlite3_stmt,
    insert_component_stmt: ?*c.sqlite3_stmt,
    
    // HOT ENTITY TRACKING for ultra-fast updates
    hot_entities: std.AutoHashMap(EntityId, void),
    dirty_positions: std.AutoHashMap(EntityId, [2]f32),
    dirty_entities: std.AutoHashMap(EntityId, void), // Track dirty entities for async persistence
    
    // PERSISTENCE SYSTEM
    persistence_thread: ?std.Thread,
    persistence_queue: std.fifo.LinearFifo(PersistenceCommand, .Dynamic),
    persistence_mutex: std.Thread.Mutex,
    should_stop_persistence: std.atomic.Value(bool),
    persistent_db_path: ?[]u8, // Owned copy
    
    next_entity_id: EntityId,
    
    pub fn init(allocator: Allocator, persistent_path: ?[]const u8) !Self {
        // Always use in-memory database for the main ECS (for max speed)
        // The persistent_path is only used for background persistence
        var db: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(":memory:", &db);
        
        if (rc != c.SQLITE_OK) {
            std.debug.print("Failed to open database: {s}\n", .{c.sqlite3_errmsg(db)});
            return error.SQLiteOpenFailed;
        }
        
        // Make a copy of the persistent path if provided and it's not ":memory:"
        const persistent_db_path = if (persistent_path) |original_path| blk: {
            if (std.mem.eql(u8, original_path, ":memory:")) {
                break :blk null; // Don't persist in-memory databases
            }
            break :blk try allocator.dupe(u8, original_path);
        } else null;
        
        var world = Self{
            .db = db,
            .allocator = allocator,
            .insert_entity_stmt = null,
            .insert_component_stmt = null,
            .hot_entities = std.AutoHashMap(EntityId, void).init(allocator),
            .dirty_positions = std.AutoHashMap(EntityId, [2]f32).init(allocator),
            .dirty_entities = std.AutoHashMap(EntityId, void).init(allocator),
            .persistence_thread = null,
            .persistence_queue = std.fifo.LinearFifo(PersistenceCommand, .Dynamic).init(allocator),
            .persistence_mutex = std.Thread.Mutex{},
            .should_stop_persistence = std.atomic.Value(bool).init(false),
            .persistent_db_path = persistent_db_path,
            .next_entity_id = 1,
        };
        
        try world.createTables();
        try world.prepareStatements();
        
        // Don't start persistence thread in init - wait for explicit call
        // This avoids race conditions during object construction
        
        return world;
    }
    
    pub fn deinit(self: *Self) void {
        // Signal the persistence thread to stop
        if (self.persistence_thread != null) {
            self.should_stop_persistence.store(true, .release);
            
            // Send shutdown command
            self.persistence_mutex.lock();
            self.persistence_queue.writeItem(.shutdown) catch {};
            self.persistence_mutex.unlock();
            
            // Wait for thread to finish
            if (self.persistence_thread) |thread| {
                thread.join();
                std.debug.print("🛑 Persistence thread joined\n", .{});
            }
        }
        
        // Clean up persistence queue
        self.persistence_queue.deinit();
        
        // Free persistent path if we own it
        if (self.persistent_db_path) |path| {
            self.allocator.free(path);
        }
        
        if (self.insert_entity_stmt) |stmt| _ = c.sqlite3_finalize(stmt);
        if (self.insert_component_stmt) |stmt| _ = c.sqlite3_finalize(stmt);
        self.hot_entities.deinit();
        self.dirty_positions.deinit();
        self.dirty_entities.deinit();
        if (self.db) |db| _ = c.sqlite3_close(db);
    }
    
    /// Create the ECS tables optimized for batch operations
    fn createTables(self: *Self) !void {
        var errmsg: [*c]u8 = null;
        
        // Entities table
        const entities_sql = 
            \\CREATE TABLE IF NOT EXISTS entities (
            \\    id INTEGER PRIMARY KEY,
            \\    created_at INTEGER DEFAULT (unixepoch()),
            \\    active INTEGER DEFAULT 1
            \\);
        ;
        
        var rc = c.sqlite3_exec(self.db, entities_sql, null, null, &errmsg);
        if (rc != c.SQLITE_OK) {
            std.debug.print("Error creating entities table: {s}\n", .{errmsg});
            if (errmsg != null) c.sqlite3_free(errmsg);
            return error.SQLiteExecFailed;
        }
        
        // Components table with optimized schema for batch queries
        const components_sql = 
            \\CREATE TABLE IF NOT EXISTS components (
            \\    entity_id INTEGER NOT NULL,
            \\    component_type INTEGER NOT NULL,
            \\    x REAL,
            \\    y REAL,
            \\    z REAL,
            \\    dx REAL,
            \\    dy REAL,
            \\    dz REAL,
            \\    health_current INTEGER,
            \\    health_max INTEGER,
            \\    energy_current REAL,
            \\    energy_max REAL,
            \\    ai_state INTEGER,
            \\    ai_target INTEGER,
            \\    data BLOB,
            \\    PRIMARY KEY (entity_id, component_type),
            \\    FOREIGN KEY (entity_id) REFERENCES entities(id)
            \\);
        ;
        
        rc = c.sqlite3_exec(self.db, components_sql, null, null, &errmsg);
        if (rc != c.SQLITE_OK) {
            std.debug.print("Error creating components table: {s}\n", .{errmsg});
            if (errmsg != null) c.sqlite3_free(errmsg);
            return error.SQLiteExecFailed;
        }
        
        // Indexes for fast queries
        const indexes = [_][]const u8{
            "CREATE INDEX IF NOT EXISTS idx_components_type ON components(component_type);",
            "CREATE INDEX IF NOT EXISTS idx_components_entity ON components(entity_id);",
            "CREATE INDEX IF NOT EXISTS idx_position ON components(component_type, x, y) WHERE component_type = 1;",
            "CREATE INDEX IF NOT EXISTS idx_velocity ON components(component_type, dx, dy) WHERE component_type = 2;",
            "CREATE INDEX IF NOT EXISTS idx_health ON components(component_type, health_current) WHERE component_type = 3;",
        };
        
        for (indexes) |index_sql| {
            rc = c.sqlite3_exec(self.db, index_sql.ptr, null, null, &errmsg);
            if (rc != c.SQLITE_OK) {
                std.debug.print("Error creating index: {s}\n", .{errmsg});
                if (errmsg != null) c.sqlite3_free(errmsg);
                return error.SQLiteExecFailed;
            }
        }
        
        // Optimize SQLite for batch performance
        const optimizations = [_][]const u8{
            "PRAGMA journal_mode = WAL;",           // Write-Ahead Logging for concurrency
            "PRAGMA synchronous = NORMAL;",         // Balance safety/speed (could be OFF for max speed)
            "PRAGMA cache_size = -131072;",         // 128MB cache (doubled from 64MB)
            "PRAGMA foreign_keys = OFF;",           // Disable FK checks for speed
            "PRAGMA temp_store = MEMORY;",          // Store temp tables in memory
            "PRAGMA mmap_size = 536870912;",        // 512MB memory mapped I/O (doubled)
            "PRAGMA page_size = 65536;",            // 64KB page size for better throughput
            "PRAGMA wal_autocheckpoint = 0;",       // Disable auto-checkpoint for max WAL performance
            "PRAGMA locking_mode = EXCLUSIVE;",     // Exclusive mode for single-writer performance
            "PRAGMA optimize;",                     // SQLite auto-optimization
        };
        
        for (optimizations) |pragma_sql| {
            rc = c.sqlite3_exec(self.db, pragma_sql.ptr, null, null, &errmsg);
            if (rc != c.SQLITE_OK) {
                std.debug.print("Warning: Optimization failed: {s}\n", .{errmsg});
                if (errmsg != null) c.sqlite3_free(errmsg);
                // Don't fail on optimizations
            }
        }
    }
    
    /// Prepare statements for high-performance operations
    fn prepareStatements(self: *Self) !void {
        var rc = c.sqlite3_prepare_v2(self.db, "INSERT INTO entities (id) VALUES (?)", -1, &self.insert_entity_stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
        
        // Use REPLACE for automatic overwrite - this is the magic!
        rc = c.sqlite3_prepare_v2(self.db, 
            \\REPLACE INTO components 
            \\(entity_id, component_type, x, y, z, dx, dy, dz, health_current, health_max, energy_current, energy_max, ai_state, ai_target, data)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        , -1, &self.insert_component_stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
    }
    
    /// Create a new entity
    pub fn createEntity(self: *Self) !EntityId {
        const entity_id = self.next_entity_id;
        self.next_entity_id += 1;
        
        var rc = c.sqlite3_bind_int64(self.insert_entity_stmt, 1, entity_id);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_step(self.insert_entity_stmt);
        if (rc != c.SQLITE_DONE) return error.SQLiteStepFailed;
        
        _ = c.sqlite3_reset(self.insert_entity_stmt);
        return entity_id;
    }
    
    /// Batch create multiple entities
    pub fn createEntities(self: *Self, count: u32) ![]EntityId {
        var entities = try self.allocator.alloc(EntityId, count);
        
        var errmsg: [*c]u8 = null;
        var rc = c.sqlite3_exec(self.db, "BEGIN TRANSACTION;", null, null, &errmsg);
        if (rc != c.SQLITE_OK) {
            if (errmsg != null) c.sqlite3_free(errmsg);
            return error.SQLiteExecFailed;
        }
        
        for (0..count) |i| {
            entities[i] = try self.createEntity();
        }
        
        rc = c.sqlite3_exec(self.db, "COMMIT;", null, null, &errmsg);
        if (rc != c.SQLITE_OK) {
            if (errmsg != null) c.sqlite3_free(errmsg);
            return error.SQLiteExecFailed;
        }
        
        return entities;
    }
    
    /// Add position component (optimized for spatial data) - NOW WITH VELOCITY!
    pub fn addPosition(self: *Self, entity_id: EntityId, x: f32, y: f32) !void {
        var rc = c.sqlite3_bind_int64(self.insert_component_stmt, 1, entity_id);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_int(self.insert_component_stmt, 2, 1); // Position type
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_double(self.insert_component_stmt, 3, x);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_double(self.insert_component_stmt, 4, y);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        // Initialize velocity to zero in position component
        rc = c.sqlite3_bind_null(self.insert_component_stmt, 5); // z position
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_double(self.insert_component_stmt, 6, 0.0); // dx
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_double(self.insert_component_stmt, 7, 0.0); // dy
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        // Bind remaining parameters as NULL
        for (8..16) |i| {
            rc = c.sqlite3_bind_null(self.insert_component_stmt, @intCast(i));
            if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        }
        
        rc = c.sqlite3_step(self.insert_component_stmt);
        if (rc != c.SQLITE_DONE) return error.SQLiteStepFailed;
        
        _ = c.sqlite3_reset(self.insert_component_stmt);
        self.markEntityDirty(entity_id);
    }
    
    /// Add velocity to existing position component (NO SEPARATE VELOCITY COMPONENT!)
    pub fn addVelocity(self: *Self, entity_id: EntityId, dx: f32, dy: f32) !void {
        // Update the position component with velocity - no separate component needed!
        const update_velocity_sql = 
            \\UPDATE components SET dx = ?, dy = ? 
            \\WHERE entity_id = ? AND component_type = 1;
        ;
        
        var stmt: ?*c.sqlite3_stmt = null;
        var rc = c.sqlite3_prepare_v2(self.db, update_velocity_sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);
        
        rc = c.sqlite3_bind_double(stmt, 1, dx);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_double(stmt, 2, dy);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_int64(stmt, 3, entity_id);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_step(stmt);
        if (rc != c.SQLITE_DONE) return error.SQLiteStepFailed;
        
        self.markEntityDirty(entity_id);
    }
    
    /// Add health component
    pub fn addHealth(self: *Self, entity_id: EntityId, current: i32, max: i32) !void {
        var rc = c.sqlite3_bind_int64(self.insert_component_stmt, 1, entity_id);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_int(self.insert_component_stmt, 2, 3); // Health type
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        // Bind position and velocity as NULL
        for (3..8) |i| {
            rc = c.sqlite3_bind_null(self.insert_component_stmt, @intCast(i));
            if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        }
        
        rc = c.sqlite3_bind_null(self.insert_component_stmt, 8); // dz
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_int(self.insert_component_stmt, 9, current);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_int(self.insert_component_stmt, 10, max);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        // Bind remaining parameters as NULL
        for (11..16) |i| {
            rc = c.sqlite3_bind_null(self.insert_component_stmt, @intCast(i));
            if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        }
        
        rc = c.sqlite3_step(self.insert_component_stmt);
        if (rc != c.SQLITE_DONE) return error.SQLiteStepFailed;
        
        _ = c.sqlite3_reset(self.insert_component_stmt);
        self.markEntityDirty(entity_id);
    }
    
    /// BATCH OPERATIONS FOR HIGH PERFORMANCE
    
    /// Batch create entities (much faster than individual creates)
    pub fn batchCreateEntities(self: *Self, count: u32) !ArrayList(EntityId) {
        var entities = ArrayList(EntityId).init(self.allocator);
        
        var errmsg: [*c]u8 = null;
        var rc = c.sqlite3_exec(self.db, "BEGIN TRANSACTION;", null, null, &errmsg);
        if (rc != c.SQLITE_OK) {
            if (errmsg != null) c.sqlite3_free(errmsg);
            return error.SQLiteExecFailed;
        }
        
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const entity_id = self.next_entity_id;
            self.next_entity_id += 1;
            
            rc = c.sqlite3_bind_int64(self.insert_entity_stmt, 1, entity_id);
            if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
            
            rc = c.sqlite3_step(self.insert_entity_stmt);
            if (rc != c.SQLITE_DONE) return error.SQLiteStepFailed;
            
            try entities.append(entity_id);
            _ = c.sqlite3_reset(self.insert_entity_stmt);
        }
        
        rc = c.sqlite3_exec(self.db, "COMMIT;", null, null, &errmsg);
        if (rc != c.SQLITE_OK) {
            if (errmsg != null) c.sqlite3_free(errmsg);
            return error.SQLiteExecFailed;
        }
        
        return entities;
    }
    
    /// Batch add components using a single transaction
    pub fn batchAddPositionVelocity(self: *Self, entities: []const EntityId, positions: []const [2]f32, velocities: []const [2]f32) !void {
        if (entities.len != positions.len or entities.len != velocities.len) {
            return error.MismatchedArrayLengths;
        }
        
        var errmsg: [*c]u8 = null;
        var rc = c.sqlite3_exec(self.db, "BEGIN TRANSACTION;", null, null, &errmsg);
        if (rc != c.SQLITE_OK) {
            if (errmsg != null) c.sqlite3_free(errmsg);
            return error.SQLiteExecFailed;
        }
        
        for (entities, positions, velocities) |entity_id, pos, vel| {
            // Add Position component
            try self.addPosition(entity_id, pos[0], pos[1]);
            
            // Add Velocity component  
            try self.addVelocity(entity_id, vel[0], vel[1]);
        }
        
        rc = c.sqlite3_exec(self.db, "COMMIT;", null, null, &errmsg);
        if (rc != c.SQLITE_OK) {
            if (errmsg != null) c.sqlite3_free(errmsg);
            return error.SQLiteExecFailed;
        }
    }
    
    /// ULTRA-FAST movement update using REPLACE (leverages 2M writes/sec!)
    pub fn batchMovementUpdateReplace(self: *Self, dt: f32) !u32 {
        // Instead of UPDATE, use REPLACE to write new positions at 2M/sec speed!
        const replace_sql = 
            \\REPLACE INTO components (entity_id, component_type, x, y, z, dx, dy, dz, health_current, health_max, energy_current, energy_max, ai_state, ai_target, data)
            \\SELECT 
            \\  p.entity_id, 
            \\  1, -- Position component type
            \\  p.x + v.dx * ?, -- New X
            \\  p.y + v.dy * ?, -- New Y
            \\  p.z, p.dx, p.dy, p.dz, -- Keep other fields
            \\  p.health_current, p.health_max, p.energy_current, p.energy_max, p.ai_state, p.ai_target, p.data
            \\FROM components p
            \\JOIN components v ON p.entity_id = v.entity_id
            \\WHERE p.component_type = 1 AND v.component_type = 2;
        ;
        
        var stmt: ?*c.sqlite3_stmt = null;
        var rc = c.sqlite3_prepare_v2(self.db, replace_sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);
        
        rc = c.sqlite3_bind_double(stmt, 1, dt);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_double(stmt, 2, dt);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_step(stmt);
        if (rc != c.SQLITE_DONE) return error.SQLiteStepFailed;
        
        return @intCast(c.sqlite3_changes(self.db));
    }
    
    /// ULTRA-OPTIMIZED: Single SQL statement that only updates moving entities
    pub fn batchMovementUpdateOptimized(self: *Self, dt: f32) !u32 {
        // This combines the best of both: single SQL statement + only moving entities
        const optimized_sql = 
            \\REPLACE INTO components (entity_id, component_type, x, y, z, dx, dy, dz, health_current, health_max, energy_current, energy_max, ai_state, ai_target, data)
            \\SELECT 
            \\  p.entity_id, 
            \\  1, -- Position component type
            \\  p.x + v.dx * ?, -- New X
            \\  p.y + v.dy * ?, -- New Y
            \\  p.z, p.dx, p.dy, p.dz, -- Keep other fields
            \\  p.health_current, p.health_max, p.energy_current, p.energy_max, p.ai_state, p.ai_target, p.data
            \\FROM components p
            \\JOIN components v ON p.entity_id = v.entity_id
            \\WHERE p.component_type = 1 AND v.component_type = 2 
            \\  AND (v.dx != 0 OR v.dy != 0);
        ;
        
        var stmt: ?*c.sqlite3_stmt = null;
        var rc = c.sqlite3_prepare_v2(self.db, optimized_sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);
        
        rc = c.sqlite3_bind_double(stmt, 1, dt);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_double(stmt, 2, dt);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_step(stmt);
        if (rc != c.SQLITE_DONE) return error.SQLiteStepFailed;
        
        const changes = @as(u32, @intCast(c.sqlite3_changes(self.db)));
        
        // DEBUG: Print what we're actually updating
        if (changes > 0) {
            std.debug.print("DEBUG: Updated {d} entities with dt={d:.6}\n", .{ changes, dt });
        }
        
        return changes;
    }
    
    /// Batch movement update using SQL (OPTIMIZED - no subqueries)
    pub fn batchMovementUpdate(self: *Self, dt: f32) !u32 {
        // Use the OPTIMIZED approach for maximum performance
        return self.batchMovementUpdateOptimized(dt);
    }
    
    /// Batch movement system using SQL
    pub fn batchMovementSystem(self: *Self, dt: f32) !void {
        _ = try self.batchMovementUpdate(dt);
    }
    
    /// ULTRA-OPTIMIZED: Direct UPDATE without REPLACE
    pub fn batchMovementUpdateUltra(self: *Self, dt: f32) !u32 {
        // Direct UPDATE like the raw sqlite test - should be much faster
        const ultra_sql = 
            \\UPDATE components SET x = x + (
            \\  SELECT v.dx * ? FROM components v 
            \\  WHERE v.entity_id = components.entity_id AND v.component_type = 2
            \\), y = y + (
            \\  SELECT v.dy * ? FROM components v 
            \\  WHERE v.entity_id = components.entity_id AND v.component_type = 2
            \\)
            \\WHERE component_type = 1 AND entity_id IN (
            \\  SELECT entity_id FROM components 
            \\  WHERE component_type = 2 AND (dx != 0 OR dy != 0)
            \\);
        ;
        
        var stmt: ?*c.sqlite3_stmt = null;
        var rc = c.sqlite3_prepare_v2(self.db, ultra_sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);
        
        rc = c.sqlite3_bind_double(stmt, 1, dt);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_double(stmt, 2, dt);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_step(stmt);
        if (rc != c.SQLITE_DONE) return error.SQLiteStepFailed;
        
        const changes = @as(u32, @intCast(c.sqlite3_changes(self.db)));
        
        // DEBUG: Print what we're actually updating
        if (changes > 0) {
            std.debug.print("DEBUG: Ultra-optimized updated {d} entities with dt={d:.6}\n", .{ changes, dt });
        }
        
        return changes;
    }
    
    /// BLAZING FAST: No JOIN, direct position updates in memory
    pub fn batchMovementUpdateBlazing(self: *Self, dt: f32) !u32 {
        // Simple approach: Update positions directly using velocity stored in position component
        // This eliminates the need for JOIN completely!
        const blazing_sql = 
            \\UPDATE components 
            \\SET x = x + dx * ?, y = y + dy * ?
            \\WHERE component_type = 1 AND (dx != 0 OR dy != 0);
        ;
        
        var stmt: ?*c.sqlite3_stmt = null;
        var rc = c.sqlite3_prepare_v2(self.db, blazing_sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);
        
        rc = c.sqlite3_bind_double(stmt, 1, dt);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_double(stmt, 2, dt);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_step(stmt);
        if (rc != c.SQLITE_DONE) return error.SQLiteStepFailed;
        
        const changes = @as(u32, @intCast(c.sqlite3_changes(self.db)));
        
        // DEBUG: Print what we're actually updating
        if (changes > 0) {
            std.debug.print("DEBUG: Blazing fast updated {d} entities with dt={d:.6}\n", .{ changes, dt });
        }
        
        return changes;
    }
    
    /// Blazing fast batch movement system - no JOIN needed!
    pub fn batchMovementSystemBlazing(self: *Self, dt: f32) !void {
        _ = try self.batchMovementUpdateBlazing(dt);
    }
    
    /// Query all movement entities for native processing (NO JOIN - BLAZING FAST!)
    pub fn batchQueryMovementEntities(self: *Self) !ArrayList(MovementData) {
        var result = ArrayList(MovementData).init(self.allocator);
        
        const query_sql = 
            \\SELECT entity_id, x, y, dx, dy
            \\FROM components
            \\WHERE component_type = 1 AND (dx != 0 OR dy != 0);
        ;
        
        var stmt: ?*c.sqlite3_stmt = null;
        var rc = c.sqlite3_prepare_v2(self.db, query_sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);
        
        while (true) {
            rc = c.sqlite3_step(stmt);
            if (rc == c.SQLITE_DONE) break;
            if (rc != c.SQLITE_ROW) return error.SQLiteStepFailed;
            
            const entity_data = MovementData{
                .entity_id = @intCast(c.sqlite3_column_int64(stmt, 0)),
                .x = @floatCast(c.sqlite3_column_double(stmt, 1)),
                .y = @floatCast(c.sqlite3_column_double(stmt, 2)),
                .dx = @floatCast(c.sqlite3_column_double(stmt, 3)),
                .dy = @floatCast(c.sqlite3_column_double(stmt, 4)),
            };
            try result.append(entity_data);
        }
        
        return result;
    }
    
    /// ULTIMATE SPEED: Read + Calculate + REPLACE approach (Native)
    pub fn batchMovementUpdateNative(self: *Self, dt: f32) !u32 {
        // Step 1: Read all movement data at 2M reads/sec
        var movement_data = try self.batchQueryMovementEntities();
        defer movement_data.deinit();
        
        if (movement_data.items.len == 0) return 0;
        
        // Step 2: Calculate new positions in native Zig (BLAZING FAST)
        for (movement_data.items) |*data| {
            data.x += data.dx * dt;
            data.y += data.dy * dt;
        }
        
        // Step 3: REPLACE all new positions at 2M writes/sec
        var errmsg: [*c]u8 = null;
        var rc = c.sqlite3_exec(self.db, "BEGIN TRANSACTION;", null, null, &errmsg);
        if (rc != c.SQLITE_OK) {
            if (errmsg != null) c.sqlite3_free(errmsg);
            return error.SQLiteExecFailed;
        }
        
        for (movement_data.items) |data| {
            // Use prepared statement for maximum speed
            rc = c.sqlite3_bind_int64(self.insert_component_stmt, 1, data.entity_id);
            if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
            
            rc = c.sqlite3_bind_int(self.insert_component_stmt, 2, 1); // Position type
            if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
            
            rc = c.sqlite3_bind_double(self.insert_component_stmt, 3, data.x);
            if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
            
            rc = c.sqlite3_bind_double(self.insert_component_stmt, 4, data.y);
            if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
            
            // Bind remaining as NULL
            for (5..16) |i| {
                rc = c.sqlite3_bind_null(self.insert_component_stmt, @intCast(i));
                if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
            }
            
            rc = c.sqlite3_step(self.insert_component_stmt);
            if (rc != c.SQLITE_DONE) return error.SQLiteStepFailed;
            
            _ = c.sqlite3_reset(self.insert_component_stmt);
        }
        
        rc = c.sqlite3_exec(self.db, "COMMIT;", null, null, &errmsg);
        if (rc != c.SQLITE_OK) {
            if (errmsg != null) c.sqlite3_free(errmsg);
            return error.SQLiteExecFailed;
        }
        
        return @intCast(movement_data.items.len);
    }

    /// Helper for executing SQL statements 
    pub fn execSql(self: *Self, sql: []const u8) !void {
        var errmsg: [*c]u8 = null;
        const rc = c.sqlite3_exec(self.db, sql.ptr, null, null, &errmsg);
        if (rc != c.SQLITE_OK) {
            if (errmsg != null) c.sqlite3_free(errmsg);
            return error.SQLiteExecFailed;
        }
    }

    /// Get performance statistics
    pub fn getStats(self: *Self) !SqliteStats {
        var stmt: ?*c.sqlite3_stmt = null;
        
        // Get entity count
        var rc = c.sqlite3_prepare_v2(self.db, "SELECT COUNT(*) FROM entities WHERE active = 1", -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
        
        rc = c.sqlite3_step(stmt);
        const entity_count = if (rc == c.SQLITE_ROW) c.sqlite3_column_int64(stmt, 0) else 0;
        _ = c.sqlite3_finalize(stmt);
        
        // Get component count
        rc = c.sqlite3_prepare_v2(self.db, "SELECT COUNT(*) FROM components", -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
        
        rc = c.sqlite3_step(stmt);
        const component_count = if (rc == c.SQLITE_ROW) c.sqlite3_column_int64(stmt, 0) else 0;
        _ = c.sqlite3_finalize(stmt);
        
        return SqliteStats{
            .entity_count = @intCast(entity_count),
            .component_count = @intCast(component_count),
            .cache_hits = @intCast(self.hot_entities.count()), // Hot entities tracked
            .cache_misses = @intCast(self.dirty_positions.count()), // Dirty positions
        };
    }
    
    /// GAME OF LIFE SPECIALIZED METHODS
    
    /// Add a Game of Life cell component (alive/dead state stored in health component)
    pub fn addGameOfLifeCell(self: *Self, entity_id: EntityId, x: i32, y: i32, alive: bool) !void {
        // Use position component for grid coordinates
        try self.addPosition(entity_id, @floatFromInt(x), @floatFromInt(y));
        
        // Use health component for alive/dead state (1=alive, 0=dead)
        try self.addHealth(entity_id, if (alive) 1 else 0, 1);
    }
    
    /// ULTRA-OPTIMIZED: Game of Life step using pure SQL
    pub fn gameOfLifeStep(self: *SqliteWorld) !u32 {
        // Step 1: Calculate neighbor counts for all cells in one query
        const neighbor_count_sql = 
            \\CREATE TEMP TABLE IF NOT EXISTS neighbor_counts AS
            \\SELECT 
            \\    c1.entity_id,
            \\    c1.x, c1.y,
            \\    c1.health_current as current_state,
            \\    COALESCE(SUM(c2.health_current), 0) as neighbor_count
            \\FROM components c1
            \\LEFT JOIN components c2 ON 
            \\    c2.component_type = 3 AND c2.health_current = 1 AND
            \\    ABS(c1.x - c2.x) <= 1 AND ABS(c1.y - c2.y) <= 1 AND
            \\    NOT (c1.x = c2.x AND c1.y = c2.y)
            \\WHERE c1.component_type = 3
            \\GROUP BY c1.entity_id, c1.x, c1.y, c1.health_current;
        ;
        
        // Step 2: Apply Game of Life rules and update states
        const update_states_sql = 
            \\UPDATE components 
            \\SET health_current = CASE
            \\    WHEN (SELECT current_state FROM neighbor_counts WHERE neighbor_counts.entity_id = components.entity_id) = 1 THEN
            \\        -- Living cell
            \\        CASE WHEN (SELECT neighbor_count FROM neighbor_counts WHERE neighbor_counts.entity_id = components.entity_id) IN (2, 3) THEN 1 ELSE 0 END
            \\    ELSE
            \\        -- Dead cell  
            \\        CASE WHEN (SELECT neighbor_count FROM neighbor_counts WHERE neighbor_counts.entity_id = components.entity_id) = 3 THEN 1 ELSE 0 END
            \\    END
            \\WHERE component_type = 3;
        ;
        
        // Step 3: Clean up temp table
        const cleanup_sql = "DROP TABLE neighbor_counts;";
        
        // Execute the steps
        try self.execSql(neighbor_count_sql);
        try self.execSql(update_states_sql);
        
        // Get count of changes
        var stmt: ?*c.sqlite3_stmt = null;
        var rc = c.sqlite3_prepare_v2(self.db, "SELECT COUNT(*) FROM components WHERE component_type = 3 AND health_current = 1", -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);
        
        rc = c.sqlite3_step(stmt);
        const alive_count = if (rc == c.SQLITE_ROW) c.sqlite3_column_int64(stmt, 0) else 0;
        
        try self.execSql(cleanup_sql);
        
        return @intCast(alive_count);
    }
    
    /// BLAZING FAST: Game of Life using batch read + native compute + batch write
    pub fn gameOfLifeStepNative(self: *Self, width: u32, height: u32) !u32 {
        // Step 1: Read all cell states in one query
        var grid = try self.allocator.alloc(bool, width * height);
        defer self.allocator.free(grid);
        var entity_map = try self.allocator.alloc(EntityId, width * height);
        defer self.allocator.free(entity_map);
        
        // Initialize grid
        @memset(grid, false);
        @memset(entity_map, 0);
        
        const read_sql = 
            \\SELECT c1.entity_id, c2.x, c2.y, c1.health_current 
            \\FROM components c1
            \\JOIN components c2 ON c1.entity_id = c2.entity_id
            \\WHERE c1.component_type = 3 AND c2.component_type = 1
            \\ORDER BY c2.x, c2.y;
        ;
        
        var stmt: ?*c.sqlite3_stmt = null;
        var rc = c.sqlite3_prepare_v2(self.db, read_sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);
        
        while (true) {
            rc = c.sqlite3_step(stmt);
            if (rc == c.SQLITE_DONE) break;
            if (rc != c.SQLITE_ROW) return error.SQLiteStepFailed;
            
            const entity_id = @as(EntityId, @intCast(c.sqlite3_column_int64(stmt, 0)));
            const x = @as(u32, @intFromFloat(c.sqlite3_column_double(stmt, 1)));
            const y = @as(u32, @intFromFloat(c.sqlite3_column_double(stmt, 2)));
            const alive = c.sqlite3_column_int(stmt, 3) == 1;
            
            if (x < width and y < height) {
                const idx = y * width + x;
                grid[idx] = alive;
                entity_map[idx] = entity_id;
            }
        }
        
        // Step 2: Compute next generation in native Zig (BLAZING FAST!)
        var next_grid = try self.allocator.alloc(bool, width * height);
        defer self.allocator.free(next_grid);
        
        for (0..height) |y| {
            for (0..width) |x| {
                const idx = y * width + x;
                var neighbors: u32 = 0;
                
                // Count neighbors (proper bounds checking)
                const y_start = if (y == 0) 0 else y - 1;
                const y_end = if (y == height - 1) height else y + 2;
                const x_start = if (x == 0) 0 else x - 1;
                const x_end = if (x == width - 1) width else x + 2;
                
                for (y_start..y_end) |ny| {
                    for (x_start..x_end) |nx| {
                        if (nx == x and ny == y) continue; // Skip self
                        
                        const nidx = ny * width + nx;
                        if (grid[nidx]) neighbors += 1;
                    }
                }
                
                // Apply Game of Life rules
                next_grid[idx] = if (grid[idx]) 
                    (neighbors == 2 or neighbors == 3)
                else 
                    (neighbors == 3);
            }
        }
        
        // Step 3: Update in-memory state immediately (no I/O blocking!)
        var alive_count: u32 = 0;
        for (0..width * height) |i| {
            if (grid[i] != next_grid[i]) {
                const entity_id = entity_map[i];
                if (entity_id != 0) {
                    // Update in-memory state immediately using prepared statement
                    var update_rc = c.sqlite3_bind_int(self.insert_component_stmt, 1, @intCast(entity_id));
                    if (update_rc != c.SQLITE_OK) return error.SQLiteBindFailed;
                    
                    update_rc = c.sqlite3_bind_int(self.insert_component_stmt, 2, 3); // Health type
                    if (update_rc != c.SQLITE_OK) return error.SQLiteBindFailed;
                    
                    // Bind position and velocity as NULL
                    for (3..9) |j| {
                        update_rc = c.sqlite3_bind_null(self.insert_component_stmt, @intCast(j));
                        if (update_rc != c.SQLITE_OK) return error.SQLiteBindFailed;
                    }
                    
                    update_rc = c.sqlite3_bind_int(self.insert_component_stmt, 9, if (next_grid[i]) 1 else 0);
                    if (update_rc != c.SQLITE_OK) return error.SQLiteBindFailed;
                    
                    update_rc = c.sqlite3_bind_int(self.insert_component_stmt, 10, 1); // max health
                    if (update_rc != c.SQLITE_OK) return error.SQLiteBindFailed;
                    
                    // Bind remaining parameters as NULL
                    for (11..16) |j| {
                        update_rc = c.sqlite3_bind_null(self.insert_component_stmt, @intCast(j));
                        if (update_rc != c.SQLITE_OK) return error.SQLiteBindFailed;
                    }
                    
                    update_rc = c.sqlite3_step(self.insert_component_stmt);
                    if (update_rc != c.SQLITE_DONE) return error.SQLiteStepFailed;
                    
                    _ = c.sqlite3_reset(self.insert_component_stmt);
                }
            }
            if (next_grid[i]) alive_count += 1;
        }
        
        // Optional: Trigger async persistence every N generations
        // This would queue a snapshot command to the persistence thread
        // without blocking the main computation thread
        // (Note: async persistence not implemented in native mode)
        
        return alive_count;
    }

    /// Multi-threaded Game of Life using native computation with thread-based parallelization
    pub fn gameOfLifeStepMultiThreaded(self: *Self, width: u32, height: u32, num_threads: u32) !u32 {
        // Step 1: Read all cell states in one query (same as native)
        var grid = try self.allocator.alloc(bool, width * height);
        defer self.allocator.free(grid);
        var entity_map = try self.allocator.alloc(EntityId, width * height);
        defer self.allocator.free(entity_map);
        
        // Initialize grid
        @memset(grid, false);
        @memset(entity_map, 0);
        
        const read_sql = 
            \\SELECT c1.entity_id, c2.x, c2.y, c1.health_current 
            \\FROM components c1
            \\JOIN components c2 ON c1.entity_id = c2.entity_id
            \\WHERE c1.component_type = 3 AND c2.component_type = 1
            \\ORDER BY c2.x, c2.y;
        ;
        
        var stmt: ?*c.sqlite3_stmt = null;
        var rc = c.sqlite3_prepare_v2(self.db, read_sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);
        
        while (true) {
            rc = c.sqlite3_step(stmt);
            if (rc == c.SQLITE_DONE) break;
            if (rc != c.SQLITE_ROW) return error.SQLiteStepFailed;
            
            const entity_id = @as(EntityId, @intCast(c.sqlite3_column_int64(stmt, 0)));
            const x = @as(u32, @intFromFloat(c.sqlite3_column_double(stmt, 1)));
            const y = @as(u32, @intFromFloat(c.sqlite3_column_double(stmt, 2)));
            const alive = c.sqlite3_column_int(stmt, 3) == 1;
            
            if (x < width and y < height) {
                const idx = y * width + x;
                grid[idx] = alive;
                entity_map[idx] = entity_id;
            }
        }
        
        // Step 2: Multi-threaded computation of next generation
        const next_grid = try self.allocator.alloc(bool, width * height);
        defer self.allocator.free(next_grid);
        
        // Thread data structure
        const ThreadData = struct {
            grid: []const bool,
            next_grid: []bool,
            width: u32,
            height: u32,
            start_row: u32,
            end_row: u32,
        };
        
        var threads = try self.allocator.alloc(std.Thread, num_threads);
        defer self.allocator.free(threads);
        var thread_data = try self.allocator.alloc(ThreadData, num_threads);
        defer self.allocator.free(thread_data);
        
        const rows_per_thread = height / num_threads;
        
        // Worker function for each thread
        const worker = struct {
            fn run(data: *ThreadData) void {
                for (data.start_row..data.end_row) |y| {
                    for (0..data.width) |x| {
                        const idx = y * data.width + x;
                        var neighbors: u32 = 0;
                        
                        // Count neighbors (proper bounds checking)
                        const y_start = if (y == 0) 0 else y - 1;
                        const y_end = if (y == data.height - 1) data.height else y + 2;
                        const x_start = if (x == 0) 0 else x - 1;
                        const x_end = if (x == data.width - 1) data.width else x + 2;
                        
                        for (y_start..y_end) |ny| {
                            for (x_start..x_end) |nx| {
                                if (nx == x and ny == y) continue; // Skip self
                                
                                const nidx = ny * data.width + nx;
                                if (data.grid[nidx]) neighbors += 1;
                            }
                        }
                        
                        // Apply Game of Life rules
                        data.next_grid[idx] = if (data.grid[idx]) 
                            (neighbors == 2 or neighbors == 3)
                        else 
                            (neighbors == 3);
                    }
                }
            }
        }.run;
        
        // Spawn threads
        for (0..num_threads) |i| {
            const start_row = @as(u32, @intCast(i)) * rows_per_thread;
            const end_row = if (i == num_threads - 1) height else start_row + rows_per_thread;
            
            thread_data[i] = ThreadData{
                .grid = grid,
                .next_grid = next_grid,
                .width = width,
                .height = height,
                .start_row = start_row,
                .end_row = end_row,
            };
            
            threads[i] = try std.Thread.spawn(.{}, worker, .{&thread_data[i]});
        }
        
        // Wait for all threads to complete
        for (threads) |thread| {
            thread.join();
        }
        
        // Step 3: Update database (single-threaded for consistency)
        var alive_count: u32 = 0;
        for (0..width * height) |i| {
            if (grid[i] != next_grid[i]) {
                const entity_id = entity_map[i];
                if (entity_id != 0) {
                    // Update in-memory state immediately using prepared statement
                    var update_rc = c.sqlite3_bind_int(self.insert_component_stmt, 1, @intCast(entity_id));
                    if (update_rc != c.SQLITE_OK) return error.SQLiteBindFailed;
                    
                    update_rc = c.sqlite3_bind_int(self.insert_component_stmt, 2, 3); // Health type
                    if (update_rc != c.SQLITE_OK) return error.SQLiteBindFailed;
                    
                    // Bind position and velocity as NULL
                    for (3..9) |j| {
                        update_rc = c.sqlite3_bind_null(self.insert_component_stmt, @intCast(j));
                        if (update_rc != c.SQLITE_OK) return error.SQLiteBindFailed;
                    }
                    
                    update_rc = c.sqlite3_bind_int(self.insert_component_stmt, 9, if (next_grid[i]) 1 else 0);
                    if (update_rc != c.SQLITE_OK) return error.SQLiteBindFailed;
                    
                    update_rc = c.sqlite3_bind_int(self.insert_component_stmt, 10, 1); // max health
                    if (update_rc != c.SQLITE_OK) return error.SQLiteBindFailed;
                    
                    // Bind remaining parameters as NULL
                    for (11..16) |j| {
                        update_rc = c.sqlite3_bind_null(self.insert_component_stmt, @intCast(j));
                        if (update_rc != c.SQLITE_OK) return error.SQLiteBindFailed;
                    }
                    
                    update_rc = c.sqlite3_step(self.insert_component_stmt);
                    if (update_rc != c.SQLITE_DONE) return error.SQLiteStepFailed;
                    
                    _ = c.sqlite3_reset(self.insert_component_stmt);
                }
            }
            if (next_grid[i]) alive_count += 1;
        }
        
        return alive_count;
    }

    /// Get the count of alive cells (Game of Life)
    pub fn getAliveCellCount(self: *Self) !u32 {
        const count_sql = "SELECT COUNT(*) FROM components WHERE component_type = 3 AND health_current = 1;";
        var stmt: ?*c.sqlite3_stmt = null;
        var rc = c.sqlite3_prepare_v2(self.db, count_sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);
        rc = c.sqlite3_step(stmt);
        if (rc != c.SQLITE_ROW) return error.SQLiteStepFailed;
        return @intCast(c.sqlite3_column_int(stmt, 0));
    }

    /// Enable maximum speed mode (Game of Life)
    pub fn enableMaxSpeedMode(self: *Self) !void {
        const max_speed_optimizations = [_][]const u8{
            "PRAGMA synchronous = OFF;",            // Maximum speed, tiny crash risk
            "PRAGMA journal_mode = MEMORY;",        // Keep journal in memory only
            "PRAGMA locking_mode = EXCLUSIVE;",     // Exclusive access for single writer
            "PRAGMA temp_store = MEMORY;",          // All temp data in memory
            "PRAGMA count_changes = OFF;",          // Don't count changes for speed
            "PRAGMA auto_vacuum = NONE;",           // Disable auto-vacuum
        };
        var errmsg: [*c]u8 = null;
        for (max_speed_optimizations) |pragma_sql| {
            const rc = c.sqlite3_exec(self.db, pragma_sql.ptr, null, null, &errmsg);
            if (rc != c.SQLITE_OK) {
                std.debug.print("Warning: Max speed optimization failed: {s}\n", .{errmsg});
                if (errmsg != null) c.sqlite3_free(errmsg);
            }
        }
        std.debug.print("🚀 Maximum speed mode enabled (reduced durability guarantees)\n", .{});
    }

    /// Start the persistence thread
    pub fn startPersistence(self: *Self) !void {
        if (self.persistence_thread != null) {
            std.debug.print("⚠️  Persistence thread already running\n", .{});
            return;
        }
        self.persistence_thread = try std.Thread.spawn(.{}, persistenceWorker, .{self});
        std.debug.print("🚀 Background persistence thread started\n", .{});
    }
    
    /// Mark an entity as dirty for async persistence
    pub fn markEntityDirty(self: *Self, entity_id: EntityId) void {
        _ = self.dirty_entities.put(entity_id, {}) catch unreachable;
    }

    /// Save a single entity and its components to persistent DB
    pub fn saveEntityToPersistentDb(self: *Self, persistent_db: *c.sqlite3, entity_id: EntityId) !void {
        // Insert or update entity
        var entity_stmt: ?*c.sqlite3_stmt = null;
        var rc = c.sqlite3_prepare_v2(persistent_db, "INSERT OR REPLACE INTO entities (id) VALUES (?)", -1, &entity_stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
        defer _ = c.sqlite3_finalize(entity_stmt);
        rc = c.sqlite3_bind_int64(entity_stmt, 1, entity_id);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        rc = c.sqlite3_step(entity_stmt);
        if (rc != c.SQLITE_DONE) return error.SQLiteStepFailed;

        // Copy all components for this entity
        var comp_stmt: ?*c.sqlite3_stmt = null;
        rc = c.sqlite3_prepare_v2(self.db, "SELECT component_type, x, y, z, dx, dy, dz, health_current, health_max, energy_current, energy_max, ai_state, ai_target, data FROM components WHERE entity_id = ?", -1, &comp_stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
        defer _ = c.sqlite3_finalize(comp_stmt);
        rc = c.sqlite3_bind_int64(comp_stmt, 1, entity_id);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;

        // Prepare insert for persistent DB
        var persist_comp_stmt: ?*c.sqlite3_stmt = null;
        rc = c.sqlite3_prepare_v2(persistent_db,
            "REPLACE INTO components (entity_id, component_type, x, y, z, dx, dy, dz, health_current, health_max, energy_current, energy_max, ai_state, ai_target, data) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            -1, &persist_comp_stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
        defer _ = c.sqlite3_finalize(persist_comp_stmt);

        while (true) {
            rc = c.sqlite3_step(comp_stmt);
            if (rc == c.SQLITE_DONE) break;
            if (rc != c.SQLITE_ROW) return error.SQLiteStepFailed;
            // Bind all fields
            rc = c.sqlite3_bind_int64(persist_comp_stmt, 1, entity_id);
            if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
            for (0..15) |i| {
                switch (i) {
                    0 => rc = c.sqlite3_bind_int(persist_comp_stmt, 2, c.sqlite3_column_int(comp_stmt, 0)),
                    1 => rc = c.sqlite3_bind_double(persist_comp_stmt, 3, c.sqlite3_column_double(comp_stmt, 1)),
                    2 => rc = c.sqlite3_bind_double(persist_comp_stmt, 4, c.sqlite3_column_double(comp_stmt, 2)),
                    3 => rc = c.sqlite3_bind_double(persist_comp_stmt, 5, c.sqlite3_column_double(comp_stmt, 3)),
                    4 => rc = c.sqlite3_bind_double(persist_comp_stmt, 6, c.sqlite3_column_double(comp_stmt, 4)),
                    5 => rc = c.sqlite3_bind_double(persist_comp_stmt, 7, c.sqlite3_column_double(comp_stmt, 5)),
                    6 => rc = c.sqlite3_bind_double(persist_comp_stmt, 8, c.sqlite3_column_double(comp_stmt, 6)),
                    7 => rc = c.sqlite3_bind_int(persist_comp_stmt, 9, c.sqlite3_column_int(comp_stmt, 7)),
                    8 => rc = c.sqlite3_bind_int(persist_comp_stmt, 10, c.sqlite3_column_int(comp_stmt, 8)),
                    9 => rc = c.sqlite3_bind_double(persist_comp_stmt, 11, c.sqlite3_column_double(comp_stmt, 9)),
                    10 => rc = c.sqlite3_bind_double(persist_comp_stmt, 12, c.sqlite3_column_double(comp_stmt, 10)),
                    11 => rc = c.sqlite3_bind_int(persist_comp_stmt, 13, c.sqlite3_column_int(comp_stmt, 11)),
                    12 => rc = c.sqlite3_bind_int(persist_comp_stmt, 14, c.sqlite3_column_int(comp_stmt, 12)),
                    13 => {
                        // data BLOB
                        if (c.sqlite3_column_type(comp_stmt, 13) != c.SQLITE_NULL) {
                            rc = c.sqlite3_bind_blob(persist_comp_stmt, 15, c.sqlite3_column_blob(comp_stmt, 13), c.sqlite3_column_bytes(comp_stmt, 13), null);
                        } else {
                            rc = c.sqlite3_bind_null(persist_comp_stmt, 15);
                        }
                    },
                    else => {},
                }
                if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
            }
            rc = c.sqlite3_step(persist_comp_stmt);
            if (rc != c.SQLITE_DONE) return error.SQLiteStepFailed;
            _ = c.sqlite3_reset(persist_comp_stmt);
        }
    }
};

/// Data structure for movement system batch processing
pub const MovementData = struct {
    entity_id: EntityId,
    x: f32,
    y: f32,
    dx: f32,
    dy: f32,
};

/// Performance statistics for SQLite ECS
pub const SqliteStats = struct {
    entity_count: u32,
    component_count: u32,
    cache_hits: i64,
    cache_misses: i64,
};

/// Commands for background persistence thread
pub const PersistenceCommand = union(enum) {
    snapshot: SnapshotData,
    save_entity: struct { entity_id: EntityId },
    save_component: struct { entity_id: EntityId, component_type: u32, data: [16]?f64 },
    shutdown,
};

/// Snapshot data for background persistence  
pub const SnapshotData = struct {
    entities: ArrayList(EntityId),
    components: ArrayList(ComponentRow),
    timestamp: i64,
    
    pub fn deinit(self: *SnapshotData) void {
        self.entities.deinit();
        self.components.deinit();
    }
};

/// Component row for persistence
pub const ComponentRow = struct {
    entity_id: EntityId,
    component_type: u32,
    x: ?f32 = null,
    y: ?f32 = null,
    z: ?f32 = null,
    dx: ?f32 = null,
    dy: ?f32 = null,
    dz: ?f32 = null,
    health_current: ?i32 = null,
    health_max: ?i32 = null,
    energy_current: ?f32 = null,
    energy_max: ?f32 = null,
    ai_state: ?i32 = null,
    ai_target: ?i32 = null,
};

/// Background persistence worker thread
fn persistenceWorker(world: *SqliteWorld) void {
    var persistent_db: ?*c.sqlite3 = null;
    
    std.debug.print("🔧 Persistence worker starting...\n", .{});
    
    // Open persistent database - use safer string handling
    if (world.persistent_db_path) |path| {
        std.debug.print("🔧 Worker received path: ptr={*}, len={d}\n", .{ path.ptr, path.len });
        
        // Skip in-memory databases
        if (std.mem.eql(u8, path, ":memory:")) {
            std.debug.print("⚠️  Persistence worker: in-memory database, exiting\n", .{});
            return;
        }
        
        // Create null-terminated copy for C API
        var path_buf: [256]u8 = undefined;
        if (path.len >= path_buf.len) {
            std.debug.print("❌ Persistence path too long: {d} chars\n", .{path.len});
            return;
        }
        @memcpy(path_buf[0..path.len], path);
        path_buf[path.len] = 0;
        
        const rc = c.sqlite3_open(path_buf[0..path.len :0].ptr, &persistent_db);
        if (rc != c.SQLITE_OK) {
            std.debug.print("Failed to open persistent database (rc={})\n", .{rc});
            return;
        }
        std.debug.print("📁 Persistence worker connected to: {s}\n", .{path});
    } else {
        std.debug.print("⚠️  Persistence worker: no path specified, exiting\n", .{});
        return; // No persistent path specified
    }
    
    defer {
        if (persistent_db) |db| _ = c.sqlite3_close(db);
    }
    
    // Create tables in persistent database
    if (persistent_db) |db| {
        _ = createPersistentTables(world, db) catch |err| {
            std.debug.print("Failed to create persistent tables: {}\n", .{err});
            return;
        };
    }
    
    var last_snapshot_time = std.time.nanoTimestamp();
    const snapshot_interval_ns = 5 * std.time.ns_per_s; // 5 second snapshots
    
    while (!world.should_stop_persistence.load(.acquire)) {
        // Check if it's time for a snapshot
        const current_time = std.time.nanoTimestamp();
        if (current_time - last_snapshot_time >= snapshot_interval_ns) {
            createSnapshot(world) catch |err| {
                std.debug.print("Snapshot failed: {}\n", .{err});
            };
            last_snapshot_time = current_time;
        }
        
        // Process persistence queue
        world.persistence_mutex.lock();
        const maybe_command = world.persistence_queue.readItem();
        world.persistence_mutex.unlock();
        
        if (maybe_command) |command| {
            switch (command) {
                .snapshot => |snapshot| {
                    saveSnapshot(world, persistent_db.?, snapshot) catch |err| {
                        std.debug.print("Failed to save snapshot: {}\n", .{err});
                    };
                },
                .save_entity => |data| {
                    if (persistent_db) |db| {
                        // Call saveEntityToPersistentDb as a public static method
                        SqliteWorld.saveEntityToPersistentDb(world, db, data.entity_id) catch |err| {
                            std.debug.print("Failed to persist entity {d}: {}\n", .{data.entity_id, err});
                        };
                    }
                },
                .shutdown => break,
                else => {
                    // Handle other commands
                },
            }
        } else {
            // No commands, sleep briefly
            std.time.sleep(10 * std.time.ns_per_ms); // 10ms
        }
    }
    
    std.debug.print("🛑 Persistence worker shutting down\n", .{});
}

/// Create a snapshot of current world state
fn createSnapshot(self: *SqliteWorld) !void {
    // This runs on the main thread but quickly captures data
    var entities = ArrayList(EntityId).init(self.allocator);
    var components = ArrayList(ComponentRow).init(self.allocator);
    
    // Quick snapshot of current state
    var entity_stmt: ?*c.sqlite3_stmt = null;
    var rc = c.sqlite3_prepare_v2(self.db, "SELECT id FROM entities WHERE active = 1", -1, &entity_stmt, null);
    if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
    defer _ = c.sqlite3_finalize(entity_stmt);
    
    while (true) {
        rc = c.sqlite3_step(entity_stmt);
        if (rc == c.SQLITE_DONE) break;
        if (rc != c.SQLITE_ROW) return error.SQLiteStepFailed;
        
        const entity_id = @as(EntityId, @intCast(c.sqlite3_column_int64(entity_stmt, 0)));
        try entities.append(entity_id);
    }
    
    // Snapshot components
    var comp_stmt: ?*c.sqlite3_stmt = null;
    rc = c.sqlite3_prepare_v2(self.db, "SELECT entity_id, component_type, x, y, dx, dy, health_current, health_max FROM components", -1, &comp_stmt, null);
    if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
    defer _ = c.sqlite3_finalize(comp_stmt);
    
    while (true) {
        rc = c.sqlite3_step(comp_stmt);
        if (rc == c.SQLITE_DONE) break;
        if (rc != c.SQLITE_ROW) return error.SQLiteStepFailed;
        
        const comp = ComponentRow{
            .entity_id = @as(EntityId, @intCast(c.sqlite3_column_int64(comp_stmt, 0))),
            .component_type = @as(u32, @intCast(c.sqlite3_column_int(comp_stmt, 1))),
            .x = if (c.sqlite3_column_type(comp_stmt, 2) != c.SQLITE_NULL) @as(f32, @floatCast(c.sqlite3_column_double(comp_stmt, 2))) else null,
            .y = if (c.sqlite3_column_type(comp_stmt, 3) != c.SQLITE_NULL) @as(f32, @floatCast(c.sqlite3_column_double(comp_stmt, 3))) else null,
            .dx = if (c.sqlite3_column_type(comp_stmt, 4) != c.SQLITE_NULL) @as(f32, @floatCast(c.sqlite3_column_double(comp_stmt, 4))) else null,
            .dy = if (c.sqlite3_column_type(comp_stmt, 5) != c.SQLITE_NULL) @as(f32, @floatCast(c.sqlite3_column_double(comp_stmt, 5))) else null,
            .health_current = if (c.sqlite3_column_type(comp_stmt, 6) != c.SQLITE_NULL) @as(i32, @intCast(c.sqlite3_column_int(comp_stmt, 6))) else null,
            .health_max = if (c.sqlite3_column_type(comp_stmt, 7) != c.SQLITE_NULL) @as(i32, @intCast(c.sqlite3_column_int(comp_stmt, 7))) else null,
        };
        try components.append(comp);
    }
    
    // Send snapshot to persistence thread
    const snapshot = SnapshotData{
        .entities = entities,
        .components = components,
        .timestamp = @intCast(std.time.nanoTimestamp()),
    };
    
    self.persistence_mutex.lock();
    defer self.persistence_mutex.unlock();
    
    try self.persistence_queue.writeItem(.{ .snapshot = snapshot });
    std.debug.print("📸 Snapshot queued: {d} entities, {d} components\n", .{ entities.items.len, components.items.len });
}

/// Create tables in persistent database
fn createPersistentTables(self: *SqliteWorld, persistent_db: *c.sqlite3) !void {
    _ = self;
    // Always drop tables before creating them to ensure a clean slate
    const drops = [_][]const u8{
        "DROP TABLE IF EXISTS components;",
        "DROP TABLE IF EXISTS entities;",
    };
    for (drops) |sql| {
        var errmsg: [*c]u8 = null;
        const rc = c.sqlite3_exec(persistent_db, sql.ptr, null, null, &errmsg);
        if (rc != c.SQLITE_OK) {
            if (errmsg != null) c.sqlite3_free(errmsg);
            return error.SQLiteExecFailed;
        }
    }
    // Create tables with correct schema (including foreign key)
    const tables = [_][]const u8{
        \\CREATE TABLE IF NOT EXISTS entities (
        \\    id INTEGER PRIMARY KEY,
        \\    created_at INTEGER DEFAULT (unixepoch()),
        \\    active INTEGER DEFAULT 1
        \\);,
        \\CREATE TABLE IF NOT EXISTS components (
        \\    entity_id INTEGER NOT NULL,
        \\    component_type INTEGER NOT NULL,
        \\    x REAL, y REAL, z REAL,
        \\    dx REAL, dy REAL, dz REAL,
        \\    health_current INTEGER, health_max INTEGER,
        \\    energy_current REAL, energy_max REAL,
        \\    ai_state INTEGER, ai_target INTEGER,
        \\    data BLOB,
        \\    PRIMARY KEY (entity_id, component_type),
        \\    FOREIGN KEY (entity_id) REFERENCES entities(id)
        \\);,
    };
    
    for (tables) |sql| {
        var errmsg: [*c]u8 = null;
        const rc = c.sqlite3_exec(persistent_db, sql.ptr, null, null, &errmsg);
        if (rc != c.SQLITE_OK) {
            if (errmsg != null) c.sqlite3_free(errmsg);
            return error.SQLiteExecFailed;
        }
    }
}

/// Save snapshot to persistent database
fn saveSnapshot(self: *SqliteWorld, persistent_db: *c.sqlite3, snapshot: SnapshotData) !void {
    _ = self;
    var errmsg: [*c]u8 = null;
    var rc = c.sqlite3_exec(persistent_db, "BEGIN TRANSACTION;", null, null, &errmsg);
    if (rc != c.SQLITE_OK) {
        if (errmsg != null) c.sqlite3_free(errmsg);
        return error.SQLiteExecFailed;
    }
    
    // Clear old data
    _ = c.sqlite3_exec(persistent_db, "DELETE FROM components;", null, null, null);
    _ = c.sqlite3_exec(persistent_db, "DELETE FROM entities;", null, null, null);
    
    // Save entities
    var entity_stmt: ?*c.sqlite3_stmt = null;
    rc = c.sqlite3_prepare_v2(persistent_db, "INSERT INTO entities (id) VALUES (?)", -1, &entity_stmt, null);
    if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
    defer _ = c.sqlite3_finalize(entity_stmt);
    
    for (snapshot.entities.items) |entity_id| {
        rc = c.sqlite3_bind_int64(entity_stmt, 1, entity_id);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_step(entity_stmt);
        if (rc != c.SQLITE_DONE) return error.SQLiteStepFailed;
        
        _ = c.sqlite3_reset(entity_stmt);
    }
    
    // Save components
    var comp_stmt: ?*c.sqlite3_stmt = null;
    rc = c.sqlite3_prepare_v2(persistent_db, 
        "INSERT INTO components (entity_id, component_type, x, y, dx, dy, health_current, health_max) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", 
        -1, &comp_stmt, null);
    if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
    defer _ = c.sqlite3_finalize(comp_stmt);
    
    for (snapshot.components.items) |comp| {
        rc = c.sqlite3_bind_int64(comp_stmt, 1, comp.entity_id);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_int(comp_stmt, 2, @intCast(comp.component_type));
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        if (comp.x) |x| {
            rc = c.sqlite3_bind_double(comp_stmt, 3, x);
        } else {
            rc = c.sqlite3_bind_null(comp_stmt, 3);
        }
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        if (comp.y) |y| {
            rc = c.sqlite3_bind_double(comp_stmt, 4, y);
        } else {
            rc = c.sqlite3_bind_null(comp_stmt, 4);
        }
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        if (comp.dx) |dx| {
            rc = c.sqlite3_bind_double(comp_stmt, 5, dx);
        } else {
            rc = c.sqlite3_bind_null(comp_stmt, 5);
        }
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        if (comp.dy) |dy| {
            rc = c.sqlite3_bind_double(comp_stmt, 6, dy);
        } else {
            rc = c.sqlite3_bind_null(comp_stmt, 6);
        }
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        if (comp.health_current) |health| {
            rc = c.sqlite3_bind_int(comp_stmt, 7, health);
        } else {
            rc = c.sqlite3_bind_null(comp_stmt, 7);
        }
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        if (comp.health_max) |health_max| {
            rc = c.sqlite3_bind_int(comp_stmt, 8, health_max);
        } else {
            rc = c.sqlite3_bind_null(comp_stmt, 8);
        }
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_step(comp_stmt);
        if (rc != c.SQLITE_DONE) return error.SQLiteStepFailed;
        
        _ = c.sqlite3_reset(comp_stmt);
    }
    
    rc = c.sqlite3_exec(persistent_db, "COMMIT;", null, null, &errmsg);
    if (rc != c.SQLITE_OK) {
        if (errmsg != null) c.sqlite3_free(errmsg);
        return error.SQLiteExecFailed;
    }
    
    std.debug.print("💾 Snapshot saved to disk: {d} entities, {d} components\n", .{ snapshot.entities.items.len, snapshot.components.items.len });
}

