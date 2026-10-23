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

wait('ready && cardGroups.length === 1 && shellDevices.length === 1')
assert value('cards.length === 1 && cards[0].reader === "Keycard simulator"'), 'Simulator required'
assert value('shellDevices[0].serial') == '62a772f85e4be6226108b56c0b1cf9', 'Known emulator required'
reader=value('wallets.findIndex(function(g){return g.id.indexOf("seed:") === 0})')
click('addAccounts_'+str(reader));pick(0,[(0,'Reader savings')])
wait('cardGroups[0].accounts.length === 1 && !working')
click('manageWallet_'+str(reader));setp('walletName','text','Reader wallet');click('saveWalletName');wait('cardGroups[0].name === "Reader wallet"');close('manageWalletDialog')
evaluate('openAdd({id:"shell:"+shellDevices[0].serial+":", serial:shellDevices[0].serial,pending:true,transport:"shell",accounts:[],connected:true})')
pick(0,[(0,'Shell savings')],pin=False)
wait('shellGroups.length === 1 && shellGroups[0].accounts.length === 1 && !working')
wait('wallets.length === 1 && wallets[0].connections.length === 2')
assert value('wallets[0].accounts.length') == 1
assert value('wallets[0].accounts[0].aliases') == ['Reader savings','Shell savings']
evaluate('openAdd(wallets[0]); selectedConnectionId = "shell:" + shellDevices[0].serial + ":"')
assert value('shell'), 'The merged wallet adds through the Shell it names'
pick(1,[(0,'Second account')],pin=False);wait('shellGroups[0].accounts.length === 2 && !working')
click('manageWallet_0');setp('walletName','text','Unified wallet');click('saveWalletName');wait('cardGroups[0].name === "Unified wallet" && shellGroups[0].name === "Unified wallet"')
click('renameAccount_0');setp('accountName','text','Unified savings');click('saveAccountName');wait('!opened','renameAccountDialog')
wait('cardGroups[0].accounts[0].label === "Unified savings" && shellGroups[0].accounts[0].label === "Unified savings"')
close('manageWalletDialog')
print('PASS: same master key merges reader and Shell; account deduplication, labels, connection selection, derivation, and rename across both providers',flush=True)
Path('/tmp/keycard-seed-check/unified.png').write_bytes(base64.b64decode(send('screenshot')['image']))
