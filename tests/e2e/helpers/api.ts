import { expect, type APIRequestContext } from '@playwright/test';

export const E2E_PASSWORD = 'CafeConnectE2E!';

export type E2ERefs = {
  tokens: Record<string, string>;
  tables: Record<string, any>;
  menu: Record<string, any>;
};

export async function login(request: APIRequestContext, username: string): Promise<string> {
  const response = await request.post('/api/auth/token/', {
    data: { username, password: E2E_PASSWORD },
  });
  expect(response.ok(), `${username} should log in`).toBeTruthy();
  const body = await response.json();
  expect(body.token, `${username} token`).toBeTruthy();
  return body.token;
}

export async function apiGet(request: APIRequestContext, token: string, path: string): Promise<any> {
  const response = await request.get(path, {
    headers: { Authorization: `Token ${token}` },
  });
  expect(response.ok(), `GET ${path}`).toBeTruthy();
  return response.json();
}

export async function apiPost(
  request: APIRequestContext,
  token: string,
  path: string,
  data?: Record<string, unknown>,
): Promise<any> {
  const response = await request.post(path, {
    headers: { Authorization: `Token ${token}` },
    data,
  });
  expect(response.ok(), `POST ${path}`).toBeTruthy();
  return response.json().catch(() => ({}));
}

export async function apiPatch(
  request: APIRequestContext,
  token: string,
  path: string,
  data: Record<string, unknown>,
): Promise<any> {
  const response = await request.patch(path, {
    headers: { Authorization: `Token ${token}` },
    data,
  });
  expect(response.ok(), `PATCH ${path}`).toBeTruthy();
  return response.json().catch(() => ({}));
}

export async function getE2ERefs(request: APIRequestContext): Promise<E2ERefs> {
  const tokens = {
    manager: await login(request, 'e2e_manager'),
    waiter: await login(request, 'e2e_waiter'),
    kitchen: await login(request, 'e2e_kitchen'),
    bar: await login(request, 'e2e_bar'),
  };
  const bootstrap = await apiGet(request, tokens.manager, '/api/staff/bootstrap/');
  const tables = Object.fromEntries(
    bootstrap.tables
      .filter((table: any) => [901, 902, 903].includes(Number(table.number)))
      .map((table: any) => [String(table.number), table]),
  );
  const menu = Object.fromEntries(
    bootstrap.menu
      .filter((item: any) => String(item.name).startsWith('E2E '))
      .map((item: any) => [item.name, item]),
  );
  expect(Object.keys(tables).sort()).toEqual(['901', '902', '903']);
  for (const name of ['E2E Kitchen Item', 'E2E Bar Drink', 'E2E Staff Hidden Item', 'E2E Stopped Item']) {
    expect(menu[name], `${name} should be seeded`).toBeTruthy();
  }
  return { tokens, tables, menu };
}

export async function findOrderByNote(
  request: APIRequestContext,
  token: string,
  note: string,
): Promise<any | null> {
  const bootstrap = await apiGet(request, token, '/api/staff/bootstrap/');
  return bootstrap.orders.find((order: any) => order.note === note) || null;
}

export async function expectOrderByNote(
  request: APIRequestContext,
  token: string,
  note: string,
): Promise<any> {
  let found: any | null = null;
  await expect
    .poll(async () => {
      found = await findOrderByNote(request, token, note);
      return found ? 1 : 0;
    }, { message: `order with note "${note}" should appear` })
    .toBe(1);
  return found;
}
