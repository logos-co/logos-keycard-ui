#!/usr/bin/env python3
"""Exercise forgetting in an isolated fixture profile (never a personal profile).
Requires QML inspector port 3769, no reader, and three fixture groups:
Travel card and Backup test card sharing one offer, then Empty test card with none.
"""
import socket

def send(command, params=None):
    with socket.create_connection(("127.0.0.1", 3769), timeout=10) as sock:
        f = sock.makefile("rwb")
        f.write((json.dumps({"command": command, "params": params or {}}) + "\n").encode())
        f.flush()
        reply = json.loads(f.readline())
        if "error" in reply:
            raise RuntimeError(reply["error"])
        return reply.get("result", reply)

import time,json

def obj(name):
 r=send('findByProperty',{'property':'objectName','value':name});assert r['count']==1,(name,r);return r['matches'][0]['id']
def ev(expr):return send('evaluate',{'objectId':obj('keycardRoot'),'expression':expr})
def val(expr):return json.loads(ev('JSON.stringify('+expr+')'))
def click(name):return send('click',{'objectId':obj(name)})
def wait(expr):
 for _ in range(100):
  if val(expr):return
  time.sleep(.1)
 raise AssertionError((expr,ev('backend.lastError')))
wait('ready && cardGroups.length === 3')
assert val('cardGroups.map(function(g){return g.name})') == ['Travel card','Backup test card','Empty test card']
assert val('accounts.length')==1
click('manageWallet_2');click('forgetWallet');time.sleep(.2)
click('cancelForgetSavedCard');send('evaluate',{'objectId':obj('manageWalletDialog'),'expression':'close()'})
assert val('cardGroups.length')==3
print('PASS: Cancel leaves cards and accounts intact')
click('manageWallet_2');click('forgetWallet');click('confirmForgetSavedCard')
wait('cardGroups.length === 2')
assert val('accounts.length')==1
print('PASS: empty card can be forgotten')
click('manageWallet_0');click('forgetWallet');click('confirmForgetSavedCard')
wait('cardGroups.length === 1')
assert val('cardGroups[0].name')=='Backup test card'
assert val('accounts.length')==1
print('PASS: forgetting one card preserves the account shared with the backup card')
click('manageWallet_0');click('forgetWallet');click('confirmForgetSavedCard')
wait('cardGroups.length === 0 && accounts.length === 0')
print('PASS: forgetting the last card removes its offered accounts')
