"""Seed the Opening and Closing checklists (manager-editable afterwards) and
default post/deadline times on the default VenueSettings row."""

import datetime

from django.db import migrations

CHECKLISTS = [
    {
        "key": "opening",
        "title": "Opening checklist",
        "title_it": "Checklist di apertura",
        "task_category": "opening",
        "items": [
            ("Turn on coffee machine & grinder", "Accendi macchina caffè e macinino"),
            ("Stock the bar fridge", "Rifornisci il frigo del bar"),
            ("Set the terrace tables", "Prepara i tavoli in terrazza"),
            ("Check the till float", "Controlla il fondo cassa"),
            ("Pastry display filled & labelled", "Vetrina dolci piena ed etichettata"),
            ("Menu boards & lights on", "Lavagne menu e luci accese"),
        ],
    },
    {
        "key": "closing",
        "title": "Closing checklist",
        "title_it": "Checklist di chiusura",
        "task_category": "closing",
        "items": [
            ("Clean the espresso machine group", "Pulisci il gruppo della macchina"),
            ("Empty & wipe the bar fridges", "Svuota e pulisci i frigo del bar"),
            ("Stack terrace furniture & lock up", "Impila i mobili in terrazza e chiudi"),
            ("Cash up & store the till float", "Conta la cassa e riponi il fondo"),
            ("Floors mopped, bins out", "Pavimenti lavati, rifiuti fuori"),
        ],
    },
]


def seed(apps, schema_editor):
    ChecklistTemplate = apps.get_model("core", "ChecklistTemplate")
    ChecklistItem = apps.get_model("core", "ChecklistItem")
    VenueSettings = apps.get_model("core", "VenueSettings")

    for spec in CHECKLISTS:
        template, created = ChecklistTemplate.objects.get_or_create(
            key=spec["key"],
            defaults={
                "title": spec["title"],
                "title_it": spec["title_it"],
                "task_category": spec["task_category"],
            },
        )
        if created:
            for order, (text, text_it) in enumerate(spec["items"]):
                ChecklistItem.objects.create(
                    template=template, text=text, text_it=text_it, sort_order=order
                )

    VenueSettings.objects.filter(
        slug="default", opening_checklist_time__isnull=True
    ).update(
        opening_checklist_time=datetime.time(8, 0),
        opening_checklist_deadline=datetime.time(10, 0),
        closing_checklist_time=datetime.time(21, 30),
        closing_checklist_deadline=datetime.time(23, 0),
    )


def unseed(apps, schema_editor):
    ChecklistTemplate = apps.get_model("core", "ChecklistTemplate")
    ChecklistTemplate.objects.filter(key__in=["opening", "closing"]).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0032_chat_tasks_checklists"),
    ]

    operations = [
        migrations.RunPython(seed, unseed),
    ]
