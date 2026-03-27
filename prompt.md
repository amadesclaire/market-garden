# Market Garden Planner — Claude Code Session Prompt

## Critical working rules

Do not write more than what is asked for in the current task. If you see an
opportunity to build ahead, note it with a // TODO comment instead. Stop at
each checkpoint and wait for explicit approval before proceeding. When in
doubt, do less and ask.

---

<project>

Market Garden Planner is a local-first desktop web application for planning,
visualising, and managing any market garden CSA operation. It is
configuration-driven — all farm-specific details (beds, zones, crops,
livestock, members, products) live in YAML files. The application reads
whatever configuration is present and works with it. It has no hardcoded
assumptions about farm size, number of beds, zones, or members. The
reference implementation is Yarrow Farm, a CSA in North Norfolk, UK — this
is the seed data, not the application's identity.

At its core is an interactive Three.js farm visualisation — a top-down
orthographic view of the farm divided into whatever zones are configured
(which may include intensive veg beds, polytunnel, berry areas, orchard,
herb and flower beds, or any other zone type) — that animates week by week
through the growing season, showing each bed's crop, growth stage, and
harvest status as a living timelapse of the farm year. Alongside the canvas,
a week scrubber lets you move through all 52 weeks, with server-rendered
panels updating to show projected box compositions for each configured
membership tier, estimated harvest quantities, costs, and surplus available
for processing into preserves. The data model captures everything from
individual bed plantings and succession schedules through to product
inventories, member share tiers, and weekly box compositions. The application
is the farm's digital twin — the same model that drives the visualisation
will eventually feed Claude-powered reasoning about crop planning, harvest
projections, and surplus management.

### Four subsystems — build in this order, no exceptions

1. **Data model** — farms, beds, crops, plantings, harvests, costs,
   products, box compositions. Foundation for everything else. Get this
   wrong and we are refactoring forever.

2. **Timeline engine** — week-by-week simulation of what is planted,
   growing, harvestable, and in the box. The logic layer between data and
   visualisation.

3. **Box composer** — given a week's projected harvests, what goes in each
   box tier? What is the estimated value?

4. **Three.js visualisation** — stateless rendering layer that reads from
   the data model. Built last, when the JSON shapes it consumes are stable
   and tested.

</project>

---

<stack>

- **Runtime**: Bun (bun:sqlite for database — no separate driver needed)
- **API**: Hono
- **Database**: SQLite via bun:sqlite — raw SQL only, no ORM, no Drizzle
- **Frontend**: Hono serves server-rendered HTML. HTMX (loaded via CDN,
  no npm install) handles dynamic panel updates. Three.js (CDN) handles
  the canvas.
- **No frontend framework** — no React, no Preact, no Svelte, no Vue,
  no Astro, no Vite, no build step for frontend assets whatsoever
- **CSS**: Plain CSS, functional and minimal. No Tailwind.
- **Config**: YAML files are the canonical source of truth for all farm
  configuration. The application reads them at startup and syncs to SQLite.

</stack>

---

<structure>

```
market-garden/
├── src/
│   ├── index.ts          # Bun entrypoint — starts Hono server on port 3000
│   ├── db.ts             # SQLite connection, migration runner
│   ├── loader.ts         # YAML reader — syncs farm/, plants/, products/ to DB
│   ├── simulation.ts     # Week state engine — the core planning logic
│   └── routes/
│       ├── api.ts        # JSON API endpoints consumed by Three.js
│       └── ui.ts         # Server-rendered HTML endpoints (HTMX targets)
├── public/
│   ├── main.js           # Three.js canvas — vanilla JS, no bundler
│   └── style.css
├── migrations/
│   └── 001_initial.sql   # Single migration file to start
├── farm/                 # Farm-specific configuration (YAML) — the reference implementation is Yarrow Farm
│   ├── farm.yaml
│   ├── zones/
│   │   ├── veg-beds.yaml
│   │   ├── polytunnel.yaml
│   │   ├── orchard.yaml
│   │   ├── berry-acre.yaml
│   │   ├── herb-flowers.yaml
│   │   └── mushrooms.yaml
│   ├── livestock/
│   │   ├── hens.yaml
│   │   └── hives.yaml
│   └── members/
│       └── shares.yaml
├── plants/               # Canonical plant library (YAML)
│   ├── vegetables.yaml
│   ├── fruit-trees.yaml
│   ├── berries.yaml
│   ├── herbs-medicinal.yaml
│   ├── flowers.yaml
│   └── mushrooms.yaml
└── products/             # Canonical product library (YAML)
    ├── fresh.yaml
    ├── preserved.yaml
    ├── baked.yaml
    ├── medicinal.yaml
    └── honey-beeswax.yaml
```

</structure>

---

<constraints>

- Plain SQL migrations in `/migrations/`, numbered sequentially
  (001*, 002*, etc.). One file per migration. Never edit a migration
  after it has been applied — add a new one.
- Long files over many small ones. Keep related logic together. Do not
  split a module into multiple files just to keep line counts down.
- `// TODO` comments for known gaps rather than placeholder
  implementations. Never invent behaviour that has not been specified.
- No README files.
- No tests for API routes, server setup, or UI rendering.
- The simulation engine (src/simulation.ts) should have unit tests.
- Test inputs are synthetic planting records with known expected outputs.
- Use Bun's built-in test runner (bun test) — no Jest, no Vitest.
- No TypeScript strict mode, but use types where they add clarity.
- YAML files are the source of truth. The SQLite database is a derived,
  queryable cache. On startup: read YAML → diff against DB → apply
  changes. If a record exists in DB but not in YAML, log a warning
  but do not delete it.
- The YAML examples in this prompt are illustrative of shape and
  structure. Do not attempt to fill in entries marked with comments
  like `# ... etc`. Generate only what is explicitly shown, plus
  minimal seed data sufficient to demonstrate one complete crop cycle
  through the simulation.
- All monetary values stored as integers (minor currency units — pence,
  cents, etc.) in the database. The currency symbol is read from farm.yaml
  and used for display only. The reference implementation uses GBP (£).
- Weeks are integers 1–52. Years are four-digit integers. A planting
  spans from sow_week/sow_year to clear_week/clear_year.
- The application must work correctly regardless of how many zones, beds,
  tiers, or livestock entries are present in the YAML. Nothing is
  hardcoded to a specific count.

</constraints>

---

<data_model>

The YAML files below define the shapes for all configuration. These are the
reference implementation files for Yarrow Farm — they illustrate the full
range of things the application must be able to model. The schema must
accommodate whatever a user puts in these files, not just the specific
entries shown here. Study the shapes carefully before designing the schema.

### farm/farm.yaml

```yaml
farm:
  name: Yarrow Farm
  location: North Norfolk, England
  latitude: 52.9
  longitude: 1.1
  total_acres: 4.0
  established_year: 2025
  season_start_week: 14 # early April
  season_end_week: 44 # early November
  box_day: wednesday
  currency: GBP
  currency_symbol: "£"

livestock:
  hens:
    flock_size: 20
    breed: Rhode Island Red
    housing: mobile_ark
    eggs_per_hen_per_week: 5.5
    seasonal_variation:
      - weeks: [1, 8]
        multiplier: 0.6 # winter lay reduction
      - weeks: [9, 52]
        multiplier: 1.0
    feed_kg_per_hen_per_day: 0.12
    feed_cost_per_kg_gbp: 0.45

  hives:
    count: 2
    type: national
    expected_honey_kg_per_hive_per_year: 12
    inspection_interval_weeks: 2
    winter_feeding_weeks: [40, 52, 1, 10]
    forage_radius_km: 3

infrastructure:
  polytunnel:
    count: 1
    width_m: 6
    length_m: 15
    heated: false
    irrigation: drip

  water:
    source: mains
    rainwater_harvesting: true
    irrigation_zones: 4

  cold_storage:
    capacity_litres: 400
    temperature_c: 4
```

### farm/zones/veg-beds.yaml

Beds are rendered as sequential rows in the visualisation — no precise
map coordinates needed, just ordered lines within the zone. Any number
of beds may be present. The application renders whatever is in the YAML.

```yaml
zone:
  name: Intensive Veg
  type: veg
  description: Permanent raised beds, no-dig system

beds:
  - id: V01
    width_m: 0.75
    length_m: 8.0
    orientation: north-south
    established_year: 2025
    soil_notes: Heavy clay, amended with compost
    irrigation_zone: 1

  - id: V02
    width_m: 0.75
    length_m: 8.0
    orientation: north-south
    established_year: 2025
    irrigation_zone: 1

  - id: V03
    width_m: 0.75
    length_m: 8.0
    orientation: north-south
    established_year: 2025
    irrigation_zone: 2

  # Additional beds follow the same shape.
  # The application renders however many beds are present — no fixed count.
```

### farm/zones/orchard.yaml

Each row renders as a horizontal line of evenly spaced tree markers.
Rows stack vertically in the visualisation. Any number of rows and trees
may be present. Mixed rows (multiple species) are supported.

```yaml
zone:
  name: Orchard
  type: orchard
  description: MM106 rootstock apples, semi-vigorous pears and stone fruit

rows:
  - id: OR1
    label: Early Apples
    tree_spacing_m: 4.5
    trees:
      - id: OR1-T1
        plant_ref: apple-discovery
        planted_year: 2025
        rootstock: MM106
        position: 1

      - id: OR1-T2
        plant_ref: apple-rev-wilks
        planted_year: 2025
        rootstock: MM106
        position: 2

      - id: OR1-T3
        plant_ref: apple-grenadier
        planted_year: 2025
        rootstock: MM106
        position: 3

      - id: OR1-T4
        plant_ref: apple-irish-peach
        planted_year: 2025
        rootstock: MM106
        position: 4

      - id: OR1-T5
        plant_ref: apple-katy
        planted_year: 2025
        rootstock: MM106
        position: 5

  - id: OR2
    label: Mid Apples
    tree_spacing_m: 4.5
    trees:
      - id: OR2-T1
        plant_ref: apple-cox
        planted_year: 2025
        rootstock: MM106
        position: 1

      - id: OR2-T2
        plant_ref: apple-sunset
        planted_year: 2025
        rootstock: MM106
        position: 2

  - id: OR3
    label: Late Apples
    tree_spacing_m: 4.5
    trees:
      - id: OR3-T1
        plant_ref: apple-bramley
        planted_year: 2025
        rootstock: MM106
        position: 1

  - id: OR4
    label: Pears
    tree_spacing_m: 4.5
    trees:
      - id: OR4-T1
        plant_ref: pear-beth
        planted_year: 2025
        rootstock: quince-a
        position: 1

  - id: OR5
    label: Stone Fruit
    tree_spacing_m: 4.0
    trees:
      - id: OR5-T1
        plant_ref: plum-opal
        planted_year: 2025
        rootstock: st-julien-a
        position: 1

  - id: OR6
    label: Damsons and Quince
    tree_spacing_m: 4.0
    trees:
      - id: OR6-T1
        plant_ref: damson-shropshire
        planted_year: 2025
        rootstock: st-julien-a
        position: 1

  - id: OR7
    label: Nuts and Specials
    tree_spacing_m: 5.0
    trees:
      - id: OR7-T1
        plant_ref: walnut-broadview
        planted_year: 2025
        rootstock: own-root
        position: 1

      - id: OR7-T2
        plant_ref: mulberry-chelsea
        planted_year: 2025
        rootstock: own-root
        position: 2

      - id: OR7-T3
        plant_ref: fig-brown-turkey
        planted_year: 2025
        rootstock: own-root
        position: 3
```

### farm/zones/berry-acre.yaml

```yaml
zone:
  name: Berry Acre
  type: berry

rows:
  - id: BR1
    label: Strawberries PYO
    type: bed
    width_m: 1.2
    length_m: 40.0
    plant_ref: strawberry-elsanta
    plants_per_m2: 4
    established_year: 2025

  - id: BR2
    label: Summer Raspberries
    type: row
    length_m: 30.0
    plant_ref: raspberry-glen-ample
    cane_spacing_m: 0.4
    row_spacing_m: 1.8
    established_year: 2025

  - id: BR3
    label: Autumn Raspberries
    type: row
    length_m: 30.0
    plant_ref: raspberry-autumn-bliss
    cane_spacing_m: 0.4
    row_spacing_m: 1.8
    established_year: 2025

  - id: BR4
    label: Blackcurrants
    type: row
    length_m: 35.0
    plant_ref: blackcurrant-ben-lomond
    bush_spacing_m: 1.5
    established_year: 2025
    bush_count: 23

  - id: BR5
    label: Redcurrants and Whitecurrants
    type: row
    length_m: 20.0
    plants:
      - plant_ref: redcurrant-rovada
        count: 5
      - plant_ref: whitecurrant-white-versailles
        count: 4
    bush_spacing_m: 1.5
    established_year: 2025

  - id: BR6
    label: Gooseberries
    type: row
    length_m: 25.0
    plants:
      - plant_ref: gooseberry-invicta
        count: 6
      - plant_ref: gooseberry-hinnonmaki-red
        count: 5
      - plant_ref: gooseberry-pax
        count: 5
    bush_spacing_m: 1.5
    established_year: 2025

  - id: BR7
    label: Honeyberries
    type: row
    length_m: 15.0
    plants:
      - plant_ref: honeyberry-borealis
        count: 3
      - plant_ref: honeyberry-tundra
        count: 3
      - plant_ref: honeyberry-aurora
        count: 3
    bush_spacing_m: 1.5
    established_year: 2025

  - id: BR8
    label: Hybrid Berries
    type: row
    length_m: 25.0
    plants:
      - plant_ref: tayberry
        count: 5
      - plant_ref: boysenberry
        count: 4
      - plant_ref: loganberry-ly654
        count: 4
    plant_spacing_m: 2.5
    established_year: 2025

  - id: BR9
    label: Blueberries
    type: raised_bed
    width_m: 1.5
    length_m: 12.0
    substrate: ericaceous
    plants:
      - plant_ref: blueberry-bluecrop
        count: 4
      - plant_ref: blueberry-chandler
        count: 2
      - plant_ref: blueberry-darrow
        count: 3
    established_year: 2025
```

### plants/vegetables.yaml (structure — two examples)

All vegetables follow this shape. The growth_stages array is the key
driver for the Three.js visualisation — week_offset_start is weeks
after sow date.

```yaml
plants:
  - id: tomato-sungold
    name: Tomato
    variety: Sungold
    category: vegetable
    family: Solanaceae
    description: Cherry tomato, exceptional sweetness, orange when ripe

    cultivation:
      propagation: indoor_sow
      sow_week_range: [8, 12]
      transplant_weeks_after_sow: 6
      final_spacing_cm: 60
      plants_per_sqm: 0.28
      rows_per_bed: 1
      direct_sow: false
      support_required: true

    timing:
      weeks_in_propagation: 6
      weeks_to_first_harvest: 16 # from sow date
      harvest_window_weeks: 14
      succession_needed: false

    yield:
      expected_kg_per_plant: 3.5
      expected_kg_per_sqm: 1.0
      harvest_unit: punnet
      harvest_unit_size_kg: 0.25
      harvest_frequency: weekly

    requirements:
      water: high
      water_litres_per_sqm_per_week: 8
      fertiliser: medium_high
      fertiliser_notes: High potassium once fruiting begins
      sun: full
      frost_tolerant: false
      polytunnel_recommended: true

    rotation:
      group: solanaceae
      years_before_return: 4
      avoid_following: [potato, pepper, aubergine]
      good_companions: [basil, calendula]

    economics:
      seed_cost_per_plant_gbp: 0.15
      retail_value_per_unit_gbp: 1.80
      box_tier: [larder, full_yarrow]

    growth_stages:
      - stage: sown
        week_offset_start: 0
        week_offset_end: 1
        color_hex: "#8B6914"
        canopy_coverage: 0.0
        description: Seed sown in propagation tray

      - stage: germinating
        week_offset_start: 1
        week_offset_end: 2
        color_hex: "#A0784A"
        canopy_coverage: 0.02
        description: Germination underway

      - stage: seedling
        week_offset_start: 2
        week_offset_end: 4
        color_hex: "#7AB648"
        canopy_coverage: 0.05
        description: True leaves forming in propagation

      - stage: transplant_ready
        week_offset_start: 5
        week_offset_end: 6
        color_hex: "#5A9E30"
        canopy_coverage: 0.08
        description: Ready to move to final position

      - stage: establishing
        week_offset_start: 6
        week_offset_end: 9
        color_hex: "#4A8E25"
        canopy_coverage: 0.2
        description: Settling into final bed

      - stage: vegetative
        week_offset_start: 9
        week_offset_end: 13
        color_hex: "#3A7E18"
        canopy_coverage: 0.6
        description: Strong vegetative growth

      - stage: flowering
        week_offset_start: 13
        week_offset_end: 15
        color_hex: "#6EAE30"
        canopy_coverage: 0.75
        description: Yellow flowers opening

      - stage: fruiting
        week_offset_start: 15
        week_offset_end: 16
        color_hex: "#E8A020"
        canopy_coverage: 0.85
        description: Green fruit swelling

      - stage: harvestable
        week_offset_start: 16
        week_offset_end: 29
        color_hex: "#E84020"
        canopy_coverage: 0.9
        description: Ripe fruit, harvest weekly

      - stage: past_peak
        week_offset_start: 29
        week_offset_end: 31
        color_hex: "#B03010"
        canopy_coverage: 0.7
        description: Yield declining

      - stage: cleared
        week_offset_start: 31
        week_offset_end: 999
        color_hex: "#8B6914"
        canopy_coverage: 0.0
        description: Plants removed, bed cleared

  - id: carrot-nantes
    name: Carrot
    variety: Nantes 2
    category: vegetable
    family: Apiaceae

    cultivation:
      propagation: direct_sow
      sow_week_range: [14, 28]
      direct_sow: true
      final_spacing_cm: 6
      plants_per_sqm: 28
      rows_per_bed: 4

    timing:
      weeks_to_first_harvest: 12
      harvest_window_weeks: 6
      succession_needed: true
      succession_interval_weeks: 3

    yield:
      expected_kg_per_sqm: 4.0
      harvest_unit: weight
      harvest_unit_size_kg: 0.5
      harvest_frequency: once

    requirements:
      water: medium
      water_litres_per_sqm_per_week: 4
      fertiliser: low
      fertiliser_notes: Avoid fresh manure — causes forking
      sun: full
      frost_tolerant: true

    rotation:
      group: apiaceae
      years_before_return: 3
      avoid_following: [parsnip, parsley, fennel]

    economics:
      seed_cost_per_sqm_gbp: 0.40
      retail_value_per_unit_gbp: 0.90
      box_tier: [field, larder, full_yarrow]

    growth_stages:
      - stage: sown
        week_offset_start: 0
        week_offset_end: 2
        color_hex: "#8B6914"
        canopy_coverage: 0.0

      - stage: germinating
        week_offset_start: 2
        week_offset_end: 3
        color_hex: "#9B7824"
        canopy_coverage: 0.02

      - stage: seedling
        week_offset_start: 3
        week_offset_end: 6
        color_hex: "#7AB648"
        canopy_coverage: 0.1

      - stage: establishing
        week_offset_start: 6
        week_offset_end: 9
        color_hex: "#5A9630"
        canopy_coverage: 0.4

      - stage: mature
        week_offset_start: 9
        week_offset_end: 12
        color_hex: "#4A8625"
        canopy_coverage: 0.8

      - stage: harvestable
        week_offset_start: 12
        week_offset_end: 17
        color_hex: "#E87820"
        canopy_coverage: 0.9

      - stage: past_peak
        week_offset_start: 17
        week_offset_end: 19
        color_hex: "#C06010"
        canopy_coverage: 0.6

      - stage: cleared
        week_offset_start: 19
        week_offset_end: 999
        color_hex: "#8B6914"
        canopy_coverage: 0.0
```

### plants/fruit-trees.yaml (structure — one example)

Trees use a repeating annual_cycle keyed to week-of-year rather than
weeks-after-sow. They also have a maturity arc across years affecting
yield.

```yaml
trees:
  - id: apple-discovery
    name: Apple
    variety: Discovery
    category: fruit_tree
    family: Rosaceae
    rootstock: MM106

    maturity:
      years_to_first_fruit: 3
      years_to_full_production: 6
      productive_life_years: 40

    annual_cycle:
      - stage: dormant
        weeks: [1, 9]
        color_hex: "#8B7355"
        description: Bare branches

      - stage: budding
        weeks: [10, 12]
        color_hex: "#A0855A"
        description: Buds swelling

      - stage: blossom
        weeks: [13, 15]
        color_hex: "#FFB7C5"
        description: Full blossom — peak bee forage
        bee_forage_value: high

      - stage: leafing
        weeks: [15, 20]
        color_hex: "#90C840"
        description: Leaves open, fruitlets forming

      - stage: summer_growth
        weeks: [20, 28]
        color_hex: "#60A820"
        description: Fruit swelling

      - stage: ripening
        weeks: [28, 32]
        color_hex: "#C8D820"
        description: Fruit colouring

      - stage: harvest_ready
        weeks: [32, 35]
        color_hex: "#E84020"
        description: Pick August — does not store

      - stage: post_harvest
        weeks: [35, 44]
        color_hex: "#70A830"
        description: Post-harvest, leaves on

      - stage: leaf_fall
        weeks: [44, 48]
        color_hex: "#C8A030"
        description: Autumn colour

      - stage: dormant
        weeks: [48, 52]
        color_hex: "#8B7355"
        description: Dormant

    yield:
      kg_per_tree_at_maturity: 25
      yield_by_year:
        1: 0.0
        2: 0.0
        3: 0.1
        4: 0.3
        5: 0.6
        6: 1.0
      harvest_unit: weight
      storage_weeks: 0

    bee_forage:
      blossom_weeks: [13, 15]
      value: high

    economics:
      tree_cost_gbp: 18
      annual_input_cost_gbp: 8
      retail_value_per_kg_gbp: 2.50
```

### products/preserved.yaml (structure — two examples)

```yaml
products:
  - id: blackcurrant-jam
    name: Blackcurrant Jam
    category: preserved
    subcategory: jam
    unit: jar_320g
    retail_price_gbp: 5.50

    production:
      source_crops: [blackcurrant-ben-lomond, blackcurrant-ben-hope]
      kg_fruit_per_jar: 0.28
      other_inputs:
        - ingredient: sugar
          amount_kg: 0.26
          cost_per_kg_gbp: 0.90
        - ingredient: lemon_juice
          amount_ml: 15
          cost_per_litre_gbp: 1.50
      labour_minutes_per_jar: 8
      labour_rate_gbp_per_hour: 12
      jar_cost_gbp: 0.45
      lid_cost_gbp: 0.08
      label_cost_gbp: 0.12

    shelf_life_days: 365
    storage: cool_dark
    available_weeks: [1, 52]
    production_season_weeks: [28, 35]
    box_tiers: [larder, full_yarrow]
    gift_suitable: true

  - id: damson-gin
    name: Damson Gin
    category: preserved
    subcategory: liqueur
    unit: bottle_350ml
    retail_price_gbp: 18.00

    production:
      source_crops: [damson-shropshire]
      kg_fruit_per_bottle: 0.3
      other_inputs:
        - ingredient: gin
          amount_ml: 350
          cost_per_litre_gbp: 16.00
        - ingredient: sugar
          amount_g: 120
          cost_per_kg_gbp: 0.90
      labour_minutes_per_bottle: 5
      steeping_weeks: 12
      bottle_cost_gbp: 1.20
      label_cost_gbp: 0.20

    shelf_life_days: 730
    available_weeks: [1, 52]
    production_season_weeks: [36, 40]
    box_tiers: [full_yarrow]
    gift_suitable: true
    notes: High margin, excellent Christmas gift product
```

### products/baked.yaml (structure — two examples)

```yaml
products:
  - id: sourdough-ball
    name: Sourdough Ball
    category: baked
    unit: loaf_400g
    retail_price_gbp: 4.50

    production:
      inputs:
        - ingredient: flour_strong_white
          amount_g: 300
          cost_per_kg_gbp: 0.85
        - ingredient: flour_wholemeal
          amount_g: 100
          cost_per_kg_gbp: 1.10
        - ingredient: salt
          amount_g: 8
          cost_per_kg_gbp: 0.60
        - ingredient: starter
          amount_g: 80
          cost: 0
      labour_minutes_per_loaf: 20
      bake_day: tuesday
      packaging_cost_gbp: 0.08

    shelf_life_days: 5
    available_weeks: [1, 52]
    box_tiers: [field, larder, full_yarrow]

  - id: meringue-kisses
    name: Meringue Kisses
    category: baked
    unit: bag_12
    retail_price_gbp: 4.00

    production:
      inputs:
        - ingredient: egg_whites
          amount_g: 120
          cost: 0 # from farm hens, internal cost only
        - ingredient: caster_sugar
          amount_g: 240
          cost_per_kg_gbp: 1.20
      labour_minutes_per_batch: 25 # one batch = ~60 kisses / 5 bags
      bake_temp_c: 100
      bake_hours: 1.5
      packaging_cost_gbp: 0.12

    variants:
      - id: meringue-lavender
        name: Lavender Meringue Kisses
        additional_input: dried_lavender_flowers
        amount_g: 2
      - id: meringue-rose
        name: Rose Meringue Kisses
        additional_input: rose_water
        amount_ml: 5
      - id: meringue-brown-sugar
        name: Brown Sugar Meringues
        substitute: muscovado_sugar

    shelf_life_days: 21
    storage: airtight_cool_dry
    available_weeks: [1, 52]
    seasonal_pairing:
      - weeks: [20, 24]
        pair_with: honeyberry
      - weeks: [24, 28]
        pair_with: strawberry
      - weeks: [28, 36]
        pair_with: raspberry
      - weeks: [36, 42]
        pair_with: blackberry

    box_tiers: [larder, full_yarrow]
    notes: Make during dry weather only. Store in airtight tins.
```

### members/shares.yaml

Any number of tiers and drop points may be configured. The application
renders whatever tiers are present — it does not assume three tiers or
any specific tier names.

```yaml
tiers:
  - id: field
    name: Field Share
    price_gbp: 480
    weeks: 30
    description: Veg, eggs, sourdough

  - id: larder
    name: Larder Share
    price_gbp: 570
    weeks: 30
    description: Field plus honey, mushrooms, monthly preserve, meringues

  - id: full_yarrow
    name: Full Yarrow Share
    price_gbp: 660
    weeks: 30
    description: Larder plus cut flowers, medicinal teas, limited products

drop_points:
  - id: farm
    label: Farm pickup
    location: Yarrow Farm, North Norfolk
  - id: holt
    label: Holt
    location: TBC
  - id: wells
    label: Wells-next-the-Sea
    location: TBC
  - id: fakenham
    label: Fakenham
    location: TBC
```

</data_model>

---

<api_contracts>

These JSON shapes are fixed contracts. Do not deviate from them. The
Three.js canvas and HTMX panels will be built to consume exactly these
shapes in Phase 2. Note that arrays like beds, orchard, and boxes must
contain whatever the configuration has — no hardcoded lengths or assumptions
about specific zones being present.

### GET /api/week/:week

Returns the full farm state for a given week of the current year.

```json
{
  "week": 28,
  "year": 2025,
  "farm_summary": {
    "active_plantings": 14,
    "harvestable_beds": 8,
    "projected_harvest_kg": 42.5,
    "projected_box_value_gbp": 18.4,
    "estimated_costs_this_week_gbp": 95.0
  },
  "beds": [
    {
      "id": "V01",
      "label": "V01",
      "zone": "Intensive Veg",
      "zone_type": "veg",
      "growth_stage": "harvestable",
      "canopy_coverage": 0.9,
      "color_hex": "#E84020",
      "crop_name": "Tomato",
      "crop_variety": "Sungold",
      "weeks_since_sow": 20,
      "is_harvestable": true,
      "projected_harvest_kg": 2.4,
      "projected_harvest_unit": "punnet",
      "active_planting_id": "uuid-here"
    }
  ],
  "orchard": [
    {
      "id": "OR1-T1",
      "label": "OR1-T1",
      "zone": "Orchard",
      "tree_name": "Discovery Apple",
      "growth_stage": "summer_growth",
      "color_hex": "#60A820",
      "year_of_growth": 1,
      "yield_multiplier": 0.0,
      "estimated_yield_kg": 0.0,
      "bee_forage_value": "none"
    }
  ],
  "boxes": [
    {
      "tier_id": "field",
      "tier_name": "Field Share",
      "items": [
        {
          "product_id": "tomato-sungold",
          "product_name": "Tomato Sungold",
          "quantity": 1,
          "unit": "punnet 250g",
          "value_gbp": 1.8,
          "source_beds": ["V01"]
        }
      ],
      "total_value_gbp": 22.4,
      "item_count": 9,
      "hungry_gap_risk": false
    }
  ],
  "livestock": {
    "eggs_projected_this_week": 110,
    "honey_extractable": false,
    "hive_inspection_due": false
  }
}
```

### GET /api/farm

Returns the full static farm structure. Called once on load.

```json
{
  "farm": { "name": "Yarrow Farm" },
  "zones": [
    {
      "id": "intensive-veg",
      "name": "Intensive Veg",
      "type": "veg",
      "beds": [
        {
          "id": "V01",
          "label": "V01",
          "width_m": 0.75,
          "length_m": 8.0,
          "area_sqm": 6.0
        }
      ]
    }
  ],
  "livestock": {
    "hens": { "flock_size": 20 },
    "hives": { "count": 2 }
  }
}
```

### GET /api/beds

Returns all beds with their current planting schedules.

```json
{
  "beds": [
    {
      "id": "V01",
      "label": "V01",
      "zone": "Intensive Veg",
      "area_sqm": 6.0,
      "plantings": [
        {
          "id": "uuid",
          "crop_id": "tomato-sungold",
          "crop_name": "Tomato Sungold",
          "sow_week": 10,
          "sow_year": 2025,
          "expected_first_harvest_week": 26,
          "expected_last_harvest_week": 40,
          "status": "active"
        }
      ]
    }
  ]
}
```

### GET /ui/bed/:id — HTMX target

Returns an HTML fragment (not a full page) for the bed detail panel.
Includes crop info, current growth stage, projected harvests by week,
and planting history.

### GET /ui/week/:week/boxes — HTMX target

Returns an HTML fragment showing box compositions for all configured
tiers for the given week.

### GET /ui/week/:week/costs — HTMX target

Returns an HTML fragment showing cost breakdown for the given week.

</api_contracts>

---

<simulation_logic>

The simulation engine is the heart of this application. Implement it in
`src/simulation.ts`. For any given week it must:

```
for each bed:
  find active planting where sow_week <= current_week
    and (clear_week is null or clear_week > current_week)
    and sow_year = current_year

  if no active planting:
    return { growth_stage: "empty", color_hex: "#8B6914", canopy_coverage: 0 }

  calculate weeks_since_sow = current_week - planting.sow_week

  find the growth_stage entry from plant definition where:
    week_offset_start <= weeks_since_sow < week_offset_end

  calculate projected_harvest:
    if growth_stage == "harvestable":
      yield_per_sqm * bed_area_sqm * (actual_yield_modifier ?? 1.0)
    else:
      0

for each orchard tree:
  find the annual_cycle stage where current_week falls within stage.weeks
  calculate years_of_growth = current_year - tree.planted_year
  apply yield_by_year multiplier

for each box tier:
  collect all harvestable produce this week
  apply tier allocation rules (which products go in which tiers)
  calculate total estimated value
```

The week scrubber in the UI calls `/api/week/:week` on change. The
response drives both the Three.js canvas update and the HTMX panel
swaps simultaneously.

</simulation_logic>

---

<task>

## Phase 1 — Task 1 of 3: Schema only

Your first task is this and nothing more:

1. Study all YAML shapes defined in `<data_model>` above.
2. Design the SQLite schema that can store every entity and relationship
   shown across all YAML files.
3. Write the complete schema as `migrations/001_initial.sql`.
4. Include a brief comment above each table explaining its purpose and
   any non-obvious design decisions.

**Do not write any TypeScript yet.**
**Do not create any YAML files yet.**
**Do not set up Hono or any server code yet.**

Show me the complete `migrations/001_initial.sql` and stop.
Wait for my review and explicit "proceed" before writing anything else.

Key schema design notes:

- Monetary values as INTEGER (minor currency units). No REAL for money.
- Weeks as INTEGER 1–52. Years as INTEGER four digits.
- growth_stages for vegetables live in their own table keyed to
  plant_id, ordered by week_offset_start.
- annual_cycle stages for trees live in their own table keyed to
  plant_id, using week_start and week_end integers.
- The distinction between veg beds (planting cycles) and orchard
  trees (permanent, annual cycles) must be clear in the schema.
- Zone rows in berry and orchard zones may contain multiple plant_refs
  (mixed rows) — the schema must accommodate this.
- No counts, sizes, or zone types should be hardcoded. The schema must
  support any farm configuration that conforms to the YAML shapes above.

</task>

Before writing any code, output a complete plan.yaml file covering
all tasks required to build the full application across both phases.
Each task must include: id, name, description, done (false), context,
depends_on (list of task ids), and phase (1 or 2). Use the subsystems
and build order defined above. This file will be used to coordinate
work across sessions and sub-agents. Output plan.yaml and stop —
wait for review before proceeding to Task 1.

```yaml
# example task
tasks:
  - id: schema
    name: Initial SQLite schema
    description: >
      Write migrations/001_initial.sql covering all entities
      from the YAML data model. No application code.
    done: false
    context: >
      Foundation for everything. Must be reviewed and approved
      before any other task begins.
    depends_on: []
    phase: 1
```
