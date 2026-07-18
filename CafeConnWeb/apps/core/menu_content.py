"""Conservative starter copy for the Sissi menu.

This is deliberately *not* a source of legal allergen declarations. It gives
the guest menu useful, reviewable information until the venue confirms every
recipe and supplier label. Entries are tagged ``allergen_review`` so staff can
find and replace inferred values without guessing.
"""

ALLERGEN_REVIEW_TAG = "allergen_review"


def _contains(name, *words):
    lowered = name.lower()
    return any(word in lowered for word in words)


def menu_content(name, category):
    """Return Italian guest copy and *indicative* EU-style allergen labels."""
    allergens = set()
    name_l = name.lower()

    if category == "Caffetteria":
        description = "Preparazione espressa al banco."
        composition = "Chiedi allo staff per latte, varianti e disponibilità."
        if _contains(name, "capp", "latte", "macchi", "panna", "cioccolata", "flat white"):
            allergens.add("Latte")
        if _contains(name, "orzo"):
            allergens.add("Glutine")
    elif category in {"Bevande", "Analcolici"}:
        description = "Bevanda servita fredda, salvo diversa indicazione."
        composition = "Chiedi allo staff per ingredienti, zuccheri e varianti."
        if _contains(name, "milkshake"):
            allergens.add("Latte")
    elif category == "Birra":
        description = "Birra selezionata servita fresca."
        composition = "Formato come indicato nel nome."
        allergens.add("Glutine")
    elif category == "Vino":
        description = "Vino selezionato del territorio e non solo."
        composition = "Calice o bottiglia, come indicato nel nome."
        allergens.add("Solfiti")
    elif category in {"Cocktail & Aperitivi", "Liquori/Grappe/Amari"}:
        description = "Preparato al momento dal bar."
        composition = "Chiedi al bartender per ricetta, gradazione e varianti."
        if _contains(name, "spritz", "negr", "martini", "vino", "prosecco", "mimosa"):
            allergens.add("Solfiti")
    elif category in {"Pasticceria", "Dolci", "Gelati"}:
        description = "Dolce della selezione Sissi."
        composition = "Chiedi allo staff per gusti, farciture e disponibilità del giorno."
        allergens.update({"Glutine", "Uova", "Latte"})
        if _contains(name, "nutella", "nocciola", "carote"):
            allergens.add("Frutta a guscio")
    elif category in {"Panini", "Piadine", "Toast"}:
        description = "Preparato espresso con ingredienti selezionati."
        composition = "Chiedi allo staff per ingredienti, sostituzioni e disponibilità."
        allergens.update({"Glutine", "Latte"})
        if _contains(name, "tonno", "salmone"):
            allergens.add("Pesce")
        if _contains(name, "uova", "maionese", "tartara"):
            allergens.add("Uova")
        if _contains(name, "noci"):
            allergens.add("Frutta a guscio")
    elif category in {"Tortel", "Secondi", "Uova/colazione salata", "Fritti/stuzzichini"}:
        description = "Piatto preparato al momento dalla cucina."
        composition = "Chiedi allo staff per ingredienti, contorni e disponibilità."
        if category != "Fritti/stuzzichini" or "patatine" not in name_l:
            allergens.add("Glutine")
        if _contains(name, "uova", "omelette", "bacon"):
            allergens.add("Uova")
        if _contains(name, "formaggio", "fontina", "caprese"):
            allergens.add("Latte")
    else:
        description = "Proposta della selezione Sissi."
        composition = "Chiedi allo staff per ingredienti e disponibilità."

    if _contains(name, "acqua", "bicchiere h2o"):
        allergens.clear()
        description = "Acqua minerale servita fresca."
        composition = "Naturale o frizzante, come indicato."

    return {
        "description": description,
        "composition": composition,
        "allergens": sorted(allergens),
    }
