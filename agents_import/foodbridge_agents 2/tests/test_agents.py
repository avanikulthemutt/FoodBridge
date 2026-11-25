from sqlalchemy import text

from app.agents import freshness_agent, llm, matching_agent, notification_agent, orchestrator, pickup_agent
from app.services.db_calls import accept_match


def one(db, sql, **p):
    return db.execute(text(sql), p).scalar()


def actions(db, agent, action=None):
    return db.execute(text("SELECT COUNT(*) FROM agent_actions WHERE agent = :a AND (CAST(:x AS TEXT) IS NULL OR action = :x)"),
                      {"a": agent, "x": action}).scalar_one()


def test_cycle_runs_clean_and_is_idempotent(fresh_db):
    r1 = orchestrator.run_cycle("test")
    assert r1["errors"] == {}, r1
    assert actions(fresh_db, "matching", "explain") >= 1           # every live offer set explained
    n1 = one(fresh_db, "SELECT COUNT(*) FROM notifications")
    a1 = one(fresh_db, "SELECT COUNT(*) FROM agent_actions")
    r2 = orchestrator.run_cycle("test")
    assert r2["errors"] == {}
    fresh_db.rollback()
    assert one(fresh_db, "SELECT COUNT(*) FROM notifications") == n1  # no duplicate notifications
    assert one(fresh_db, "SELECT COUNT(*) FROM agent_actions") == a1


def test_shelf_life_expires_unsafe_food(fresh_db):
    # donation 1 is cooked food (4 h shelf life): pretend it was cooked 6 h ago but donor expiry is later
    fresh_db.execute(text("UPDATE donations SET prepared_at = NOW() - INTERVAL '6 hours', "
                          "expiry_at = NOW() + INTERVAL '2 hours', pickup_start = NOW() - INTERVAL '5 hours', "
                          "pickup_end = NOW() + INTERVAL '1 hour' WHERE donation_id = 1"))
    fresh_db.commit()
    freshness_agent.sweep(fresh_db); fresh_db.commit()
    assert one(fresh_db, "SELECT status FROM donations WHERE donation_id = 1") == "expired"
    assert one(fresh_db, "SELECT COUNT(*) FROM matches WHERE donation_id = 1 AND status IN ('notified','suggested')") == 0
    assert one(fresh_db, "SELECT COUNT(*) FROM notifications WHERE related_donation_id = 1 "
                         "AND notification_type = 'donation_expiring'") == 1


def test_urgency_only_escalates(fresh_db):
    fresh_db.execute(text("UPDATE donations SET expiry_at = NOW() + INTERVAL '50 minutes', "
                          "pickup_start = NOW() - INTERVAL '5 minutes', pickup_end = NOW() + INTERVAL '40 minutes', prepared_at = NOW() - INTERVAL '10 minutes' "
                          "WHERE donation_id = 3"))
    fresh_db.commit()
    freshness_agent.sweep(fresh_db); fresh_db.commit()
    assert one(fresh_db, "SELECT urgency_level FROM donations WHERE donation_id = 3") == "critical"
    # a donation with plenty of time must NOT be downgraded
    assert one(fresh_db, "SELECT urgency_level FROM donations WHERE donation_id = 4") == "critical"


def test_pickup_prefers_vehicle_that_fits_and_reassigns_noshow(fresh_db):
    fresh_db.execute(text("UPDATE volunteers SET current_latitude = 12.9719, current_longitude = 77.6412"))
    fresh_db.commit()
    matching_agent.sweep(fresh_db); fresh_db.commit()   # seed only pre-matched 1 and 2; agent matches 3 and 4
    mid = one(fresh_db, "SELECT match_id FROM matches WHERE donation_id = 4 AND status = 'notified' LIMIT 1")
    delivery_id = accept_match(fresh_db, mid); fresh_db.commit()
    vid = pickup_agent.assign(fresh_db, delivery_id); fresh_db.commit()
    # 340 meals fits no vehicle; the car (Priya, id 2) is the least undersized
    assert vid == 2
    assert one(fresh_db, "SELECT status FROM deliveries WHERE delivery_id = :d", d=delivery_id) == "assigned"
    otp = one(fresh_db, "SELECT pickup_otp FROM deliveries WHERE delivery_id = :d", d=delivery_id)
    assert one(fresh_db, "SELECT COUNT(*) FROM notifications WHERE message LIKE :p", p=f"%OTP {otp}%") == 1  # only the donor sees the code

    # volunteer never starts -> released and given to someone else
    fresh_db.execute(text("UPDATE deliveries SET assigned_at = NOW() - INTERVAL '30 minutes' WHERE delivery_id = :d"),
                     {"d": delivery_id}); fresh_db.commit()
    pickup_agent.sweep(fresh_db); fresh_db.commit()
    assert actions(fresh_db, "pickup", "noshow_release") == 1
    new_vid = one(fresh_db, "SELECT volunteer_id FROM deliveries WHERE delivery_id = :d", d=delivery_id)
    assert new_vid not in (None, 2)


def test_no_volunteer_alerts_ngo_once(fresh_db):
    fresh_db.execute(text("UPDATE volunteers SET is_available = FALSE"))
    mid = one(fresh_db, "SELECT match_id FROM matches WHERE donation_id = 1 AND status = 'notified' LIMIT 1")
    did = accept_match(fresh_db, mid)
    fresh_db.execute(text("UPDATE deliveries SET created_at = NOW() - INTERVAL '20 minutes' WHERE delivery_id = :d"), {"d": did})
    fresh_db.commit()
    pickup_agent.sweep(fresh_db); pickup_agent.sweep(fresh_db); fresh_db.commit()
    assert one(fresh_db, "SELECT COUNT(*) FROM notifications WHERE title = 'No volunteer available yet'") == 1


def test_silent_ngos_trigger_widening_and_giveup(fresh_db):
    fresh_db.execute(text("UPDATE matches SET notified_at = NOW() - INTERVAL '30 minutes' WHERE donation_id = 1 AND status = 'notified'"))
    fresh_db.commit()
    matching_agent.sweep(fresh_db); fresh_db.commit()
    assert actions(fresh_db, "matching", "widen") >= 1
    assert one(fresh_db, "SELECT COUNT(*) FROM matches WHERE donation_id = 1 AND status = 'expired'") >= 1


def test_reminders_and_delivery_messages(fresh_db):
    matching_agent.sweep(fresh_db); fresh_db.commit()
    fresh_db.execute(text("UPDATE matches SET notified_at = NOW() - INTERVAL '10 minutes' WHERE donation_id = 4 AND status = 'notified'"))
    fresh_db.commit()
    notification_agent.sweep(fresh_db); fresh_db.commit()
    assert one(fresh_db, "SELECT COUNT(*) FROM notifications WHERE title = 'Food is still waiting for you'") >= 1
    assert one(fresh_db, "SELECT COUNT(*) FROM notifications WHERE notification_type = 'delivery_done'") >= 2  # seed delivery


def test_llm_output_is_validated(fresh_db, monkeypatch):
    monkeypatch.setattr(llm, "enabled", lambda: True)
    live = matching_agent._live_matches(fresh_db, 1)
    ids = [m["match_id"] for m in live]
    # a hallucinated id must be ignored and fall back to the SQL ranking
    monkeypatch.setattr(llm, "ask_json", lambda *a, **k: {"recommended_match_id": 99999, "reasons": {}})
    matching_agent.explain(fresh_db, 1); fresh_db.commit()
    row = fresh_db.execute(text("SELECT used_llm, detail FROM agent_actions WHERE action = 'explain' AND donation_id = 1")).first()
    assert row[0] is False and row[1]["recommended_match_id"] == ids[0]
    # a valid answer is accepted
    fresh_db.execute(text("DELETE FROM agent_actions WHERE action = 'explain'")); fresh_db.commit()
    pick = ids[-1]
    monkeypatch.setattr(llm, "ask_json", lambda *a, **k: {"recommended_match_id": pick, "reasons": {str(pick): "Has a fridge"}})
    matching_agent.explain(fresh_db, 1); fresh_db.commit()
    row = fresh_db.execute(text("SELECT used_llm, detail FROM agent_actions WHERE action = 'explain' AND donation_id = 1")).first()
    assert row[0] is True and row[1]["recommended_match_id"] == pick
