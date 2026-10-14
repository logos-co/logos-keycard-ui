#!/usr/bin/env python3
"""Default pairing UI test; isolated profile + simulator only, inspector port 3773.
Never runs against a real reader. Never prints/snapshots generated recovery words.
"""
from pathlib import Path
import json, socket, time, os
PROFILE = Path('/tmp/keycard-routing-ui/profile')

def send(command, params=None):
    with socket.create_connection(('127.0.0.1',3773),timeout=30) as sock:
        sock.sendall((json.dumps({'command':command,'params':params or {}})+'\n').encode())
        reply=json.loads(sock.makefile('rb').readline())
    if 'error' in reply: raise RuntimeError(reply['error'])
    return reply.get('result',reply)
def obj(name):
    r=send('findByProperty',{'property':'objectName','value':name})
    assert r['count']==1, name
    return r['matches'][0]['id']
def ev(expr,name='cardAdministrationDialog'):
    return send('evaluate',{'objectId':obj(name),'expression':expr})
def value(expr,name='cardAdministrationDialog'): return json.loads(ev('JSON.stringify('+expr+')',name))
def wait(expr,name='cardAdministrationDialog'):
    for _ in range(300):
        if value(expr,name): return
        time.sleep(.1)
    raise AssertionError('UI condition timed out: '+expr)
def click(name): send('click',{'objectId':obj(name)})
def setp(name, prop, v): send('setProperty',{'objectId':obj(name),'property':prop,'value':v})
def choose(action):
    i=value('choices.findIndex(function(c){return c.id === '+json.dumps(action)+'})')
    assert i>=0, action
    setp('adminOperation','currentIndex',i)
def submit():
    assert value('enabled','adminSubmit')
    click('adminSubmit');wait('!busy')
    assert not value('failed'), 'Admin operation failed (details in UI, omitted to protect secrets)'

wait('ready && cards.length === 1','keycardRoot')
assert value('cards[0].reader','keycardRoot')=='Keycard simulator', 'Simulator required'
assert value('cards[0].secureChannel','keycardRoot')==1, '3.x simulator required'
assert value('cards[0].paired','keycardRoot'), 'Default pairing must finish before the manual UI'
click('cardAdministration');wait('opened')
assert value('choices.findIndex(function(c){return c.id === "pair"})')==-1
submit()
status=value('message')
assert "This app's slot:" in status
slot=int(status.rsplit('slot: ',1)[1])
choose('unpair');setp('adminPin','text','123456');setp('adminSlot','text',str(slot))
submit();click('adminRefresh');wait('!selected.paired')
choose('pair');setp('adminPairing','text','KeycardDefaultPairing');submit()
click('adminRefresh');wait('selected.paired')
# Default setup requires only PIN and PUK; advanced custom passwords require confirmation.
choose('factory_reset');setp('adminConfirmation','text','RESET');submit()
click('adminRefresh');wait('!changed && action === "initialize"')
assert not value('visible','adminPairing')
for name, text in [('adminNewPin','123456'),('adminRepeatPin','123456'),('adminPuk','987654321098'),('adminRepeatPuk','987654321098')]: setp(name,'text',text)
assert value('enabled','adminSubmit')
click('adminAdvanced');click('adminCustomPairing')
assert value('visible','adminPairing') and not value('enabled','adminSubmit')
setp('adminPairing','text','custom test password');setp('adminRepeatPairing','text','different')
assert not value('enabled','adminSubmit')
# Closing advanced options returns to the default and clears the custom password.
click('adminAdvanced')
assert not value('visible','adminPairing') and value('text','adminPairing') == ''
submit();click('adminRefresh');wait('selected.initialized && selected.paired')
choose('factory_reset');setp('adminConfirmation','text','RESET');submit()
click('adminRefresh');wait('!changed && action === "initialize"')
for name, text in [('adminNewPin','123456'),('adminRepeatPin','123456'),('adminPuk','987654321098'),('adminRepeatPuk','987654321098')]: setp(name,'text',text)
click('adminAdvanced');click('adminCustomPairing')
setp('adminPairing','text','custom test password');setp('adminRepeatPairing','text','custom test password')
submit();click('adminRefresh');wait('selected.initialized && !selected.paired')
choose('pair');setp('adminPairing','text','custom test password');submit()
click('adminRefresh');wait('selected.paired')
ev('close()')
# Mixed remembered/connected devices: only live connections reach the selector.
fixture={'id':'test:device-filter','pending':True,'connected':True,'accounts':[], 'connections':[
    {'id':'old-reader','transport':'reader','connected':False},
    {'id':'live-reader','transport':'reader','connected':True},
    {'serial':'old-shell','transport':'shell','connected':False},
    {'serial':'live-shell','transport':'shell','connected':True}]}
ev('openAdd('+json.dumps(fixture)+')','keycardRoot')
assert value('connections.length','keycardRoot')==2
assert value('model.length','walletConnection')==2
assert all('old-' not in label for label in value('model','walletConnection'))
ev('pendingWallet = Object.assign({}, pendingWallet, {connections: pendingWallet.connections.map(function(c) { return Object.assign({}, c, {connected:false}) })})','keycardRoot')
assert value('connections.length','keycardRoot')==0
assert not value('connected','keycardRoot')
print('PASS: default and advanced custom setup, automatic/manual pairing, connected-device selector')
print('PASS: automatic default pairing reaches UI; explicit unpair remains unpaired; manual pairing works')
