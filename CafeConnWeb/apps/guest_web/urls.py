from django.urls import path

from apps.guest_web import views, views_feed, views_wallet

app_name = "guest_web"

urlpatterns = [
    path("", views.menu_page, name="menu"),
    path("t/<int:table_id>/", views.menu_page, name="menu-for-table"),
    path("n/<int:table_number>/", views.menu_page, name="menu-for-table-number"),
    path("qr/n/<int:table_number>.svg", views.table_qr_svg, name="table-qr-svg"),
    path("qr/n/<int:table_number>/print/", views.table_qr_print, name="table-qr-print"),
    path("feed/", views_feed.feed_posts, name="feed"),
    path("wallet/", views_wallet.wallet_state, name="wallet"),
    path("wallet/claim/", views_wallet.claim_coupon_view, name="wallet-claim"),
    path("wallet/recover/<str:token>/", views_wallet.recover_wallet, name="wallet-recover"),
    path("order/", views.create_guest_order, name="create-order"),
    path("order/<int:order_id>/status/", views.guest_order_status, name="order-status"),
    path("attention/", views.create_attention_signal, name="create-attention"),
    path("attention/cancel/", views.cancel_attention_signal, name="cancel-attention"),
    path("prototype/", views.prototype_page, name="prototype"),
]
