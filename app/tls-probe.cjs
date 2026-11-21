const tls = require('node:tls');
const net = require('node:net');
const [ip, hostname] = process.argv.slice(2);
if (!net.isIP(ip) || !/^[a-z0-9.-]+$/i.test(hostname || '')) process.exit(2);
async function probe(sni) {
  return new Promise(resolve => {
    let done = false;
    const result = {sni, ip, tcp: false, tls: false, local: null};
    const socket = tls.connect({host: ip, port: 443, servername: sni, rejectUnauthorized: true});
    function finish(error) {
      if (done) return;
      done = true;
      if (error) result.error = error;
      socket.destroy();
      resolve(result);
    }
    socket.on('connect', () => {result.tcp = true; result.local = socket.localAddress;});
    socket.on('secureConnect', () => {result.tls = true; finish();});
    socket.on('error', error => finish(error.code));
    socket.setTimeout(4000, () => finish('timeout'));
  });
}
(async () => {
  const actual = await probe(hostname);
  const control = await probe('www.google.com');
  console.log(JSON.stringify({actual, control}));
})().catch(() => process.exit(1));
