const http = require('node:http');
const net = require('node:net');
const dns = require('node:dns').promises;
const fs = require('node:fs');

function splitHello(record, hostname, mode) {
  if (record.length < 6 || record[0] !== 22 || record[5] !== 1) return record;
  const size = 5 + record.readUInt16BE(3);
  if (record.length < size) throw new Error('Incomplete TLS record');
  const payload = record.subarray(5, size);
  let position = mode === 'record1' ? 1 : mode === 'record5' ? 5 : 32;
  if (mode === 'sni') {
    const hostPosition = payload.indexOf(Buffer.from(hostname));
    if (hostPosition >= 0) position = hostPosition + Math.floor(hostname.length / 2);
  }
  if (mode === 'tcp') return record;
  position = Math.max(1, Math.min(payload.length - 1, position));
  const header = length => {const h = Buffer.from(record.subarray(0, 5)); h.writeUInt16BE(length, 3); return h;};
  return Buffer.concat([header(position), payload.subarray(0, position), header(payload.length - position), payload.subarray(position), record.subarray(size)]);
}
function publicV4(ip) {
  if (net.isIP(ip) !== 4) return false;
  const [a,b] = ip.split('.').map(Number);
  return a !== 0 && a !== 10 && a !== 127 && a < 224 && !(a === 169 && b === 254) && !(a === 172 && b >= 16 && b <= 31) && !(a === 192 && b === 168) && !(a === 100 && b >= 64 && b <= 127);
}
function vpnOn() {
  try {const lines=fs.readFileSync('C:/ProgramData/VPNUS/service.log','utf8').split(/\r?\n/).filter(line=>/\[tunnel\] (?:(?:dis)?connected\s*$|connect: bringing up tunnel)/.test(line));return lines.length && !/\] disconnected\s*$/.test(lines.at(-1));} catch {return false;}
}
function makeServer({mode = 'sni', chunk = 32, delay = 5, respectVpn = false} = {}) {
  const server = http.createServer((req, res) => {
    if (req.url === '/youtube.pac') {
      res.writeHead(200, {'Content-Type':'application/x-ns-proxy-autoconfig','Cache-Control':'no-store'});
      res.end(`function FindProxyForURL(url,host){if(dnsDomainIs(host,'.googlevideo.com')||host==='googlevideo.com')return 'PROXY 127.0.0.1:${server.address().port}; DIRECT';return 'DIRECT';}`);
    } else {res.writeHead(404);res.end();}
  });
  server.on('connect', async (req, client, head) => {
    const match = /^([a-z0-9.-]+):443$/i.exec(req.url || '');
    if (!match || !/(^|\.)googlevideo\.com$/i.test(match[1])) {client.end('HTTP/1.1 403 Forbidden\r\n\r\n');return;}
    const hostname = match[1].toLowerCase();
    client.pause();
    let remote;
    try {
      const ips = await dns.lookup(hostname, {all:true, family:4});
      const address = ips.find(item => publicV4(item.address));
      if (!address) throw new Error('Non-public target');
      remote = net.connect({host:address.address,port:443});
      remote.setNoDelay(true);client.setNoDelay(true);
      let buffer = Buffer.from(head), writing = false, ready = false, finished = false;
      const abort = () => {client.destroy();remote.destroy();};
      client.on('error', abort);remote.on('error', abort);
      client.on('close', () => remote.destroy());remote.on('close', () => client.destroy());
      const deadline = setTimeout(abort, 15000);
      deadline.unref();
      async function receive(data) {
        if (finished) return;
        buffer = Buffer.concat([buffer,data]);
        if (buffer.length > 131072) return abort();
        if (!ready || writing || buffer.length < 5) return;
        const size = 5 + buffer.readUInt16BE(3);
        if (size > 65540) return abort();
        if (buffer.length < size) return;
        writing = true;client.pause();
        try {
          const first = splitHello(buffer.subarray(0,size),hostname,mode);
          const tail = buffer.subarray(size);buffer=Buffer.alloc(0);
          for (let offset=0;offset<first.length;offset+=chunk) {
            if (remote.destroyed) return abort();
            if (!remote.write(first.subarray(offset,offset+chunk))) await new Promise((resolve,reject)=>{remote.once('drain',resolve);remote.once('error',reject);});
            if(delay) await new Promise(resolve=>setTimeout(resolve,delay));
          }
          if(tail.length) remote.write(tail);
          if(buffer.length) remote.write(buffer);
          buffer=Buffer.alloc(0);finished=true;clearTimeout(deadline);
          client.removeListener('data',receive);client.pipe(remote);client.resume();
        } catch {abort();}
      }
      client.on('data',receive);
      remote.pipe(client);
      remote.once('connect',()=>{
        ready=true;client.write('HTTP/1.1 200 Connection Established\r\n\r\n');
        if(respectVpn && vpnOn()) {finished=true;clearTimeout(deadline);if(buffer.length)remote.write(buffer);buffer=Buffer.alloc(0);client.removeListener('data',receive);client.pipe(remote);client.resume();return;}
        client.resume();receive(Buffer.alloc(0));
      });
    } catch {if(remote)remote.destroy();client.end('HTTP/1.1 502 Bad Gateway\r\n\r\n');}
  });
  return server;
}
module.exports={splitHello,publicV4,makeServer};
if(require.main===module){
  const [mode='sni',portText='0',statusFile,aware] = process.argv.slice(2);
  if(!['sni','record1','record5','tcp'].includes(mode))process.exit(2);
  const server=makeServer({mode,respectVpn:aware==='vpn-aware'});
  server.on('error',error=>{console.error(error.code);process.exit(1);});
  server.listen(Number(portText),'127.0.0.1',()=>{
    const status={PID:process.pid,Port:server.address().port,Mode:mode,Started:new Date().toISOString(),Product:'MyZapret TLS record proxy'};
    if(statusFile)fs.writeFileSync(statusFile,JSON.stringify(status));
    console.log(JSON.stringify(status));
  });
}
