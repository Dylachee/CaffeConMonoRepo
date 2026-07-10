import { expect, test } from '@playwright/test';
import { apiGet, getE2ERefs } from './helpers/api';
import { openGuestTable } from './helpers/guest';

test.describe('environment / smoke', () => {
  test('backend, guest menu, staff shell, login, and seeded data are available', async ({ page, request }) => {
    const health = await request.get('/api/health/');
    expect(health.ok()).toBeTruthy();
    expect(await health.json()).toMatchObject({ status: 'ok' });

    const refs = await getE2ERefs(request);
    await openGuestTable(page, 901);
    await expect(page.getByTestId('table-pill')).toContainText('901');

    await page.goto('/staff/');
    await expect(page).toHaveTitle(/cafeconnect/i);

    const bootstrap = await apiGet(request, refs.tokens.waiter, '/api/staff/bootstrap/');
    expect(bootstrap.currentUser.username).toBe('e2e_waiter');
    expect(bootstrap.currentUser.role).toBe('waiter');
    expect(bootstrap.tables.length).toBeGreaterThanOrEqual(3);
    expect(bootstrap.menu.find((item: any) => item.name === 'E2E Kitchen Item')).toBeTruthy();
  });
});
