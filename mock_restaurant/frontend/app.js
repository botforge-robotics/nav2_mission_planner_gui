/**
 * BistroBot Kiosk Interactive App Logic
 * Seamlessly pairs with NavPro Mini Mission Planner 'ui_browser' node.
 */

// State
let categories = [];
let menuItems = [];
let activeCategory = 'all';
let searchQuery = '';
let cart = {}; // { itemId: { item, quantity } }

// DOM Elements
const categoriesBar = document.getElementById('categoriesBar');
const menuGrid = document.getElementById('menuGrid');
const activeCategoryTitle = document.getElementById('activeCategoryTitle');
const resultsCount = document.getElementById('resultsCount');
const searchInput = document.getElementById('searchInput');
const clearSearch = document.getElementById('clearSearch');

// Cart DOM
const openCartBtn = document.getElementById('openCartBtn');
const cartDrawer = document.getElementById('cartDrawer');
const cartBackdrop = document.getElementById('cartBackdrop');
const closeCartDrawerBtn = document.getElementById('closeCartDrawerBtn');
const cartItemsList = document.getElementById('cartItemsList');
const cartCountBadge = document.getElementById('cartCountBadge');
const cartTotalSummary = document.getElementById('cartTotalSummary');
const cartSubtotal = document.getElementById('cartSubtotal');
const cartTax = document.getElementById('cartTax');
const cartGrandTotal = document.getElementById('cartGrandTotal');
const placeOrderBtn = document.getElementById('placeOrderBtn');

// Order Modal DOM
const orderSuccessModal = document.getElementById('orderSuccessModal');
const confirmedOrderId = document.getElementById('confirmedOrderId');
const confirmedEstTime = document.getElementById('confirmedEstTime');
const orderedItemsPreview = document.getElementById('orderedItemsPreview');
const finishOrderAndContinueBtn = document.getElementById('finishOrderAndContinueBtn');
const closeModalOnlyBtn = document.getElementById('closeModalOnlyBtn');
const missionCloseBtn = document.getElementById('missionCloseBtn');

// -------------------------------------------------------------
// Initialization
// -------------------------------------------------------------
async function init() {
  await fetchCategories();
  await fetchMenu();
  setupEventListeners();
}

// -------------------------------------------------------------
// Fetch APIs
// -------------------------------------------------------------
async function fetchCategories() {
  try {
    const res = await fetch('/api/categories');
    const data = await res.json();
    if (data.ok) {
      categories = data.categories;
      renderCategories();
    }
  } catch (err) {
    console.error('Failed to load categories:', err);
  }
}

async function fetchMenu() {
  try {
    const res = await fetch('/api/menu');
    const data = await res.json();
    if (data.ok) {
      menuItems = data.items;
      renderMenu();
    }
  } catch (err) {
    console.error('Failed to load menu items:', err);
    menuGrid.innerHTML = `
      <div class="empty-state">
        <p>⚠️ Failed to load menu items from backend server.</p>
      </div>`;
  }
}

// -------------------------------------------------------------
// Render Categories
// -------------------------------------------------------------
function renderCategories() {
  categoriesBar.innerHTML = categories.map(cat => `
    <button class="category-chip ${cat.id === activeCategory ? 'active' : ''}" data-cat="${cat.id}">
      <span>${cat.icon}</span>
      <span>${cat.name}</span>
    </button>
  `).join('');

  categoriesBar.querySelectorAll('.category-chip').forEach(btn => {
    btn.addEventListener('click', () => {
      activeCategory = btn.getAttribute('data-cat');
      renderCategories();
      renderMenu();
    });
  });
}

// -------------------------------------------------------------
// Render Menu Items
// -------------------------------------------------------------
function renderMenu() {
  let filtered = menuItems;

  // Filter by category
  if (activeCategory !== 'all') {
    filtered = filtered.filter(item => item.category === activeCategory);
  }

  // Filter by search query
  if (searchQuery.trim()) {
    const q = searchQuery.toLowerCase();
    filtered = filtered.filter(item =>
      item.name.toLowerCase().includes(q) ||
      item.description.toLowerCase().includes(q) ||
      item.tags.some(t => t.toLowerCase().includes(q))
    );
  }

  // Update header text
  const currentCatObj = categories.find(c => c.id === activeCategory);
  activeCategoryTitle.textContent = searchQuery ? `Search: "${searchQuery}"` : (currentCatObj?.name || 'All Specialties');
  resultsCount.textContent = `${filtered.length} delicious item${filtered.length === 1 ? '' : 's'}`;

  if (filtered.length === 0) {
    menuGrid.innerHTML = `
      <div class="empty-state">
        <p>🍽️ No dishes found matching your selection.</p>
        <button onclick="clearFilter()" style="margin-top:12px; padding:8px 16px; background:var(--bg-surface-elevated); border:1px solid var(--border); color:#FFF; border-radius:8px; cursor:pointer;">
          Clear Filters
        </button>
      </div>`;
    return;
  }

  menuGrid.innerHTML = filtered.map(item => {
    const inCartQty = cart[item.id] ? cart[item.id].quantity : 0;
    const tagHtml = item.tags.map(t => {
      const cls = t.toLowerCase().replace(/[\s-]/g, '-');
      return `<span class="food-tag tag-${cls}">${t}</span>`;
    }).join('');

    return `
      <div class="food-card" data-id="${item.id}">
        <div class="food-image-wrap">
          <img src="${item.image}" alt="${item.name}" class="food-image" loading="lazy" onerror="this.onerror=null; this.src='https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=600';">
          <div class="food-tags">${tagHtml}</div>
          <span class="prep-badge">⏱ ${item.prep_time}</span>
        </div>
        <div class="food-details">
          <div class="food-title-row">
            <h3 class="food-name">${item.name}</h3>
            <span class="food-rating">★ ${item.rating.toFixed(1)}</span>
          </div>
          <p class="food-desc">${item.description}</p>
          <div class="food-action-row">
            <span class="food-price">$${item.price.toFixed(2)}</span>
            ${inCartQty > 0 ? `
              <div class="qty-controls">
                <button class="qty-btn" onclick="decrementCart('${item.id}')">−</button>
                <span class="qty-val">${inCartQty}</span>
                <button class="qty-btn" onclick="incrementCart('${item.id}')">+</button>
              </div>
            ` : `
              <button class="add-btn" onclick="addToCart('${item.id}')">
                <span>+ Add</span>
              </button>
            `}
          </div>
        </div>
      </div>
    `;
  }).join('');
}

window.clearFilter = function() {
  activeCategory = 'all';
  searchQuery = '';
  searchInput.value = '';
  clearSearch.style.display = 'none';
  renderCategories();
  renderMenu();
};

// -------------------------------------------------------------
// Cart Management
// -------------------------------------------------------------
window.addToCart = function(itemId) {
  const item = menuItems.find(i => i.id === itemId);
  if (!item) return;

  if (cart[itemId]) {
    cart[itemId].quantity += 1;
  } else {
    cart[itemId] = { item, quantity: 1 };
  }
  updateCartUI();
  renderMenu();
};

window.incrementCart = function(itemId) {
  if (cart[itemId]) {
    cart[itemId].quantity += 1;
    updateCartUI();
    renderMenu();
  }
};

window.decrementCart = function(itemId) {
  if (cart[itemId]) {
    cart[itemId].quantity -= 1;
    if (cart[itemId].quantity <= 0) {
      delete cart[itemId];
    }
    updateCartUI();
    renderMenu();
  }
};

function updateCartUI() {
  const items = Object.values(cart);
  const totalCount = items.reduce((sum, entry) => sum + entry.quantity, 0);
  const subtotal = items.reduce((sum, entry) => sum + (entry.item.price * entry.quantity), 0);
  const tax = subtotal * 0.05;
  const grandTotal = subtotal + tax;

  // Header summary
  cartCountBadge.textContent = totalCount;
  cartTotalSummary.textContent = `$${grandTotal.toFixed(2)}`;

  // Drawer totals
  cartSubtotal.textContent = `$${subtotal.toFixed(2)}`;
  cartTax.textContent = `$${tax.toFixed(2)}`;
  cartGrandTotal.textContent = `$${grandTotal.toFixed(2)}`;
  placeOrderBtn.disabled = totalCount === 0;

  // Drawer items list
  if (items.length === 0) {
    cartItemsList.innerHTML = `
      <div style="text-align:center; padding:40px 10px; color:var(--text-muted);">
        <p style="font-size:32px; margin-bottom:10px;">🛒</p>
        <p style="font-size:14px; font-weight:600;">Your cart is empty</p>
        <p style="font-size:12px; margin-top:4px;">Tap "+ Add" on any gourmet item to begin</p>
      </div>`;
    return;
  }

  cartItemsList.innerHTML = items.map(({ item, quantity }) => `
    <div class="cart-item-card">
      <img src="${item.image}" alt="${item.name}" class="cart-item-thumb">
      <div class="cart-item-info">
        <h4 class="cart-item-name">${item.name}</h4>
        <div class="cart-item-price">$${(item.price * quantity).toFixed(2)} ($${item.price.toFixed(2)} ea)</div>
      </div>
      <div class="qty-controls">
        <button class="qty-btn" onclick="decrementCart('${item.id}')">−</button>
        <span class="qty-val">${quantity}</span>
        <button class="qty-btn" onclick="incrementCart('${item.id}')">+</button>
      </div>
    </div>
  `).join('');
}

function openCart() {
  cartDrawer.classList.add('open');
  cartBackdrop.classList.add('open');
}

function closeCart() {
  cartDrawer.classList.remove('open');
  cartBackdrop.classList.remove('open');
}

// -------------------------------------------------------------
// Place Order
// -------------------------------------------------------------
async function placeOrder() {
  const items = Object.values(cart).map(({ item, quantity }) => ({
    id: item.id,
    name: item.name,
    price: item.price,
    quantity: quantity,
  }));

  if (items.length === 0) return;

  placeOrderBtn.disabled = true;
  placeOrderBtn.innerHTML = `<span>Sending Order to Kitchen...</span>`;

  try {
    const res = await fetch('/api/orders', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        table_number: 'Table 4 (Robot Kiosk)',
        customer_name: 'Robot Guest',
        items: items,
      }),
    });

    const data = await res.json();
    if (data.ok && data.order) {
      // Clear cart
      const placedOrder = data.order;
      cart = {};
      updateCartUI();
      renderMenu();
      closeCart();

      // Show Order Success Modal
      confirmedOrderId.textContent = `#${placedOrder.order_id}`;
      confirmedEstTime.textContent = `${placedOrder.estimated_prep_minutes} Mins`;
      orderedItemsPreview.innerHTML = placedOrder.items.map(it => `
        <div style="display:flex; justify-content:space-between; margin-bottom:4px;">
          <span>${it.quantity}x ${it.name}</span>
          <span style="font-weight:700;">$${(it.price * it.quantity).toFixed(2)}</span>
        </div>
      `).join('');

      orderSuccessModal.classList.add('open');
    }
  } catch (err) {
    alert(`Failed to place order: ${err}`);
  } finally {
    placeOrderBtn.disabled = false;
    placeOrderBtn.innerHTML = `<span>Confirm & Place Order</span><span class="arrow-icon">→</span>`;
  }
}

// -------------------------------------------------------------
// Robot Mission Close Trigger
// -------------------------------------------------------------
function triggerRobotClose() {
  // Signal parent window/iframe (Flutter app webview or modal)
  if (window.parent && window.parent !== window) {
    window.parent.postMessage({ action: 'close_mission_browser', source: 'bistrobot_kiosk' }, '*');
  }

  // Also try closing window if opened as popup
  try {
    window.close();
  } catch (_) {}

  // Show friendly notification on screen
  const notice = document.createElement('div');
  notice.style.position = 'fixed';
  notice.style.bottom = '20px';
  notice.style.left = '50%';
  notice.style.transform = 'translateX(-50%)';
  notice.style.backgroundColor = '#10B981';
  notice.style.color = '#FFF';
  notice.style.padding = '14px 24px';
  notice.style.borderRadius = '12px';
  notice.style.boxShadow = '0 10px 25px rgba(0,0,0,0.5)';
  notice.style.fontWeight = 'bold';
  notice.style.zIndex = '9999';
  notice.style.textAlign = 'center';
  notice.innerHTML = '🤖 Close signal sent! Tap the top "Close & Continue Mission" button to proceed.';
  document.body.appendChild(notice);

  setTimeout(() => notice.remove(), 4000);
}

// -------------------------------------------------------------
// Setup Event Listeners
// -------------------------------------------------------------
function setupEventListeners() {
  // Search input
  searchInput.addEventListener('input', (e) => {
    searchQuery = e.target.value;
    clearSearch.style.display = searchQuery ? 'block' : 'none';
    renderMenu();
  });

  clearSearch.addEventListener('click', () => {
    searchInput.value = '';
    searchQuery = '';
    clearSearch.style.display = 'none';
    renderMenu();
  });

  // Cart open / close
  openCartBtn.addEventListener('click', openCart);
  closeCartDrawerBtn.addEventListener('click', closeCart);
  cartBackdrop.addEventListener('click', closeCart);

  // Place order
  placeOrderBtn.addEventListener('click', placeOrder);

  // Modal actions
  finishOrderAndContinueBtn.addEventListener('click', () => {
    orderSuccessModal.classList.remove('open');
    triggerRobotClose();
  });

  closeModalOnlyBtn.addEventListener('click', () => {
    orderSuccessModal.classList.remove('open');
  });

  missionCloseBtn.addEventListener('click', triggerRobotClose);
}

// Run app
window.addEventListener('DOMContentLoaded', init);
