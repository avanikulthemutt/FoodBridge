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
