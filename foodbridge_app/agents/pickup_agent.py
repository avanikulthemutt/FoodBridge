"""Pickup agent: gets accepted food from donor to NGO.
  * picks a volunteer by ETA + vehicle fit (not just straight-line distance)
  * tells donor (with the pickup OTP), NGO and volunteer
  * releases and reassigns volunteers who never start the pickup (no-show)
  * if nobody is free, alerts the NGO (self-pickup when it has transport) and the admins"""
import logging

from sqlalchemy import text
from sqlalchemy.orm import Session

from ..config import settings
from .base import log_action
from .notification_agent import notify, notify_admins

logger = logging.getLogger("foodbridge.agents.pickup")

# Tunable assumptions: average km/h and a rough meals-per-trip capacity per vehicle.
VEHICLES = {
    "none":    {"speed": 5,  "max_meals": 20},
    "bicycle": {"speed": 12, "max_meals": 30},
    "bike":    {"speed": 25, "max_meals": 60},
    "car":     {"speed": 25, "max_meals": 200},
    "van":     {"speed": 22, "max_meals": 1000},
}
UNDERSIZED_PENALTY_MIN = 1000  # scaled by how short the vehicle falls: bigger vehicle wins when nothing fits


def _rank(c: dict, meals: int) -> tuple[float, float, bool]:
    v = VEHICLES.get(c["vehicle_type"], VEHICLES["none"])
    eta = float(c["dist"]) / v["speed"] * 60
    undersized = v["max_meals"] < meals
    penalty = UNDERSIZED_PENALTY_MIN * (1 - v["max_meals"] / meals) if undersized else 0
    return eta + penalty, eta, undersized


def assign(db: Session, delivery_id: int, exclude: tuple[int, ...] = ()) -> int | None:
    """Assign the best available volunteer. Returns volunteer_id or None."""
    d = db.execute(text("""
        SELECT dl.delivery_id, dl.donation_id, dl.pickup_otp, d.title, d.total_meals, d.pickup_end,
               dr.user_id AS donor_uid, dr.organization_name, n.user_id AS ngo_uid, n.ngo_name,
               pa.latitude AS plat, pa.longitude AS plng,
               haversine_km(pa.latitude, pa.longitude, na.latitude, na.longitude) AS leg_km
          FROM deliveries dl
          JOIN donations d  ON d.donation_id = dl.donation_id
          JOIN donors dr    ON dr.donor_id = d.donor_id
          JOIN addresses pa ON pa.address_id = d.pickup_address_id
          JOIN matches m    ON m.match_id = dl.match_id
          JOIN ngos n       ON n.ngo_id = m.ngo_id
          JOIN addresses na ON na.address_id = n.address_id
         WHERE dl.delivery_id = :d AND dl.volunteer_id IS NULL
           AND dl.status = 'pending_assignment'"""), {"d": delivery_id}).mappings().first()
    if not d:
        return None

    cands = [dict(c) for c in db.execute(text("""
        SELECT v.volunteer_id, v.user_id, v.full_name, v.vehicle_type,
               haversine_km(:lat, :lng, v.current_latitude, v.current_longitude) AS dist
          FROM volunteers v JOIN users u ON u.user_id = v.user_id AND u.is_active
         WHERE v.is_available AND v.verification_status = 'verified'
           AND v.current_latitude IS NOT NULL
           AND haversine_km(:lat, :lng, v.current_latitude, v.current_longitude) <= v.service_radius_km
           AND v.volunteer_id <> ALL(CAST(:ex AS BIGINT[]))
           FOR UPDATE OF v SKIP LOCKED"""),
        {"lat": d["plat"], "lng": d["plng"], "ex": list(exclude)}).mappings().all()]
    if not cands:
        return None

    best = min(cands, key=lambda c: _rank(c, d["total_meals"])[0])
    _, eta, undersized = _rank(best, d["total_meals"])

    updated = db.execute(text("""
        UPDATE deliveries SET volunteer_id = :v, status = 'assigned', assigned_at = NOW(),
                              route_distance_km = :leg
         WHERE delivery_id = :d AND volunteer_id IS NULL"""),
        {"v": best["volunteer_id"], "leg": d["leg_km"], "d": delivery_id}).rowcount
    if not updated:
        return None
    db.execute(text("UPDATE volunteers SET is_available = FALSE WHERE volunteer_id = :v"),
               {"v": best["volunteer_id"]})

    did = d["donation_id"]
    log_action(db, "pickup", "assign_volunteer", donation_id=did, delivery_id=delivery_id,
               detail={"volunteer_id": best["volunteer_id"], "dist_km": best["dist"],
                       "eta_min": round(eta), "vehicle": best["vehicle_type"],
                       "undersized_vehicle": undersized, "candidates": len(cands)})
    notify(db, best["user_id"], "volunteer_assigned", "New pickup assigned",
           f"Collect {d['total_meals']} meals from {d['organization_name']} and deliver to "
           f"{d['ngo_name']} ({d['leg_km']} km trip). Ask the donor for the pickup OTP.",
           donation_id=did)
    notify(db, d["donor_uid"], "volunteer_assigned", "Volunteer on the way",
           f"{best['full_name']} ({best['vehicle_type']}) will reach you in about {round(eta)} min. "
           f"Share pickup OTP {d['pickup_otp']} when they arrive.",
           donation_id=did, dedupe_key=f"assigned:donor:{delivery_id}:{best['volunteer_id']}")
    notify(db, d["ngo_uid"], "volunteer_assigned", "Volunteer assigned",
           f"{best['full_name']} is collecting the food for you.",
           donation_id=did, dedupe_key=f"assigned:ngo:{delivery_id}:{best['volunteer_id']}")
    if undersized:
        notify_admins(db, "Undersized vehicle assigned",
                      f"Delivery {delivery_id} ({d['total_meals']} meals) went to a {best['vehicle_type']}: "
                      "no larger vehicle was available.", donation_id=did,
                      dedupe_key=f"undersized:{delivery_id}")
    return best["volunteer_id"]


def sweep(db: Session) -> int:
    acted = 0

    # 1) Release volunteers who accepted but never started
    for r in db.execute(text("""
        SELECT dl.delivery_id, dl.donation_id, dl.volunteer_id, v.user_id AS vol_uid, d.title
          FROM deliveries dl
          JOIN volunteers v ON v.volunteer_id = dl.volunteer_id
          JOIN donations d  ON d.donation_id = dl.donation_id
         WHERE dl.status = 'assigned'
           AND dl.assigned_at < NOW() - make_interval(mins => :m)"""),
            {"m": settings.PICKUP_NOSHOW_MINS}).mappings().all():
        db.execute(text("""UPDATE deliveries SET volunteer_id = NULL, status = 'pending_assignment',
                                  assigned_at = NULL
                            WHERE delivery_id = :d AND status = 'assigned'"""), {"d": r["delivery_id"]})
        log_action(db, "pickup", "noshow_release", donation_id=r["donation_id"],
                   delivery_id=r["delivery_id"], detail={"volunteer_id": r["volunteer_id"]})
        notify(db, r["vol_uid"], "volunteer_assigned", "Pickup reassigned",
               f"'{r['title']}' was given to someone else because it was not started in time. "
               "Share your location again to receive new pickups.",
               donation_id=r["donation_id"])
        acted += 1

    # 2) Try to staff every delivery that has no volunteer
    pending = db.execute(text("""
        SELECT dl.delivery_id, dl.donation_id, d.title, d.total_meals,
               n.user_id AS ngo_uid, COALESCE(p.has_own_transport, FALSE) AS own_transport,
               dl.created_at < NOW() - make_interval(mins => :m) AS overdue
          FROM deliveries dl
          JOIN donations d ON d.donation_id = dl.donation_id
          JOIN matches m   ON m.match_id = dl.match_id
          JOIN ngos n      ON n.ngo_id = m.ngo_id
          LEFT JOIN ngo_preferences p ON p.ngo_id = n.ngo_id
         WHERE dl.status = 'pending_assignment' AND dl.volunteer_id IS NULL
           AND d.status = 'accepted'"""), {"m": settings.NO_VOLUNTEER_ALERT_MINS}).mappings().all()
    for r in pending:
        ex = tuple(int(x[0]) for x in db.execute(text(
            "SELECT detail->>'volunteer_id' FROM agent_actions WHERE agent = 'pickup' "
            "AND action = 'noshow_release' AND delivery_id = :d"), {"d": r["delivery_id"]}).all() if x[0])
        if assign(db, r["delivery_id"], ex):
            acted += 1
        elif r["overdue"]:
            msg = (f"No volunteer is free for '{r['title']}' ({r['total_meals']} meals). "
                   + ("Since you have your own transport, please collect it yourself if you can."
                      if r["own_transport"] else "We are still searching."))
            if notify(db, r["ngo_uid"], "volunteer_assigned", "No volunteer available yet", msg,
                      donation_id=r["donation_id"], dedupe_key=f"novol:{r['delivery_id']}"):
                notify_admins(db, "Delivery needs a volunteer",
                              f"Delivery {r['delivery_id']} has had no volunteer for "
                              f"{settings.NO_VOLUNTEER_ALERT_MINS}+ min.", donation_id=r["donation_id"],
                              dedupe_key=f"novol_admin:{r['delivery_id']}")
                log_action(db, "pickup", "no_volunteer", donation_id=r["donation_id"],
                           delivery_id=r["delivery_id"], detail={"own_transport": r["own_transport"]})
                acted += 1
    return acted
