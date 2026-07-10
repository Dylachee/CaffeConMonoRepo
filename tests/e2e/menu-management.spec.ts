import { expect, test } from '@playwright/test';
import { apiPatch, getE2ERefs } from './helpers/api';
import { openGuestTable } from './helpers/guest';

test.describe('menu management', () => {
  test('manager availability toggle controls guest visibility while staff sees full menu', async ({ page, request }) => {
    const refs = await getE2ERefs(request);
    const stopped = refs.menu['E2E Stopped Item'];
    const hidden = refs.menu['E2E Staff Hidden Item'];
    expect(hidden.available).toBe(true);
    expect(stopped.available).toBe(false);

    await openGuestTable(page, 901);
    await page.getByTestId('nav-menu').click();
    const menuScreen = page.getByTestId('screen-menu');
    await expect(menuScreen.getByText('E2E Stopped Item')).toHaveCount(0);
    await expect(menuScreen.getByText('E2E Staff Hidden Item')).toHaveCount(0);

    await apiPatch(request, refs.tokens.manager, `/api/menu-items/${stopped.id}/`, { is_available: true });
    await page.reload();
    await page.getByTestId('nav-menu').click();
    await expect(menuScreen.getByText('E2E Stopped Item')).toBeVisible();

    await apiPatch(request, refs.tokens.manager, `/api/menu-items/${stopped.id}/`, { is_available: false });
    await page.reload();
    await page.getByTestId('nav-menu').click();
    await expect(menuScreen.getByText('E2E Stopped Item')).toHaveCount(0);
  });
});
