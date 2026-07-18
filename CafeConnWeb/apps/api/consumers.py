from channels.generic.websocket import AsyncJsonWebsocketConsumer


class StaffConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        user = self.scope.get("user")
        restaurant = self.scope.get("restaurant")
        if not user or user.is_anonymous or not restaurant:
            await self.close(code=4403 if user and not user.is_anonymous else 4401)
            return

        self.group_name = f"restaurant.{restaurant['id']}.staff"
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()
        await self.send_json({
            "event": "connection.ready",
            "channel": self.group_name,
            "restaurant": restaurant,
        })

    async def disconnect(self, close_code):
        if hasattr(self, "group_name"):
            await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def order_event(self, event):
        await self.send_json(event["payload"])

    async def attention_event(self, event):
        await self.send_json(event["payload"])

    async def table_event(self, event):
        await self.send_json(event["payload"])

    async def chat_event(self, event):
        # Chat messages, task bubbles and task status changes.
        await self.send_json(event["payload"])
