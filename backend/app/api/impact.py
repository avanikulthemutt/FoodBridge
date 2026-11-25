from fastapi import APIRouter, HTTPException
from ..database import get_connection

router = APIRouter(prefix="/api", tags=["impact"])

@router.get("/impact-summary")
def impact_summary():
    try:
        with get_connection() as conn:
            row = conn.execute("SELECT meals_rescued,partner_donors,ngos_served,tonnes_diverted,co2_saved_kg FROM v_impact_summary").fetchone()
        return {"meals_rescued": int(row[0]), "partner_donors": int(row[1]), "ngos_served": int(row[2]),
                "tonnes_diverted": float(row[3]), "co2_saved_kg": float(row[4])}
    except Exception as exc:
        raise HTTPException(503,"Impact summary is unavailable; apply the database schema and views first") from exc
