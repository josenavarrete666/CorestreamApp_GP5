import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../movil/build/web/', import.meta.url));
const mime = {'.html': 'text/html', '.js': 'application/javascript',
  '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png',
  '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.ttf': 'font/ttf'};

const server = createServer(async (request, response) => {
  try {
    const url = new URL(request.url ?? '/', 'http://localhost:7358');
    const file = path.resolve(root, `.${decodeURIComponent(url.pathname === '/' ? '/index.html' : url.pathname)}`);
    if (!file.startsWith(root)) {
      response.writeHead(403);
      response.end();
      return;
    }
    const content = await readFile(file);
    response.writeHead(200, {'Content-Type': mime[path.extname(file)] ?? 'application/octet-stream',
      'Cache-Control': 'no-store'});
    response.end(content);
  } catch {
    response.writeHead(404);
    response.end('Not found');
  }
}).listen(7358, '127.0.0.1', () => console.log('CoreStream Web: http://localhost:7358'));

let stopping = false;
function stop() {
  if (stopping) return;
  stopping = true;
  console.log('Stopping CoreStream Web...');
  server.close(() => process.exit(0));
  setTimeout(() => server.closeAllConnections(), 2000).unref();
}
process.on('SIGINT', stop);
process.on('SIGTERM', stop);
server.on('error', error => { console.error(`CoreStream Web: ${error.message}`); process.exitCode = 1; });
