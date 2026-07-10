import { expect, test } from '@playwright/test';
import { apiGet, getE2ERefs } from './helpers/api';
import { openGuestTable } from './helpers/guest';

test.describe('guest menu flow', () => {
  test('guest can navigate, switch language, filter categories, inspect items, and build a cart', async ({ page, request }) => {
    const refs = await getE2ERefs(request);
    await openGuestTable(page, 901);

    await page.getByTestId('lang-en').click();
    await expect(page.getByTestId('nav-profile')).toContainText('Profile');
    await page.getByTestId('lang-it').click();
    await expect(page.getByTestId('nav-profile')).toContainText('Profilo');

    await page.getByTestId('nav-menu').click();
    await expect(page.getByTestId('screen-menu')).toBeVisible();
    const menuScreen = page.getByTestId('screen-menu');
    await expect(menuScreen.getByText('E2E Kitchen Item')).toBeVisible();
    await expect(menuScreen.getByText('E2E Bar Drink')).toBeVisible();
    await expect(menuScreen.getByText('E2E Staff Hidden Item')).toHaveCount(0);
    await expect(menuScreen.getByText('E2E Stopped Item')).toHaveCount(0);

    await page.getByRole('button', { name: 'E2E Drinks' }).click();
    await expect(menuScreen.getByText('E2E Bar Drink')).toBeVisible();
    await expect(menuScreen.getByText('E2E Kitchen Item')).toBeHidden();

    await page.getByRole('button', { name: 'Tutto' }).click();
    await page.getByLabel('E2E Kitchen Item').click();
    await expect(page.getByTestId('detail')).toBeVisible();
    await expect(page.getByTestId('detail-name')).toContainText('E2E Kitchen Item');
    await page.getByTestId('detail-add').click();
    await expect(page.getByTestId('checkout')).toBeVisible();
    await expect(page.getByTestId('cart-count')).toContainText('1');
    await expect(page.getByTestId('cart-total')).toContainText('11,00');

    await page.getByTestId('checkout').click();
    await page.locator('[data-inc]').first().click();
    await expect(page.getByTestId('sheet-total')).toContainText('22,00');

    await page.getByLabel('Close').click();
    await page.getByTestId('nav-profile').click();
    await expect(page.locator('.feature').first()).toBeVisible();

    const staffMenu = await apiGet(request, refs.tokens.manager, '/api/staff/bootstrap/');
    const hidden = staffMenu.menu.find((item: any) => item.name === 'E2E Staff Hidden Item');
    const stopped = staffMenu.menu.find((item: any) => item.name === 'E2E Stopped Item');
    expect(hidden).toBeTruthy();
    expect(stopped).toMatchObject({ available: false });
  });
});
