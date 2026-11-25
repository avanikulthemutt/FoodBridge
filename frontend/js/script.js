/* FoodBridge front-end script
   1. Mobile menu   2. Scroll reveal   3. Impact counters   4. Live match card */

document.addEventListener("DOMContentLoaded", () => {

  /* ---------- 1. Mobile menu ---------- */
  const menuButton = document.getElementById("menuButton");
  const navigation = document.getElementById("navigation");
  const headerActions = document.querySelector(".header-actions");

  if (menuButton && navigation) {
    const setMenu = (open) => {
      navigation.classList.toggle("active", open);
      headerActions?.classList.toggle("active", open);
      menuButton.setAttribute("aria-expanded", String(open));
    };
    menuButton.addEventListener("click", () => setMenu(!navigation.classList.contains("active")));
    navigation.addEventListener("click", (e) => { if (e.target.closest("a")) setMenu(false); });
    document.addEventListener("click", (e) => {
      const inside = navigation.contains(e.target) || menuButton.contains(e.target) || headerActions?.contains(e.target);
      if (!inside) setMenu(false);
    });
    document.addEventListener("keydown", (e) => { if (e.key === "Escape") setMenu(false); });
  }

  /* ---------- 2. Scroll reveal ---------- */
  const revealObserver = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("visible");
        revealObserver.unobserve(entry.target);
      }
    });
  }, { threshold: 0.15 });
  document.querySelectorAll(".reveal").forEach((el) => revealObserver.observe(el));

  /* ---------- 3. Impact counters (real data only) ---------- */
  // Set these to your backend endpoints. Until then the numbers stay EMPTY.
  //   IMPACT_API_URL should return: { meals_rescued, partner_donors, ngos_served, tonnes_diverted }
  const IMPACT_API_URL = "";   // for example "http://localhost:8000/api/impact-summary"
  const MATCH_API_URL  = "";   // for example "http://localhost:8000/api/live-match"

  const counters = document.querySelectorAll(".stat strong");

  const animateCount = (el, target, decimals = 0) => {
    const start = performance.now();
    const duration = 1600;
    const tick = (now) => {
      const progress = Math.min((now - start) / duration, 1);
      const eased = 1 - Math.pow(1 - progress, 3);
      el.textContent = (target * eased).toLocaleString("en-IN", {
        minimumFractionDigits: decimals, maximumFractionDigits: decimals
      });
      if (progress < 1) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  };

  const fetchJson = async (url) => {
    if (!url) return null;
    try {
      const res = await fetch(url);
      return res.ok ? await res.json() : null;
    } catch (err) {
      console.warn("Backend not reachable:", url);
      return null;
    }
  };

  const impactSection = document.getElementById("impact");
  if (impactSection && counters.length) {
    const impactObserver = new IntersectionObserver(async (entries) => {
      if (!entries[0].isIntersecting) return;
      impactObserver.disconnect();
      const data = await fetchJson(IMPACT_API_URL);
      if (!data) return;                         // no backend data: leave empty
      counters.forEach((el) => {
        const value = Number(data[el.dataset.key]);
        if (Number.isFinite(value)) animateCount(el, value, Number(el.dataset.decimals || 0));
      });
    }, { threshold: 0.3 });
    impactObserver.observe(impactSection);
  }

  /* ---------- 4. Live match card (real data only) ---------- */
  // MATCH_API_URL should return: { donor, ngo, meals, hours, urgency, km }
  const showMatch = (m) => {
    const set = (id, value) => { document.getElementById(id).textContent = value; };
    set("mDonor", m.donor); set("mNgo", m.ngo); set("mMeals", m.meals);
    set("mHours", m.hours); set("mKm", m.km);
    const urgency = document.getElementById("mUrgency");
    urgency.textContent = m.urgency;
    urgency.className = "tag tag-" + String(m.urgency).toLowerCase();
  };

  (async () => {
    const match = await fetchJson(MATCH_API_URL);
    if (match) showMatch(match);
  })();
});
