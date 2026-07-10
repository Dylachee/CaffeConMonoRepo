import { expect, test } from '@playwright/test';
import { apiGet, apiPost, expectOrderByNote, getE2ERefs } from './helpers/api';
import { submitGuestOrder } from './helpers/guest';

test.describe('guest order lifecycle and station split', () => {
  test('guest order waits for waiter approval, carries notes, then reaches station feeds', async ({ page, request }) => {
    const refs = await getE2ERefs(request);
    const note = `E2E approval note ${Date.now()}`;

    await submitGuestOrder(page, 901, ['E2E Kitchen Item', 'E2E Bar Drink'], note);
    const order = await expectOrderByNote(request, refs.tokens.manager, note);
    expect(order.status).toBe('awaiting');
    expect(order.acceptedAt).toBeFalsy();

    const kitchenBefore = await apiGet(request, refs.tokens.kitchen, '/api/orders/station-feed/?station=kitchen');
    const barBefore = await apiGet(request, refs.tokens.bar, '/api/orders/station-feed/?station=bar');
    expect(kitchenBefore.some((candidate: any) => String(candidate.id) === String(order.id))).toBe(false);
    expect(barBefore.some((candidate: any) => String(candidate.id) === String(order.id))).toBe(false);

    const confirmed = await apiPost(request, refs.tokens.waiter, `/api/orders/${order.id}/confirm/`);
    expect(confirmed.status).toBe('new');
    expect(confirmed.notes).toBe(note);
    expect(confirmed.accepted_at).toBeTruthy();

    const kitchenAfter = await apiGet(request, refs.tokens.kitchen, '/api/orders/station-feed/?station=kitchen');
    const barAfter = await apiGet(request, refs.tokens.bar, '/api/orders/station-feed/?station=bar');
    const kitchenOrder = kitchenAfter.find((candidate: any) => String(candidate.id) === String(order.id));
    const barOrder = barAfter.find((candidate: any) => String(candidate.id) === String(order.id));
    expect(kitchenOrder.notes).toBe(note);
    expect(kitchenOrder.items).toHaveLength(1);
    expect(kitchenOrder.items[0].menu_item.name).toBe('E2E Kitchen Item');
    expect(barOrder.notes).toBe(note);
    expect(barOrder.items).toHaveLength(1);
    expect(barOrder.items[0].menu_item.name).toBe('E2E Bar Drink');

    await expect.poll(async () => {
      await page.reload();
      return page.getByTestId('order-list').textContent();
    }).toContain(note);
  });

  test('waiter can reject a guest order and stations never receive it', async ({ page, request }) => {
    const refs = await getE2ERefs(request);
    const note = `E2E rejection note ${Date.now()}`;

    await submitGuestOrder(page, 902, ['E2E Bar Drink'], note);
    const order = await expectOrderByNote(request, refs.tokens.manager, note);
    expect(order.status).toBe('awaiting');

    const rejected = await apiPost(request, refs.tokens.waiter, `/api/orders/${order.id}/reject/`);
    expect(rejected.status).toBe('cancelled');

    const barFeed = await apiGet(request, refs.tokens.bar, '/api/orders/station-feed/?station=bar');
    expect(barFeed.some((candidate: any) => String(candidate.id) === String(order.id))).toBe(false);
  });

  test('kitchen and bar can mark their own items ready; waiter delivers separately', async ({ page, request }) => {
    const refs = await getE2ERefs(request);
    const note = `E2E split ready note ${Date.now()}`;

    await submitGuestOrder(page, 903, ['E2E Kitchen Item', 'E2E Bar Drink'], note);
    const order = await expectOrderByNote(request, refs.tokens.manager, note);
    await apiPost(request, refs.tokens.waiter, `/api/orders/${order.id}/confirm/`);

    const fresh = await apiGet(request, refs.tokens.manager, `/api/orders/${order.id}/`);
    const kitchenItem = fresh.items.find((item: any) => item.station === 'kitchen');
    const barItem = fresh.items.find((item: any) => item.station === 'bar');

    await apiPost(request, refs.tokens.kitchen, `/api/order-items/${kitchenItem.id}/mark-ready/`);
    let afterKitchen = await apiGet(request, refs.tokens.manager, `/api/orders/${order.id}/`);
    expect(afterKitchen.items.find((item: any) => item.id === kitchenItem.id).ready).toBe(true);
    expect(afterKitchen.items.find((item: any) => item.id === barItem.id).ready).toBe(false);

    await apiPost(request, refs.tokens.bar, `/api/order-items/${barItem.id}/mark-ready/`);
    const afterBar = await apiGet(request, refs.tokens.manager, `/api/orders/${order.id}/`);
    expect(afterBar.items.every((item: any) => item.ready)).toBe(true);

    await apiPost(request, refs.tokens.waiter, `/api/order-items/${kitchenItem.id}/toggle-done/`);
    afterKitchen = await apiGet(request, refs.tokens.manager, `/api/orders/${order.id}/`);
    expect(afterKitchen.items.find((item: any) => item.id === kitchenItem.id).done).toBe(true);
    expect(afterKitchen.items.find((item: any) => item.id === barItem.id).done).toBe(false);
  });
});
