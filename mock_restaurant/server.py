#!/usr/bin/env python3
"""
Mock Restaurant Menu Server (Frontend + Backend REST API)
Designed for NavPro Mini autonomous robot kiosk demos.
Runs with zero external dependencies (Python 3 standard library).
"""

from __future__ import annotations

import json
import mimetypes
import os
import random
import socket
import sys
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import parse_qs, urlparse

PORT = int(os.environ.get("RESTAURANT_PORT", 5050))
BASE_DIR = Path(__file__).parent.resolve()
FRONTEND_DIR = BASE_DIR / "frontend"

CATEGORIES = [
    {"id": "all", "name": "All Items", "icon": "🍽️"},
    {"id": "starters", "name": "Starters & Bites", "icon": "🥟"},
    {"id": "burgers", "name": "Gourmet Burgers", "icon": "🍔"},
    {"id": "pizza", "name": "Artisan Pizza", "icon": "🍕"},
    {"id": "bowls", "name": "Bowls & Pastas", "icon": "🥗"},
    {"id": "beverages", "name": "Drinks & Shakes", "icon": "🥤"},
    {"id": "desserts", "name": "Desserts", "icon": "🍰"},
]

MENU_ITEMS = [
    # Starters
    {
        "id": "item-101",
        "name": "Crispy Truffle Fries",
        "category": "starters",
        "price": 6.50,
        "description": "Golden hand-cut fries tossed in aromatic white truffle oil, grated parmesan & fresh rosemary.",
        "tags": ["Veg", "Popular"],
        "rating": 4.9,
        "image": "https://images.unsplash.com/photo-1573080496219-bb080dd4f877?w=600&auto=format&fit=crop&q=80",
        "prep_time": "6-8 min",
    },
    {
        "id": "item-102",
        "name": "Buffalo Glazed Cauliflower Wings",
        "category": "starters",
        "price": 8.00,
        "description": "Crunchy tempura cauliflower florets smothered in fiery tangy buffalo sauce with ranch dip.",
        "tags": ["Veg", "Spicy"],
        "rating": 4.8,
        "image": "https://images.unsplash.com/photo-1562967914-608f82629710?w=600&auto=format&fit=crop&q=80",
        "prep_time": "8-10 min",
    },
    {
        "id": "item-103",
        "name": "Garlic Butter Prawns Skewers",
        "category": "starters",
        "price": 10.50,
        "description": "Charred ocean prawns infused with roasted garlic, lemon zest, smoked paprika and herb glaze.",
        "tags": ["Non-Veg", "Chef Special"],
        "rating": 4.9,
        "image": "https://images.unsplash.com/photo-1565680018434-b513d5e5fd47?w=600&auto=format&fit=crop&q=80",
        "prep_time": "10-12 min",
    },

    # Burgers
    {
        "id": "item-201",
        "name": "Classic Robot Smash Cheeseburger",
        "category": "burgers",
        "price": 12.00,
        "description": "Double smashed beef patties, melted aged cheddar, caramelized onions & secret robot relish sauce.",
        "tags": ["Non-Veg", "Bestseller"],
        "rating": 5.0,
        "image": "https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=600&auto=format&fit=crop&q=80",
        "prep_time": "12-14 min",
    },
    {
        "id": "item-202",
        "name": "Smoked BBQ Bacon Crunch Burger",
        "category": "burgers",
        "price": 13.50,
        "description": "Prime beef patty, crispy smoked bacon, crispy onion rings, Monterey Jack & tangy hickory BBQ sauce.",
        "tags": ["Non-Veg"],
        "rating": 4.8,
        "image": "https://images.unsplash.com/photo-1586190848861-99aa4a171e90?w=600&auto=format&fit=crop&q=80",
        "prep_time": "12-15 min",
    },
    {
        "id": "item-203",
        "name": "Avocado Garden Veggie Burger",
        "category": "burgers",
        "price": 11.00,
        "description": "Quinoa & black bean patty with ripe avocado slices, butter lettuce, tomato and vegan garlic aioli.",
        "tags": ["Veg", "Healthy"],
        "rating": 4.7,
        "image": "https://images.unsplash.com/photo-1520072959219-c595dc870360?w=600&auto=format&fit=crop&q=80",
        "prep_time": "10-12 min",
    },

    # Pizza
    {
        "id": "item-301",
        "name": "Rustic Margherita Napoletana",
        "category": "pizza",
        "price": 14.00,
        "description": "San Marzano tomato base, fresh buffalo mozzarella, fragrant sweet basil & cold-pressed EVOO.",
        "tags": ["Veg", "Classic"],
        "rating": 4.9,
        "image": "https://images.unsplash.com/photo-1604382355076-af4b0eb60143?w=600&auto=format&fit=crop&q=80",
        "prep_time": "10-12 min",
    },
    {
        "id": "item-302",
        "name": "Double Pepperoni Hot Honey Pizza",
        "category": "pizza",
        "price": 16.50,
        "description": "Loaded with crispy pepperoni cups, hot chili honey drizzle, fresh mozzarella & oregano.",
        "tags": ["Non-Veg", "Chef Special", "Spicy"],
        "rating": 5.0,
        "image": "https://images.unsplash.com/photo-1628840042765-356cda07504e?w=600&auto=format&fit=crop&q=80",
        "prep_time": "12-14 min",
    },
    {
        "id": "item-303",
        "name": "Wild Mushroom & Truffle Cream Pizza",
        "category": "pizza",
        "price": 15.50,
        "description": "Roasted cremini & shiitake mushrooms, truffle ricotta cream, fontina cheese and fresh thyme.",
        "tags": ["Veg"],
        "rating": 4.8,
        "image": "https://images.unsplash.com/photo-1513104890138-7c749659a591?w=600&auto=format&fit=crop&q=80",
        "prep_time": "12-14 min",
    },

    # Bowls & Pastas
    {
        "id": "item-401",
        "name": "Teriyaki Salmon Power Bowl",
        "category": "bowls",
        "price": 15.00,
        "description": "Glazed Atlantic salmon fillet, seasoned jasmine rice, edamame, pickled cucumber & sesame crunch.",
        "tags": ["Non-Veg", "Healthy"],
        "rating": 4.9,
        "image": "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=600&auto=format&fit=crop&q=80",
        "prep_time": "10-12 min",
    },
    {
        "id": "item-402",
        "name": "Creamy Tuscan Chicken Rigatoni",
        "category": "bowls",
        "price": 14.50,
        "description": "Bronze-cut rigatoni pasta in a velvety sun-dried tomato garlic sauce with grilled chicken strips.",
        "tags": ["Non-Veg"],
        "rating": 4.8,
        "image": "https://images.unsplash.com/photo-1621996346565-e3d5d6281788?w=600&auto=format&fit=crop&q=80",
        "prep_time": "12-15 min",
    },
    {
        "id": "item-403",
        "name": "Mediterranean Falafel Hummus Bowl",
        "category": "bowls",
        "price": 11.50,
        "description": "Crisp herb falafels, silky roasted garlic hummus, kalamata olives, cherry tomatoes & warm pita.",
        "tags": ["Veg", "Vegan"],
        "rating": 4.7,
        "image": "https://images.unsplash.com/photo-1540420773420-3366772f4999?w=600&auto=format&fit=crop&q=80",
        "prep_time": "8-10 min",
    },

    # Beverages
    {
        "id": "item-501",
        "name": "Iced Berry Hibiscus Cooler",
        "category": "beverages",
        "price": 4.50,
        "description": "Brewed ruby hibiscus flowers, muddled raspberries, fresh mint leaves and sparkling soda.",
        "tags": ["Veg", "Refreshing"],
        "rating": 4.8,
        "image": "https://images.unsplash.com/photo-1513558161293-cdaf765ed2fd?w=600&auto=format&fit=crop&q=80",
        "prep_time": "3-5 min",
    },
    {
        "id": "item-502",
        "name": "Belgian Chocolate Shake",
        "category": "beverages",
        "price": 6.00,
        "description": "Decadent dark chocolate gelato blended with fresh milk, chocolate shavings & whipped cream.",
        "tags": ["Veg", "Sweet"],
        "rating": 4.9,
        "image": "https://images.unsplash.com/photo-1572490122747-3968b75cc699?w=600&auto=format&fit=crop&q=80",
        "prep_time": "4-6 min",
    },
    {
        "id": "item-503",
        "name": "Matcha Vanilla Cold Foam Latte",
        "category": "beverages",
        "price": 5.50,
        "description": "Ceremonial grade Uji matcha layered over almond milk with silky vanilla cold foam.",
        "tags": ["Veg"],
        "rating": 4.7,
        "image": "https://images.unsplash.com/photo-1536256263959-770b48d82b0a?w=600&auto=format&fit=crop&q=80",
        "prep_time": "3-5 min",
    },

    # Desserts
    {
        "id": "item-601",
        "name": "Warm Molten Lava Chocolate Cake",
        "category": "desserts",
        "price": 7.50,
        "description": "Rich cocoa sponge with an oozing liquid chocolate center, served with Madagascar vanilla gelato.",
        "tags": ["Veg", "Bestseller"],
        "rating": 5.0,
        "image": "https://images.unsplash.com/photo-1606313564200-e75d5e30476c?w=600&auto=format&fit=crop&q=80",
        "prep_time": "6-8 min",
    },
    {
        "id": "item-602",
        "name": "Classic New York Blueberry Cheesecake",
        "category": "desserts",
        "price": 7.00,
        "description": "Dense and velvety cream cheese on a buttery graham crust topped with wild blueberry compote.",
        "tags": ["Veg"],
        "rating": 4.9,
        "image": "https://images.unsplash.com/photo-1533134242443-d4fd215305ad?w=600&auto=format&fit=crop&q=80",
        "prep_time": "2-4 min",
    },
]

# In-memory orders store
ORDERS = []


def get_local_ip() -> str:
    """Detect LAN IP address."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
    except Exception:
        ip = "127.0.0.1"
    finally:
        s.close()
    return ip


class RestaurantHandler(BaseHTTPRequestHandler):
    """Handles REST API and static file serving for the Restaurant Kiosk."""

    def _send_cors_headers(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")

    def _send_json(self, data: any, status: int = 200) -> None:
        payload = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self._send_cors_headers()
        self.end_headers()
        self.wfile.write(payload)

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self._send_cors_headers()
        self.end_headers()

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)

        # REST API endpoints
        if path == "/api/categories":
            return self._send_json({"ok": True, "categories": CATEGORIES})

        if path == "/api/menu":
            category = query.get("category", ["all"])[0]
            if category and category != "all":
                filtered = [i for i in MENU_ITEMS if i["category"] == category]
            else:
                filtered = MENU_ITEMS
            return self._send_json({"ok": True, "count": len(filtered), "items": filtered})

        if path == "/api/menu/search":
            q = query.get("q", [""])[0].strip().lower()
            if not q:
                return self._send_json({"ok": True, "count": len(MENU_ITEMS), "items": MENU_ITEMS})
            results = [
                i for i in MENU_ITEMS
                if q in i["name"].lower()
                or q in i["description"].lower()
                or any(q in t.lower() for t in i["tags"])
                or q in i["category"].lower()
            ]
            return self._send_json({"ok": True, "query": q, "count": len(results), "items": results})

        if path == "/api/orders":
            return self._send_json({"ok": True, "count": len(ORDERS), "orders": ORDERS})

        # Static files serving
        if path in ("/", "/index.html"):
            target_file = FRONTEND_DIR / "index.html"
        else:
            rel_path = path.lstrip("/")
            target_file = FRONTEND_DIR / rel_path

        if target_file.exists() and target_file.is_file():
            mime_type, _ = mimetypes.guess_type(str(target_file))
            if not mime_type:
                mime_type = "application/octet-stream"
            with open(target_file, "rb") as f:
                content = f.read()

            self.send_response(200)
            self.send_header("Content-Type", f"{mime_type}; charset=utf-8" if "text" in mime_type or "javascript" in mime_type else mime_type)
            self.send_header("Content-Length", str(len(content)))
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(content)
            return

        # 404
        self._send_json({"error": "not_found", "message": f"Resource '{path}' not found"}, status=404)

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/api/orders":
            content_len = int(self.headers.get("Content-Length", 0))
            if content_len == 0:
                return self._send_json({"error": "bad_request", "message": "No order body provided"}, status=400)

            try:
                body = self.rfile.read(content_len).decode("utf-8")
                req_data = json.loads(body)
            except Exception as e:
                return self._send_json({"error": "bad_request", "message": f"Invalid JSON: {e}"}, status=400)

            items = req_data.get("items", [])
            if not items:
                return self._send_json({"error": "bad_request", "message": "Order must contain at least one item"}, status=400)

            order_id = f"ROBOT-{random.randint(1000, 9999)}"
            table_no = req_data.get("table_number", "Table 4 (Robot Station)")
            customer = req_data.get("customer_name", "Robot Demo Guest")
            total = sum(float(item.get("price", 0)) * int(item.get("quantity", 1)) for item in items)

            order = {
                "order_id": order_id,
                "created_at": time.time(),
                "created_at_iso": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime()),
                "status": "Confirmed & Kitchen Preparing",
                "table": table_no,
                "customer": customer,
                "items": items,
                "total_amount": round(total, 2),
                "currency": "$",
                "estimated_prep_minutes": random.randint(10, 15),
                "demo_mode": "No payment needed (Robot Demo)",
            }

            ORDERS.insert(0, order)
            return self._send_json({
                "ok": True,
                "message": f"Order #{order_id} placed successfully! Robot can proceed to next stop.",
                "order": order,
            }, status=201)

        self._send_json({"error": "not_found", "message": f"Endpoint '{path}' not found"}, status=404)

    def log_message(self, format: str, *args: any) -> None:
        # Subtle console logging
        sys.stderr.write(f"[MockRestaurant] {self.address_string()} - {args[0]} {args[1]}\n")


def run() -> None:
    host = "0.0.0.0"
    server = HTTPServer((host, PORT), RestaurantHandler)
    local_ip = get_local_ip()

    print("\n" + "=" * 65)
    print(" 🍽️  NAVPRO MINI MOCK RESTAURANT KIOSK SERVER IS RUNNING!")
    print("=" * 65)
    print(f" • Local Frontend UI:   http://localhost:{PORT}")
    print(f" • Network Frontend UI: http://{local_ip}:{PORT}")
    print(f" • REST API Menu:       http://{local_ip}:{PORT}/api/menu")
    print(f" • REST API Orders:     http://{local_ip}:{PORT}/api/orders")
    print("-" * 65)
    print(f" 👉 In Mission Planner 'ui_browser' node, set URL to:")
    print(f"    http://{local_ip}:{PORT}  (or http://localhost:{PORT})")
    print("=" * 65 + "\n")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[MockRestaurant] Stopping server...")
        server.server_close()


if __name__ == "__main__":
    run()
