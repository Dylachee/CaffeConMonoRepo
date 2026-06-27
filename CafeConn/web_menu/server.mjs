import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { basename, extname, join } from "node:path";

const port = Number(process.env.PORT || 4173);
const root = new URL(".", import.meta.url).pathname;
const types = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
};

createServer(async (request, response) => {
  const url = new URL(request.url, `http://${request.headers.host}`);
  const pathname = url.pathname === "/" ? "/index.html" : url.pathname;
  const filePath = extname(pathname) ? join(root, pathname) : join(root, "index.html");

  try {
    let file;
    try {
      file = await readFile(filePath);
    } catch {
      file = await readFile(join(root, basename(filePath)));
    }
    response.writeHead(200, { "Content-Type": types[extname(filePath)] || "text/plain; charset=utf-8" });
    response.end(file);
  } catch {
    response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    response.end("Not found");
  }
}).listen(port, () => {
  console.log(`CafeConnect is running at http://localhost:${port}`);
});
