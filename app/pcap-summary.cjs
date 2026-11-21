const fs=require('node:fs');
function summarize(buf,target){
 let offset=0,little=true,interfaces=[],flows=new Map(),packets=0,unsupported=0;
 while(offset+12<=buf.length){
  if(buf.readUInt32LE(offset)===0x0a0d0d0a){little=buf.readUInt32LE(offset+8)===0x1a2b3c4d;interfaces=[];}
  const u32=p=>little?buf.readUInt32LE(p):buf.readUInt32BE(p);
  const type=u32(offset),size=u32(offset+4);
  if(size<12||offset+size>buf.length)throw new Error('Invalid pcapng block');
  if(type===1)interfaces.push(little?buf.readUInt16LE(offset+8):buf.readUInt16BE(offset+8));
  if(type===6){
   const iface=u32(offset+8),cap=u32(offset+20);
   const p=buf.subarray(offset+28,offset+28+Math.min(cap,size-32));
   let ip=0;
   if(interfaces[iface]===1){if(p.length<14){offset+=size;continue;}ip=14;let eth=p.readUInt16BE(12);if(eth===0x8100&&p.length>=18){eth=p.readUInt16BE(16);ip=18;}if(eth!==0x0800){offset+=size;continue;}}
   else if(interfaces[iface]!==101){unsupported++;offset+=size;continue;}
   if(p.length<ip+20||p[ip]>>4!==4||p[ip+9]!==6||(p.readUInt16BE(ip+6)&0x1fff)!==0){offset+=size;continue;}
   const src=[...p.subarray(ip+12,ip+16)].join('.'),dst=[...p.subarray(ip+16,ip+20)].join('.');
   if(src!==target&&dst!==target){offset+=size;continue;}
   const tcp=ip+(p[ip]&15)*4;if(p.length<tcp+20){offset+=size;continue;}
   const incoming=src===target,local=incoming?dst:src,port=p.readUInt16BE(tcp+(incoming?2:0));
   const key=local+':'+port;let f=flows.get(key);
   if(!f){f={local,port,synOut:0,synAckIn:0,rstIn:0,clientHelloOut:0,serverHelloIn:0,tlsAlertIn:0,inboundDataBytes:0,outboundDataBytes:0};flows.set(key,f);}
   const flags=p[tcp+13],data=tcp+(p[tcp+12]>>4)*4,length=Math.max(0,p.readUInt16BE(ip+2)-(data-ip));
   if(incoming){if((flags&0x12)===0x12)f.synAckIn++;if(flags&4)f.rstIn++;f.inboundDataBytes+=length;if(p.length>data+5&&p[data]===22&&p[data+5]===2)f.serverHelloIn++;if(p.length>data&&p[data]===21)f.tlsAlertIn++;}
   else{if((flags&0x12)===2)f.synOut++;f.outboundDataBytes+=length;if(p.length>data+5&&p[data]===22&&p[data+5]===1)f.clientHelloOut++;}
   packets++;
  }
  offset+=size;
 }
 return {target,packets,unsupported,flows:[...flows.values()],note:'Observed NIC packet snapshots; duplicate snapshots and retransmissions may be counted. Missing ServerHello alone does not locate the dropping device.'};
}
function summarizeText(text,target){
 const block=(type,body)=>{const b=Buffer.alloc(body.length+12);b.writeUInt32LE(type);b.writeUInt32LE(b.length,4);body.copy(b,8);b.writeUInt32LE(b.length,b.length-4);return b;};
 const sh=Buffer.alloc(16);sh.writeUInt32LE(0x1a2b3c4d);sh.writeUInt16LE(1,4);
 const parts=[block(0x0a0d0d0a,sh)];
 for(const link of [1,101]){const id=Buffer.alloc(8);id.writeUInt16LE(link);id.writeUInt32LE(65535,4);parts.push(block(1,id));}
 let link=null,hex='';
 function flush(){
  if(link!==null&&hex){const p=Buffer.from(hex,'hex'),body=Buffer.alloc(20+Math.ceil(p.length/4)*4);body.writeUInt32LE(link,0);body.writeUInt32LE(p.length,12);body.writeUInt32LE(p.length,16);p.copy(body,20);parts.push(block(6,body));}
  link=null;hex='';
 }
 for(const line of text.split(/\r?\n/)){
  if(/^\[/.test(line)){flush();if(line.includes('Microsoft-Windows-PktMon')){const match=line.match(/(?:тип|type)\s+(Ethernet|IP)\s*,/i);if(match)link=match[1].toLowerCase()==='ip'?1:0;}}
  else if(link!==null){const match=line.match(/^\s*0x[0-9a-f]+:\s+((?:[0-9a-f]{4}(?:\s+|$))+)/i);if(match)hex+=match[1].replace(/\s/g,'');}
 }
 flush();const result=summarize(Buffer.concat(parts),target);result.source='Pktmon text hex (includes raw IP events omitted by etl2pcap)';return result;
}
module.exports={summarize,summarizeText};
if(require.main===module){try{const text=process.argv[4]==='--text',buf=fs.readFileSync(process.argv[2]);console.log(JSON.stringify(text?summarizeText(buf.toString(buf[0]===255&&buf[1]===254?'utf16le':'utf8').replace(/^\uFEFF/,''),process.argv[3]):summarize(buf,process.argv[3]),null,2));}catch(e){console.error(e.message);process.exit(1);}}
