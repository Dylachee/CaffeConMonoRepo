from channels.generic.websocket import AsyncJsonWebsocketConsumer


class StaffConsumer(AsyncJsonWebsocketConsumer):
    group_name = "staff"

    async def connect(self):
        user = self.scope.get("user")
        if not user or user.is_anonymous:
            await self.close(code=4401)
            return

        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()
        await self.send_json({"event": "connection.ready", "channel": self.group_name})

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def order_event(self, event):
        await self.send_json(event["payload"])

    async def attention_event(self, event):
        await self.send_json(event["payload"])
