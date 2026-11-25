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
