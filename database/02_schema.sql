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
