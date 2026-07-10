import { expect, test } from '@playwright/test';
import { apiGet, apiPatch, getE2ERefs } from './helpers/api';
import { openGuestTable } from './helpers/guest';

test.describe('attention, service, roles, and permissions', () => {
  test('guest can call and cancel waiter; staff sees waiting table state', async ({ page, request }) => {
    const refs = await getE2ERefs(request);
    await openGuestTable(page, 901);
    await page.getByTestId('nav-service').click();
    await page.getByTestId('signal-call-waiter').click();
    await expect(page.getByTestId('signal-pending')).toBeVisible();

    await expect.poll(async () => {
      const bootstrap = await apiGet(request, refs.tokens.waiter, '/api/staff/bootstrap/');
      return bootstrap.tables.find((table: any) => Number(table.number) === 901);
    }).toMatchObject({ status: 'waiting', attention: 'call' });

    await page.getByTestId('cancel-signal').click();
    await expect(page.getByTestId('signal-idle')).toBeVisible();
    await expect.poll(async () => {
      const bootstrap = await apiGet(request, refs.tokens.waiter, '/api/staff/bootstrap/');
      return bootstrap.tables.find((table: any) => Number(table.number) === 901);
    }).toMatchObject({ attention: null });
  });

  test('bill request uses the same service pipeline', async ({ page, request }) => {
    const refs = await getE2ERefs(request);
    await openGuestTable(page, 902);
    await page.getByTestId('nav-service').click();
    await page.getByTestId('signal-bill').click();
    await expect(page.getByTestId('signal-pending')).toContainText(/conto|bill/i);

    await expect.poll(async () => {
      const bootstrap = await apiGet(request, refs.tokens.waiter, '/api/staff/bootstrap/');
      return bootstrap.tables.find((table: any) => Number(table.number) === 902);
    }).toMatchObject({ status: 'waiting', attention: 'bill' });
  });

  test('role permissions protect staff actions', async ({ request }) => {
    const refs = await getE2ERefs(request);
    const tableId = refs.tables['903'].id;

    const kitchenTablePatch = await request.patch(`/api/tables/${tableId}/`, {
      headers: { Authorization: `Token ${refs.tokens.kitchen}` },
      data: { status: 'occupied' },
    });
    expect(kitchenTablePatch.status()).toBe(403);

    await apiPatch(request, refs.tokens.waiter, `/api/tables/${tableId}/`, { status: 'occupied' });
    await apiPatch(request, refs.tokens.waiter, `/api/tables/${tableId}/`, { status: 'free' });

    const managerStats = await request.get('/api/staff/stats/', {
      headers: { Authorization: `Token ${refs.tokens.manager}` },
    });
    expect(managerStats.ok()).toBeTruthy();

    const waiterStats = await request.get('/api/staff/stats/', {
      headers: { Authorization: `Token ${refs.tokens.waiter}` },
    });
    expect(waiterStats.status()).toBe(403);

    const anonymousBootstrap = await request.get('/api/staff/bootstrap/');
    expect(anonymousBootstrap.status()).toBe(401);
  });
});
