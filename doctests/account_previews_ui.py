#!/usr/bin/env python3
"""Run against an EMPTY isolated profile on inspector port 3773, with the Keycard
simulator and default USB Shell emulator with the same test seed. Refuses non-simulator device identities.
"""
import os,sys,time,json,base64
from pathlib import Path
os.environ['QML_INSPECTOR_PORT']='3773'
import socket

def send(command, params=None):
    with socket.create_connection(('127.0.0.1', 3773), timeout=30) as sock:
        sock.sendall((json.dumps({'command': command, 'params': params or {}})+'\n').encode())
        reply=json.loads(sock.makefile('rb').readline())
    if 'error' in reply: raise RuntimeError(reply['error'])
    return reply.get('result',reply)
def obj(name):
    result=send('findByProperty',{'property':'objectName','value':name})
    assert result['count']==1,(name,result)
    return result['matches'][0]['id']
def ev(expr,name): return send('evaluate',{'objectId':obj(name),'expression':expr})
def get(expr,name): return json.loads(ev('JSON.stringify('+expr+')',name))
def click(name): return send('click',{'objectId':obj(name)})
def setp(name,prop,val): return send('setProperty',{'objectId':obj(name),'property':prop,'value':val})
ROOT='keycardRoot'
def value(expr,name=ROOT):return get(expr,name)
def evaluate(expr,name=ROOT):return ev(expr,name)
def wait(expr,name=ROOT):
 for i in range(300):
  if value(expr,name):return
  time.sleep(.1)
 raise AssertionError((expr,value('backend.lastError')))
def close(name):evaluate('close()',name)
def pick(first, picks, pin=True):
 """Show five accounts from `first`, tick the rows in `picks` ([(row, name)]), name them, add them."""
 setp('firstIndex','text',str(first))
 if pin: setp('offerPin','text','123456')
 click('showAccounts');time.sleep(.5);wait('exporting.state === "done" && !working')
 for row,_ in picks: click('selectAccount_'+str(row))
 click('nameAccounts')
 for n,(_,name) in enumerate(picks): setp('addAccountName_'+str(n),'text',name)
 click('keepAccounts');wait('!opened','addAccountsDialog')
def rename_account(wallet, label):
 click('manageWallet_'+str(wallet));click('renameAccount_0')
 setp('accountName','text',label);click('saveAccountName')
 wait('!opened','renameAccountDialog');close('manageWalletDialog')

wait('ready && cards.length === 1')
assert value('cards[0].reader') == 'Keycard simulator'
assert value('cards[0].identity') == '0263c24955ff1e53b5f0de3f61507581494b8a843370f228efdee6a887f2c4cf42'
wallet_id='seed:'+value('cards[0].keyUid')
run_label='Preview '+str(time.time_ns())+' '
for family, coin, script in [('evm',0,0),('bitcoin',1,0),('bitcoin_taproot',1,1)]:
 evaluate('openAdd(wallets.find(function(g){return g.id === '+json.dumps(wallet_id)+'}))')
 setp('accountType','currentIndex',coin)
 setp('bitcoinType','currentIndex',script)
 setp('accountNetwork','currentIndex',0)
 pick(0,[(0,run_label+family)])
 wait('!working && cardGroups.some(function(g){return g.accounts.some(function(a){return a.label === '+json.dumps(run_label+family)+'})})')
index=value('wallets.findIndex(function(g){return g.id === '+json.dumps(wallet_id)+'})')
rows=value('wallets['+str(index)+'].accounts')
assert {'evm','bitcoin','bitcoin_taproot'}.issubset({a['family'] for a in rows})
expected={'bitcoin':'bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu','bitcoin_taproot':'bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr'}
for i,a in enumerate(rows):
 assert a['path'] in value('text','accountPath_'+str(index)+'_'+str(i))
 assert a['preview']['address'] == value('value','accountCopy_'+str(index)+'_'+str(i))
 assert a['preview']['address'][:8] in value('text','accountLine_'+str(index)+'_'+str(i))
 if a.get('label') == run_label+a['family'] and a['family'] in expected:
  assert a['preview']['address']==expected[a['family']]
  assert a['preview']['path']==a['path']+'/0/0'
Path('/tmp/keycard-account-addresses.png').write_bytes(base64.b64decode(send('screenshot')['image']))
# Disconnect only this known test simulator; public previews must remain visible.
import signal,subprocess
pid=int(Path('/tmp/keycard-routing-ui/applet.pid').read_text())
command=subprocess.check_output(['ps','-p',str(pid),'-o','command='],text=True)
assert 'keycard-simulator 47391' in command
os.killpg(pid,signal.SIGTERM)
wait('cards.length === 0')
after=value('wallets.find(function(g){return g.id === '+json.dumps(wallet_id)+'}).accounts')
assert [(a['id'],a['preview']) for a in rows]==[(a['id'],a['preview']) for a in after]
print('PASS: EVM, native SegWit and Taproot paths, published receive addresses, full copy values, offline previews')
