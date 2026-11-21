const net = require('node:net');
const tls = require('node:tls');
const fs = require('node:fs');
const output = process.argv[2];
if (!output) process.exit(2);
let finished = false;
const server = net.createServer(socket => {
  let bytes = Buffer.alloc(0);
  socket.on('data', data => {
    bytes = Buffer.concat([bytes, data]);
    if (bytes.length < 5) return;
    const size = 5 + bytes.readUInt16BE(3);
    if (bytes.length < size || finished) return;
    finished = true;
    fs.writeFileSync(output, bytes.subarray(0, size));
    socket.destroy();
    server.close();
  });
});
server.listen(0, '127.0.0.1', () => {
  const client = tls.connect({host: '127.0.0.1', port: server.address().port, servername: 'www.onetrust.com', ecdhCurve: 'X25519:P-256'});
  client.on('error', () => {});
  client.setTimeout(3000, () => client.destroy());
});
setTimeout(() => {if (!finished) process.exit(1);}, 4000).unref();
