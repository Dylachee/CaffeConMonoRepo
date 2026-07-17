"""Built-in storefront theme presets.

Curated, harmonious palettes the storefront editor offers as one-tap starting
points. "sissi" is the canonical default — it MUST stay byte-identical to the
values shipped in VenueSettings' field defaults (and originally hardcoded in
menu.html), because "zero configuration renders pixel-identical" is an
acceptance criterion.

Keys mirror the guest page CSS variables:
    bg, card, ink, mut, line, accent, accent_deep, accent_soft
"""

SISSI_PALETTE = {
    "bg": "#f2efe8",
    "card": "#ffffff",
    "ink": "#1e1b16",
    "mut": "#8b8377",
    "line": "#e7e2d8",
    "accent": "#c8821e",
    "accent_deep": "#9a6310",
    "accent_soft": "#f1e2c8",
}

THEME_PRESETS = [
    {
        "key": "sissi",
        "name": "Sissi",
        "name_it": "Sissi",
        "palette": SISSI_PALETTE,
    },
    {
        "key": "cafe",
        "name": "Morning café",
        "name_it": "Caffè del mattino",
        "palette": {
            "bg": "#f5f1ea",
            "card": "#ffffff",
            "ink": "#2b211a",
            "mut": "#95897b",
            "line": "#e9e1d4",
            "accent": "#8c5a3c",
            "accent_deep": "#6b422a",
            "accent_soft": "#efe0d3",
        },
    },
    {
        "key": "night-bar",
        "name": "Night bar",
        "name_it": "Bar di sera",
        "palette": {
            "bg": "#16151a",
            "card": "#211f27",
            "ink": "#f2eee9",
            "mut": "#9b93a6",
            "line": "#332f3c",
            "accent": "#d9a441",
            "accent_deep": "#b4832a",
            "accent_soft": "#3a3040",
        },
    },
    {
        "key": "patisserie",
        "name": "Patisserie",
        "name_it": "Pasticceria",
        "palette": {
            "bg": "#faf3f1",
            "card": "#ffffff",
            "ink": "#33222a",
            "mut": "#a08b93",
            "line": "#f0e2e2",
            "accent": "#c96f8e",
            "accent_deep": "#a34e6f",
            "accent_soft": "#f6dfe6",
        },
    },
    {
        "key": "wine-bar",
        "name": "Wine bar",
        "name_it": "Enoteca",
        "palette": {
            "bg": "#f4efe9",
            "card": "#fffdf9",
            "ink": "#2c1a1c",
            "mut": "#93807c",
            "line": "#e8ddd4",
            "accent": "#8e3b46",
            "accent_deep": "#6c2a34",
            "accent_soft": "#efdcd8",
        },
    },
    {
        "key": "garden",
        "name": "Garden terrace",
        "name_it": "Terrazza verde",
        "palette": {
            "bg": "#f1f4ec",
            "card": "#ffffff",
            "ink": "#1f2418",
            "mut": "#88917b",
            "line": "#e0e6d6",
            "accent": "#5d7f3f",
            "accent_deep": "#465f2f",
            "accent_soft": "#e2ead4",
        },
    },
    {
        "key": "riviera",
        "name": "Riviera blue",
        "name_it": "Riviera blu",
        "palette": {
            "bg": "#eef2f4",
            "card": "#ffffff",
            "ink": "#182028",
            "mut": "#7f8d99",
            "line": "#dde5ea",
            "accent": "#2f6f96",
            "accent_deep": "#215471",
            "accent_soft": "#d8e6ee",
        },
    },
]


def preset_by_key(key: str) -> dict | None:
    for preset in THEME_PRESETS:
        if preset["key"] == key:
            return preset
    return None
