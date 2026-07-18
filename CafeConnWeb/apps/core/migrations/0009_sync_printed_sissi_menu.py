from decimal import Decimal

from django.db import migrations


PRINTED_MENU = [
    # Colazione
    ("Croissant o Krapfen crema", "Colazione", "bar", "Croissant o krapfen alla crema.", "2.50"),
    ("Croissant o Krapfen marmellata", "Colazione", "bar", "Croissant o krapfen alla marmellata.", "2.50"),
    ("Croissant o Krapfen pistacchio", "Colazione", "bar", "Croissant o krapfen al pistacchio.", "2.50"),
    ("Croissant vegano", "Colazione", "bar", "Croissant vegano.", "3.00"),
    ("Biscotto Occhio di Bue", "Colazione", "bar", "Biscotto occhio di bue.", "3.00"),
    ("Banana bread", "Colazione", "bar", "Banana bread.", "3.70"),
    ("Crepe con nutella o miele", "Colazione", "bar", "Crepe con nutella o miele.", "7.00"),
    ("Crostata cocco e frutti rossi", "Colazione", "bar", "Crostata cocco e frutti rossi.", "7.30"),
    ("Toast classico cotto formaggio", "Colazione", "bar", "Toast classico con cotto e formaggio.", "7.00"),
    ("Baby toast", "Colazione", "bar", "Baby toast.", "6.00"),
    ("Omelette cotto formaggio", "Colazione", "kitchen", "Omelette con cotto e formaggio.", "13.00"),
    ("Pan carre toscano", "Colazione", "kitchen", "Pan carre toscano.", "13.00"),
    ("Avocado toast", "Colazione", "kitchen", "Avocado toast.", "8.00"),
    ("Uovo all'occhio di bue bacon e pan carre tostato", "Colazione", "kitchen", "Uovo all'occhio di bue con bacon e pan carre tostato.", "13.00"),
    # Analcolici
    ("Crodino/San bitter", "Analcolici", "bar", "Aperitivo analcolico.", "6.00"),
    ("Lunisia assenzio e genziana", "Analcolici", "bar", "Analcolico con assenzio e genziana.", "6.00"),
    ("Succo di pomodoro condito", "Analcolici", "bar", "Succo di pomodoro condito.", "6.00"),
    ("Analcolici Sissi", "Analcolici", "bar", "Analcolico della casa.", "8.00"),
    # Aperitivi
    ("Aperol Spritz", "Aperitivi", "bar", "Aperol spritz.", "8.00"),
    ("Limoncello Spritz", "Aperitivi", "bar", "Limoncello spritz.", "10.00"),
    ("Campari Soda", "Aperitivi", "bar", "Campari soda.", "4.00"),
    ("Americano-Negroni", "Aperitivi", "bar", "Americano o Negroni.", "10.00"),
    ("Negroni Sbagliato-Negrosky", "Aperitivi", "bar", "Negroni sbagliato o Negrosky.", "10.00"),
    ("Daiquiri", "Aperitivi", "bar", "Daiquiri.", "10.00"),
    ("Campari Shakerato", "Aperitivi", "bar", "Campari shakerato.", "7.00"),
    # Cocktails
    ("Bloody Mary", "Cocktails", "bar", "Bloody Mary.", "7.00"),
    ("Moscow Mule", "Cocktails", "bar", "Moscow Mule.", "10.00"),
    ("Margarita", "Cocktails", "bar", "Margarita.", "10.00"),
    ("Caipirinha", "Cocktails", "bar", "Caipirinha.", "10.00"),
    ("Cosmopolitan", "Cocktails", "bar", "Cosmopolitan.", "10.00"),
    ("Cuba Libre", "Cocktails", "bar", "Cuba Libre.", "10.00"),
    ("Sex on the Beach", "Cocktails", "bar", "Sex on the Beach.", "10.00"),
    ("Long Island Iced Tea", "Cocktails", "bar", "Long Island Iced Tea.", "13.00"),
    ("Sissi Club Base Cocktail", "Cocktails", "bar", "Cocktail base Sissi Club.", "12.00"),
    ("Vodka Tonic", "Cocktails", "bar", "Vodka tonic.", "12.00"),
    ("Classic Cocktails", "Cocktails", "bar", "Cocktail classico.", "12.00"),
    ("Gin Tonic Base Bombay", "Cocktails", "bar", "Gin tonic base Bombay.", "14.00"),
    # Da stuzzicare
    ("Patatine fritte", "Da stuzzicare", "kitchen", "Patatine fritte.", "5.50"),
    ("Sticks di polenta, rosti di patate, speck, lardo, miele, formaggio e noci", "Da stuzzicare", "kitchen", "Sticks di polenta, rosti di patate, speck, lardo, miele, formaggio e noci.", "25.00"),
    # Cucina
    ("Tortel di patate con la caprese", "Cucina", "kitchen", "Tortel di patate con la caprese.", "14.00"),
    ("Tortel di patate con lardo e miele", "Cucina", "kitchen", "Tortel di patate con lardo e miele.", "16.00"),
    ("Tortel di patate con speck e formaggio", "Cucina", "kitchen", "Tortel di patate con speck e formaggio.", "16.00"),
    ("Tortel di patate con salsiccia", "Cucina", "kitchen", "Tortel di patate con salsiccia.", "16.00"),
    ("Canederli allo speck", "Cucina", "kitchen", "Canederli allo speck.", "14.00"),
    ("Cotoletta con patatine fritte", "Cucina", "kitchen", "Cotoletta con patatine fritte.", "16.00"),
    # Panini
    ("Bocconcino Sissi", "Panini", "kitchen", "Wurstel, ketchup e cipolla caramellata.", "12.00"),
    ("Hot Dog Amalia", "Panini", "kitchen", "Wurstel, senape e crauti.", "12.00"),
    ("Maxi Toast", "Panini", "kitchen", "Cotto, formaggio, insalata, salsa tonnata e cipolla fritta.", "12.00"),
    ("Rendena", "Panini", "kitchen", "Speck, formaggio Casolet e salsa yogurt.", "8.50"),
    ("Snowboard", "Panini", "kitchen", "Cotoletta, maionese, pomodoro, insalata e salsa BBQ.", "13.00"),
    ("Vegetariano", "Panini", "kitchen", "Mozzarella e pomodoro.", "8.00"),
    ("Burgerini Sissi", "Panini", "kitchen", "Burger bun, hamburger di manzo, cheddar, pomodoro, insalata e salsa.", "14.00"),
    ("Hamburger vegetariano", "Panini", "kitchen", "Burger bun, burger ai vegetali grigliate e scamorza, pomodoro, insalata e cipolla fritta.", "14.00"),
    ("Sissi Club Sandwich", "Panini", "kitchen", "Cotto, pomodoro, maionese e insalata.", "7.00"),
    ("Toast vegetariano", "Panini", "kitchen", "Formaggio, pomodoro e insalata.", "8.00"),
    ("Piadina cotto", "Panini", "kitchen", "Formaggio, pomodoro e insalata.", "8.00"),
    ("Smile Toast Sandwich", "Panini", "kitchen", "Toast sandwich Sissi.", "12.50"),
    ("Piadina speck", "Panini", "kitchen", "Brie, miele, noci e rucola.", "8.80"),
    # Dolci
    ("Crostata del giorno", "Dolci", "bar", "Crostata del giorno.", "5.00"),
    ("Strudel di mele", "Dolci", "bar", "Strudel di mele.", "3.50"),
    ("Sacher con panna", "Dolci", "bar", "Sacher con panna.", "6.50"),
    ("Torta di carote con la panna", "Dolci", "bar", "Torta di carote con la panna.", "6.50"),
    ("Pallina di gelato", "Dolci", "bar", "Pallina di gelato.", "2.50"),
    ("Cheesecake Sissi", "Dolci", "bar", "Cheesecake Sissi.", "7.00"),
    ("Crepes con Nutella", "Dolci", "bar", "Crepes con Nutella.", "7.00"),
    # Caffetteria
    ("Espresso", "Caffetteria", "bar", "Espresso.", "1.50"),
    ("Americano", "Caffetteria", "bar", "Americano.", "2.00"),
    ("Decaffeinato", "Caffetteria", "bar", "Decaffeinato.", "2.00"),
    ("Macchiato", "Caffetteria", "bar", "Macchiato.", "2.00"),
    ("Caffe con panna", "Caffetteria", "bar", "Caffe con panna.", "2.50"),
    ("Mocaccino", "Caffetteria", "bar", "Mocaccino.", "3.00"),
    ("Cappuccino", "Caffetteria", "bar", "Cappuccino.", "2.00"),
    ("Cappuccino con miele e cannella", "Caffetteria", "bar", "Cappuccino con miele e cannella.", "3.00"),
    ("Latte Macchiato", "Caffetteria", "bar", "Latte macchiato.", "3.50"),
    ("Muggaccino", "Caffetteria", "bar", "Muggaccino.", "3.50"),
    ("Punch", "Caffetteria", "bar", "Punch.", "5.00"),
    ("Ginseng", "Caffetteria", "bar", "Ginseng.", "2.50"),
    ("Cioccolata calda con panna", "Caffetteria", "bar", "Cioccolata calda con panna.", "5.00"),
    ("Flat White", "Caffetteria", "bar", "Flat white.", "3.50"),
    ("The e tisane", "Caffetteria", "bar", "The e tisane.", "3.50"),
    # Bibite
    ("Acqua 0,5", "Bibite", "bar", "Acqua 0,5 l.", "2.50"),
    ("Spremuta", "Bibite", "bar", "Spremuta.", "4.00"),
    ("The freddo", "Bibite", "bar", "The freddo.", "4.00"),
    ("Coca Cola", "Bibite", "bar", "Coca Cola.", "4.00"),
    ("Coca Cola Zero", "Bibite", "bar", "Coca Cola Zero.", "4.00"),
    ("Limonata/Aranciata", "Bibite", "bar", "Limonata o aranciata.", "4.50"),
    ("Schweppes", "Bibite", "bar", "Schweppes.", "4.50"),
    ("Tonica Galvanina", "Bibite", "bar", "Tonica Galvanina.", "4.50"),
    ("Crodino", "Bibite", "bar", "Crodino.", "4.50"),
    ("Ginger Beer", "Bibite", "bar", "Ginger beer.", "4.50"),
    ("Succo di frutta", "Bibite", "bar", "Succo di frutta.", "4.50"),
    ("Red Bull", "Bibite", "bar", "Red Bull.", "5.00"),
    ("Sissi Club Mate", "Bibite", "bar", "Sissi Club Mate.", "6.50"),
    # Birra
    ("Konigburg alla spina 0,25 l", "Birra", "bar", "Birra Konigburg alla spina 0,25 l.", "4.00"),
    ("Konigburg alla spina 0,5 l", "Birra", "bar", "Birra Konigburg alla spina 0,5 l.", "7.00"),
    ("Poretti 1664 blanche", "Birra", "bar", "Poretti 1664 blanche.", "5.00"),
    ("Peroni Gran Riserva", "Birra", "bar", "Peroni Gran Riserva.", "5.00"),
    ("Doppio Malto 0,5 l", "Birra", "bar", "Doppio malto 0,5 l.", "7.50"),
    # Vino
    ("Pinot Grigio", "Vino al calice e bottiglie", "bar", "Vino al calice.", "6.00"),
    ("Sauvignon", "Vino al calice e bottiglie", "bar", "Vino al calice.", "6.00"),
    ("Gewurztraminer", "Vino al calice e bottiglie", "bar", "Vino al calice.", "6.00"),
    ("Ribolla Gialla", "Vino al calice e bottiglie", "bar", "Vino al calice.", "6.00"),
    ("Marzemino", "Vino al calice e bottiglie", "bar", "Vino al calice.", "6.00"),
    ("Lagrein", "Vino al calice e bottiglie", "bar", "Vino al calice.", "6.50"),
    ("Prosecco Valdobbiadene", "Vino al calice e bottiglie", "bar", "Prosecco Valdobbiadene.", "5.00"),
    ("Trento DOC", "Vino al calice e bottiglie", "bar", "Trento DOC.", "8.00"),
    # Grappe e liquori
    ("Grappa barricata", "Grappe e liquori", "bar", "Grappa barricata.", "6.00"),
    ("Amari", "Grappe e liquori", "bar", "Amari.", "6.00"),
]

POPULAR = {
    "Aperol Spritz",
    "Cappuccino",
    "Cotoletta con patatine fritte",
    "Burgerini Sissi",
    "Strudel di mele",
}


def infer_allergens(name, description, category):
    text = f"{name} {description}".lower()
    allergens = []
    if any(word in text for word in ["latte", "formaggio", "mozzarella", "panna", "cappuccino", "cioccolata", "cheesecake", "gelato", "milk"]):
        allergens.append("Milk")
    if any(word in text for word in ["croissant", "krapfen", "toast", "crepe", "tortel", "canederli", "cotoletta", "burger", "hamburger", "sandwich", "piadina", "strudel", "sacher", "crostata", "birra"]):
        allergens.append("Gluten")
    if any(word in text for word in ["uovo", "omelette", "crema", "maionese", "sacher", "torta"]):
        allergens.append("Eggs")
    if any(word in text for word in ["noci", "nutella", "pistacchio"]):
        allergens.append("Nuts")
    if "senape" in text:
        allergens.append("Mustard")
    if category == "Vino al calice e bottiglie":
        allergens.append("Sulphites")
    return allergens


def default_prep(category):
    if category in {"Cucina", "Panini", "Da stuzzicare", "Colazione"}:
        return 12
    if category == "Dolci":
        return 7
    return 5


def default_portion(category):
    if category in {"Caffetteria", "Bibite", "Birra", "Aperitivi", "Cocktails", "Analcolici", "Vino al calice e bottiglie", "Grappe e liquori"}:
        return "150-250 ml"
    if category == "Dolci":
        return "1 portion"
    return "1 plate"


def sync_printed_menu(apps, schema_editor):
    MenuItem = apps.get_model("core", "MenuItem")
    names = [item[0] for item in PRINTED_MENU]
    MenuItem.objects.exclude(name__in=names).update(is_available=False, is_promoted=False)

    for name, category, station, description, price in PRINTED_MENU:
        tags = ["popular"] if name in POPULAR else []
        defaults = {
            "description": description,
            "price": Decimal(price),
            "category": category,
            "station": station,
            "tags": tags,
            "composition": description,
            "allergens": infer_allergens(name, description, category),
            "is_available": True,
            "is_promoted": False,
            "preparation_minutes": default_prep(category),
            "portion_weight": default_portion(category),
            "calories": None,
            "image_url": "",
        }
        existing = MenuItem.objects.filter(name=name).order_by("id").first()
        if existing:
            for field, value in defaults.items():
                setattr(existing, field, value)
            existing.save()
        else:
            MenuItem.objects.create(name=name, **defaults)


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0008_ensure_django_admin_superuser"),
    ]

    operations = [
        migrations.RunPython(sync_printed_menu, migrations.RunPython.noop),
    ]
