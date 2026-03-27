-- Migration 001 — initial schema
-- Covers every entity in the YAML data model: farm config, livestock,
-- zones, beds, orchard rows/trees, berry rows, plant library (all
-- categories), growth stages, annual cycles, plantings, products,
-- share tiers, and drop points.
--
-- Design rules:
--   - All monetary values as INTEGER (minor currency units — pence/cents).
--   - Weeks as INTEGER 1–52. Years as INTEGER four digits.
--   - BOOLEAN columns stored as INTEGER (0/1).
--   - JSON arrays (box_tiers, rotation companions, etc.) stored as TEXT.
--   - No hardcoded zone types, bed counts, or tier names.

-- ─── Migration tracker ────────────────────────────────────────────────────────

-- Tracks which .sql files have been applied. The migration runner inserts
-- a row here after successfully executing each file.
CREATE TABLE schema_migrations (
  filename   TEXT PRIMARY KEY,
  applied_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ─── Farm ─────────────────────────────────────────────────────────────────────

-- Single-row table holding top-level farm metadata. The CHECK (id = 1)
-- constraint enforces the singleton pattern without application logic.
CREATE TABLE farm (
  id                  INTEGER PRIMARY KEY CHECK (id = 1),
  name                TEXT    NOT NULL,
  location            TEXT,
  latitude            REAL,
  longitude           REAL,
  total_acres         REAL,
  established_year    INTEGER,
  season_start_week   INTEGER CHECK (season_start_week BETWEEN 1 AND 52),
  season_end_week     INTEGER CHECK (season_end_week   BETWEEN 1 AND 52),
  box_day             TEXT,
  currency            TEXT    NOT NULL DEFAULT 'GBP',
  currency_symbol     TEXT    NOT NULL DEFAULT '£'
);

-- ─── Infrastructure ───────────────────────────────────────────────────────────

-- Farm infrastructure (polytunnel, water, cold storage, etc.) stored as
-- key/JSON-blob pairs. The structure varies too much between farms to
-- model relationally; it is not queried by the simulation engine.
CREATE TABLE infrastructure (
  key    TEXT PRIMARY KEY, -- e.g. 'polytunnel', 'water', 'cold_storage'
  config TEXT NOT NULL     -- JSON object from the YAML block
);

-- ─── Livestock ────────────────────────────────────────────────────────────────

-- Laying hen flock. eggs_per_hen_per_week is REAL because the YAML value
-- (5.5) is not an integer. Feed cost stored as pence.
CREATE TABLE hens_config (
  id                        INTEGER PRIMARY KEY CHECK (id = 1),
  flock_size                INTEGER NOT NULL,
  breed                     TEXT,
  housing                   TEXT,
  eggs_per_hen_per_week     REAL    NOT NULL,
  feed_kg_per_hen_per_day   REAL,
  feed_cost_per_kg_pence    INTEGER
);

-- Seasonal laying multipliers. A week that falls in any matching range has
-- its egg count scaled by multiplier. Ranges may overlap; the loader is
-- responsible for non-overlapping entries.
CREATE TABLE hens_seasonal_variation (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  week_start  INTEGER NOT NULL CHECK (week_start BETWEEN 1 AND 52),
  week_end    INTEGER NOT NULL CHECK (week_end   BETWEEN 1 AND 52),
  multiplier  REAL    NOT NULL DEFAULT 1.0
);

-- Beehive configuration. Single row.
CREATE TABLE hives_config (
  id                                  INTEGER PRIMARY KEY CHECK (id = 1),
  count                               INTEGER NOT NULL,
  type                                TEXT,
  expected_honey_kg_per_hive_per_year REAL,
  inspection_interval_weeks           INTEGER,
  forage_radius_km                    REAL
);

-- Winter feeding weeks for hives. The YAML provides a flat list of week
-- numbers (not a contiguous range), so each week gets its own row.
CREATE TABLE hive_winter_feeding_weeks (
  week INTEGER PRIMARY KEY CHECK (week BETWEEN 1 AND 52)
);

-- ─── Zones ────────────────────────────────────────────────────────────────────

-- A zone is any named area of the farm: veg beds, polytunnel, orchard,
-- berry acre, herb & flower beds, mushroom area, etc. The type field
-- drives rendering and determines whether the zone uses beds
-- (type = 'veg') or zone_rows (type = 'orchard' | 'berry' | etc.).
CREATE TABLE zones (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  type        TEXT NOT NULL,
  description TEXT
);

-- ─── Beds (veg zones) ─────────────────────────────────────────────────────────

-- Individual beds within veg-type zones. Each bed has a sequence of
-- planting records (see plantings table). Orchard and berry zones use
-- zone_rows + orchard_trees instead.
CREATE TABLE beds (
  id               TEXT PRIMARY KEY,
  zone_id          TEXT    NOT NULL REFERENCES zones(id),
  width_m          REAL,
  length_m         REAL,
  orientation      TEXT,
  established_year INTEGER,
  soil_notes       TEXT,
  irrigation_zone  INTEGER
);

-- ─── Zone rows (orchard / berry) ─────────────────────────────────────────────

-- A row within an orchard or berry zone. In the orchard each row holds
-- individually identified trees (see orchard_trees). In the berry acre
-- each row holds a species count (see zone_row_plants). The nullable
-- spacing columns cover the full range of row types in the YAML.
CREATE TABLE zone_rows (
  id               TEXT PRIMARY KEY,
  zone_id          TEXT NOT NULL REFERENCES zones(id),
  label            TEXT,
  row_type         TEXT,  -- 'bed' | 'row' | 'raised_bed' (from berry YAML)
  width_m          REAL,
  length_m         REAL,
  tree_spacing_m   REAL,
  bush_spacing_m   REAL,
  plant_spacing_m  REAL,
  cane_spacing_m   REAL,
  row_spacing_m    REAL,
  established_year INTEGER,
  substrate        TEXT,  -- e.g. 'ericaceous' for blueberries
  bush_count       INTEGER,
  plants_per_m2    REAL
);

-- Plant species within a berry (or similar) zone row. Handles both
-- single-species rows (one record, count = null, derived from spacing)
-- and mixed rows with explicit counts per species.
-- Not used for orchard rows — those use orchard_trees instead.
CREATE TABLE zone_row_plants (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  zone_row_id TEXT    NOT NULL REFERENCES zone_rows(id),
  plant_ref   TEXT    NOT NULL, -- references plants.id
  count       INTEGER,          -- explicit count; null if derived from spacing
  UNIQUE (zone_row_id, plant_ref)
);

-- Individual orchard tree instances. Each tree has a stable id, belongs
-- to a zone row, references a plant species, and records its planting
-- year and position within the row. Yield is calculated from the plant's
-- yield_by_year table scaled against years_of_growth.
CREATE TABLE orchard_trees (
  id           TEXT PRIMARY KEY,
  zone_row_id  TEXT    NOT NULL REFERENCES zone_rows(id),
  plant_ref    TEXT    NOT NULL, -- references plants.id
  planted_year INTEGER NOT NULL,
  rootstock    TEXT,
  position     INTEGER           -- left-to-right order within the row
);

-- ─── Plant library ────────────────────────────────────────────────────────────

-- Core plant identity. All categories share this table: vegetable,
-- fruit_tree, berry, herb, flower, mushroom. One row per cultivar.
-- Category determines which companion tables are populated.
CREATE TABLE plants (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  variety     TEXT,
  category    TEXT NOT NULL, -- 'vegetable' | 'fruit_tree' | 'berry' | 'herb' | 'flower' | 'mushroom'
  family      TEXT,
  description TEXT
);

-- Cultivation details — how and when to sow or transplant.
-- direct_sow and support_required are BOOLEAN (0/1).
CREATE TABLE plant_cultivation (
  plant_id                    TEXT PRIMARY KEY REFERENCES plants(id),
  propagation                 TEXT, -- 'indoor_sow' | 'direct_sow' | etc.
  sow_week_start              INTEGER,
  sow_week_end                INTEGER,
  transplant_weeks_after_sow  INTEGER,
  final_spacing_cm            REAL,
  plants_per_sqm              REAL,
  rows_per_bed                INTEGER,
  direct_sow                  INTEGER NOT NULL DEFAULT 0,
  support_required            INTEGER NOT NULL DEFAULT 0
);

-- Timing from sow to harvest and succession interval.
-- succession_needed is BOOLEAN (0/1).
CREATE TABLE plant_timing (
  plant_id                   TEXT PRIMARY KEY REFERENCES plants(id),
  weeks_in_propagation       INTEGER,
  weeks_to_first_harvest     INTEGER,
  harvest_window_weeks       INTEGER,
  succession_needed          INTEGER NOT NULL DEFAULT 0,
  succession_interval_weeks  INTEGER
);

-- Yield — expected output per unit area or per plant. Covers both annuals
-- (expected_kg_per_sqm) and fruit trees (kg_per_tree_at_maturity).
-- storage_weeks is meaningful for fruit that keeps (e.g. late apples).
CREATE TABLE plant_yield (
  plant_id                 TEXT PRIMARY KEY REFERENCES plants(id),
  expected_kg_per_plant    REAL,
  expected_kg_per_sqm      REAL,
  kg_per_tree_at_maturity  REAL,
  harvest_unit             TEXT, -- 'punnet' | 'weight' | 'bunch' | etc.
  harvest_unit_size_kg     REAL,
  harvest_frequency        TEXT, -- 'weekly' | 'once' | etc.
  storage_weeks            INTEGER
);

-- Growing requirements — water, nutrients, sun, frost tolerance.
-- frost_tolerant and polytunnel_recommended are BOOLEAN (0/1).
CREATE TABLE plant_requirements (
  plant_id                      TEXT PRIMARY KEY REFERENCES plants(id),
  water                         TEXT, -- 'low' | 'medium' | 'high'
  water_litres_per_sqm_per_week REAL,
  fertiliser                    TEXT,
  fertiliser_notes              TEXT,
  sun                           TEXT, -- 'full' | 'partial' | 'shade'
  frost_tolerant                INTEGER NOT NULL DEFAULT 0,
  polytunnel_recommended        INTEGER NOT NULL DEFAULT 0
);

-- Rotation group and companion planting. avoid_following and
-- good_companions are stored as JSON arrays of plant ids.
CREATE TABLE plant_rotation (
  plant_id          TEXT PRIMARY KEY REFERENCES plants(id),
  rotation_group    TEXT,
  years_before_return  INTEGER,
  avoid_following   TEXT, -- JSON array, e.g. '["potato","pepper"]'
  good_companions   TEXT  -- JSON array, e.g. '["basil","calendula"]'
);

-- Economics — seed/tree cost and retail value. Nullable columns cover
-- the distinctions between per-plant seeding (tomato), per-sqm (carrot),
-- and per-tree (apple). All values in minor currency units (pence).
-- box_tiers is a JSON array of tier ids.
CREATE TABLE plant_economics (
  plant_id                   TEXT PRIMARY KEY REFERENCES plants(id),
  seed_cost_per_plant_pence  INTEGER,
  seed_cost_per_sqm_pence    INTEGER,
  tree_cost_pence            INTEGER,
  annual_input_cost_pence    INTEGER,
  retail_value_per_unit_pence INTEGER,
  retail_value_per_kg_pence  INTEGER,
  box_tiers                  TEXT -- JSON array e.g. '["field","larder","full_yarrow"]'
);

-- Growth stages for annual plants — indexed by weeks elapsed since sow.
-- The simulation finds the stage where:
--   week_offset_start <= weeks_since_sow < week_offset_end
-- Rows are ordered by week_offset_start. week_offset_end of 999 means
-- "until cleared".
CREATE TABLE plant_growth_stages (
  id                 INTEGER PRIMARY KEY AUTOINCREMENT,
  plant_id           TEXT    NOT NULL REFERENCES plants(id),
  stage              TEXT    NOT NULL,
  week_offset_start  INTEGER NOT NULL,
  week_offset_end    INTEGER NOT NULL,
  color_hex          TEXT,
  canopy_coverage    REAL,
  description        TEXT
);
CREATE INDEX idx_growth_stages_plant ON plant_growth_stages (plant_id, week_offset_start);

-- Annual cycle stages for perennial plants (trees, fruit bushes) —
-- indexed by week-of-year rather than weeks-since-sow. The simulation
-- finds the stage where week_start <= current_week <= week_end.
-- bee_forage_value is populated only on blossom-type stages.
CREATE TABLE plant_annual_cycle (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  plant_id         TEXT    NOT NULL REFERENCES plants(id),
  stage            TEXT    NOT NULL,
  week_start       INTEGER NOT NULL CHECK (week_start BETWEEN 1 AND 52),
  week_end         INTEGER NOT NULL CHECK (week_end   BETWEEN 1 AND 52),
  color_hex        TEXT,
  description      TEXT,
  bee_forage_value TEXT    -- 'none' | 'low' | 'medium' | 'high'; null if not applicable
);
CREATE INDEX idx_annual_cycle_plant ON plant_annual_cycle (plant_id, week_start);

-- Tree maturity arc — years from planting to first fruit and full yield.
CREATE TABLE plant_maturity (
  plant_id                  TEXT PRIMARY KEY REFERENCES plants(id),
  years_to_first_fruit      INTEGER,
  years_to_full_production  INTEGER,
  productive_life_years     INTEGER
);

-- Per-year yield multiplier for fruit trees. multiplier is a fraction of
-- kg_per_tree_at_maturity (0.0 = no fruit, 1.0 = full yield).
-- year_number is years since planting (1-indexed).
CREATE TABLE plant_yield_by_year (
  plant_id    TEXT    NOT NULL REFERENCES plants(id),
  year_number INTEGER NOT NULL,
  multiplier  REAL    NOT NULL,
  PRIMARY KEY (plant_id, year_number)
);

-- Bee forage summary for trees — quick lookup without scanning annual_cycle.
-- Duplicates the blossom entry in plant_annual_cycle for performance.
CREATE TABLE plant_bee_forage (
  plant_id             TEXT PRIMARY KEY REFERENCES plants(id),
  blossom_week_start   INTEGER,
  blossom_week_end     INTEGER,
  value                TEXT -- 'low' | 'medium' | 'high'
);

-- ─── Plantings ────────────────────────────────────────────────────────────────

-- A planting record binds a plant species to a veg bed for a defined
-- period. This is the primary input to the timeline engine.
--   - clear_week / clear_year are NULL until the crop is removed.
--   - expected_first/last_harvest_week are derived at insert time from
--     plant_timing; stored here so they survive plant library edits.
--   - actual_yield_modifier defaults to 1.0; set lower for poor harvests.
--   - status: 'planned' → 'active' (once sow_week passes) → 'complete'.
CREATE TABLE plantings (
  id                          TEXT PRIMARY KEY, -- UUID
  bed_id                      TEXT    NOT NULL REFERENCES beds(id),
  plant_id                    TEXT    NOT NULL REFERENCES plants(id),
  sow_week                    INTEGER NOT NULL CHECK (sow_week  BETWEEN 1 AND 52),
  sow_year                    INTEGER NOT NULL,
  clear_week                  INTEGER          CHECK (clear_week BETWEEN 1 AND 52),
  clear_year                  INTEGER,
  expected_first_harvest_week INTEGER,
  expected_last_harvest_week  INTEGER,
  actual_yield_modifier       REAL    NOT NULL DEFAULT 1.0,
  status                      TEXT    NOT NULL DEFAULT 'planned',
  notes                       TEXT
);
CREATE INDEX idx_plantings_bed    ON plantings (bed_id);
CREATE INDEX idx_plantings_active ON plantings (sow_year, status);

-- ─── Products ─────────────────────────────────────────────────────────────────

-- Product library: fresh produce, preserves, baked goods, medicinal
-- products, honey and beeswax. available_week_start/end and
-- production_season_week_start/end capture the [start, end] pairs
-- from the YAML. All prices in minor currency units. box_tiers is a
-- JSON array of tier ids. gift_suitable is BOOLEAN (0/1).
CREATE TABLE products (
  id                            TEXT PRIMARY KEY,
  name                          TEXT    NOT NULL,
  category                      TEXT    NOT NULL, -- 'fresh' | 'preserved' | 'baked' | 'medicinal' | 'honey_beeswax'
  subcategory                   TEXT,
  unit                          TEXT,
  retail_price_pence            INTEGER NOT NULL,
  shelf_life_days               INTEGER,
  storage                       TEXT,
  available_week_start          INTEGER,
  available_week_end            INTEGER,
  production_season_week_start  INTEGER,
  production_season_week_end    INTEGER,
  box_tiers                     TEXT, -- JSON array
  gift_suitable                 INTEGER NOT NULL DEFAULT 0,
  notes                         TEXT
);

-- Source crops for a product — which plant species provide the main
-- raw ingredient. One product may draw from several crops
-- (e.g. a mixed-berry jam).
CREATE TABLE product_source_crops (
  product_id  TEXT NOT NULL REFERENCES products(id),
  plant_ref   TEXT NOT NULL, -- references plants.id
  PRIMARY KEY (product_id, plant_ref)
);

-- Input ingredients and materials for a product. Unit is stored as a
-- separate text column ('g', 'ml', 'kg', 'units') so that diverse YAML
-- amount types can be stored uniformly. Fixed-cost items (jars, labels,
-- packaging) use cost_pence directly; variable-cost items use
-- cost_per_kg_pence or cost_per_litre_pence with amount and unit.
CREATE TABLE product_inputs (
  id                   INTEGER PRIMARY KEY AUTOINCREMENT,
  product_id           TEXT    NOT NULL REFERENCES products(id),
  ingredient           TEXT    NOT NULL,
  amount               REAL,
  unit                 TEXT,             -- 'g' | 'ml' | 'kg' | 'units'
  cost_per_kg_pence    INTEGER,
  cost_per_litre_pence INTEGER,
  cost_pence           INTEGER           -- for fixed-cost items (jar, label, packaging)
);

-- Production details — labour time, packaging parameters, baking
-- settings, steeping duration. One row per product; nullable columns
-- cover the range of product types.
CREATE TABLE product_production (
  product_id              TEXT PRIMARY KEY REFERENCES products(id),
  kg_fruit_per_unit       REAL,    -- for preserves: kg source fruit per output unit
  labour_minutes_per_unit REAL,
  labour_rate_pence_per_hour INTEGER,
  steeping_weeks          INTEGER, -- for liqueurs
  bake_day                TEXT,    -- e.g. 'tuesday'
  bake_temp_c             INTEGER,
  bake_hours              REAL
);

-- Product variants — flavour or ingredient variations on a base product
-- (e.g. lavender, rose, brown-sugar meringues). Variants share the
-- base recipe and differ only in the additional_input or substitute.
CREATE TABLE product_variants (
  id               TEXT PRIMARY KEY,
  product_id       TEXT NOT NULL REFERENCES products(id),
  name             TEXT NOT NULL,
  additional_input TEXT,
  amount_g         REAL,
  amount_ml        REAL,
  substitute       TEXT -- ingredient in the base recipe this replaces
);

-- Seasonal pairings — products that complement a crop during a week range.
-- Informational; used by the box composer for suggested combinations.
CREATE TABLE product_seasonal_pairings (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  product_id  TEXT    NOT NULL REFERENCES products(id),
  week_start  INTEGER NOT NULL CHECK (week_start BETWEEN 1 AND 52),
  week_end    INTEGER NOT NULL CHECK (week_end   BETWEEN 1 AND 52),
  pair_with   TEXT    NOT NULL -- plant_ref or product_id
);

-- ─── CSA membership ───────────────────────────────────────────────────────────

-- Share tiers — any number may be configured. The application renders
-- whatever tiers are present; no tier names are hardcoded. price_pence
-- is the full-season share price in minor currency units.
CREATE TABLE share_tiers (
  id          TEXT PRIMARY KEY,
  name        TEXT    NOT NULL,
  price_pence INTEGER NOT NULL,
  weeks       INTEGER,
  description TEXT
);

-- Box pickup and drop points. location is a free-text address or TBC.
CREATE TABLE drop_points (
  id       TEXT PRIMARY KEY,
  label    TEXT NOT NULL,
  location TEXT
);

-- Costs
CREATE TABLE costs (
  id                  TEXT PRIMARY KEY,
  category            TEXT NOT NULL,
  description         TEXT,
  amount_pence        INTEGER NOT NULL,
  date                TEXT NOT NULL,
  amortise_over_years INTEGER,
  related_crop_id     TEXT REFERENCES plants(id) ON DELETE SET NULL,
  related_bed_id      TEXT REFERENCES beds(id) ON DELETE SET NULL,
  notes               TEXT
);

-- Members
CREATE TABLE members (
  id           TEXT PRIMARY KEY,
  name         TEXT NOT NULL,
  email        TEXT NOT NULL UNIQUE,
  tier_id      TEXT NOT NULL REFERENCES share_tiers(id),
  drop_point   TEXT NOT NULL REFERENCES drop_points(id),
  start_week   INTEGER NOT NULL CHECK (start_week BETWEEN 1 AND 52),
  start_year   INTEGER NOT NULL,
  skip_weeks   TEXT, -- JSON array of week numbers
  active       INTEGER NOT NULL DEFAULT 1,
  notes        TEXT
);
