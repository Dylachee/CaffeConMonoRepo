from django.urls import path

from apps.guest_web import views

app_name = "guest_web"

urlpatterns = [
    path("", views.menu_page, name="menu"),
    path("order/", views.create_guest_order, name="create-order"),
    path("attention/", views.create_attention_signal, name="create-attention"),
    path("prototype/", views.prototype_page, name="prototype"),
]
