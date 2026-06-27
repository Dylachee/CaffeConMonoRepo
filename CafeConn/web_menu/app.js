const CONFIG = {
  tableId: readTableId(),
  useMockApi: true,
  apiBaseUrl: "https://your-api.example.com",
};

const MENU_IMAGES = {
  breakfast: "https://images.unsplash.com/photo-1555507036-ab1f4038808a?auto=format&fit=crop&w=900&q=80",
  coffee: "https://images.unsplash.com/photo-1461023058943-07fcbe16d735?auto=format&fit=crop&w=900&q=80",
  drinks: "https://images.unsplash.com/photo-1544145945-f90425340c7e?auto=format&fit=crop&w=900&q=80",
  wine: "https://images.unsplash.com/photo-1510812431401-41d2bd2722f3?auto=format&fit=crop&w=900&q=80",
  cocktail: "https://images.unsplash.com/photo-1551024709-8f23befc6f87?auto=format&fit=crop&w=900&q=80",
  savory: "https://images.unsplash.com/photo-1528735602780-2552fd46c7af?auto=format&fit=crop&w=900&q=80",
  kitchen: "https://images.unsplash.com/photo-1544025162-d76694265947?auto=format&fit=crop&w=900&q=80",
  dessert: "https://images.unsplash.com/photo-1488477181946-6428a0291777?auto=format&fit=crop&w=900&q=80",
  crepes: "https://images.unsplash.com/photo-1519676867240-f03562e64548?auto=format&fit=crop&w=900&q=80",
  chocolate: "https://images.unsplash.com/photo-1549007994-cb92caebd54b?auto=format&fit=crop&w=900&q=80",
};

const MOCK_MENU = [
  menuItem("croissant-crema-marmellata-nutella-pistacchio", "Croissant crema-marmellata-nutella pistacchio", "Colazione", 2.5, "breakfast", 142, ["Breakfast"], true),
  menuItem("croissant-vegano", "Croissant vegano", "Colazione", 2.5, "breakfast", 96, ["Vegan"]),
  menuItem("krapfen-crema-marmellata-nutella-pistacchio", "Krapfen crema-marmellata-nutella pistacchio", "Colazione", 2.5, "breakfast", 88, ["Breakfast"]),
  menuItem("biscotto-occhio-di-bue", "Biscotto Occhio di Bue marmellata-nutella", "Colazione", 3.6, "dessert", 74, ["Sweet"]),
  menuItem("french-toast-miele-noci", "French Toast con miele e noci o topping a scelta, frutti di bosco", "Colazione", 7, "breakfast", 119, ["Sweet"]),
  menuItem("toast-classico-cotto-formaggio", "Toast Classico cotto formaggio", "Colazione", 6.5, "savory", 82, ["Savory"]),
  menuItem("uovo-wurstel-pane-tostato", "Uovo all'occhio di bue, wurstel e pane tostato", "Colazione", 12, "breakfast", 64, ["Eggs"]),

  menuItem("espresso", "Espresso", "Caffetteria", 1.5, "coffee", 151, ["Coffee"]),
  menuItem("decaffeinato", "Decaffeinato", "Caffetteria", 2, "coffee", 42, ["Coffee"]),
  menuItem("americano", "Americano", "Caffetteria", 2, "coffee", 68, ["Coffee"]),
  menuItem("corretto", "Corretto", "Caffetteria", 3, "coffee", 55, ["Coffee"]),
  menuItem("caffe-con-panna", "Caffe con panna", "Caffetteria", 2.5, "coffee", 83, ["Coffee", "Dairy"]),
  menuItem("cappuccino", "Cappuccino", "Caffetteria", 3, "coffee", 134, ["Coffee", "Dairy"]),
  menuItem("decaffeinato-speciale", "Decaffeinato speciale", "Caffetteria", 3.5, "coffee", 33, ["Coffee"]),
  menuItem("latte-bianco", "Latte Bianco", "Caffetteria", 2, "coffee", 31, ["Dairy"]),
  menuItem("latte-macchiato", "Latte Macchiato", "Caffetteria", 3.5, "coffee", 71, ["Coffee", "Dairy"]),
  menuItem("latte-macchiato-topping", "Latte macchiato con topping a scelta", "Caffetteria", 4.5, "coffee", 59, ["Coffee", "Dairy"]),
  menuItem("bombardino", "Bombardino", "Caffetteria", 5, "coffee", 46, ["Hot drink"]),
  menuItem("punch", "Punch", "Caffetteria", 5, "drinks", 39, ["Hot drink"]),
  menuItem("vin-brule", "Vin brule", "Caffetteria", 6, "wine", 52, ["Hot drink"]),
  menuItem("cioccolata-calda-con-panna", "Cioccolata calda con panna", "Caffetteria", 6, "chocolate", 121, ["Chocolate"]),
  menuItem("orzo-ginseng", "Orzo/ginseng", "Caffetteria", 2, "coffee", 37, ["Coffee"], false, "2/2.5"),

  menuItem("acqua-05", "Acqua 0,5", "Bibite", 2.5, "drinks", 40, ["Water"]),
  menuItem("succo-di-frutta", "Succo di frutta", "Bibite", 4, "drinks", 61, ["Juice"]),
  menuItem("the-freddo", "The freddo", "Bibite", 4, "drinks", 48, ["Cold drink"]),
  menuItem("coca-cola-sprite", "Coca cola/sprite", "Bibite", 4.5, "drinks", 77, ["Soft drink"]),
  menuItem("lemonsoda-aranciata", "Lemonsoda/Aranciata", "Bibite", 4.5, "drinks", 43, ["Soft drink"]),
  menuItem("limonata-chinotto", "Limonata/chinotto", "Bibite", 4.5, "drinks", 41, ["Soft drink"]),
  menuItem("spremuta-arancia", "Spremuta arancia", "Bibite", 6, "drinks", 82, ["Juice"]),
  menuItem("tonica-cedrata", "Tonica/Cedrata", "Bibite", 4.5, "drinks", 35, ["Soft drink"]),

  menuItem("kronenbourg-025", "Kronenbourg 1664 alla spina 0,25l", "Birra", 4, "drinks", 50, ["Beer"]),
  menuItem("kronenbourg-05", "Kronenbourg 1664 alla spina 0,5l", "Birra", 7, "drinks", 58, ["Beer"]),
  menuItem("birra-bottiglia-033", "0,33l in bottiglia", "Birra", 5, "drinks", 34, ["Beer"]),
  menuItem("peroni-gran-riserva", "Peroni Gran Riserva Doppio Malto 0,5l", "Birra", 7.5, "drinks", 46, ["Beer"]),

  menuItem("pinot-grigio", "Pinot grigio", "Vino al calice e bottiglie", 6, "wine", 63, ["Wine"], false, "6-33"),
  menuItem("lugana", "Lugana", "Vino al calice e bottiglie", 6, "wine", 55, ["Wine"], false, "Ask"),
  menuItem("gewurztraminer", "Gewurztraminer", "Vino al calice e bottiglie", 6, "wine", 52, ["Wine"], false, "Ask"),
  menuItem("lagrein", "Lagrein", "Vino al calice e bottiglie", 6, "wine", 48, ["Wine"], false, "6-35"),
  menuItem("marzemino", "Marzemino", "Vino al calice e bottiglie", 6, "wine", 35, ["Wine"], false, "Ask"),
  menuItem("teroldego", "Teroldego", "Vino al calice e bottiglie", 6, "wine", 37, ["Wine"], false, "Ask"),
  menuItem("prosecco-valdobbiadene", "Prosecco Valdobbiadene", "Vino al calice e bottiglie", 6, "wine", 73, ["Wine"], false, "6-33"),
  menuItem("trento-doc", "Trento DOC", "Vino al calice e bottiglie", 8, "wine", 69, ["Wine"], false, "8-52"),

  menuItem("bloody-mary", "Bloody Mary", "Cocktails", 12, "cocktail", 59, ["Cocktail"]),
  menuItem("moscow-mule", "Moscow Mule", "Cocktails", 12, "cocktail", 89, ["Cocktail"]),
  menuItem("margarita", "Margarita", "Cocktails", 12, "cocktail", 82, ["Cocktail"]),
  menuItem("caipiroska-caipirinha", "Caipiroska/Caipirinha", "Cocktails", 12, "cocktail", 67, ["Cocktail"]),
  menuItem("cosmopolitan", "Cosmopolitan", "Cocktails", 12, "cocktail", 61, ["Cocktail"]),
  menuItem("cuba-libre", "Cuba Libre", "Cocktails", 12, "cocktail", 58, ["Cocktail"]),
  menuItem("sex-on-the-beach", "Sex on the beach", "Cocktails", 12, "cocktail", 77, ["Cocktail"]),
  menuItem("long-island-iced-tea", "Long Island Iced Tea", "Cocktails", 12, "cocktail", 84, ["Cocktail"]),
  menuItem("tequila-sunrise", "Tequila Sunrise", "Cocktails", 12, "cocktail", 72, ["Cocktail"]),
  menuItem("vodka-tonic", "Vodka Tonic", "Cocktails", 12, "cocktail", 56, ["Cocktail"]),
  menuItem("sissi-signature-cocktail", "Sissi Signature Cocktail", "Cocktails", 12, "cocktail", 113, ["Signature"]),
  menuItem("gin-tonic-base-bombay", "Gin Tonic Base Bombay", "Cocktails", 12, "cocktail", 80, ["Cocktail"]),
  menuItem("premium-cocktails", "Premium Cocktails", "Cocktails", 14, "cocktail", 74, ["Premium"]),

  menuItem("aperol-spritz", "Aperol Spritz", "Aperitivi", 8, "cocktail", 108, ["Aperitivo"]),
  menuItem("limoncello-spritz", "Limoncello Spritz", "Aperitivi", 9, "cocktail", 92, ["Aperitivo"]),
  menuItem("campari-soda", "Campari Soda", "Aperitivi", 6, "cocktail", 49, ["Aperitivo"]),
  menuItem("americano-negroni", "Americano-Negroni", "Aperitivi", 10, "cocktail", 75, ["Aperitivo"]),
  menuItem("negroni-sbagliato-negrosky", "Negroni Sbagliato-Negrosky", "Aperitivi", 10, "cocktail", 66, ["Aperitivo"]),
  menuItem("daiquiri-mimosa", "Daiquiri/Mimosa", "Aperitivi", 10, "cocktail", 57, ["Aperitivo"]),
  menuItem("campari-shakerato", "Campari Shakerato", "Aperitivi", 7, "cocktail", 43, ["Aperitivo"]),

  menuItem("taglierino-val-rendena", "Taglierino Val Rendena", "Da stuzzicare", 20, "savory", 51, ["Sharing"]),
  menuItem("tagliere-val-rendena", "Tagliere Val Rendena", "Da stuzzicare", 24, "savory", 65, ["Sharing"]),
  menuItem("patatine-fritte-stuzzicare", "Patatine Fritte", "Da stuzzicare", 5.5, "savory", 84, ["Fries"]),
  menuItem("crodino-san-bitter", "Crodino-San bitter", "Analcolici", 6, "drinks", 47, ["Alcohol-free"]),
  menuItem("lurisia-assenzio-genziana", "Lurisia Assenzio o Genziana", "Analcolici", 6, "drinks", 36, ["Alcohol-free"]),
  menuItem("succo-pomodoro-condito", "Succo di pomodoro condito", "Analcolici", 6, "drinks", 31, ["Alcohol-free"]),
  menuItem("analcolico-sissi", "Analcolico Sissi", "Analcolici", 8, "drinks", 62, ["Signature"]),

  menuItem("tortel-patate-lardo-speck", "Tortel di patate con lardo o speck", "Cucina di Sissi", 16, "kitchen", 98, ["Kitchen"]),
  menuItem("tortel-patate-salsiccia-crauti", "Tortel di patate con la salsiccia e crauti", "Cucina di Sissi", 16, "kitchen", 74, ["Kitchen"]),
  menuItem("tortel-patate-formaggio-uova", "Tortel di patate con il formaggio alla piastra e uova", "Cucina di Sissi", 16, "kitchen", 81, ["Kitchen"]),
  menuItem("lasagnetta-bolognese", "Lasagnetta alla bolognese", "Cucina di Sissi", 13, "kitchen", 88, ["Pasta"]),
  menuItem("risotto-porcini", "Risotto ai porcini", "Cucina di Sissi", 14, "kitchen", 79, ["Rice"]),
  menuItem("hamburger-sissi", "Hamburger Sissi: burger bun, manzo, formaggio, pomodoro, insalata, salsa", "Cucina di Sissi", 14, "savory", 128, ["Burger"]),
  menuItem("patatine-fritte-cucina", "Patatine fritte", "Cucina di Sissi", 5.5, "savory", 91, ["Fries"]),
  menuItem("panino-wurstel-crauti", "Panino con wurstel e crauti, maionese/ketchup/senape", "Cucina di Sissi", 8.5, "savory", 64, ["Sandwich"]),
  menuItem("cotoletta-patatine", "Cotoletta con patatine fritte", "Cucina di Sissi", 16, "kitchen", 84, ["Kitchen"]),
  menuItem("piatto-alpinista", "Piatto dell'alpinista: tortel di patate, salsiccia, formaggio alla piastra, sottaceti", "Cucina di Sissi", 22, "kitchen", 95, ["Kitchen"]),

  menuItem("toast-cotto-formaggio", "Toast Cotto Formaggio", "Da mangiare tutto il giorno", 6.5, "savory", 70, ["Toast"]),
  menuItem("panino-cotto-formaggio-pomodoro-insalata", "Panino cotto, formaggio, pomodoro, insalata", "Da mangiare tutto il giorno", 8, "savory", 64, ["Sandwich"]),
  menuItem("panino-speck-formaggio-cetriolini", "Panino Speck, formaggio, Cetriolini", "Da mangiare tutto il giorno", 8, "savory", 58, ["Sandwich"]),
  menuItem("panino-vegetariano", "Panino Vegetariano: mozzarella e pomodoro", "Da mangiare tutto il giorno", 8, "savory", 62, ["Vegetarian"]),
  menuItem("piadina-cotto-formaggio-pomodoro-insalata", "Piadina cotto, formaggio, pomodoro, insalata", "Da mangiare tutto il giorno", 8, "savory", 59, ["Piadina"]),
  menuItem("piadina-speck-brie-rucola-noci-miele", "Piadina Speck, brie, rucola, noci, miele", "Da mangiare tutto il giorno", 8.5, "savory", 67, ["Piadina"]),

  menuItem("crostata-del-giorno", "Crostata del giorno", "Dolci", 4.5, "dessert", 66, ["Dessert"]),
  menuItem("strudel-mele-panna", "Strudel di Mele con la panna", "Dolci", 6.5, "dessert", 77, ["Dessert"]),
  menuItem("strudel-mele-gelato", "Strudel di mele con gelato", "Dolci", 7.5, "dessert", 78, ["Dessert"]),
  menuItem("sacher", "Sacher", "Dolci", 6.5, "dessert", 72, ["Dessert"]),
  menuItem("linz", "Linz", "Dolci", 6.5, "dessert", 44, ["Dessert"]),
  menuItem("torta-carote", "Torta di carote", "Dolci", 6, "dessert", 57, ["Dessert"]),
  menuItem("crepes-nutella-dolci", "Crepes con Nutella", "Dolci", 7, "crepes", 101, ["Crepes"]),
  menuItem("coppa-gelato-artigianale", "Coppa Gelato artigianale", "Dolci", 5, "dessert", 69, ["Gelato"]),
  menuItem("grappa-barricata-18-lune", "Grappa Barricata/18 lune", "Grappe e liquori", 6, "drinks", 42, ["Liquor"]),
  menuItem("amari", "Amari", "Grappe e liquori", 6, "drinks", 40, ["Liquor"]),

  menuItem("croissant-prosciutto-fontina-insalata", "Croissant Prosciutto Cotto, Fontina, Insalata", "Sfiziosita del giorno", 7, "savory", 78, ["Brunch"]),
  menuItem("croissant-brie-miele-noci", "Croissant Brie Miele Noci", "Sfiziosita del giorno", 8.5, "breakfast", 90, ["Brunch"]),
  menuItem("french-toast-nutella", "French Toast Nutella", "Sfiziosita del giorno", 8, "breakfast", 106, ["Brunch"]),
  menuItem("omelette-prosciutto-fontina-pane", "Omelette con Prosciutto Cotto, Fontina e Pane Tostato", "Sfiziosita del giorno", 13, "breakfast", 76, ["Brunch"]),
  menuItem("snowboardtoast", "Snowboardtoast: pan carre, prosciutto cotto, pomodoro, insalata, uovo", "Sfiziosita del giorno", 15, "savory", 64, ["Brunch"]),
  menuItem("tost-vegetariano", "Tost Vegetariano: pan carre, fontina, pomodoro, insalata", "Sfiziosita del giorno", 7, "savory", 53, ["Vegetarian"]),
  menuItem("crack-burger", "Crack Burger: burger bun, ketchup, manzo, cheddar, cetriolini, rucola, insalata, uovo, pomodoro", "Sfiziosita del giorno", 18, "savory", 122, ["Burger"]),
  menuItem("bocconcino-di-sissi", "Bocconcino di Sissi: panino con salsiccia, formaggio fuso, ketchup, cetriolini", "Sfiziosita del giorno", 12, "savory", 87, ["Signature"]),
  menuItem("vellutata-carote-gamberetto", "Vellutata di Carote con gamberetto", "Sfiziosita del giorno", 14, "kitchen", 49, ["Soup"]),
  menuItem("panino-crudo-mozzarella-pomodoro", "Panino Crudo Mozzarella Pomodoro", "Sfiziosita del giorno", 8.5, "savory", 61, ["Sandwich"]),
  menuItem("toast-bresaola-formaggio-rucola", "Toast Bresaola Formaggio Rucola", "Sfiziosita del giorno", 8, "savory", 60, ["Toast"]),

  menuItem("crepes-prosciutto-fontina", "Crepes con prosciutto cotto e fontina", "Crepes", 14, "crepes", 63, ["Savory"]),
  menuItem("crepes-brie-noci-miele", "Crepes con brie noci e miele", "Crepes", 15, "crepes", 72, ["Savory"]),
  menuItem("crepes-mozzarella-pomodoro", "Crepes con mozzarella e pomodoro", "Crepes", 15, "crepes", 58, ["Savory"]),
  menuItem("crepes-brie-speck-rucola", "Crepes con brie speck e rucola", "Crepes", 15, "crepes", 70, ["Savory"]),
  menuItem("crepes-bresaola-brie-rucola", "Crepes con bresaola brie e rucola", "Crepes", 15, "crepes", 66, ["Savory"]),
  menuItem("crepes-crema-pasticcera-frutti-bosco", "Crepes con la crema pasticcera e frutti di bosco", "Crepes", 15, "crepes", 86, ["Sweet"]),
  menuItem("crepes-miele-noci", "Crepes con miele e noci", "Crepes", 14, "crepes", 73, ["Sweet"]),
  menuItem("crepes-nutella-marmellata-gelato", "Crepes con Nutella/Marmellata e gelato artigianale", "Crepes", 18, "crepes", 104, ["Sweet"]),
  menuItem("crepes-crema-pasticcera-gelato", "Crepes con la crema pasticcera e gelato artigianale", "Crepes", 18, "crepes", 89, ["Sweet"]),
  menuItem("crepes-topping-caramello-nocciola-frutti-bosco", "Crepes con topping al caramello/nocciola/frutti di bosco", "Crepes", 16, "crepes", 82, ["Sweet"]),

  menuItem("cappuccino-miele-cannella", "Cappuccino al Miele e Cannella", "Bevande speciali", 3.5, "coffee", 72, ["Hot drink"]),
  menuItem("cioccolata-calda-liquore", "Cioccolata Calda 100cl con Liquore al Caramello Salato o Cacao e Nocciola", "Bevande speciali", 12, "chocolate", 84, ["Hot drink"]),
  menuItem("cioccolata-arancia-cannella-grappa-rum", "Cioccolata all'arancia e cannella con grappa e rum caraibico", "Bevande speciali", 12, "chocolate", 78, ["Hot drink"]),
  menuItem("coppa-gelato-affogato-liquore", "Coppa Gelato Artigianale Affogato al liquore al caramello salato o cacao e nocciola", "Bevande speciali", 11, "dessert", 73, ["Gelato"]),

  menuItem("cioccolata-classica", "Cioccolata Classica", "Cioccolata", 5.5, "chocolate", 93, ["Chocolate"], false, null, "Gusto intenso e deciso del cioccolato fondente."),
  menuItem("cioccolata-con-panna", "Cioccolata con Panna", "Cioccolata", 6, "chocolate", 97, ["Chocolate"], false, null, "Fondente o bianca con panna."),
  menuItem("cioccolata-peperoncino", "Cioccolata al Peperoncino", "Cioccolata", 7, "chocolate", 71, ["Chocolate"], false, null, "Retrogusto piccantino e pungente con la dolcezza del cioccolato."),
  menuItem("cioccolata-arancia-cannella", "Cioccolata all'arancia e cannella", "Cioccolata", 7, "chocolate", 86, ["Chocolate"], false, null, "Nota speziata e avvolgente con arancia e cannella."),
  menuItem("cioccolata-bianca-menta", "Cioccolata Bianca alla menta", "Cioccolata", 6.5, "chocolate", 74, ["Chocolate"], false, null, "Nota fresca e pungente alla menta, servita con panna."),
  menuItem("cioccolata-nocciola", "Nocciola", "Cioccolata", 7, "chocolate", 88, ["Chocolate"], false, null, "Fondente con panna, topping alla nocciola e granella."),
];

const Api = {
  async getMenu() {
    if (CONFIG.useMockApi) return delay(withLocalLikes(MOCK_MENU));
    return request("/api/menu");
  },

  async createOrder(payload) {
    if (CONFIG.useMockApi) {
      return delay({
        id: Math.floor(1000 + Math.random() * 9000),
        status: "preparing",
        tableId: payload.tableId,
        createdAt: new Date().toISOString(),
        items: payload.items,
      });
    }

    return request("/api/orders", {
      method: "POST",
      body: JSON.stringify(payload),
    });
  },

  async getOrderStatus(orderId) {
    if (CONFIG.useMockApi) return delay({ id: orderId, status: "preparing" });
    return request(`/api/orders/${orderId}`);
  },

  async callWaiter(tableId) {
    if (CONFIG.useMockApi) return delay({ ok: true, tableId });
    return request("/api/waiter-call", {
      method: "POST",
      body: JSON.stringify({ tableId }),
    });
  },

  async requestBill(orderId, tableId) {
    if (CONFIG.useMockApi) return delay({ ok: true, orderId, tableId });
    return request("/api/bill-request", {
      method: "POST",
      body: JSON.stringify({ orderId, tableId }),
    });
  },

  async likeMenuItem(itemId, liked) {
    if (CONFIG.useMockApi) {
      saveLocalLike(itemId, liked);
      return delay({ ok: true, itemId, liked });
    }

    return request(`/api/menu/${itemId}/like`, {
      method: "POST",
      body: JSON.stringify({ liked }),
    });
  },
};

const state = {
  menu: [],
  activeCategory: "All",
  search: "",
  cart: new Map(),
  selectedItem: null,
  selectedQuantity: 1,
  heroIndex: 0,
  heroTimer: null,
  heroTouchX: null,
  latestOrder: null,
};

const $ = (selector) => document.querySelector(selector);
const money = (value) => `\u20ac${value.toFixed(2)}`;
const priceText = (item) => (item.priceLabel ? labelPrice(item.priceLabel) : money(item.price));

const menuView = $("#menuView");
const cartView = $("#cartView");
const statusView = $("#statusView");
const categoryRow = $("#categoryRow");
const menuGrid = $("#menuGrid");
const detailSheet = $("#detailSheet");
const suggestionRow = $("#suggestionRow");
const heroCard = $("#heroCard");
const toast = $("#toast");

document.addEventListener("DOMContentLoaded", init);

async function init() {
  bindEvents();
  renderTableNumber();
  state.menu = await Api.getMenu();
  renderMenu();
  renderCart();
  renderHero();
  renderSuggestions();
  startHeroTimer();
}

function bindEvents() {
  $("#menuSearch").addEventListener("input", (event) => {
    state.search = event.target.value.trim().toLowerCase();
    renderMenu();
  });

  $("#floatingCart").addEventListener("click", () => showScreen("cart"));
  $("#statusShortcut").addEventListener("click", () => {
    if (state.latestOrder) showScreen("status");
    else showToast("Place an order first.");
  });
  $("#heroDetails").addEventListener("click", () => openItem(getHeroItems()[state.heroIndex]));
  heroCard.addEventListener("pointerdown", (event) => {
    state.heroTouchX = event.clientX;
  });
  heroCard.addEventListener("pointerup", (event) => {
    if (state.heroTouchX === null) return;
    const distance = event.clientX - state.heroTouchX;
    state.heroTouchX = null;
    if (Math.abs(distance) > 45) moveHero(distance > 0 ? -1 : 1, true);
  });

  document.querySelectorAll("[data-go]").forEach((button) => {
    button.addEventListener("click", () => showScreen(button.dataset.go));
  });

  document.querySelectorAll("[data-close-sheet]").forEach((element) => {
    element.addEventListener("click", closeSheet);
  });

  $("#sheetMinus").addEventListener("click", () => updateSheetQuantity(-1));
  $("#sheetPlus").addEventListener("click", () => updateSheetQuantity(1));
  $("#sheetLike").addEventListener("click", toggleSelectedLike);
  $("#addToCart").addEventListener("click", addSelectedToCart);
  $("#placeOrder").addEventListener("click", placeOrder);
  $("#callWaiter").addEventListener("click", callWaiter);
  $("#requestBill").addEventListener("click", requestBill);
}

function showScreen(name) {
  menuView.classList.toggle("screen-active", name === "menu");
  cartView.classList.toggle("screen-active", name === "cart");
  statusView.classList.toggle("screen-active", name === "status");
  window.scrollTo({ top: 0, behavior: "smooth" });
}

function renderTableNumber() {
  document.querySelectorAll("[data-table-number]").forEach((element) => {
    element.textContent = CONFIG.tableId;
  });
}

function renderHero() {
  const items = getHeroItems();
  if (state.heroIndex >= items.length) state.heroIndex = 0;
  const item = items[state.heroIndex];
  if (!item) return;
  $("#heroImage").src = item.image;
  $("#heroImage").alt = item.name;
  $("#heroTitle").textContent = heroText(item.name);
  $("#heroTitle").title = item.name;
  $("#heroDescription").textContent = heroText(item.description, 5);
  $("#heroDescription").title = item.description;
  $("#heroDots").innerHTML = items
    .map(
      (_, index) => `
        <button class="${index === state.heroIndex ? "active" : ""}" type="button" data-hero-dot="${index}" aria-label="Show featured item ${index + 1}"></button>
      `
    )
    .join("");

  $("#heroDots").querySelectorAll("button").forEach((button) => {
    button.addEventListener("click", () => {
      state.heroIndex = Number(button.dataset.heroDot);
      renderHero();
      restartHeroTimer();
    });
  });
}

function moveHero(direction, userAction = false) {
  const items = getHeroItems();
  if (!items.length) return;
  state.heroIndex = (state.heroIndex + direction + items.length) % items.length;
  renderHero();
  if (userAction) restartHeroTimer();
}

function startHeroTimer() {
  stopHeroTimer();
  state.heroTimer = window.setInterval(() => moveHero(1), 5200);
}

function stopHeroTimer() {
  if (!state.heroTimer) return;
  window.clearInterval(state.heroTimer);
  state.heroTimer = null;
}

function restartHeroTimer() {
  startHeroTimer();
}

function renderSuggestions() {
  const items = getTopItems(3);
  suggestionRow.innerHTML = items
    .map(
      (item) => `
        <button class="suggestion-card" type="button" data-id="${item.id}">
          <img src="${item.image}" alt="" loading="lazy" />
          <span>
            <strong>${item.name}</strong>
            <small>${likeLabel(item.likes)}</small>
          </span>
        </button>
      `
    )
    .join("");

  suggestionRow.querySelectorAll("button").forEach((button) => {
    button.addEventListener("click", () => openItem(findMenuItem(button.dataset.id)));
  });
}

function renderMenu() {
  const categories = ["All", ...new Set(state.menu.map((item) => item.category))];
  categoryRow.innerHTML = categories
    .map((category) => {
      const active = category === state.activeCategory ? " active" : "";
      return `<button class="category-button${active}" type="button" data-category="${category}">${category}</button>`;
    })
    .join("");

  categoryRow.querySelectorAll("button").forEach((button) => {
    button.addEventListener("click", () => {
      state.activeCategory = button.dataset.category;
      renderMenu();
    });
  });

  const items = state.menu.filter((item) => {
    const categoryMatch = state.activeCategory === "All" || item.category === state.activeCategory;
    const textMatch = !state.search || item.name.toLowerCase().includes(state.search);
    return categoryMatch && textMatch;
  });

  menuGrid.innerHTML = items
    .map(
      (item) => `
        <button class="menu-card" type="button" data-id="${item.id}">
          <img src="${item.image}" alt="${item.name}" loading="lazy" />
          <h3>${item.name}</h3>
          <div class="card-meta">
            <p class="price">${priceText(item)}</p>
            <p class="likes">&hearts; ${item.likes}</p>
          </div>
        </button>
      `
    )
    .join("");

  menuGrid.querySelectorAll(".menu-card").forEach((card) => {
    card.addEventListener("click", () => openItem(findMenuItem(card.dataset.id)));
  });
}

function renderCart() {
  const cartItems = [...state.cart.values()];
  const cartCount = cartItems.reduce((sum, item) => sum + item.quantity, 0);
  const cartTotal = cartItems.reduce((sum, item) => sum + item.quantity * item.price, 0);

  $("#cartCount").textContent = cartCount;
  $("#floatingCart").style.display = cartCount ? "grid" : "none";
  $("#cartTotal").textContent = money(cartTotal);
  $("#emptyCart").style.display = cartItems.length ? "none" : "block";
  $("#placeOrder").disabled = cartItems.length === 0;

  $("#cartList").innerHTML = cartItems
    .map(
      (item) => `
        <article class="cart-item">
          <div>
            <h3>${item.name}</h3>
            <p class="price">${priceText(item)}</p>
          </div>
          <div class="stepper">
            <button type="button" data-cart-dec="${item.id}" aria-label="Decrease ${item.name}">&minus;</button>
            <span>${item.quantity}</span>
            <button type="button" data-cart-inc="${item.id}" aria-label="Increase ${item.name}">+</button>
          </div>
        </article>
      `
    )
    .join("");

  $("#cartList").querySelectorAll("[data-cart-dec]").forEach((button) => {
    button.addEventListener("click", () => changeCartQuantity(button.dataset.cartDec, -1));
  });

  $("#cartList").querySelectorAll("[data-cart-inc]").forEach((button) => {
    button.addEventListener("click", () => changeCartQuantity(button.dataset.cartInc, 1));
  });
}

function renderOrder() {
  const order = state.latestOrder;
  if (!order) return;

  const time = new Date(order.createdAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  $("#orderTitle").textContent = `Order #${order.id}`;
  $("#orderMeta").textContent = `Table ${order.tableId} - ${time}`;
  $("#statusChip").textContent = "Preparing";
  $("#orderItems").innerHTML = order.items
    .map(
      (item) => `
        <article class="order-item">
          <div>
            <h3>${item.name}</h3>
            <p>${item.quantity} x <span class="price">${priceText(item)}</span> &middot; &hearts; ${item.likes}</p>
          </div>
          <span class="status-dot" aria-label="Preparing"></span>
        </article>
      `
    )
    .join("");
}

function openItem(item) {
  if (!item) return;
  state.selectedItem = item;
  state.selectedQuantity = 1;
  $("#sheetImage").src = item.image;
  $("#sheetImage").alt = item.name;
  $("#sheetTitle").textContent = item.name;
  $("#sheetPrice").textContent = priceText(item);
  $("#sheetDescription").textContent = item.description;
  $("#sheetNotes").value = "";
  $("#sheetTags").innerHTML = item.tags.map((tag) => `<span class="tag">${tag}</span>`).join("");
  renderSheetLike();
  updateSheetTotal();
  detailSheet.classList.add("open");
  detailSheet.setAttribute("aria-hidden", "false");
}

async function toggleSelectedLike() {
  const item = state.selectedItem;
  if (!item) return;

  const liked = !item.likedByGuest;
  item.likedByGuest = liked;
  item.likes += liked ? 1 : -1;
  await Api.likeMenuItem(item.id, liked);
  renderSheetLike();
  renderMenu();
  renderHero();
  renderSuggestions();
}

function renderSheetLike() {
  const item = state.selectedItem;
  if (!item) return;

  const button = $("#sheetLike");
  button.classList.toggle("liked", item.likedByGuest);
  button.setAttribute("aria-pressed", String(item.likedByGuest));
  $("#sheetLikes").textContent = likeLabel(item.likes);
}

function closeSheet() {
  detailSheet.classList.remove("open");
  detailSheet.setAttribute("aria-hidden", "true");
}

function updateSheetQuantity(change) {
  state.selectedQuantity = Math.max(1, state.selectedQuantity + change);
  updateSheetTotal();
}

function updateSheetTotal() {
  const item = state.selectedItem;
  $("#sheetQuantity").textContent = state.selectedQuantity;
  $("#sheetTotal").textContent = item ? money(item.price * state.selectedQuantity) : "$0.00";
}

function addSelectedToCart() {
  const item = state.selectedItem;
  if (!item) return;

  const existing = state.cart.get(item.id);
  state.cart.set(item.id, {
    ...item,
    notes: $("#sheetNotes").value.trim(),
    quantity: (existing?.quantity || 0) + state.selectedQuantity,
  });

  closeSheet();
  renderCart();
  showToast("Added to cart.");
}

function changeCartQuantity(id, change) {
  const item = state.cart.get(id);
  if (!item) return;

  const quantity = item.quantity + change;
  if (quantity <= 0) state.cart.delete(id);
  else state.cart.set(id, { ...item, quantity });

  renderCart();
}

async function placeOrder() {
  const items = [...state.cart.values()];
  if (!items.length) return;

  $("#placeOrder").disabled = true;
  const order = await Api.createOrder({
    tableId: CONFIG.tableId,
    items: items.map(({ id, name, price, priceLabel, quantity, notes, likes }) => ({ id, name, price, priceLabel, quantity, notes, likes })),
  });

  state.latestOrder = order;
  state.cart.clear();
  renderCart();
  renderOrder();
  showScreen("status");
  showToast("Order sent to the kitchen.");
}

async function callWaiter() {
  await Api.callWaiter(CONFIG.tableId);
  showToast("A waiter has been called.");
}

async function requestBill() {
  await Api.requestBill(state.latestOrder?.id, CONFIG.tableId);
  showToast("Bill request sent.");
}

function findMenuItem(id) {
  return state.menu.find((item) => item.id === id);
}

function getFeaturedItem() {
  return state.menu.find((item) => item.featured) || state.menu[0];
}

function getHeroItems() {
  return getTopItems(4);
}

function getTopItems(limit) {
  return [...state.menu].sort((a, b) => b.likes - a.likes).slice(0, limit);
}

function likeLabel(count) {
  return `${count} ${count === 1 ? "like" : "likes"}`;
}

function heroText(text, mobileWords = 4) {
  const words = text.replace(/-/g, " ").split(/\s+/).filter(Boolean);
  const limit = window.matchMedia("(max-width: 520px)").matches ? mobileWords : 7;
  return words.length > limit ? `${words.slice(0, limit).join(" ")}...` : text;
}

function labelPrice(label) {
  return label === "Ask" ? label : `\u20ac${label}`;
}

function showToast(message) {
  toast.textContent = message;
  toast.classList.add("show");
  window.clearTimeout(showToast.timeout);
  showToast.timeout = window.setTimeout(() => toast.classList.remove("show"), 2200);
}

async function request(path, options = {}) {
  const response = await fetch(`${CONFIG.apiBaseUrl}${path}`, {
    headers: {
      "Content-Type": "application/json",
      ...options.headers,
    },
    ...options,
  });

  if (!response.ok) throw new Error(`API request failed: ${response.status}`);
  return response.json();
}

function delay(value) {
  return new Promise((resolve) => {
    window.setTimeout(() => resolve(structuredClone(value)), 220);
  });
}

function menuItem(id, name, category, price, imageKey, likes, tags = [], featured = false, priceLabel = null, description = null) {
  return {
    id,
    name,
    category,
    price,
    priceLabel,
    image: MENU_IMAGES[imageKey],
    description: description || `${name} from the ${category} menu.`,
    tags,
    likes,
    featured,
  };
}

function readTableId() {
  const segment = window.location.pathname.split("/").filter(Boolean)[0];
  const pathTable = /^\d+$/.test(segment || "") ? segment : "";
  const table = pathTable || new URLSearchParams(window.location.search).get("table") || "04";
  return table.padStart(2, "0");
}

function withLocalLikes(menu) {
  const likedIds = getLikedIds();

  return menu.map((item) => ({
    ...item,
    likes: item.likes + (likedIds.includes(item.id) ? 1 : 0),
    likedByGuest: likedIds.includes(item.id),
  }));
}

function saveLocalLike(itemId, liked) {
  const likedIds = getLikedIds().filter((id) => id !== itemId);
  if (liked) likedIds.push(itemId);
  localStorage.setItem("likedMenuItems", JSON.stringify(likedIds));
}

function getLikedIds() {
  try {
    return JSON.parse(localStorage.getItem("likedMenuItems")) || [];
  } catch {
    return [];
  }
}
