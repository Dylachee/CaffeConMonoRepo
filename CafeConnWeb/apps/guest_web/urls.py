from django.urls import path

from apps.guest_web import views

app_name = "guest_web"

urlpatterns = [
    path("", views.menu_page, name="menu"),
    path("t/<int:table_id>/", views.menu_page, name="menu-for-table"),
    path("n/<int:table_number>/", views.menu_page, name="menu-for-table-number"),
    path("order/", views.create_guest_order, name="create-order"),
    path("order/<int:order_id>/status/", views.guest_order_status, name="order-status"),
    path("attention/", views.create_attention_signal, name="create-attention"),
    path("attention/cancel/", views.cancel_attention_signal, name="cancel-attention"),
    path("prototype/", views.prototype_page, name="prototype"),
]
