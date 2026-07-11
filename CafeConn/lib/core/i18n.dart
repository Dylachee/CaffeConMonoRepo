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
  static String get pinPopular =>
      t('Add to Popular', 'Aggiungi ai Popolari');
  static String get unpinPopular =>
      t('Remove from Popular', 'Rimuovi dai Popolari');
  static String get popularEmpty => t(
      'No pinned items yet. Hold any item to pin it here.',
      'Nessun preferito. Tieni premuto un piatto per aggiungerlo qui.');
  static String get dishDetails => t('Details', 'Dettagli');

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
  static String itemsCount(int n) => t('$n items', '$n articoli');
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
