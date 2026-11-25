# FoodBridge Front-end

Open `index.html` in a browser (or use the VS Code "Live Server" extension).

- `index.html`    page structure and all content sections
- `css/style.css` styles (tokens, layout, animations, responsive, reduced motion)
- `js/script.js`  mobile menu, scroll reveal, impact counters, live match card

To show real numbers, set `API_URL` in `js/script.js` to your backend endpoint
(for example `http://localhost:8000/api/impact-summary`) that returns:
`{ "meals_rescued": 0, "partner_donors": 0, "ngos_served": 0, "tonnes_diverted": 0 }`
Button links (login.html, donate.html, register.html ...) are placeholders for the pages you build next.
