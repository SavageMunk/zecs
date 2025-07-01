-- High-Performance ECS Schema for Batch Operations

-- Optimized entity-component storage with indexing
CREATE TABLE entity_components (
    entity_id INTEGER NOT NULL,
    component_type_id INTEGER NOT NULL, -- Numeric for faster joins
    component_data BLOB NOT NULL,
    x REAL, -- Direct spatial fields for fast spatial queries
    y REAL,
    z REAL,
    dx REAL, -- Velocity fields
    dy REAL,
    dz REAL,
    health_current INTEGER,
    health_max INTEGER,
    ai_state INTEGER,
    ai_target INTEGER,
    created_at INTEGER DEFAULT (unixepoch()),
    updated_at INTEGER DEFAULT (unixepoch()),
    PRIMARY KEY (entity_id, component_type_id)
) WITHOUT ROWID; -- Clustered index for better performance

-- Component type registry
CREATE TABLE component_types (
    type_id INTEGER PRIMARY KEY,
    type_name TEXT UNIQUE NOT NULL,
    type_hash INTEGER NOT NULL -- For fast lookups
);

-- Spatial index for fast proximity queries
CREATE INDEX idx_spatial ON entity_components(x, y) WHERE x IS NOT NULL AND y IS NOT NULL;
CREATE INDEX idx_entity_type ON entity_components(entity_id, component_type_id);
CREATE INDEX idx_component_type ON entity_components(component_type_id);

-- System execution tracking
CREATE TABLE system_batches (
    batch_id INTEGER PRIMARY KEY AUTOINCREMENT,
    system_name TEXT NOT NULL,
    entity_count INTEGER NOT NULL,
    execution_time_ns INTEGER NOT NULL,
    timestamp INTEGER DEFAULT (unixepoch())
);
