-- FoodBridge: everything in one file (schema + functions + sample data).
-- Run inside the foodbridge database, on a fresh database.

-- ============================================================
-- FoodBridge: Step 2 - schema (18 tables, indexes, triggers)
-- Run inside the "foodbridge" database.
-- ============================================================

-- ---------- Helper function: auto-update updated_at ----------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- GROUP A: PEOPLE AND ORGANIZATIONS
-- ============================================================

-- 1. USERS
CREATE TABLE users (
    user_id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email             VARCHAR(255) NOT NULL UNIQUE,
    phone             VARCHAR(20)  UNIQUE,
    password_hash     TEXT         NOT NULL,
    role              VARCHAR(20)  NOT NULL
                      CHECK (role IN ('donor', 'ngo', 'volunteer', 'admin')),
    is_active         BOOLEAN      NOT NULL DEFAULT TRUE,
    is_email_verified BOOLEAN      NOT NULL DEFAULT FALSE,
    last_login_at     TIMESTAMPTZ,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- 2. ADDRESSES
CREATE TABLE addresses (
    address_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    address_line1 VARCHAR(255) NOT NULL,
    address_line2 VARCHAR(255),
    landmark      VARCHAR(150),
    city          VARCHAR(100) NOT NULL,
    state         VARCHAR(100) NOT NULL,
    postal_code   VARCHAR(10)  NOT NULL,
    country       VARCHAR(60)  NOT NULL DEFAULT 'India',
    latitude      NUMERIC(9,6) NOT NULL CHECK (latitude  BETWEEN -90  AND 90),
    longitude     NUMERIC(9,6) NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- 3. DONORS
CREATE TABLE donors (
    donor_id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id             BIGINT NOT NULL UNIQUE REFERENCES users(user_id) ON DELETE CASCADE,
    organization_name   VARCHAR(200) NOT NULL,
    donor_type          VARCHAR(30)  NOT NULL
                        CHECK (donor_type IN ('restaurant', 'hotel', 'college_canteen',
                                              'event_organizer', 'other')),
    contact_person      VARCHAR(120) NOT NULL,
    contact_phone       VARCHAR(20)  NOT NULL,
    address_id          BIGINT NOT NULL REFERENCES addresses(address_id),
    fssai_license_no    VARCHAR(30),
    verification_status VARCHAR(20)  NOT NULL DEFAULT 'pending'
                        CHECK (verification_status IN ('pending', 'verified', 'rejected')),
    is_active           BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- 4. NGOS
CREATE TABLE ngos (
    ngo_id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id             BIGINT NOT NULL UNIQUE REFERENCES users(user_id) ON DELETE CASCADE,
    ngo_name            VARCHAR(200) NOT NULL,
    registration_number VARCHAR(50)  NOT NULL UNIQUE,
    contact_person      VARCHAR(120) NOT NULL,
    contact_phone       VARCHAR(20)  NOT NULL,
    address_id          BIGINT NOT NULL REFERENCES addresses(address_id),
    description         TEXT,
    people_served_daily INTEGER CHECK (people_served_daily >= 0),
    verification_status VARCHAR(20)  NOT NULL DEFAULT 'pending'
                        CHECK (verification_status IN ('pending', 'verified', 'rejected')),
    is_active           BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- 5. VOLUNTEERS
CREATE TABLE volunteers (
    volunteer_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id             BIGINT NOT NULL UNIQUE REFERENCES users(user_id) ON DELETE CASCADE,
    full_name           VARCHAR(120) NOT NULL,
    phone               VARCHAR(20)  NOT NULL,
    address_id          BIGINT REFERENCES addresses(address_id),
    vehicle_type        VARCHAR(20)  NOT NULL DEFAULT 'none'
                        CHECK (vehicle_type IN ('none', 'bicycle', 'bike', 'car', 'van')),
    service_radius_km   NUMERIC(5,2) NOT NULL DEFAULT 5 CHECK (service_radius_km > 0),
    is_available        BOOLEAN      NOT NULL DEFAULT TRUE,
    current_latitude    NUMERIC(9,6),
    current_longitude   NUMERIC(9,6),
    verification_status VARCHAR(20)  NOT NULL DEFAULT 'pending'
                        CHECK (verification_status IN ('pending', 'verified', 'rejected')),
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- 6. VERIFICATION_DOCUMENTS
CREATE TABLE verification_documents (
    document_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id          BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    document_type    VARCHAR(30) NOT NULL
                     CHECK (document_type IN ('fssai_license', 'ngo_registration', 'gst_certificate',
                                              'government_id', 'other')),
    document_number  VARCHAR(80),
    file_url         TEXT NOT NULL,
    status           VARCHAR(20) NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'approved', 'rejected')),
    reviewed_by      BIGINT REFERENCES users(user_id),
    reviewed_at      TIMESTAMPTZ,
    rejection_reason TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- GROUP B: FOOD DONATIONS
-- ============================================================

-- 7. FOOD_CATEGORIES
CREATE TABLE food_categories (
    category_id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_name           VARCHAR(80) NOT NULL UNIQUE,
    description             TEXT,
    default_shelf_life_hrs  INTEGER NOT NULL DEFAULT 4 CHECK (default_shelf_life_hrs > 0),
    requires_refrigeration  BOOLEAN NOT NULL DEFAULT FALSE,
    is_active               BOOLEAN NOT NULL DEFAULT TRUE
);

-- 8. DONATIONS (one post; meals total is kept in sync by a trigger on donation_items)
CREATE TABLE donations (
    donation_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    donor_id            BIGINT NOT NULL REFERENCES donors(donor_id),
    pickup_address_id   BIGINT NOT NULL REFERENCES addresses(address_id),
    title               VARCHAR(200) NOT NULL,
    description         TEXT,
    total_meals         INTEGER NOT NULL DEFAULT 0 CHECK (total_meals >= 0),
    urgency_level       VARCHAR(10) NOT NULL DEFAULT 'medium'
                        CHECK (urgency_level IN ('low', 'medium', 'high', 'critical')),
    prepared_at         TIMESTAMPTZ NOT NULL,
    expiry_at           TIMESTAMPTZ NOT NULL,
    pickup_start        TIMESTAMPTZ NOT NULL,
    pickup_end          TIMESTAMPTZ NOT NULL,
    status              VARCHAR(20) NOT NULL DEFAULT 'available'
                        CHECK (status IN ('draft', 'available', 'matched', 'accepted',
                                          'picked_up', 'delivered', 'expired', 'cancelled')),
    special_instructions TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_expiry_after_prepared CHECK (expiry_at > prepared_at),
    CONSTRAINT chk_pickup_window         CHECK (pickup_end > pickup_start),
    CONSTRAINT chk_pickup_before_expiry  CHECK (pickup_end <= expiry_at)
);

-- 9. DONATION_ITEMS
CREATE TABLE donation_items (
    item_id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    donation_id       BIGINT NOT NULL REFERENCES donations(donation_id) ON DELETE CASCADE,
    category_id       BIGINT NOT NULL REFERENCES food_categories(category_id),
    item_name         VARCHAR(150) NOT NULL,
    quantity          NUMERIC(10,2) NOT NULL CHECK (quantity > 0),
    unit              VARCHAR(15) NOT NULL
                      CHECK (unit IN ('kg', 'litre', 'plates', 'packets', 'pieces')),
    estimated_meals   INTEGER NOT NULL CHECK (estimated_meals > 0),
    weight_kg         NUMERIC(10,2) CHECK (weight_kg >= 0),
    food_type         VARCHAR(10) NOT NULL DEFAULT 'veg'
                      CHECK (food_type IN ('veg', 'non_veg', 'egg', 'vegan')),
    freshness_status  VARCHAR(15) NOT NULL DEFAULT 'fresh'
                      CHECK (freshness_status IN ('fresh', 'good', 'use_soon')),
    storage_condition VARCHAR(15) NOT NULL DEFAULT 'room_temp'
                      CHECK (storage_condition IN ('room_temp', 'hot', 'chilled', 'frozen')),
    allergens         VARCHAR(200),
    notes             TEXT
);

-- ============================================================
-- GROUP C: AI MATCHING
-- ============================================================

-- 10. NGO_PREFERENCES
CREATE TABLE ngo_preferences (
    preference_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ngo_id               BIGINT NOT NULL UNIQUE REFERENCES ngos(ngo_id) ON DELETE CASCADE,
    max_distance_km      NUMERIC(6,2) NOT NULL DEFAULT 15 CHECK (max_distance_km > 0),
    min_meals_per_pickup INTEGER NOT NULL DEFAULT 1  CHECK (min_meals_per_pickup >= 0),
    daily_capacity_meals INTEGER NOT NULL DEFAULT 200 CHECK (daily_capacity_meals > 0),
    accepts_veg_only     BOOLEAN NOT NULL DEFAULT FALSE,
    has_cold_storage     BOOLEAN NOT NULL DEFAULT FALSE,
    has_own_transport    BOOLEAN NOT NULL DEFAULT FALSE,
    open_time            TIME NOT NULL DEFAULT '06:00',
    close_time           TIME NOT NULL DEFAULT '22:00',
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 10b. NGO_ACCEPTED_CATEGORIES (many-to-many: which food types an NGO accepts)
--      If an NGO has no rows here, it is treated as accepting all categories.
CREATE TABLE ngo_accepted_categories (
    ngo_id      BIGINT NOT NULL REFERENCES ngos(ngo_id) ON DELETE CASCADE,
    category_id BIGINT NOT NULL REFERENCES food_categories(category_id) ON DELETE CASCADE,
    PRIMARY KEY (ngo_id, category_id)
);

-- 10c. MATCHING_CONFIG (AI weights live in the database, so they can be tuned without code changes)
CREATE TABLE matching_config (
    config_id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    version_name       VARCHAR(40) NOT NULL UNIQUE,
    weight_quantity    NUMERIC(4,2) NOT NULL CHECK (weight_quantity >= 0),
    weight_freshness   NUMERIC(4,2) NOT NULL CHECK (weight_freshness >= 0),
    weight_urgency     NUMERIC(4,2) NOT NULL CHECK (weight_urgency >= 0),
    weight_distance    NUMERIC(4,2) NOT NULL CHECK (weight_distance >= 0),
    avg_speed_kmph     NUMERIC(5,2) NOT NULL DEFAULT 25 CHECK (avg_speed_kmph > 0),
    pickup_buffer_mins INTEGER NOT NULL DEFAULT 30 CHECK (pickup_buffer_mins >= 0),
    is_active          BOOLEAN NOT NULL DEFAULT FALSE,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_weights_sum CHECK (weight_quantity + weight_freshness + weight_urgency + weight_distance = 1.00)
);
-- Only one config may be active at a time
CREATE UNIQUE INDEX uq_matching_config_active ON matching_config (is_active) WHERE is_active;

-- 11. MATCHES
CREATE TABLE matches (
    match_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    donation_id      BIGINT NOT NULL REFERENCES donations(donation_id) ON DELETE CASCADE,
    ngo_id           BIGINT NOT NULL REFERENCES ngos(ngo_id),
    config_id        BIGINT REFERENCES matching_config(config_id),
    total_score      NUMERIC(5,2) NOT NULL CHECK (total_score BETWEEN 0 AND 100),
    quantity_score   NUMERIC(5,2) NOT NULL CHECK (quantity_score  BETWEEN 0 AND 100),
    freshness_score  NUMERIC(5,2) NOT NULL CHECK (freshness_score BETWEEN 0 AND 100),
    urgency_score    NUMERIC(5,2) NOT NULL CHECK (urgency_score   BETWEEN 0 AND 100),
    distance_score   NUMERIC(5,2) NOT NULL CHECK (distance_score  BETWEEN 0 AND 100),
    distance_km      NUMERIC(7,2) NOT NULL CHECK (distance_km >= 0),
    rank_position    INTEGER NOT NULL CHECK (rank_position > 0),
    status           VARCHAR(15) NOT NULL DEFAULT 'suggested'
                     CHECK (status IN ('suggested', 'notified', 'accepted', 'rejected',
                                       'expired', 'cancelled')),
    notified_at      TIMESTAMPTZ,
    responded_at     TIMESTAMPTZ,
    rejection_reason TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (donation_id, ngo_id)
);
-- A donation can have at most ONE accepted match
CREATE UNIQUE INDEX uq_one_accepted_match ON matches (donation_id) WHERE status = 'accepted';

-- ============================================================
-- GROUP D: DELIVERY AND AUDIT
-- ============================================================

-- 12. DELIVERIES
CREATE TABLE deliveries (
    delivery_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    donation_id         BIGINT NOT NULL UNIQUE REFERENCES donations(donation_id),
    match_id            BIGINT NOT NULL UNIQUE REFERENCES matches(match_id),
    volunteer_id        BIGINT REFERENCES volunteers(volunteer_id),
    status              VARCHAR(20) NOT NULL DEFAULT 'pending_assignment'
                        CHECK (status IN ('pending_assignment', 'assigned', 'en_route_pickup',
                                          'picked_up', 'in_transit', 'delivered',
                                          'failed', 'cancelled')),
    pickup_otp          CHAR(4),
    delivery_otp        CHAR(4),
    assigned_at         TIMESTAMPTZ,
    picked_up_at        TIMESTAMPTZ,
    delivered_at        TIMESTAMPTZ,
    pickup_proof_url    TEXT,
    delivery_proof_url  TEXT,
    route_distance_km   NUMERIC(7,2) CHECK (route_distance_km >= 0),
    failure_reason      TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 13. DONATION_STATUS_HISTORY (filled automatically by a trigger)
CREATE TABLE donation_status_history (
    history_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    donation_id  BIGINT NOT NULL REFERENCES donations(donation_id) ON DELETE CASCADE,
    old_status   VARCHAR(20),
    new_status   VARCHAR(20) NOT NULL,
    changed_by   BIGINT REFERENCES users(user_id),
    note         TEXT,
    changed_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- GROUP E: FEEDBACK AND IMPACT
-- ============================================================

-- 14. REVIEWS
CREATE TABLE reviews (
    review_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    donation_id      BIGINT NOT NULL REFERENCES donations(donation_id) ON DELETE CASCADE,
    reviewer_user_id BIGINT NOT NULL REFERENCES users(user_id),
    reviewee_user_id BIGINT NOT NULL REFERENCES users(user_id),
    rating           SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment          TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_no_self_review CHECK (reviewer_user_id <> reviewee_user_id),
    UNIQUE (donation_id, reviewer_user_id, reviewee_user_id)
);

-- 15. IMPACT_RECORDS
CREATE TABLE impact_records (
    impact_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    donation_id     BIGINT NOT NULL UNIQUE REFERENCES donations(donation_id),
    donor_id        BIGINT NOT NULL REFERENCES donors(donor_id),
    ngo_id          BIGINT NOT NULL REFERENCES ngos(ngo_id),
    meals_served    INTEGER NOT NULL CHECK (meals_served >= 0),
    food_weight_kg  NUMERIC(10,2) NOT NULL CHECK (food_weight_kg >= 0),
    co2_saved_kg    NUMERIC(10,2) NOT NULL CHECK (co2_saved_kg >= 0),
    recorded_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- GROUP F: SYSTEM
-- ============================================================

-- 16. NOTIFICATIONS
CREATE TABLE notifications (
    notification_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id              BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    notification_type    VARCHAR(30) NOT NULL
                         CHECK (notification_type IN ('new_match', 'match_accepted', 'match_rejected',
                                                      'volunteer_assigned', 'pickup_done',
                                                      'delivery_done', 'donation_expiring',
                                                      'verification_update', 'system')),
    title                VARCHAR(150) NOT NULL,
    message              TEXT NOT NULL,
    related_donation_id  BIGINT REFERENCES donations(donation_id) ON DELETE SET NULL,
    related_match_id     BIGINT REFERENCES matches(match_id) ON DELETE SET NULL,
    is_read              BOOLEAN NOT NULL DEFAULT FALSE,
    read_at              TIMESTAMPTZ,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX idx_addresses_lat_lng     ON addresses (latitude, longitude);
CREATE INDEX idx_addresses_city        ON addresses (city);
CREATE INDEX idx_donors_address        ON donors (address_id);
CREATE INDEX idx_donors_type_status    ON donors (donor_type, verification_status);
CREATE INDEX idx_ngos_address          ON ngos (address_id);
CREATE INDEX idx_ngos_status           ON ngos (verification_status, is_active);
CREATE INDEX idx_volunteers_available  ON volunteers (is_available, verification_status);
CREATE INDEX idx_documents_user        ON verification_documents (user_id);
CREATE INDEX idx_documents_status      ON verification_documents (status);
CREATE INDEX idx_donations_donor       ON donations (donor_id);
CREATE INDEX idx_donations_status_exp  ON donations (status, expiry_at);
CREATE INDEX idx_donation_items_don    ON donation_items (donation_id);
CREATE INDEX idx_donation_items_cat    ON donation_items (category_id);
CREATE INDEX idx_matches_ngo_status    ON matches (ngo_id, status);
CREATE INDEX idx_matches_donation_rank ON matches (donation_id, rank_position);
CREATE INDEX idx_deliveries_volunteer  ON deliveries (volunteer_id, status);
CREATE INDEX idx_history_donation      ON donation_status_history (donation_id, changed_at);
CREATE INDEX idx_reviews_reviewee      ON reviews (reviewee_user_id);
CREATE INDEX idx_impact_donor          ON impact_records (donor_id);
CREATE INDEX idx_impact_ngo            ON impact_records (ngo_id);
CREATE INDEX idx_notifications_user    ON notifications (user_id, is_read, created_at DESC);

-- ============================================================
-- TRIGGERS
-- ============================================================
CREATE TRIGGER trg_users_updated      BEFORE UPDATE ON users      FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_donors_updated     BEFORE UPDATE ON donors     FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_ngos_updated       BEFORE UPDATE ON ngos       FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_volunteers_updated BEFORE UPDATE ON volunteers FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_donations_updated  BEFORE UPDATE ON donations  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_deliveries_updated BEFORE UPDATE ON deliveries FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_ngo_pref_updated   BEFORE UPDATE ON ngo_preferences FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Keep donations.total_meals equal to the sum of its items
CREATE OR REPLACE FUNCTION sync_donation_meals()
RETURNS TRIGGER AS $$
DECLARE
    v_donation_id BIGINT;
BEGIN
    v_donation_id := COALESCE(NEW.donation_id, OLD.donation_id);
    UPDATE donations
       SET total_meals = COALESCE((SELECT SUM(estimated_meals)
                                     FROM donation_items
                                    WHERE donation_id = v_donation_id), 0)
     WHERE donation_id = v_donation_id;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_items_sync_meals
AFTER INSERT OR UPDATE OR DELETE ON donation_items
FOR EACH ROW EXECUTE FUNCTION sync_donation_meals();

-- Log every donation status change automatically
CREATE OR REPLACE FUNCTION log_donation_status()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO donation_status_history (donation_id, old_status, new_status)
        VALUES (NEW.donation_id, NULL, NEW.status);
    ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO donation_status_history (donation_id, old_status, new_status)
        VALUES (NEW.donation_id, OLD.status, NEW.status);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_donations_status_log
AFTER INSERT OR UPDATE OF status ON donations
FOR EACH ROW EXECUTE FUNCTION log_donation_status();

-- ============================================================
-- FoodBridge: Step 3 - AI matching engine, helper functions, views
-- Run AFTER 02_schema.sql
-- ============================================================

-- ------------------------------------------------------------
-- Distance between two lat/lng points in km (Haversine formula)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION haversine_km(lat1 NUMERIC, lon1 NUMERIC, lat2 NUMERIC, lon2 NUMERIC)
RETURNS NUMERIC AS $$
    SELECT ROUND(
        (6371 * acos(LEAST(1.0, GREATEST(-1.0,
            cos(radians(lat1)) * cos(radians(lat2)) * cos(radians(lon2) - radians(lon1)) +
            sin(radians(lat1)) * sin(radians(lat2))
        ))))::numeric, 2);
$$ LANGUAGE sql IMMUTABLE;

-- ------------------------------------------------------------
-- generate_matches(donation_id, how_many)
-- Scores every eligible NGO on 4 signals and saves the top N in "matches".
--   Quantity  : can the NGO take all the meals (remaining daily capacity)?
--   Freshness : how much safe time is left after travelling there?
--   Urgency   : urgent food scores higher for nearby NGOs
--   Distance  : closer is better, relative to the NGO's max distance
-- Returns the number of matches created.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION generate_matches(p_donation_id BIGINT, p_limit INTEGER DEFAULT 5)
RETURNS INTEGER AS $$
DECLARE
    v_cfg       matching_config%ROWTYPE;
    v_don       donations%ROWTYPE;
    v_lat       NUMERIC;
    v_lng       NUMERIC;
    v_urg_base  NUMERIC;
    v_hrs_left  NUMERIC;
    v_has_nonveg BOOLEAN;
    v_needs_cold BOOLEAN;
    v_count     INTEGER;
BEGIN
    SELECT * INTO v_cfg FROM matching_config WHERE is_active LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No active row in matching_config';
    END IF;

    SELECT * INTO v_don FROM donations WHERE donation_id = p_donation_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Donation % not found', p_donation_id;
    END IF;
    IF v_don.status NOT IN ('available', 'matched') THEN
        RAISE EXCEPTION 'Donation % has status %, cannot match', p_donation_id, v_don.status;
    END IF;
    IF v_don.total_meals <= 0 THEN
        RAISE EXCEPTION 'Donation % has no items', p_donation_id;
    END IF;

    v_hrs_left := EXTRACT(EPOCH FROM (v_don.expiry_at - NOW())) / 3600.0;
    IF v_hrs_left <= 0 THEN
        RAISE EXCEPTION 'Donation % has already expired', p_donation_id;
    END IF;

    SELECT latitude, longitude INTO v_lat, v_lng
      FROM addresses WHERE address_id = v_don.pickup_address_id;

    v_urg_base := CASE v_don.urgency_level
                      WHEN 'low' THEN 25 WHEN 'medium' THEN 50
                      WHEN 'high' THEN 75 ELSE 100 END;

    SELECT EXISTS (SELECT 1 FROM donation_items
                    WHERE donation_id = p_donation_id AND food_type IN ('non_veg', 'egg'))
      INTO v_has_nonveg;

    SELECT EXISTS (SELECT 1 FROM donation_items di
                     JOIN food_categories fc ON fc.category_id = di.category_id
                    WHERE di.donation_id = p_donation_id
                      AND (fc.requires_refrigeration OR di.storage_condition IN ('chilled', 'frozen')))
      INTO v_needs_cold;

    -- Remove old suggestions that nobody acted on (rejected/accepted rows stay)
    DELETE FROM matches
     WHERE donation_id = p_donation_id AND status IN ('suggested', 'notified');

    INSERT INTO matches (donation_id, ngo_id, config_id, total_score, quantity_score,
                         freshness_score, urgency_score, distance_score, distance_km, rank_position)
    WITH candidates AS (
        SELECT n.ngo_id,
               haversine_km(v_lat, v_lng, a.latitude, a.longitude)           AS dist_km,
               COALESCE(p.max_distance_km, 15)                               AS max_km,
               COALESCE(p.daily_capacity_meals, 200) - COALESCE(used.meals, 0) AS remaining
          FROM ngos n
          JOIN users u          ON u.user_id = n.user_id AND u.is_active
          JOIN addresses a      ON a.address_id = n.address_id
          LEFT JOIN ngo_preferences p ON p.ngo_id = n.ngo_id
          LEFT JOIN LATERAL (
                SELECT SUM(d.total_meals) AS meals
                  FROM matches m
                  JOIN donations d ON d.donation_id = m.donation_id
                 WHERE m.ngo_id = n.ngo_id
                   AND m.status = 'accepted'
                   AND m.responded_at >= date_trunc('day', NOW())
          ) used ON TRUE
         WHERE n.verification_status = 'verified'
           AND n.is_active
           AND NOT EXISTS (SELECT 1 FROM matches m2
                            WHERE m2.donation_id = p_donation_id AND m2.ngo_id = n.ngo_id)
           AND (NOT COALESCE(p.accepts_veg_only, FALSE) OR NOT v_has_nonveg)
           AND (COALESCE(p.has_cold_storage, FALSE)     OR NOT v_needs_cold)
           AND v_don.total_meals >= COALESCE(p.min_meals_per_pickup, 1)
           AND (NOT EXISTS (SELECT 1 FROM ngo_accepted_categories nac WHERE nac.ngo_id = n.ngo_id)
                OR EXISTS (SELECT 1 FROM ngo_accepted_categories nac
                             JOIN donation_items di ON di.category_id = nac.category_id
                            WHERE nac.ngo_id = n.ngo_id AND di.donation_id = p_donation_id))
    ),
    eligible AS (
        SELECT c.*,
               c.dist_km / v_cfg.avg_speed_kmph + v_cfg.pickup_buffer_mins / 60.0 AS travel_hrs
          FROM candidates c
         WHERE c.remaining > 0
           AND c.dist_km <= c.max_km
    ),
    scored AS (
        SELECT e.ngo_id, e.dist_km,
               100.0 * LEAST(e.remaining, v_don.total_meals) / v_don.total_meals       AS q,
               100.0 * LEAST(1.0, GREATEST(0.0, (v_hrs_left - e.travel_hrs) / v_hrs_left)) AS f,
               100.0 * GREATEST(0.0, 1.0 - e.dist_km / e.max_km)                       AS d
          FROM eligible e
         WHERE v_hrs_left > e.travel_hrs
    ),
    with_urgency AS (
        SELECT s.*,
               LEAST(100.0, v_urg_base * 0.6 + s.d * 0.4) AS u
          FROM scored s
    ),
    totals AS (
        SELECT f.*,
               (v_cfg.weight_quantity * f.q + v_cfg.weight_freshness * f.f +
                v_cfg.weight_urgency  * f.u + v_cfg.weight_distance  * f.d) AS total
          FROM with_urgency f
    )
    SELECT p_donation_id, t.ngo_id, v_cfg.config_id,
           ROUND(t.total, 2), ROUND(t.q, 2), ROUND(t.f, 2), ROUND(t.u, 2), ROUND(t.d, 2),
           t.dist_km,
           ROW_NUMBER() OVER (ORDER BY t.total DESC, t.dist_km ASC)
      FROM totals t
     ORDER BY t.total DESC, t.dist_km ASC
     LIMIT p_limit;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    IF v_count > 0 THEN
        -- Tell each matched NGO
        INSERT INTO notifications (user_id, notification_type, title, message,
                                   related_donation_id, related_match_id)
        SELECT n.user_id, 'new_match', 'New food donation near you',
               format('%s meals from %s, %s km away. Pickup by %s.',
                      d.total_meals, dn.organization_name, m.distance_km,
                      to_char(d.pickup_end AT TIME ZONE 'Asia/Kolkata', 'HH12:MI AM')),
               d.donation_id, m.match_id
          FROM matches m
          JOIN ngos n      ON n.ngo_id = m.ngo_id
          JOIN donations d ON d.donation_id = m.donation_id
          JOIN donors dn   ON dn.donor_id = d.donor_id
         WHERE m.donation_id = p_donation_id AND m.status = 'suggested';

        UPDATE matches SET status = 'notified', notified_at = NOW()
         WHERE donation_id = p_donation_id AND status = 'suggested';

        UPDATE donations SET status = 'matched'
         WHERE donation_id = p_donation_id AND status = 'available';
    END IF;

    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- accept_match(match_id): NGO accepts -> other offers cancelled,
-- donation accepted, delivery row created, both sides notified.
-- Returns the new delivery_id.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION accept_match(p_match_id BIGINT)
RETURNS BIGINT AS $$
DECLARE
    v_m           matches%ROWTYPE;
    v_delivery_id BIGINT;
    v_otp1        CHAR(4);
    v_otp2        CHAR(4);
BEGIN
    SELECT * INTO v_m FROM matches WHERE match_id = p_match_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Match % not found', p_match_id;
    END IF;
    IF v_m.status NOT IN ('suggested', 'notified') THEN
        RAISE EXCEPTION 'Match % is already %', p_match_id, v_m.status;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM donations
                    WHERE donation_id = v_m.donation_id AND status IN ('available', 'matched')) THEN
        RAISE EXCEPTION 'Donation % is no longer open', v_m.donation_id;
    END IF;

    UPDATE matches SET status = 'accepted', responded_at = NOW() WHERE match_id = p_match_id;
    UPDATE matches SET status = 'cancelled'
     WHERE donation_id = v_m.donation_id AND match_id <> p_match_id
       AND status IN ('suggested', 'notified');
    UPDATE donations SET status = 'accepted' WHERE donation_id = v_m.donation_id;

    v_otp1 := lpad(floor(random() * 10000)::int::text, 4, '0');
    v_otp2 := lpad(floor(random() * 10000)::int::text, 4, '0');

    INSERT INTO deliveries (donation_id, match_id, pickup_otp, delivery_otp)
    VALUES (v_m.donation_id, p_match_id, v_otp1, v_otp2)
    RETURNING delivery_id INTO v_delivery_id;

    -- Notify the donor
    INSERT INTO notifications (user_id, notification_type, title, message,
                               related_donation_id, related_match_id)
    SELECT dn.user_id, 'match_accepted', 'Your donation was accepted',
           format('%s accepted your donation. A volunteer will be assigned soon.', n.ngo_name),
           d.donation_id, p_match_id
      FROM donations d
      JOIN donors dn ON dn.donor_id = d.donor_id
      JOIN ngos n    ON n.ngo_id = v_m.ngo_id
     WHERE d.donation_id = v_m.donation_id;

    RETURN v_delivery_id;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- assign_nearest_volunteer(delivery_id)
-- Picks the nearest available, verified volunteer who is within
-- their own service radius of the pickup address.
-- Returns volunteer_id, or NULL if nobody is available.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION assign_nearest_volunteer(p_delivery_id BIGINT)
RETURNS BIGINT AS $$
DECLARE
    v_donation_id  BIGINT;
    v_lat          NUMERIC;
    v_lng          NUMERIC;
    v_volunteer_id BIGINT;
BEGIN
    SELECT d.donation_id, a.latitude, a.longitude
      INTO v_donation_id, v_lat, v_lng
      FROM deliveries dl
      JOIN donations d ON d.donation_id = dl.donation_id
      JOIN addresses a ON a.address_id = d.pickup_address_id
     WHERE dl.delivery_id = p_delivery_id AND dl.volunteer_id IS NULL;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    SELECT v.volunteer_id INTO v_volunteer_id
      FROM volunteers v
      JOIN users u ON u.user_id = v.user_id AND u.is_active
     WHERE v.is_available
       AND v.verification_status = 'verified'
       AND v.current_latitude IS NOT NULL
       AND haversine_km(v_lat, v_lng, v.current_latitude, v.current_longitude) <= v.service_radius_km
     ORDER BY haversine_km(v_lat, v_lng, v.current_latitude, v.current_longitude)
     LIMIT 1;

    IF v_volunteer_id IS NULL THEN
        RETURN NULL;
    END IF;

    UPDATE deliveries SET volunteer_id = v_volunteer_id, status = 'assigned', assigned_at = NOW()
     WHERE delivery_id = p_delivery_id;
    UPDATE volunteers SET is_available = FALSE WHERE volunteer_id = v_volunteer_id;

    INSERT INTO notifications (user_id, notification_type, title, message, related_donation_id)
    SELECT vo.user_id, 'volunteer_assigned', 'New pickup assigned',
           'You have a new food pickup. Open the app for details.', v_donation_id
      FROM volunteers vo WHERE vo.volunteer_id = v_volunteer_id;

    RETURN v_volunteer_id;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- When a delivery moves to picked_up / delivered, update the donation,
-- free the volunteer, and create the impact record automatically.
-- CO2 factor (2.5 kg CO2e saved per kg of food) is an ASSUMPTION for demo
-- purposes; replace it with a cited figure before publishing numbers.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION on_delivery_status_change()
RETURNS TRIGGER AS $$
DECLARE
    v_donor_id BIGINT;
    v_ngo_id   BIGINT;
    v_meals    INTEGER;
    v_weight   NUMERIC;
BEGIN
    IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
        RETURN NULL;
    END IF;

    IF NEW.status = 'picked_up' THEN
        UPDATE donations SET status = 'picked_up' WHERE donation_id = NEW.donation_id;

    ELSIF NEW.status = 'delivered' THEN
        UPDATE donations SET status = 'delivered' WHERE donation_id = NEW.donation_id;

        SELECT d.donor_id, m.ngo_id, d.total_meals,
               COALESCE(NULLIF((SELECT SUM(weight_kg) FROM donation_items
                                 WHERE donation_id = d.donation_id), 0), d.total_meals * 0.4)
          INTO v_donor_id, v_ngo_id, v_meals, v_weight
          FROM donations d
          JOIN matches m ON m.match_id = NEW.match_id
         WHERE d.donation_id = NEW.donation_id;

        INSERT INTO impact_records (donation_id, donor_id, ngo_id, meals_served,
                                    food_weight_kg, co2_saved_kg)
        VALUES (NEW.donation_id, v_donor_id, v_ngo_id, v_meals, v_weight, ROUND(v_weight * 2.5, 2))
        ON CONFLICT (donation_id) DO NOTHING;

        IF NEW.volunteer_id IS NOT NULL THEN
            UPDATE volunteers SET is_available = TRUE WHERE volunteer_id = NEW.volunteer_id;
        END IF;

    ELSIF NEW.status IN ('failed', 'cancelled') AND NEW.volunteer_id IS NOT NULL THEN
        UPDATE volunteers SET is_available = TRUE WHERE volunteer_id = NEW.volunteer_id;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_delivery_status
AFTER UPDATE OF status ON deliveries
FOR EACH ROW EXECUTE FUNCTION on_delivery_status_change();

-- ------------------------------------------------------------
-- expire_old_donations(): run every few minutes (cron / pg_cron / backend job)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION expire_old_donations()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER;
BEGIN
    UPDATE matches SET status = 'expired'
     WHERE status IN ('suggested', 'notified')
       AND donation_id IN (SELECT donation_id FROM donations
                            WHERE status IN ('available', 'matched') AND expiry_at < NOW());

    UPDATE donations SET status = 'expired'
     WHERE status IN ('available', 'matched') AND expiry_at < NOW();
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- VIEWS (ready-made queries for your dashboards and landing page)
-- ============================================================

-- Landing page counters: meals rescued, partner donors, NGOs served, tonnes diverted
CREATE OR REPLACE VIEW v_impact_summary AS
SELECT COALESCE(SUM(meals_served), 0)                          AS meals_rescued,
       COUNT(DISTINCT donor_id)                                AS partner_donors,
       COUNT(DISTINCT ngo_id)                                  AS ngos_served,
       ROUND(COALESCE(SUM(food_weight_kg), 0) / 1000.0, 3)     AS tonnes_diverted,
       COALESCE(SUM(co2_saved_kg), 0)                          AS co2_saved_kg
  FROM impact_records;

-- Open donations with donor details and hours left (for the NGO feed and map)
CREATE OR REPLACE VIEW v_open_donations AS
SELECT d.donation_id, d.title, d.total_meals, d.urgency_level, d.status,
       dn.organization_name, dn.donor_type,
       a.latitude, a.longitude, a.city,
       d.pickup_start, d.pickup_end, d.expiry_at,
       ROUND((EXTRACT(EPOCH FROM (d.expiry_at - NOW())) / 3600.0)::numeric, 1) AS hours_left
  FROM donations d
  JOIN donors dn   ON dn.donor_id = d.donor_id
  JOIN addresses a ON a.address_id = d.pickup_address_id
 WHERE d.status IN ('available', 'matched') AND d.expiry_at > NOW();

-- Average rating and review count per user (donor, NGO or volunteer)
CREATE OR REPLACE VIEW v_user_ratings AS
SELECT reviewee_user_id AS user_id,
       ROUND(AVG(rating), 2) AS avg_rating,
       COUNT(*)              AS review_count
  FROM reviews
 GROUP BY reviewee_user_id;

-- Per-donor leaderboard
CREATE OR REPLACE VIEW v_donor_leaderboard AS
SELECT dn.donor_id, dn.organization_name, dn.donor_type,
       COUNT(i.impact_id)                 AS donations_completed,
       COALESCE(SUM(i.meals_served), 0)   AS total_meals,
       COALESCE(SUM(i.co2_saved_kg), 0)   AS total_co2_saved_kg
  FROM donors dn
  LEFT JOIN impact_records i ON i.donor_id = dn.donor_id
 GROUP BY dn.donor_id, dn.organization_name, dn.donor_type
 ORDER BY total_meals DESC;

-- ============================================================
-- FoodBridge: Step 4 - reference data + sample data (Bengaluru)
-- Run AFTER 02_schema.sql and 03_functions_and_views.sql
-- Run on a FRESH database: IDs below assume numbering starts at 1.
-- Passwords are placeholders; use bcrypt/argon2 hashes in the real app.
-- ============================================================

-- ---------- Reference data ----------
INSERT INTO food_categories (category_name, description, default_shelf_life_hrs, requires_refrigeration) VALUES
('Cooked Meals',         'Rice, curries, dal, biryani, thali',          4,  FALSE),  -- 1
('Bakery & Bread',       'Bread, buns, rolls, cakes',                   24, FALSE),  -- 2
('Fruits & Vegetables',  'Fresh fruits and vegetables',                 48, FALSE),  -- 3
('Packaged Food',        'Sealed packets, biscuits, snacks',            720, FALSE), -- 4
('Dairy & Beverages',    'Curd, milk, buttermilk, juices',              12, TRUE),   -- 5
('Sweets & Desserts',    'Payasam, laddu, halwa, desserts',             8,  FALSE),  -- 6
('Raw Grains & Groceries','Rice, flour, pulses, oil (uncooked)',        2160, FALSE);-- 7

-- AI weights (must add up to 1.00). Change these to tune the matching.
INSERT INTO matching_config (version_name, weight_quantity, weight_freshness, weight_urgency, weight_distance, is_active) VALUES
('v1_balanced', 0.25, 0.25, 0.20, 0.30, TRUE);

-- ---------- Addresses ----------
INSERT INTO addresses (address_line1, landmark, city, state, postal_code, latitude, longitude) VALUES
('100 Feet Road, Indiranagar',   'Near Metro Station',  'Bengaluru', 'Karnataka', '560038', 12.971900, 77.641200), -- 1  Green Leaf
('12 MG Road',                   'Opposite Trinity',    'Bengaluru', 'Karnataka', '560001', 12.975600, 77.606600), -- 2  Grand Orchid
('Basavanagudi Main Road',       'Near Bull Temple',    'Bengaluru', 'Karnataka', '560004', 12.943000, 77.574000), -- 3  Sunrise canteen
('8th Cross, Malleshwaram',      'Near Sampige Road',   'Bengaluru', 'Karnataka', '560003', 12.996500, 77.571300), -- 4  Royal Palace
('5th Block, Koramangala',       'Near Forum Mall',     'Bengaluru', 'Karnataka', '560095', 12.935200, 77.624500), -- 5  Hope Foundation
('4th Block, Jayanagar',         'Near Shopping Complex','Bengaluru','Karnataka', '560011', 12.925000, 77.593800), -- 6  Annapurna
('Shivajinagar Bus Stand Road',  'Near Russell Market', 'Bengaluru', 'Karnataka', '560051', 12.985700, 77.605700), -- 7  Asha Kiran
('ITPL Main Road, Whitefield',   'Near Phoenix Mall',   'Bengaluru', 'Karnataka', '560066', 12.969800, 77.750000), -- 8  Little Hearts
('Sector 2, HSR Layout',         'Near Park',           'Bengaluru', 'Karnataka', '560102', 12.911600, 77.647400), -- 9  Volunteer 1
('CMH Road, Indiranagar',        'Near Hospital',       'Bengaluru', 'Karnataka', '560038', 12.978400, 77.640800), -- 10 Volunteer 2
('15th Cross, Malleshwaram',     'Near Park',           'Bengaluru', 'Karnataka', '560055', 12.998000, 77.570000); -- 11 Volunteer 3

-- ---------- Users ----------
INSERT INTO users (email, phone, password_hash, role, is_email_verified) VALUES
('admin@foodbridge.org',      '9000000001', 'hashed_pw_admin', 'admin',     TRUE), -- 1
('contact@greenleaf.com',     '9000000002', 'hashed_pw_d1',    'donor',     TRUE), -- 2
('manager@grandorchid.com',   '9000000003', 'hashed_pw_d2',    'donor',     TRUE), -- 3
('mess@sunrisecollege.edu',   '9000000004', 'hashed_pw_d3',    'donor',     TRUE), -- 4
('events@royalpalace.com',    '9000000005', 'hashed_pw_d4',    'donor',     TRUE), -- 5
('help@hopefoundation.org',   '9000000006', 'hashed_pw_n1',    'ngo',       TRUE), -- 6
('info@annapurnatrust.org',   '9000000007', 'hashed_pw_n2',    'ngo',       TRUE), -- 7
('care@ashakiran.org',        '9000000008', 'hashed_pw_n3',    'ngo',       TRUE), -- 8
('office@littlehearts.org',   '9000000009', 'hashed_pw_n4',    'ngo',       TRUE), -- 9
('ravi.kumar@example.com',    '9000000010', 'hashed_pw_v1',    'volunteer', TRUE), -- 10
('priya.nair@example.com',    '9000000011', 'hashed_pw_v2',    'volunteer', TRUE), -- 11
('arjun.das@example.com',     '9000000012', 'hashed_pw_v3',    'volunteer', TRUE); -- 12

-- ---------- Donors ----------
INSERT INTO donors (user_id, organization_name, donor_type, contact_person, contact_phone, address_id, fssai_license_no, verification_status) VALUES
(2, 'Green Leaf Restaurant',      'restaurant',      'Suresh Rao',   '9000000002', 1, '10020041000123', 'verified'), -- 1
(3, 'Grand Orchid Hotel',         'hotel',           'Meena Iyer',   '9000000003', 2, '10020041000456', 'verified'), -- 2
(4, 'Sunrise College Canteen',    'college_canteen', 'Kiran Patil',  '9000000004', 3, '10020041000789', 'verified'), -- 3
(5, 'Royal Palace Wedding Hall',  'event_organizer', 'Farhan Sheikh','9000000005', 4, '10020041000987', 'verified'); -- 4

-- ---------- NGOs ----------
INSERT INTO ngos (user_id, ngo_name, registration_number, contact_person, contact_phone, address_id, description, people_served_daily, verification_status) VALUES
(6, 'Hope Foundation',      'KA/NGO/2015/0001', 'Anita Sharma',  '9000000006', 5, 'Feeds children and homeless people daily.',       300, 'verified'), -- 1
(7, 'Annapurna Seva Trust', 'KA/NGO/2018/0042', 'Ramesh Nair',   '9000000007', 6, 'Community kitchen for the elderly (vegetarian).',  150, 'verified'), -- 2
(8, 'Asha Kiran Shelter',   'KA/NGO/2012/0107', 'Sister Mary',   '9000000008', 7, 'Night shelter for homeless adults.',               250, 'verified'), -- 3
(9, 'Little Hearts Home',   'KA/NGO/2019/0233', 'Deepa Menon',   '9000000009', 8, 'Children''s home in Whitefield.',                  100, 'verified'); -- 4

INSERT INTO ngo_preferences (ngo_id, max_distance_km, min_meals_per_pickup, daily_capacity_meals, accepts_veg_only, has_cold_storage, has_own_transport) VALUES
(1, 12, 20, 300, FALSE, TRUE,  FALSE),
(2, 10, 20, 150, TRUE,  FALSE, FALSE),
(3, 15, 30, 250, FALSE, FALSE, TRUE),
(4,  8, 10, 100, FALSE, FALSE, FALSE);

-- Annapurna accepts only cooked meals, bakery and packaged food. Others have no rows = accept all.
INSERT INTO ngo_accepted_categories (ngo_id, category_id) VALUES (2, 1), (2, 2), (2, 4);

-- ---------- Volunteers ----------
INSERT INTO volunteers (user_id, full_name, phone, address_id, vehicle_type, service_radius_km, is_available, current_latitude, current_longitude, verification_status) VALUES
(10, 'Ravi Kumar',  '9000000010', 9,  'bike',    10, TRUE, 12.911600, 77.647400, 'verified'), -- 1
(11, 'Priya Nair',  '9000000011', 10, 'car',     15, TRUE, 12.978400, 77.640800, 'verified'), -- 2
(12, 'Arjun Das',   '9000000012', 11, 'bicycle',  5, TRUE, 12.998000, 77.570000, 'verified'); -- 3

-- ---------- Verification documents ----------
INSERT INTO verification_documents (user_id, document_type, document_number, file_url, status, reviewed_by, reviewed_at) VALUES
(2, 'fssai_license',    '10020041000123',   'https://files.foodbridge.org/docs/greenleaf_fssai.pdf',  'approved', 1, NOW()),
(3, 'fssai_license',    '10020041000456',   'https://files.foodbridge.org/docs/grandorchid_fssai.pdf','approved', 1, NOW()),
(6, 'ngo_registration', 'KA/NGO/2015/0001', 'https://files.foodbridge.org/docs/hope_reg.pdf',         'approved', 1, NOW()),
(7, 'ngo_registration', 'KA/NGO/2018/0042', 'https://files.foodbridge.org/docs/annapurna_reg.pdf',    'approved', 1, NOW()),
(10,'government_id',    NULL,               'https://files.foodbridge.org/docs/ravi_id.pdf',          'pending',  NULL, NULL);

-- ============================================================
-- DONATIONS (times are relative to NOW() so the demo always works)
-- ============================================================
INSERT INTO donations (donor_id, pickup_address_id, title, description, urgency_level,
                       prepared_at, expiry_at, pickup_start, pickup_end, status, special_instructions) VALUES
-- 1: Green Leaf dinner surplus (high urgency, ~4 hrs left)
(1, 1, 'Dinner surplus - veg biryani and paneer', 'Freshly cooked, packed in containers', 'high',
    NOW() - INTERVAL '1 hour', NOW() + INTERVAL '4 hours', NOW() + INTERVAL '30 minutes', NOW() + INTERVAL '3 hours',
    'available', 'Ask for the manager at the back entrance'),
-- 2: Grand Orchid banquet surplus (medium urgency, ~6 hrs left, includes non-veg)
(2, 2, 'Banquet surplus - rice, dal, chicken curry, rolls', 'Corporate dinner leftovers', 'medium',
    NOW() - INTERVAL '1 hour', NOW() + INTERVAL '6 hours', NOW() + INTERVAL '1 hour', NOW() + INTERVAL '5 hours',
    'available', 'Pickup from service gate'),
-- 3: College canteen (low urgency, includes curd that needs a fridge)
(3, 3, 'Canteen lunch leftovers', 'After mess hours', 'low',
    NOW() - INTERVAL '2 hours', NOW() + INTERVAL '5 hours', NOW() + INTERVAL '1 hour', NOW() + INTERVAL '4 hours',
    'available', NULL),
-- 4: Wedding hall (critical, ~3 hrs left, large quantity)
(4, 4, 'Wedding reception surplus - veg thali', 'Large quantity, packed plates', 'critical',
    NOW() - INTERVAL '1 hour', NOW() + INTERVAL '3 hours', NOW() + INTERVAL '15 minutes', NOW() + INTERVAL '2 hours',
    'available', 'Bring large vehicle'),
-- 5: Old completed donation (already delivered yesterday)
(1, 1, 'Lunch surplus - veg meals', 'Completed earlier', 'medium',
    NOW() - INTERVAL '26 hours', NOW() - INTERVAL '20 hours', NOW() - INTERVAL '25 hours', NOW() - INTERVAL '22 hours',
    'delivered', NULL);

-- ---------- Donation items (donations.total_meals is filled by trigger) ----------
INSERT INTO donation_items (donation_id, category_id, item_name, quantity, unit, estimated_meals, weight_kg, food_type, freshness_status, storage_condition) VALUES
(1, 1, 'Veg biryani',              25,  'kg',      100, 25,  'veg',     'fresh', 'hot'),
(1, 1, 'Paneer butter masala',      8,  'kg',       20,  8,  'veg',     'fresh', 'hot'),

(2, 1, 'Steamed rice',             30,  'kg',      120, 30,  'veg',     'fresh', 'hot'),
(2, 1, 'Dal tadka',                10,  'kg',       40, 10,  'veg',     'fresh', 'hot'),
(2, 1, 'Chicken curry',            12,  'kg',       30, 12,  'non_veg', 'fresh', 'hot'),
(2, 2, 'Dinner rolls',             40,  'pieces',   40,  4,  'veg',     'good',  'room_temp'),

(3, 1, 'Veg pulao',                12,  'kg',       50, 12,  'veg',     'good',  'hot'),
(3, 3, 'Bananas',                   5,  'kg',       10,  5,  'vegan',   'fresh', 'room_temp'),
(3, 5, 'Curd',                     10,  'litre',    20, 10,  'veg',     'fresh', 'chilled'),

(4, 1, 'Veg thali (packed plates)', 300, 'plates', 300, 105, 'veg',     'fresh', 'hot'),
(4, 6, 'Payasam',                  20,  'litre',    40, 20,  'veg',     'fresh', 'hot'),

(5, 1, 'Veg meals',                 80, 'plates',   80,  28, 'veg',     'fresh', 'hot');

-- ---------- Completed donation #5: match, delivery, impact, reviews ----------
INSERT INTO matches (donation_id, ngo_id, config_id, total_score, quantity_score, freshness_score,
                     urgency_score, distance_score, distance_km, rank_position, status,
                     notified_at, responded_at)
VALUES (5, 1, 1, 88.50, 100.00, 85.00, 70.00, 90.00, 3.20, 1, 'accepted',
        NOW() - INTERVAL '25 hours', NOW() - INTERVAL '24 hours');

INSERT INTO deliveries (donation_id, match_id, volunteer_id, status, pickup_otp, delivery_otp,
                        assigned_at, picked_up_at, delivered_at, route_distance_km)
VALUES (5, (SELECT match_id FROM matches WHERE donation_id = 5), 1, 'delivered', '4821', '7350',
        NOW() - INTERVAL '24 hours', NOW() - INTERVAL '23 hours', NOW() - INTERVAL '22 hours', 3.4);

INSERT INTO impact_records (donation_id, donor_id, ngo_id, meals_served, food_weight_kg, co2_saved_kg)
VALUES (5, 1, 1, 80, 28.00, 70.00);

INSERT INTO reviews (donation_id, reviewer_user_id, reviewee_user_id, rating, comment) VALUES
(5, 6, 2, 5, 'Food was fresh and well packed. Thank you!'),
(5, 2, 6, 5, 'Quick pickup, very professional team.'),
(5, 2, 10, 4, 'Volunteer arrived on time.');

-- ============================================================
-- Run the AI matching for donations 1 and 2 (3 and 4 are left for you to test)
-- ============================================================
SELECT generate_matches(1);
SELECT generate_matches(2);
