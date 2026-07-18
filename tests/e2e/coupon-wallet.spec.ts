import { expect, test, type APIRequestContext } from '@playwright/test';
import { login } from './helpers/api';

async function createCampaign(request: APIRequestContext, token: string, slug: string) {
  const response = await request.post('/api/staff/coupons/campaigns/', {
    headers: { Authorization: `Token ${token}` },
    data: {
      slug,
      title: 'E2E welcome treat',
      title_it: 'Omaggio di benvenuto E2E',
      description: 'One free treat with any coffee.',
      description_it: 'Un omaggio con ogni caffe.',
      discount_type: 'percent',
      discount_value: '15',
    },
  });
  expect(response.status(), 'campaign created').toBe(201);
  return response.json();
}

test.describe('coupon wallet', () => {
  test('wallet tab is lazy and ordinary guests stay wallet-cookie-free', async ({ page, context }) => {
    const walletRequests: string[] = [];
    page.on('request', (request) => {
      if (request.url().includes('/menu/wallet/')) walletRequests.push(request.url());
    });

    await page.goto('/menu/n/901/');
    await page.getByTestId('nav-menu').click();
    await expect(page.getByTestId('screen-menu')).toBeVisible();
    await page.getByTestId('nav-profile').click();
    await expect(page.getByTestId('screen-profile')).toBeVisible();

    expect(walletRequests, 'no wallet requests before the tab opens').toHaveLength(0);
    let cookies = await context.cookies();
    expect(cookies.find((c) => c.name === 'cc_wallet'), 'no wallet cookie').toBeUndefined();

    await page.getByTestId('nav-wallet').click();
    await expect(page.getByTestId('screen-wallet')).toBeVisible();
    await expect(page.getByTestId('wallet-empty')).toBeVisible();
    expect(walletRequests.length, 'wallet fetched on first open').toBeGreaterThan(0);

    // Reading the wallet never creates one.
    cookies = await context.cookies();
    expect(cookies.find((c) => c.name === 'cc_wallet')).toBeUndefined();
  });

  test('claim link -> card in wallet -> redeem -> Used ribbon', async ({ page, context, request }) => {
    const token = await login(request, 'e2e_manager');
    const campaign = await createCampaign(request, token, `e2e-coupon-${Date.now()}`);

    const issue = await request.post('/api/staff/coupons/issue/', {
      headers: { Authorization: `Token ${token}` },
      data: { campaign: campaign.id },
    });
    expect(issue.ok(), 'issue claim token').toBeTruthy();
    const { claimUrl } = await issue.json();

    // The guest scans the waiter's QR -> lands on the claim link.
    await page.goto(claimUrl);
    await expect(page.getByTestId('screen-wallet')).toBeVisible();
    const card = page.getByTestId('wallet-card');
    await expect(card).toHaveCount(1);
    await expect(card).toHaveAttribute('data-status', 'active');

    // Progressive disclosure: collapsed passes carry no QR in the DOM and no
    // visible code — only title, headline and the "Tap to use" hint.
    await expect(card.getByTestId('wallet-card-qr')).toHaveCount(0);
    await expect(card.getByTestId('wallet-card-code')).not.toBeVisible();
    const toggle = card.getByTestId('wallet-card-toggle');
    await expect(toggle).toHaveAttribute('aria-expanded', 'false');
    await expect(toggle).toContainText(/Tap to use|Tocca per usare/);

    // Tap -> the QR appears on its white scan area, with the code.
    await toggle.click();
    await expect(toggle).toHaveAttribute('aria-expanded', 'true');
    await expect(card.getByTestId('wallet-card-qr').locator('svg')).toBeVisible();
    await expect(card.getByTestId('wallet-card-code')).toBeVisible();
    await expect(card.getByTestId('wallet-card-code')).not.toBeEmpty();

    // Tap again -> collapses.
    await toggle.click();
    await expect(toggle).toHaveAttribute('aria-expanded', 'false');
    await expect(card.getByTestId('wallet-card-qr').locator('svg')).not.toBeVisible();
    await expect(page.getByTestId('wallet-recovery')).toBeVisible();

    const cookies = await context.cookies();
    const walletCookie = cookies.find((c) => c.name === 'cc_wallet');
    expect(walletCookie, 'wallet cookie set on claim').toBeTruthy();
    expect(walletCookie!.httpOnly, 'wallet cookie is httpOnly').toBe(true);

    // Idempotent: opening the same claim link again adds nothing.
    await page.goto(claimUrl);
    await expect(page.getByTestId('screen-wallet')).toBeVisible();
    await expect(page.getByTestId('wallet-card')).toHaveCount(1);

    // Staff redeems by the short code (the scanner path posts the same API).
    const code = await page.getByTestId('wallet-card').getAttribute('data-code');
    const redeem = await request.post('/api/staff/coupons/redeem/', {
      headers: { Authorization: `Token ${token}` },
      data: { code },
    });
    expect(redeem.ok(), 'redeem by code').toBeTruthy();
    expect((await redeem.json()).coupon.status).toBe('redeemed');

    // The guest reopens the wallet: the pass moved into History with a ribbon.
    await page.goto('/menu/?wallet=1');
    await expect(page.getByTestId('screen-wallet')).toBeVisible();
    await expect(page.getByTestId('wallet-history-toggle')).toBeVisible();
    await page.getByTestId('wallet-history-toggle').click();
    const usedCard = page.getByTestId('wallet-history').getByTestId('wallet-card');
    await expect(usedCard).toHaveCount(1);
    await expect(usedCard).toHaveAttribute('data-status', 'redeemed');
    await expect(usedCard.getByTestId('wallet-card-ribbon')).toHaveText(/Used|Utilizzato/);

    // A redeemed pass expands to its details but NEVER renders a QR.
    await usedCard.getByTestId('wallet-card-toggle').click();
    await expect(usedCard.getByTestId('wallet-card-toggle')).toHaveAttribute('aria-expanded', 'true');
    await expect(usedCard.getByTestId('wallet-card-code')).toBeVisible();
    await expect(usedCard.getByTestId('wallet-card-qr')).toHaveCount(0);
  });

  test('accordion behavior and 320px layout with three coupons', async ({ page, request }) => {
    const token = await login(request, 'e2e_manager');
    const run = Date.now();
    const slugs = [`e2e-acc-a-${run}`, `e2e-acc-b-${run}`, `e2e-acc-c-${run}`];
    for (const slug of slugs) await createCampaign(request, token, slug);

    // Claim all three campaigns in one browser via marketing links.
    for (const slug of slugs) {
      await page.goto(`/menu/?c=${slug}`);
      await expect(page.getByTestId('screen-wallet')).toBeVisible();
    }
    await page.setViewportSize({ width: 320, height: 700 });
    await page.goto('/menu/?wallet=1');
    await expect(page.getByTestId('screen-wallet')).toBeVisible();

    const cards = page.getByTestId('wallet-card');
    await expect(cards).toHaveCount(3);
    // Clean pass stack: zero QR SVGs in the DOM before any tap.
    await expect(page.getByTestId('wallet-card-qr')).toHaveCount(0);
    // Five tabs and the pass stack must fit 320px without sideways scroll.
    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth > document.documentElement.clientWidth,
    );
    expect(overflow, 'no horizontal overflow at 320px').toBe(false);

    // Accordion: opening the second pass collapses the first.
    const first = cards.nth(0).getByTestId('wallet-card-toggle');
    const second = cards.nth(1).getByTestId('wallet-card-toggle');
    await first.click();
    await expect(first).toHaveAttribute('aria-expanded', 'true');
    await expect(cards.nth(0).getByTestId('wallet-card-qr').locator('svg')).toBeVisible();
    await second.click();
    await expect(second).toHaveAttribute('aria-expanded', 'true');
    await expect(first).toHaveAttribute('aria-expanded', 'false');
    await expect(cards.nth(0).getByTestId('wallet-card-qr').locator('svg')).not.toBeVisible();
    await expect(cards.nth(1).getByTestId('wallet-card-qr').locator('svg')).toBeVisible();
    // Tapping the open pass again collapses it.
    await second.click();
    await expect(second).toHaveAttribute('aria-expanded', 'false');
    await expect(cards.nth(1).getByTestId('wallet-card-qr').locator('svg')).not.toBeVisible();
  });

  test('invalid claim link shows a clear message, not a silent no-op', async ({ page }) => {
    await page.goto('/menu/?claim=garbage-token');
    await expect(page.locator('#toast')).toHaveText(/valid|valido/i, { timeout: 8_000 });
    // Nothing landed in the wallet.
    await page.getByTestId('nav-wallet').click();
    await expect(page.getByTestId('wallet-empty')).toBeVisible();
  });
});
