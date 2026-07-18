import { expect, test, type APIRequestContext } from '@playwright/test';
import { login } from './helpers/api';
import { openGuestTable } from './helpers/guest';

const SOCIAL_SCRIPT_HOSTS = [
  'instagram.com',
  'threads.net',
  'platform.twitter.com',
  'connect.facebook.net',
];

async function resetFeed(request: APIRequestContext, token: string) {
  const list = await request.get('/api/staff/feed/', {
    headers: { Authorization: `Token ${token}` },
  });
  expect(list.ok(), 'staff feed list').toBeTruthy();
  const { posts } = await list.json();
  for (const post of posts) {
    await request.delete(`/api/staff/feed/${post.id}/`, {
      headers: { Authorization: `Token ${token}` },
    });
  }
}

async function createPost(request: APIRequestContext, token: string, url: string) {
  const response = await request.post('/api/staff/feed/', {
    headers: { Authorization: `Token ${token}` },
    data: { url },
  });
  expect(response.status(), `create ${url}`).toBe(201);
  return response.json();
}

test.describe('venue social feed', () => {
  test('all four tabs switch; pinned post leads the feed; fallback card when scripts are blocked', async ({ page, request }) => {
    const token = await login(request, 'e2e_manager');
    await resetFeed(request, token);

    // Unique URLs per run so the duplicate guard never trips on retries.
    const run = Date.now();
    const older = await createPost(request, token, `https://www.instagram.com/p/E2eOld${run}/`);
    const newer = await createPost(request, token, `https://www.instagram.com/p/E2eNew${run}/`);
    const pinned = await createPost(request, token, `https://www.threads.net/@sissi/post/E2ePin${run}`);
    const pin = await request.post(`/api/staff/feed/${pinned.id}/pin/`, {
      headers: { Authorization: `Token ${token}` },
    });
    expect(pin.ok(), 'pin post').toBeTruthy();

    // Block the official widget scripts: the embeds cannot upgrade, so every
    // card must degrade to the app's own fallback card.
    for (const host of SOCIAL_SCRIPT_HOSTS) {
      await page.route(`**://*${host}/**`, (route) => route.abort());
    }

    await openGuestTable(page, 901);

    // The initial render must not reference any social widget script.
    const initialSocialScripts = await page.evaluate(() =>
      Array.from(document.scripts).filter((s) =>
        /instagram\.com|threads\.net|platform\.twitter\.com|connect\.facebook\.net/.test(s.src),
      ).length,
    );
    expect(initialSocialScripts, 'no social scripts before Feed opens').toBe(0);

    // All four tabs switch.
    await page.getByTestId('nav-menu').click();
    await expect(page.getByTestId('screen-menu')).toBeVisible();
    await page.getByTestId('nav-service').click();
    await expect(page.getByTestId('screen-service')).toBeVisible();
    await page.getByTestId('nav-profile').click();
    await expect(page.getByTestId('screen-profile')).toBeVisible();
    await page.getByTestId('nav-feed').click();
    await expect(page.getByTestId('screen-feed')).toBeVisible();

    // Pinned post first, labelled; then the newest unpinned post.
    const posts = page.getByTestId('feed-post');
    await expect(posts).toHaveCount(3);
    const first = posts.first();
    await expect(first).toHaveAttribute('data-pinned', '1');
    await expect(first).toHaveAttribute('data-platform', 'threads');
    await expect(first.getByTestId('feed-pinned-tag')).toBeVisible();
    await expect(first.getByTestId('feed-pinned-tag')).toContainText(/Pinned|In evidenza/);
    await expect(posts.nth(1)).toHaveAttribute('data-platform', 'instagram');

    // Scripts blocked -> the fallback card takes over, with a safe outbound link.
    const fallback = first.getByTestId('feed-fallback');
    await expect(fallback).toBeVisible({ timeout: 10_000 });
    const link = fallback.getByRole('link');
    await expect(link).toHaveAttribute('href', pinned.source_url);
    await expect(link).toHaveAttribute('rel', /noopener/);
    await expect(link).toContainText(/Open post|Apri il post/);

    // Language switch localizes the pinned label on already-rendered cards.
    await page.getByTestId('lang-it').click();
    await expect(first.getByTestId('feed-pinned-tag')).toContainText('In evidenza');
    await page.getByTestId('lang-en').click();
    await expect(first.getByTestId('feed-pinned-tag')).toContainText('Pinned');

    // Hidden posts never reach guests: hide one and reload.
    const hide = await request.post(`/api/staff/feed/${older.id}/hide/`, {
      headers: { Authorization: `Token ${token}` },
    });
    expect(hide.ok(), 'hide post').toBeTruthy();
    await page.reload();
    await page.getByTestId('nav-feed').click();
    await expect(page.getByTestId('feed-post')).toHaveCount(2);

    void newer; // referenced to keep create order explicit
  });

  test('empty feed shows the friendly empty state', async ({ page, request }) => {
    const token = await login(request, 'e2e_manager');
    await resetFeed(request, token);

    await openGuestTable(page, 901);
    await page.getByTestId('nav-feed').click();
    await expect(page.getByTestId('feed-empty')).toBeVisible();
    await expect(page.getByTestId('feed-empty')).toContainText(/No posts yet|Ancora nessun post/);
  });
});
