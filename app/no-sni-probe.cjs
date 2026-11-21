const tls=require('node:tls');
const https=require('node:https');
function tlsOptions(host,mode){
 if(!['normal','nosni'].includes(mode))throw new Error('Invalid SNI mode');
 return {host,port:443,family:4,servername:mode==='nosni'?'':host,rejectUnauthorized:true,minVersion:'TLSv1.2',ALPNProtocols:['http/1.1'],checkServerIdentity:(_name,cert)=>tls.checkServerIdentity(host,cert)};
}
function probe(stream,mode){
 const url=new URL(stream.Url);
 if(url.protocol!=='https:'||url.port&&url.port!=='443'||url.username||url.password||!url.hostname.endsWith('.googlevideo.com')||url.pathname!=='/videoplayback')throw new Error('Expected YouTube video stream');
 return new Promise(resolve=>{
  const result={Mode:mode,Host:url.hostname,TCP:false,TLS:false,Authorized:false,HTTP:0,Bytes:0,Pass:false};
  let request,done=false;
  const agent=new https.Agent({keepAlive:false});
  const finish=error=>{if(done)return;done=true;clearTimeout(timer);if(error)result.Error=error;result.Pass=result.Authorized&&[200,206].includes(result.HTTP)&&result.Bytes>=16384&&/^video\//i.test(result.Mime||'');if(request)request.destroy();agent.destroy();resolve(result);};
  const timer=setTimeout(()=>finish('TIMEOUT'),12000);
  agent.createConnection=()=>{
   const socket=tls.connect(tlsOptions(url.hostname,mode));
   socket.on('connect',()=>{result.TCP=true;result.IP=socket.remoteAddress;result.Local=socket.localAddress;});
   socket.on('secureConnect',()=>{result.TLS=true;result.Authorized=socket.authorized;result.Protocol=socket.getProtocol();});
   return socket;
  };
  const headers={Range:'bytes=0-262143',Connection:'close'};
  if(stream.UserAgent&&!/[\r\n]/.test(stream.UserAgent))headers['User-Agent']=stream.UserAgent;
  request=https.get(url,{agent,headers},response=>{
   result.HTTP=response.statusCode;result.Mime=response.headers['content-type']||'';
   response.on('data',chunk=>{result.Bytes+=chunk.length;if(result.Bytes>=262144)finish();});
   response.on('end',()=>finish());response.on('error',error=>finish(error.code||'RESPONSE_ERROR'));
  });
  request.on('error',error=>finish(error.code||'REQUEST_ERROR'));
 });
}
module.exports={tlsOptions,probe};
if(require.main===module){let input='';process.stdin.setEncoding('utf8');process.stdin.on('data',chunk=>{input+=chunk;if(input.length>65536)process.exit(2);});process.stdin.on('end',async()=>{try{const s=JSON.parse(input);for(const mode of ['normal','nosni'])console.log(JSON.stringify(await probe(s,mode)));}catch{console.error('Invalid stream or probe failure');process.exitCode=1;}});}
