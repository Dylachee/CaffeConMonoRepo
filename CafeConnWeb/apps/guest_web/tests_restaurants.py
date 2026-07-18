from django.test import TestCase

from apps.core.models import Restaurant, Table


class RestaurantGuestRoutingTests(TestCase):
    def setUp(self):
        self.alpha = Restaurant.objects.create(name="Alpha Cafe", slug="alpha")
        self.beta = Restaurant.objects.create(name="Beta Bar", slug="beta")
        Table.objects.create(restaurant=self.alpha, number=1)

    def test_root_and_legacy_table_link_show_restaurant_chooser(self):
        self.assertContains(self.client.get("/"), "Alpha Cafe")
        response = self.client.get("/menu/n/1/")
        self.assertContains(response, "/r/alpha/n/1/")
        self.assertContains(response, "/r/beta/n/1/")

    def test_missing_table_opens_general_restaurant_page_with_direction(self):
        response = self.client.get("/r/beta/n/1/")
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "This table is not available")

    def test_old_slug_redirects_to_canonical_url(self):
        self.alpha.legacy_slugs = ["old-alpha"]
        self.alpha.save(update_fields=["legacy_slugs"])
        response = self.client.get("/r/old-alpha/n/1/")
        self.assertRedirects(response, "/r/alpha/n/1/", fetch_redirect_response=False)

    def test_table_qr_supports_inline_download_and_print(self):
        inline = self.client.get("/r/alpha/qr/n/1.svg")
        self.assertEqual(inline.status_code, 200)
        self.assertEqual(inline["Content-Type"], "image/svg+xml")
        download = self.client.get("/r/alpha/qr/n/1.svg?download=1")
        self.assertIn("attachment", download["Content-Disposition"])
        self.assertContains(self.client.get("/r/alpha/qr/n/1/print/"), "Print QR")
