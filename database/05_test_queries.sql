-- ============================================================
-- FoodBridge: Step 5 - test queries. Run them one by one.
-- ============================================================

-- 1. Total meals per open donation (trigger should have filled total_meals)
SELECT donation_id, title, total_meals, urgency_level, status FROM donations ORDER BY donation_id;

-- 2. AI ranking for donation 1 (Green Leaf, 120 meals, high urgency)
SELECT m.rank_position, n.ngo_name, m.total_score,
       m.quantity_score, m.freshness_score, m.urgency_score, m.distance_score, m.distance_km, m.status
  FROM matches m JOIN ngos n ON n.ngo_id = m.ngo_id
 WHERE m.donation_id = 1 ORDER BY m.rank_position;

-- 3. AI ranking for donation 2 (has non-veg, so veg-only Annapurna must be missing)
SELECT m.rank_position, n.ngo_name, m.total_score, m.distance_km
  FROM matches m JOIN ngos n ON n.ngo_id = m.ngo_id
 WHERE m.donation_id = 2 ORDER BY m.rank_position;

-- 4. Generate for donations 3 and 4, then compare
--    Donation 3 has chilled curd, so only NGOs with cold storage qualify.
--    Donation 4 is critical and large: see how capacity affects the quantity score.
SELECT generate_matches(3);
SELECT generate_matches(4);
SELECT m.donation_id, m.rank_position, n.ngo_name, m.total_score, m.quantity_score, m.distance_km
  FROM matches m JOIN ngos n ON n.ngo_id = m.ngo_id
 WHERE m.donation_id IN (3, 4) ORDER BY m.donation_id, m.rank_position;

-- 5. Notifications created for NGOs
SELECT u.email, n.title, n.message, n.is_read
  FROM notifications n JOIN users u ON u.user_id = n.user_id
 ORDER BY n.created_at DESC;

-- 6. FULL LIFECYCLE DEMO for donation 1 (this changes data)
--    a) NGO accepts the best match -> returns delivery_id
SELECT accept_match((SELECT match_id FROM matches WHERE donation_id = 1 AND rank_position = 1));
--    b) Assign nearest volunteer (replace 1 with the delivery_id from above if different)
SELECT assign_nearest_volunteer((SELECT delivery_id FROM deliveries WHERE donation_id = 1));
--    c) Volunteer picks up, then delivers (trigger creates the impact record)
UPDATE deliveries SET status = 'picked_up', picked_up_at = NOW() WHERE donation_id = 1;
UPDATE deliveries SET status = 'delivered', delivered_at = NOW() WHERE donation_id = 1;

-- 7. Audit trail of donation 1
SELECT old_status, new_status, changed_at
  FROM donation_status_history WHERE donation_id = 1 ORDER BY history_id;

-- 8. Landing page counters
SELECT * FROM v_impact_summary;

-- 9. Donor leaderboard and ratings
SELECT * FROM v_donor_leaderboard;
SELECT u.email, r.avg_rating, r.review_count FROM v_user_ratings r JOIN users u USING (user_id);

-- 10. Open donations feed (for the NGO map)
SELECT donation_id, organization_name, total_meals, urgency_level, hours_left FROM v_open_donations ORDER BY hours_left;

-- 11. Expire old donations (run regularly by a backend job)
SELECT expire_old_donations();
