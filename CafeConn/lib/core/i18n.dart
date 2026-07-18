/// Ultra-light EN/IT string table for the staff app.
///
/// No codegen and no BuildContext needed: [CafeState.setLanguage] flips
/// [L.lang] and calls notifyListeners(), every screen already watches the
/// state, so all visible text re-reads the table on rebuild. Menu content
/// (names/descriptions/categories) is translated separately — the hub sends
/// both languages and MenuItem.displayName picks one based on [L.lang].
library;

enum AppLang { en, it }

class L {
  static AppLang lang = AppLang.it;
  static bool get isIt => lang == AppLang.it;
  static String t(String en, String it) => isIt ? it : en;

  // ---- shell tabs ----
  static String get tables => t('Tables', 'Tavoli');
  static String get orders => t('Orders', 'Ordini');
  static String get menu => t('Menu', 'Menu');
  static String get chats => t('Chats', 'Chat');
  static String get panel => t('Panel', 'Pannello');

  // ---- table statuses / attention ----
  static String get stFree => t('Free', 'Libero');
  static String get stOccupied => t('Occupied', 'Occupato');
  static String get stWaiting =>
      t('Waiting for waiter', 'In attesa del cameriere');
  static String get attCall => t('CALL', 'CHIAMATA');
  static String get attBill => t('BILL', 'CONTO');
  static String get attGuest => t('GUEST', 'OSPITE');
  static String get attSignal => t('SIGNAL', 'SEGNALE');

  // ---- roles ----
  static String get roleAdmin => t('Admin', 'Admin');
  static String get roleManager => t('Manager', 'Manager');
  static String get roleWaiter => t('Waiter', 'Cameriere');
  static String get roleCook => t('Cook', 'Cuoco');
  static String get roleBartender => t('Bartender', 'Barista');
  static String get roleSmm => t('SMM / Content', 'SMM / Contenuti');

  // ---- order statuses (staff wording) ----
  static String get osAwaiting => t('Awaiting approval', 'Da approvare');
  static String get osAccepted => t('New', 'Nuovo');
  static String get osCooking => t('In preparation', 'In preparazione');
  static String get osReady => t('Ready', 'Pronto');
  static String get osCompleted => t('Delivered', 'Servito');
  // ---- guest-order approval ----
  static String get pendingApproval =>
      t('Pending approval', 'In attesa di approvazione');
  static String pendingApprovalN(int n) => t(
      '$n guest ${n == 1 ? 'order' : 'orders'} to approve',
      '$n ${n == 1 ? 'ordine ospite' : 'ordini ospite'} da approvare');
  static String get guestOrder => t('Guest order', 'Ordine ospite');
  static String get reviewOrder => t('Review', 'Rivedi');
  static String get sendToKitchenBar =>
      t('Send to kitchen & bar', 'Invia a cucina e bar');
  static String get rejectOrder => t('Reject', 'Rifiuta');
  static String get rejectOrderQ =>
      t('Reject this order?', 'Rifiutare questo ordine?');
  static String get rejectOrderWarn => t(
      'The guest order is cancelled and never reaches the kitchen or bar.',
      "L'ordine dell'ospite viene annullato e non raggiunge cucina o bar.");
  static String get orderApproved =>
      t('Sent to kitchen & bar', 'Inviato a cucina e bar');
  static String get orderRejected => t('Order rejected', 'Ordine rifiutato');
  static String get noPendingOrders =>
      t('No guest orders waiting', 'Nessun ordine ospite in attesa');

  // ---- tables screen ----
  static String get hall => t('Hall', 'Sala');
  static String get active => t('active', 'attivi');
  static String get free => t('free', 'liberi');
  static String get freeLower => t('free', 'libero');
  static String get connecting =>
      t('Connecting to server...', 'Connessione al server...');
  static String get demoBanner => t(
      'Demo mode: data is not from the server. Tap to sign in.',
      'Modalità demo: i dati non provengono dal server. Tocca per accedere.');
  static String get searchTable =>
      t('Search table or waiter', 'Cerca tavolo o cameriere');
  static String get all => t('All', 'Tutto');
  static String get nothingFound => t('Nothing found', 'Nessun risultato');
  static String get noTablesMatch => t('No tables match this filter or number',
      'Nessun tavolo corrisponde a questo filtro o numero');
  static String get newTable => t('New table', 'Nuovo tavolo');
  static String get editTable => t('Edit table', 'Modifica tavolo');
  static String get tableNumber => t('Table number', 'Numero del tavolo');
  static String get tagColor => t('TAG COLOR', 'COLORE ETICHETTA');
  static String get add => t('Add', 'Aggiungi');
  static String get save => t('Save', 'Salva');
  static String get filterByStatus => t('Filter by status', 'Filtra per stato');
  static String get allTables => t('All tables', 'Tutti i tavoli');
  static String tableN(Object n) => t('Table $n', 'Tavolo $n');
  static String get checkEmpty => t('Check is empty', 'Il conto è vuoto');
  static String get total => t('TOTAL', 'TOTALE');
  static String get forward => t('Forward', 'Inoltra');
  static String get open => t('Open', 'Apri');
  static String get tapToClose =>
      t('Tap the background to close', 'Tocca lo sfondo per chiudere');
  static String openedAt(String hhmm) => t('Opened $hhmm', 'Aperto $hhmm');

  // ---- table details ----
  static String get order => t('Order', 'Ordine');
  static String served(int done, int total) =>
      t('$done/$total served', '$done/$total serviti');
  static String get guestsAtTable => t('Guests at table', 'Ospiti al tavolo');
  static String get addItem => t('Add item', 'Aggiungi piatto');
  static String get clearTable => t('Clear table', 'Libera tavolo');
  static String clearTableQ(Object n) =>
      t('Clear table $n?', 'Liberare il tavolo $n?');
  static String get clearTableWarn => t(
      'The order will be moved to archive. Make sure payment was completed at the register.',
      "L'ordine sarà archiviato. Assicurati che il pagamento sia stato completato alla cassa.");
  static String get cancel => t('Cancel', 'Annulla');
  static String get yesClear => t('Yes, clear', 'Sì, libera');
  static String get changePayment => t('Change / Payment', 'Resto / Pagamento');
  static String get notes => t('Notes', 'Note');
  static String get tableStatus => t('Table status', 'Stato del tavolo');
  static String get send => t('Send', 'Invia');
  static String get noNewItems => t(
      'No new items — everything was already sent',
      'Nessun nuovo piatto — tutto è già stato inviato');
  static String sentKitchenBar(int k, int b) =>
      t('Sent · Kitchen $k · Bar $b', 'Inviato · Cucina $k · Bar $b');
  static String get couldNotSend => t('Could not send', 'Invio non riuscito');
  static String notSent(String err) => t('Not sent: $err', 'Non inviato: $err');
  static String get draftNotSent =>
      t('draft — not sent', 'bozza — non inviato');
  static String readyAt(bool bar) => t('ready at ${bar ? "bar" : "kitchen"}',
      'pronto al ${bar ? "bar" : "in cucina"}');
  static String get newNote => t('New note', 'Nuova nota');
  static String get noteText => t('Note text', 'Testo della nota');
  static String get noteHint =>
      t('Allergy, birthday, VIP...', 'Allergia, compleanno, VIP...');
  static String get note => t('note', 'nota');
  static String get changeCalculator =>
      t('Change calculator', 'Calcolo del resto');
  static String get toPay => t('To pay:', 'Da pagare:');
  static String get cashReceived => t('Cash received', 'Contanti ricevuti');
  static String get change => t('CHANGE:', 'RESTO:');
  static String get done => t('Done', 'Fatto');
  static String get orderHistory => t('Order history', 'Storico ordini');
  static String get noOrdersYet =>
      t('No orders sent yet', 'Nessun ordine inviato');
  static String get deliveredStays => t(
      'Delivered orders stay here until the table is cleared.',
      'Gli ordini serviti restano qui finché il tavolo non viene liberato.');
  static String get yesterday => t('Yesterday', 'Ieri');
  static String get historyEmptyDay =>
      t('No orders on this day', 'Nessun ordine in questo giorno');
  static String get historyEmpty =>
      t('This table has no history yet', 'Questo tavolo non ha ancora storico');
  static String get earlierDay => t('Earlier day', 'Giorno precedente');
  static String get laterDay => t('Later day', 'Giorno successivo');
  static String historyOrdersN(int n) =>
      t(n == 1 ? '1 order' : '$n orders', n == 1 ? '1 ordine' : '$n ordini');
  static String get couldNotLoad =>
      t('Could not load', 'Caricamento non riuscito');
  static String get retry => t('Retry', 'Riprova');

  // ---- composer: popular shelf ----
  static String get popular => t('Popular', 'Popolari');
  static String get pinPopular => t('Add to Popular', 'Aggiungi ai Popolari');
  static String get unpinPopular =>
      t('Remove from Popular', 'Rimuovi dai Popolari');
  static String get popularEmpty => t(
      'No pinned items yet. Hold any item to pin it here.',
      'Nessun preferito. Tieni premuto un piatto per aggiungerlo qui.');
  static String get dishDetails => t('Details', 'Dettagli');

  // ---- panel: menu management ----
  static String get guestVisible =>
      t('Visible to guests', 'Visibile agli ospiti');
  static String get waiterShelf =>
      t('Waiter Popular shelf', 'Popolari camerieri');
  static String get promoGuests =>
      t('Promote to guests', 'Promuovi agli ospiti');
  static String get promoTag => t('PROMO', 'PROMO');
  static String get savedToHub => t('Saved', 'Salvato');
  static String get notSavedErr =>
      t('Not saved — check connection', 'Non salvato — controlla la rete');
  static String itemsCount(int n) =>
      t(n == 1 ? '1 item' : '$n items', n == 1 ? '1 articolo' : '$n articoli');

  // ---- panel: team management ----
  static String get editStaffMember => t('Edit member', 'Modifica membro');
  static String get newPasswordHint => t(
      'New password (leave empty to keep the current one)',
      'Nuova password (vuota = invariata)');
  static String get topDishesToday =>
      t("Today's top sellers", 'Più venduti oggi');
  static String get delayedLabel => t('Delayed', 'In ritardo');
  static String get categoriesTitle =>
      t('Categories & colors', 'Categorie e colori');
  static String get categoriesSub => t(
      'Add, remove, rename, or recolor categories — every device follows.',
      'Aggiungi, elimina, rinomina o cambia colore alle categorie — vale su tutti i dispositivi.');
  static String get addCategory => t('Add category', 'Aggiungi categoria');
  static String get deleteCategory => t('Delete category', 'Elimina categoria');
  static String get noCategories =>
      t('No categories yet.', 'Ancora nessuna categoria.');

  // ---- order feed ----
  static String activeCount(int n) => t('$n active', '$n attivi');
  static String get kitchenU => t('KITCHEN', 'CUCINA');
  static String get barU => t('BAR', 'BAR');
  static String get kitchen => t('Kitchen', 'Cucina');
  static String get bar => t('Bar', 'Bar');
  static String get mixed => t('Mixed', 'Misto');
  static String get allDone => t('All done', 'Tutto fatto');
  static String get noActiveKitchen =>
      t('No active kitchen orders', 'Nessun ordine attivo in cucina');
  static String get noActiveBar =>
      t('No active bar orders', 'Nessun ordine attivo al bar');
  static String get startCooking => t('Start', 'Inizia');
  static String get markReady => t('Ready', 'Pronto');
  static String get markDelivered =>
      t('Delivered to guest', 'Servito al tavolo');
  static String get deliverReadyItems =>
      t('Deliver ready items below', 'Servi gli elementi pronti qui sotto');
  static String get deliverAllReady =>
      t('Deliver all ready', 'Servi tutti i pronti');
  static String deliverAllReadyN(int n) =>
      t('Deliver all ready ($n)', 'Servi tutti i pronti ($n)');
  static String get nothingReadyYet =>
      t('Nothing ready to deliver yet', 'Niente di pronto da servire');
  static String get itemReady => t('Ready', 'Pronto');
  static String get itemDelivered => t('Delivered', 'Servito');
  static String get deleteItem => t('Delete item', 'Elimina elemento');
  static String deleteItemQ(String name) =>
      t('Delete "$name"?', 'Eliminare "$name"?');
  static String get deleteItemWarn => t(
      'This removes the item from the order. The kitchen/bar feed updates for everyone.',
      "Rimuove l'elemento dall'ordine. Il feed cucina/bar si aggiorna per tutti.");
  static String get yesDelete => t('Yes, delete', 'Sì, elimina');
  static String get waitingWaiter =>
      t('Ready — waiting for waiter', 'Pronto — in attesa del cameriere');
  static String get waitingStation =>
      t('Waiting for station', 'In attesa della postazione');
  static String get inPreparation =>
      t('In preparation...', 'In preparazione...');
  static String get discussOrder => t('Discuss order', "Discuti l'ordine");
  static String get comment => t('Comment...', 'Commento...');

  // ---- menu ----
  static String get showcase =>
      t('Showcase and stop-list', 'Vetrina e stop-list');
  static String get searchItem => t('Search item...', 'Cerca piatto...');
  static String get changeSearch =>
      t('Change the search or category', 'Cambia ricerca o categoria');
  static String get takeOrder => t('Take order', 'Prendi ordine');
  static String get whichTable => t('Which table?', 'Quale tavolo?');
  static String get clientMenu => t('CLIENT', 'CLIENTE');
  static String get stop => t('STOP', 'STOP');
  static String get stopList => t('STOP-LIST', 'STOP-LIST');
  static String get composition => t('COMPOSITION', 'COMPOSIZIONE');
  static String get allergens => t('ALLERGENS', 'ALLERGENI');
  static String get noAllergens => t('No allergens', 'Senza allergeni');
  static String minutes(Object m) => t('$m min', '$m min');

  // ---- order composer ----
  static String tableOrder(Object n) =>
      t('Table $n · order', 'Tavolo $n · ordine');
  static String get tapToAdd =>
      t('Tap an item to add it', 'Tocca un piatto per aggiungerlo');
  static String get searchMenu => t('Search menu...', 'Cerca nel menu...');
  static String stopListed(String name) =>
      t('$name is stop-listed', '$name è in stop-list');
  static String get noTables => t('No tables', 'Nessun tavolo');
  static String get addTableFirst =>
      t('Add a table first', 'Aggiungi prima un tavolo');
  static String get clear => t('Clear', 'Svuota');
  static String get precheck => t('Precheck →', 'Preconto →');
  static String get newOrder => t('New order', 'Nuovo ordine');
  static String get tableU => t('TABLE', 'TAVOLO');
  static String get itemsU => t('ITEMS', 'ARTICOLI');
  static String get allItemsRemoved =>
      t('All items removed', 'Tutti gli articoli rimossi');
  static String toKitchen(int n) => t('To kitchen: $n', 'In cucina: $n');
  static String toBar(int n) => t('To bar: $n', 'Al bar: $n');
  static String get sendOrder => t('SEND ORDER', 'INVIA ORDINE');
  static String orderSent(Object table, int k, int b) => t(
      'Order for table $table sent · Kitchen $k · Bar $b',
      'Ordine per il tavolo $table inviato · Cucina $k · Bar $b');
  static String get nothingToSend => t('Nothing to send', 'Niente da inviare');
  static String notSentSaved(String err) => t(
      'Not sent: $err. Items were saved in the table check.',
      'Non inviato: $err. Gli articoli sono stati salvati nel conto del tavolo.');
  static String get addNote => t('Note...', 'Nota...');
  static String get plusNote => t('+ note', '+ nota');
  static String get minusNote => t('− note', '− nota');

  // ---- note presets ----
  static String get noOnion => t('No onion', 'Senza cipolla');
  static String get noIce => t('No ice', 'Senza ghiaccio');
  static String get soyMilk => t('Soy milk', 'Latte di soia');
  static String get spicy => t('Spicy', 'Piccante');
  static String get notSpicy => t('Not spicy', 'Non piccante');
  static String get takeaway => t('Takeaway', 'Da asporto');
  static String get noSugar => t('No sugar', 'Senza zucchero');
  static String get wellDone => t('Well done', 'Ben cotto');
  static String get lessIce => t('Less ice', 'Poco ghiaccio');
  static String get extraIce => t('Extra ice', 'Extra ghiaccio');
  static String get noLemon => t('No lemon', 'Senza limone');
  static String get noMint => t('No mint', 'Senza menta');
  static String get noTomato => t('No tomato', 'Senza pomodoro');
  static String get noCheese => t('No cheese', 'Senza formaggio');
  static String get noMayo => t('No mayo', 'Senza maionese');
  static String get noBacon => t('No bacon', 'Senza bacon');
  static String get noMushrooms => t('No mushrooms', 'Senza funghi');
  static String get noEgg => t('No egg', 'Senza uovo');
  static List<String> get notePresets =>
      [noOnion, noIce, soyMilk, spicy, notSpicy, takeaway, noSugar, wellDone];
  static List<String> get notePresetsShort =>
      [noOnion, noIce, spicy, takeaway, noSugar, wellDone];

  // ---- chat ----
  static String get teamOnline => t('Team online', 'Team online');
  static String get noMessages => t('No messages', 'Nessun messaggio');
  static String membersCount(int n) => t('$n members', '$n membri');
  static String get chatEmpty => t('Chat is empty', 'La chat è vuota');
  static String get startConversation => t(
      'Start the conversation by sending the first message',
      'Inizia la conversazione inviando il primo messaggio');
  static String get message => t('Message...', 'Messaggio...');
  static String get sentToChat => t('Sent to chat', 'Inviato in chat');
  static String get sendTo => t('SEND TO', 'INVIA A');
  static String get addComment => t('Add comment...', 'Aggiungi commento...');
  static String newOrderTable(Object n) =>
      t('New order · Table $n', 'Nuovo ordine · Tavolo $n');
  static String get forwarded => t('FORWARDED', 'INOLTRATO');
  static String get openTable => t('Open table', 'Apri tavolo');
  static String get generalChat => t('General chat', 'Chat generale');

  // ---- panel ----
  static String get systemManagement =>
      t('System management', 'Gestione del sistema');
  static String get overview => t('Overview', 'Panoramica');
  static String get team => t('Team', 'Team');
  static String get access => t('Access', 'Accessi');
  static String get revenue => t('Revenue', 'Incasso');
  static String todayOrders(int n) =>
      t('today · $n orders', 'oggi · $n ordini');
  static String get avgCheck => t('Average check', 'Scontrino medio');
  static String acrossTables(int n) => t('across $n tables', 'su $n tavoli');
  static String get occupiedNow => t('occupied now', 'occupati ora');
  static String get inProgress => t('In progress', 'In corso');
  static String oldestMin(int n) => t('oldest $n min', 'più vecchio $n min');
  static String get noQueue => t('no queue', 'nessuna coda');
  static String get revenueByHour => t('Revenue by hour', 'Incasso per ora');
  static String get noOrdersToday =>
      t('No orders yet today', 'Nessun ordine oggi');
  static String get bestHour => t('Best hour', 'Ora migliore');
  static String get avgPrepTime => t('Avg prep time', 'Tempo medio prep.');
  static String minutesShort(int n) => t('$n min', '$n min');
  static String vsYesterday(int pct) => pct >= 0
      ? t('▲ $pct% vs yesterday', '▲ $pct% rispetto a ieri')
      : t('▼ ${-pct}% vs yesterday', '▼ ${-pct}% rispetto a ieri');
  static String deltaPct(int pct) => pct >= 0 ? '▲ $pct%' : '▼ ${-pct}%';
  static String freeCount(int n) => t('$n free', '$n liberi');
  static String delayedCount(int n) => t('$n delayed', '$n in ritardo');
  static String get onTime => t('all on time', 'tutto in orario');
  static String get today => t('today', 'oggi');
  static String get last7Days => t('Last 7 days', 'Ultimi 7 giorni');
  static String get custom => t('Custom', 'Personalizzato');
  static String get searchOrders =>
      t('Search table, item, staff...', 'Cerca tavolo, piatto, staff...');
  static String get status => t('Status', 'Stato');
  static String get history => t('History', 'Storico');
  static String get noOrderHistory =>
      t('No orders in history', 'Nessun ordine nello storico');
  static String get pullToRefresh =>
      t('Pull to refresh', 'Trascina per aggiornare');
  static String get table => t('Table', 'Tavolo');
  static String get source => t('Source', 'Origine');
  static String get guest => t('Guest', 'Ospite');
  static String get staff => t('Staff', 'Personale');
  static String get items => t('Items', 'Articoli');
  static String get rolePermissions =>
      t('Role permissions', 'Permessi dei ruoli');
  // ---- staff access / capabilities ----
  static String get staffAccess => t('Staff access', 'Accessi personale');
  static String get accessHint => t(
      'Grant extra capabilities on top of each role.',
      'Concedi capacità extra oltre al ruolo.');
  static String get capWaiter =>
      t('Waiter (floor & delivery)', 'Cameriere (sala e consegna)');
  static String get capBar => t('Bar station', 'Postazione bar');
  static String get capKitchen => t('Kitchen station', 'Postazione cucina');
  static String get capMenu => t('Manage menu', 'Gestisci menu');
  static String get capContent =>
      t('Content (feed & storefront)', 'Contenuti (feed e vetrina)');
  static String get capDiscount =>
      t('Coupons (issue & redeem)', 'Coupon (emetti e riscatta)');
  static String get includedWithRole => t('role', 'ruolo');
  static String get fullAccess => t('Full access', 'Accesso completo');
  static String get connectToManage => t(
      'Connect to the hub to manage staff access.',
      "Connettiti all'hub per gestire gli accessi.");
  static String get noStaffFound =>
      t('No staff found', 'Nessun membro trovato');
  static String get byWaiter => t('By waiter', 'Per cameriere');
  // ---- order activity log ----
  static String get activity => t('Activity', 'Attività');
  static String get noActivity => t('No activity yet', 'Nessuna attività');
  static String get evCreated => t('created the order', "ha creato l'ordine");
  static String get evConfirmed =>
      t('sent to kitchen & bar', 'inviato a cucina e bar');
  static String get evRejected =>
      t('rejected the order', "ha rifiutato l'ordine");
  static String get evReady => t('marked ready', 'segnato pronto');
  static String get evDelivered => t('delivered', 'servito');
  static String get evUndelivered => t('undid delivery', 'annullato servizio');
  static String get evDeleted => t('removed', 'rimosso');
  static String get evStatus => t('changed status', 'cambiato stato');
  static String get markOutOfStock => t('Mark out of stock', 'Segna esaurito');
  static String get markAvailable => t('Mark available', 'Segna disponibile');
  static String waiterOrdersTables(int o, int t) =>
      L.isIt ? '$o ordini · $t tavoli' : '$o orders · $t tables';
  static String get newItem => t('New item', 'Nuovo piatto');
  static String get editItem => t('Edit item', 'Modifica piatto');
  static String get name => t('Name', 'Nome');
  static String get firstName => t('First name', 'Nome');
  static String get lastName => t('Surname', 'Cognome');
  static String get description => t('Description', 'Descrizione');
  static String get descriptionHint =>
      t('Composition, details...', 'Composizione, dettagli...');
  static String get price => t('Price', 'Prezzo');
  static String get timeMin => t('Time (min)', 'Tempo (min)');
  static String get category => t('Category', 'Categoria');
  static String get station => t('STATION', 'POSTAZIONE');
  static String get newStaffMember =>
      t('New staff member', 'Nuovo membro del personale');
  static String get username => t('Username', 'Nome utente');
  static String get createAccount => t('Create account', 'Crea account');
  static String get accountCreated => t('Account created', 'Account creato');
  static String get accountNeedsConnection => t(
      'Connect to the hub to create an account.',
      "Connettiti all'hub per creare un account.");
  static String get fillAllFields =>
      t('Fill in all fields.', 'Compila tutti i campi.');
  static String get edit => t('Edit', 'Modifica');
  static String get bill => t('Bill', 'Conto');

  // ---- content: venue feed ----
  static String get content => t('Content', 'Contenuti');
  static String get contentSub => t('Feed & storefront of the guest page',
      'Feed e vetrina della pagina ospiti');
  static String get feedTab => t('Feed', 'Feed');
  static String get storefrontTab => t('Storefront', 'Vetrina');
  static String get pasteSocialUrl => t(
      'Paste a post link (Instagram, Threads, X, Facebook)',
      'Incolla il link di un post (Instagram, Threads, X, Facebook)');
  static String get addPost => t('Add post', 'Aggiungi post');
  static String get feedEmptyTitle => t('No posts yet', 'Ancora nessun post');
  static String get feedEmptySub => t(
      'Paste a link above — guests see the feed on the menu page.',
      'Incolla un link qui sopra — gli ospiti vedono il feed nella pagina menu.');
  static String get pinnedLabel => t('Pinned', 'In evidenza');
  static String get hiddenLabel => t('Hidden', 'Nascosto');
  static String get pinAction => t('Pin', 'Fissa');
  static String get unpinAction => t('Unpin', 'Sblocca');
  static String get hideAction => t('Hide from guests', 'Nascondi agli ospiti');
  static String get unhideAction => t('Show to guests', 'Mostra agli ospiti');
  static String get deletePost => t('Delete post', 'Elimina post');
  static String get deletePostQ =>
      t('Delete this post?', 'Eliminare questo post?');
  static String get deletePostWarn => t(
      'The post disappears from the guest feed. The original on the social network is not touched.',
      'Il post sparisce dal feed degli ospiti. L\'originale sul social non viene toccato.');
  static String get copyLink => t('Copy link', 'Copia link');
  static String get linkCopied => t('Link copied', 'Link copiato');
  static String get postAdded =>
      t('Post added to the feed', 'Post aggiunto al feed');
  static String pinnedOfLimit(int n, int limit) =>
      t('$n of $limit pinned', '$n di $limit in evidenza');

  // ---- content: storefront editor ----
  static String get storefrontTitle => t('Storefront', 'Vetrina');
  static String get storefrontSub => t(
      'How the guest page looks — texts, colors, layout',
      'Come appare la pagina ospiti — testi, colori, layout');
  static String get themePresets => t('Theme presets', 'Temi pronti');
  static String get paletteSection => t('Palette', 'Palette');
  static String get generateFromAccent =>
      t('Generate from accent', 'Genera dall\'accento');
  static String get contrastWarning => t(
      'Low text/background contrast (below WCAG AA). Guests may struggle to read.',
      'Contrasto testo/sfondo basso (sotto WCAG AA). Gli ospiti potrebbero far fatica a leggere.');
  static String get livePreview => t('Live preview', 'Anteprima live');
  static String get venueTexts => t('Venue texts', 'Testi del locale');
  static String get venueNameLbl => t('Venue name', 'Nome del locale');
  static String get taglineEn => t('Tagline (EN)', 'Slogan (EN)');
  static String get taglineIt => t('Tagline (IT)', 'Slogan (IT)');
  static String get aboutEn => t('About (EN)', 'Chi siamo (EN)');
  static String get aboutIt => t('About (IT)', 'Chi siamo (IT)');
  static String get addressLbl => t('Address', 'Indirizzo');
  static String get addressEn => t('Address (EN)', 'Indirizzo (EN)');
  static String get addressItLbl => t('Address (IT)', 'Indirizzo (IT)');
  static String get hoursEn => t('Hours (EN)', 'Orari (EN)');
  static String get hoursIt => t('Hours (IT)', 'Orari (IT)');
  static String get mapsUrlLbl => t('Google Maps link', 'Link Google Maps');
  static String get badgesSection => t('Badges', 'Badge');
  static String badgeN(int n) => t('Badge $n', 'Badge $n');
  static String get badgeEnHint => t('English label', 'Testo inglese');
  static String get badgeItHint => t('Italian label', 'Testo italiano');
  static String get addBadge => t('+ badge', '+ badge');
  static String get blocksSection => t('Storefront blocks', 'Blocchi vetrina');
  static String get blocksHint => t(
      'Drag to reorder; switch off to hide from guests.',
      'Trascina per riordinare; spegni per nascondere agli ospiti.');
  static String blockName(String key) => switch (key) {
        'cover' => t('Cover photo', 'Foto copertina'),
        'facts' => t('Address & hours', 'Indirizzo e orari'),
        'badges' => t('Badges', 'Badge'),
        'cta' => t('Menu & service buttons', 'Pulsanti menu e servizio'),
        'popular' => t('Popular picks', 'Popolari'),
        'about' => t('About us', 'Chi siamo'),
        _ => key,
      };
  static String get imagesSection => t('Hero images', 'Immagini hero');
  static String get uploadLogo => t('Upload logo', 'Carica logo');
  static String get uploadCover => t('Upload cover', 'Carica copertina');
  static String get removeImage => t('Remove', 'Rimuovi');
  static String get pinnedLimitLbl =>
      t('Pinned posts limit', 'Limite post in evidenza');
  static String get saveStorefront => t('Save storefront', 'Salva vetrina');
  static String get storefrontSaved => t('Storefront saved', 'Vetrina salvata');
  static String get colorBg => t('Background', 'Sfondo');
  static String get colorCard => t('Cards', 'Schede');
  static String get colorInk => t('Text', 'Testo');
  static String get colorMut => t('Secondary text', 'Testo secondario');
  static String get colorLine => t('Lines', 'Linee');
  static String get colorAccent => t('Accent', 'Accento');
  static String get colorAccentDeep => t('Accent · deep', 'Accento · scuro');
  static String get colorAccentSoft => t('Accent · soft', 'Accento · chiaro');
  static String get invalidHex =>
      t('Use #RRGGBB, e.g. #C8821E', 'Usa #RRGGBB, es. #C8821E');

  // ---- coupons ----
  static String get coupons => t('Coupons', 'Coupon');
  static String get couponsSub => t('Issue, redeem and track guest coupons',
      'Emetti, riscatta e monitora i coupon');
  static String get issueTab => t('Issue', 'Emetti');
  static String get redeemTab => t('Redeem', 'Riscatta');
  static String get campaignsTab => t('Campaigns', 'Campagne');
  static String get issuePickCampaign =>
      t('Pick a campaign to issue', 'Scegli una campagna da emettere');
  static String get showQrToGuest => t(
      'Let the guest scan this QR with their phone camera',
      'Fai inquadrare questo QR con la fotocamera del telefono');
  static String get claimQrExpires =>
      t('The QR is valid for 6 hours', 'Il QR è valido per 6 ore');
  static String get noCampaigns =>
      t('No active campaigns', 'Nessuna campagna attiva');
  static String get noCampaignsSub => t(
      'Campaigns are created in the Campaigns tab (Content role).',
      'Le campagne si creano nella scheda Campagne (ruolo Contenuti).');
  static String get scanCouponQr =>
      t("Scan the guest's coupon QR", 'Inquadra il QR del coupon');
  static String get scannerUnavailable => t(
      'Camera unavailable — enter the code below.',
      'Fotocamera non disponibile — inserisci il codice qui sotto.');
  static String get couponCode => t('Coupon code', 'Codice coupon');
  static String get findCoupon => t('Find coupon', 'Cerca coupon');
  static String get redeemConfirmTitle =>
      t('Redeem this coupon?', 'Riscattare questo coupon?');
  static String get attachToOrder =>
      t('Apply to an open order', 'Applica a un ordine aperto');
  static String get noOrderAttach => t(
      'No order — just mark as used', 'Nessun ordine — segna solo come usato');
  static String get redeemAction => t('Redeem', 'Riscatta');
  static String get redeemed => t('Coupon redeemed', 'Coupon riscattato');
  static String get couponStActive => t('Active', 'Attivo');
  static String get couponStRedeemed => t('Used', 'Utilizzato');
  static String get couponStExpired => t('Expired', 'Scaduto');
  static String get couponStVoid => t('Void', 'Annullato');
  static String get newCampaign => t('New campaign', 'Nuova campagna');
  static String get editCampaign => t('Edit campaign', 'Modifica campagna');
  static String get campaignTitleEn => t('Title (EN)', 'Titolo (EN)');
  static String get campaignTitleIt => t('Title (IT)', 'Titolo (IT)');
  static String get campaignDescEn => t('Conditions (EN)', 'Condizioni (EN)');
  static String get campaignDescIt => t('Conditions (IT)', 'Condizioni (IT)');
  static String get discountTypeLbl => t('Discount type', 'Tipo di sconto');
  static String get discountPercent => t('Percent (%)', 'Percentuale (%)');
  static String get discountFixed => t('Fixed amount (€)', 'Importo fisso (€)');
  static String get discountValueLbl =>
      t('Discount value', 'Valore dello sconto');
  static String get perWalletLimitLbl =>
      t('Per-guest limit', 'Limite per ospite');
  static String get maxIssuesLbl => t(
      'Max coupons (empty = unlimited)', 'Coupon massimi (vuoto = illimitati)');
  static String get utmLbl => t('Default UTM tag', 'Tag UTM predefinito');
  static String get campaignActive => t('Active', 'Attiva');
  static String get campaignSaved => t('Campaign saved', 'Campagna salvata');
  static String issuedRedeemed(int issued, int redeemed) => t(
      '$issued issued · $redeemed redeemed',
      '$issued emessi · $redeemed riscattati');
  static String get byUtmTitle => t('By source (UTM)', 'Per fonte (UTM)');
  static String get directSource => t('(direct)', '(diretto)');
  static String get discountLine => t('Discount', 'Sconto');
  static String couponApplied(String code) => t('coupon $code', 'coupon $code');

  // ---- settings ----
  static String get settings => t('Settings', 'Impostazioni');
  static String get logout => t('Log out', 'Esci');
  static String get logoutConfirm => t(
      'Sign out and return to the login screen?',
      "Disconnettersi e tornare alla schermata di accesso?");
  static String get account => t('Account', 'Account');
  static String get currentStaff =>
      t('Current staff member', 'Membro del personale attuale');
  static String get role => t('Role', 'Ruolo');
  static String get language => t('Language', 'Lingua');
  static String get appearance => t('Appearance', 'Aspetto');
  static String get theme => t('Theme', 'Tema');
  static String get themeLight => t('Light', 'Chiaro');
  static String get themeDark => t('Dark', 'Scuro');
  static String get themeSystem => t('System', 'Sistema');
  static String get textSize => t('Text size', 'Dimensione testo');
  static String get sizeSmall => t('Small', 'Piccolo');
  static String get sizeNormal => t('Normal', 'Normale');
  static String get sizeLarge => t('Large', 'Grande');
  static String get display => t('Display', 'Schermo');
  static String get tablesPerRow => t('Tables per row', 'Tavoli per riga');
  static String get gestureHints => t('Gesture hints', 'Suggerimenti gesti');
  static String get hour24 => t('24-hour format', 'Formato 24 ore');
  static String get hapticsSound =>
      t('Haptics and sound', 'Vibrazione e suoni');
  static String get haptics => t('Haptics', 'Vibrazione');
  static String get sounds => t('Sounds', 'Suoni');
  static String get connection => t('Connection', 'Connessione');
  static String get statusLbl => t('Status', 'Stato');
  static String get connectingS => t('Connecting...', 'Connessione...');
  static String get connected => t('Connected', 'Connesso');
  static String get localMode => t('Local mode', 'Modalità locale');
  static String get server => t('Server', 'Server');
  static String get lastError => t('Last error', 'Ultimo errore');
  static String get reconnect => t('Reconnect', 'Riconnetti');
  static String get login => t('Login', 'Login');
  static String get password => t('Password', 'Password');
  static String get signIn => t('Sign in', 'Accedi');
  static String get dataSync => t('Data and sync', 'Dati e sincronizzazione');
  static String get simulateOffline =>
      t('Simulate offline (QA)', 'Simula offline (QA)');
  static String get pendingUpload => t('Pending upload', 'In attesa di invio');
  static String actionsCount(int n) => t('$n actions', '$n azioni');
  static String get resetDemo =>
      t('Reset to demo data', 'Ripristina dati demo');
  static String get resetData => t('Reset data', 'Ripristina dati');
  static String get resetWarn => t(
      'This will delete current changes and restore demo data. Continue?',
      'Le modifiche attuali saranno eliminate e i dati demo ripristinati. Continuare?');
  static String get reset => t('Reset', 'Ripristina');
  static String get aboutApp => t('About app', "Info sull'app");
  static String get version => t('Version', 'Versione');

  // ---- server chat / threads / tasks ----
  static String get chGeneral => t('General', 'Generale');
  static String get chKitchen => t('Kitchen', 'Cucina');
  static String get chBar => t('Bar', 'Bar');
  static String get chatConnectHint => t(
      'Connect to the hub to use the team chat.',
      "Connettiti all'hub per usare la chat del team.");
  static String get replyAction => t('Reply', 'Rispondi');
  static String get replyingTo => t('Replying to', 'In risposta a');
  static String viewReplies(int n) => t(
      n == 1 ? 'View 1 reply' : 'View $n replies',
      n == 1 ? 'Vedi 1 risposta' : 'Vedi $n risposte');
  static String get threadTitle => t('Thread', 'Discussione');
  static String get cafeBot => 'CafeBot';
  static String get loadOlder => t('Load older', 'Carica precedenti');
  static String get commandsTitle => t('Commands', 'Comandi');
  static String get cmdTaskHint =>
      t('/task title @name 21:30', '/task titolo @nome 21:30');
  static String get cmdTaskDesc => t('Create a task (name & time optional)',
      'Crea un compito (nome e orario facoltativi)');
  static String get cmdRemindHint =>
      t('/remind 21:30 text', '/remind 21:30 testo');
  static String get cmdRemindDesc =>
      t('The bot reminds at that time', 'Il bot ricorda a quell\'ora');
  static String get cmdDoneDesc => t('Reply under a task to complete it',
      'Rispondi sotto un compito per completarlo');
  static String get cmdOpenDesc =>
      t("List today's open tasks", 'Elenca i compiti aperti di oggi');
  static String get cmdCloseDesc => t('Post the closing checklist now',
      'Pubblica ora la checklist di chiusura');
  static String get taskDone => t('Done', 'Fatto');
  static String doneBy(String name) => t('Done · $name', 'Fatto · $name');
  static String get anyoneOnShift =>
      t('Anyone on shift', 'Chiunque in servizio');
  static String dueAtShort(String hhmm) => t('due $hhmm', 'entro $hhmm');
  static String get overdueTag => t('OVERDUE', 'IN RITARDO');
  static String get takeTask => t('Take', 'Prendi');
  static String get leaveTask => t('Leave', 'Lascia');
  static String get completeTask => t('Complete', 'Completa');
  static String get availableTasks => t('Available', 'Disponibili');

  // ---- planner ----
  static String get planner => t('Planner', 'Agenda');
  static String get plannerSub => t(
      "The day's tasks — chat and planner share them",
      'I compiti del giorno — chat e agenda condivisi');
  static String get myTasks => t('My tasks', 'I miei compiti');
  static String get sectionOverdue => t('Overdue', 'In ritardo');
  static String get sectionDone => t('Done', 'Fatti');
  static String get quickAddHint =>
      t('Add: title @name 21:30', 'Aggiungi: titolo @nome 21:30');
  static String get plannerEmpty => t(
      'Nothing planned for this day', 'Niente in programma per questo giorno');
  static String get openThread => t('Open thread', 'Apri discussione');
  static String checklistProgress(String name, int done, int total) =>
      '$name $done/$total';
  static String get catOpening => t('Opening', 'Apertura');
  static String get catClosing => t('Closing', 'Chiusura');
  static String get catCleaning => t('Cleaning', 'Pulizie');
  static String get catInventory => t('Inventory', 'Inventario');
  static String get catService => t('Service', 'Servizio');
  static String get catOther => t('Other', 'Altro');
  static String taskCategoryLabel(String wire) => switch (wire) {
        'opening' => catOpening,
        'closing' => catClosing,
        'cleaning' => catCleaning,
        'inventory' => catInventory,
        'service' => catService,
        _ => catOther,
      };

  // ---- alerts / shift ----
  static String get onShift => t('On shift', 'In servizio');
  static String get offShift => t('Off shift', 'Fuori servizio');
  static String get shiftHint => t('Alerts fire only while you are on shift.',
      'Gli avvisi suonano solo mentre sei in servizio.');
  static String get alertsSection => t('Alerts', 'Avvisi');
  static String get quietMode => t('Quiet mode', 'Modalità silenziosa');
  static String get quietModeHint => t(
      'Banners stay, sounds and vibration stop on this device.',
      'I banner restano, suoni e vibrazione si fermano su questo dispositivo.');
  static String get alertVolume => t('Alert volume', 'Volume avvisi');
  static String get accept => t('Accept', 'Prendo io');
  static String get escalatedTag => t('UNANSWERED', 'SENZA RISPOSTA');
  static String get stationMode => t('Station mode', 'Modalità postazione');
  static String get stationModeHint => t(
      'Dark idle clock for a counter tablet; glows on alerts.',
      'Orologio scuro per il tablet al banco; si illumina sugli avvisi.');
  static String get tapToOpen => t('Tap to open', 'Tocca per aprire');
  static String get pushMatrixTitle =>
      t('Background notifications', 'Notifiche in background');
  static String get pushMatrixBody => t(
      'Android (Chrome): full delivery, even locked. iPhone/iPad: iOS 16.4+ '
          'AND the app added to the Home Screen; no vibration on iOS. '
          'Desktop: while the browser runs.',
      'Android (Chrome): consegna completa, anche bloccato. iPhone/iPad: '
          'iOS 16.4+ E app aggiunta alla schermata Home; niente vibrazione su '
          'iOS. Desktop: col browser aperto.');
  static String get pushDisabledHint => t(
      'Server push keys are not configured — alerts work only while the app is open.',
      'Chiavi push del server non configurate — gli avvisi funzionano solo con l\'app aperta.');

  // ---- misc / shared ----
  static String get offlineBanner => t('Offline · orders will be saved locally',
      'Offline · gli ordini saranno salvati localmente');
  static String get acknowledge => t('Acknowledge', 'Preso in carico');
  static String get guestCalling =>
      t('Guest is calling a waiter', 'Un ospite chiama il cameriere');
  static String get guestBill =>
      t('Guest asks for the bill', "Un ospite chiede il conto");
  static String get guestSeated =>
      t('Guest seated at table', 'Ospite seduto al tavolo');
  static String get guestSignal => t('Guest signal', "Segnale dell'ospite");
  static String get close => t('Close', 'Chiudi');
}
