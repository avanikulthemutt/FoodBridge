"""FoodBridge AI agents: matching, freshness, notification, pickup.
The DB keeps the hard rules (scoring, OTPs, constraints). Agents watch the data,
decide what should happen next, act through safe SQL, and log every decision.
"""
