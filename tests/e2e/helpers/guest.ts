import { expect, type Page } from '@playwright/test';

export async function openGuestTable(page: Page, tableNumber = 901) {
  await page.goto(`/menu/n/${tableNumber}/`);
  await expect(page.locator('body')).toHaveAttribute('data-table', /\d+/);
  await expect(page.getByRole('heading', { name: /Caffè|Sissi|Cafe/i })).toBeVisible();
}

export async function submitGuestOrder(
  page: Page,
  tableNumber: number,
  itemNames: string[],
  note: string,
) {
  await openGuestTable(page, tableNumber);
  await page.getByTestId('nav-menu').click();
  for (const itemName of itemNames) {
    await page.getByLabel(`Add ${itemName}`).click();
  }
  await expect(page.getByTestId('checkout')).toBeVisible();
  await page.getByTestId('checkout').click();
  await page.getByTestId('guest-name').fill('E2E Guest');
  await page.getByTestId('order-notes').fill(note);
  await page.getByTestId('submit-order').click();
  await expect(page.getByTestId('order-status')).toBeVisible();
  await expect(page.getByTestId('order-list')).toContainText(note);
}
