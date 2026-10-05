# 🍽️ BistroBot Kiosk — Mock Restaurant Frontend & Backend

A standalone, zero-dependency mock restaurant ordering kiosk system designed for **NavPro Mini** autonomous robot dining & delivery mission demos.

## ✨ Features
- **Frontend Kiosk UI**:
  - Touch-optimized, modern food ordering interface for robot onboard screens or tablets.
  - Interactive category selector (Starters, Gourmet Burgers, Artisan Pizza, Bowls, Drinks, Desserts).
  - Real-time search by dish name, tag, or description.
  - Cart drawer with quantity controls, subtotal, and tax calculation.
  - One-tap "Place Order (Demo Mode)" without requiring real payments.
  - Order confirmation screen with unique order IDs and estimated preparation times.
  - Top persistent "Close & Continue Mission" button to signal the robot to move to the next waypoint.
- **Backend REST API** (Zero external dependencies — runs on standard Python 3):
  - `GET /api/categories`: Returns categories.
  - `GET /api/menu`: Returns list of food items with prices, tags, and images.
  - `GET /api/menu/search?q=...`: Real-time search query.
  - `POST /api/orders`: Submits new customer orders.
  - `GET /api/orders`: Retrieves placed orders.
  - Serves frontend static files at `http://<host>:5050/`.

## 🚀 How to Run

From this folder or project root:
```bash
./start_mock_restaurant.sh
# Or with a custom port:
./start_mock_restaurant.sh --port 5050
```

The script will output the exact URLs:
```
• Local Frontend UI:   http://localhost:5050
• Network Frontend UI: http://192.168.0.x:5050
• REST API Menu:       http://192.168.0.x:5050/api/menu
• REST API Orders:     http://192.168.0.x:5050/api/orders
```

## 🤖 Using in Mission Planner (`ui_browser` Node)
1. Add a **"Open Web Page (Browser)"** node to your mission graph.
2. Set the URL to `http://<HOST_IP>:5050` (or click the Mock Restaurant preset).
3. The robot drives to the destination waypoint and opens the restaurant menu on screen.
4. The user browses, adds food, places their order, and taps **"Close & Continue"** (or the robot's top Close button).
5. Only then does the robot proceed to its next mission item!
