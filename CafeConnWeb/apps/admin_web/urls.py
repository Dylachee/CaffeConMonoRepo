from django.urls import path

from apps.admin_web import views

app_name = "admin_web"

urlpatterns = [
    path("", views.dashboard, name="dashboard"),
    path("orders/<int:order_id>/status/", views.update_order_status, name="update-order-status"),
    path("menu/<int:item_id>/toggle/", views.toggle_menu_item, name="toggle-menu-item"),
    path("menu/create/", views.create_menu_item, name="create-menu-item"),
    path("attention/<int:signal_id>/ack/", views.ack_attention_signal, name="ack-attention"),
    path("prototype/", views.prototype_page, name="prototype"),
]
