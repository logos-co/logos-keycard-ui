#!/usr/bin/env python3
"""Destructive ADMIN UI test; isolated profile + simulator only, inspector port 3773.
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
# The expected factory simulator identity is different from every physical card used in the demo.
assert value('cards[0].identity','keycardRoot')=='0263c24955ff1e53b5f0de3f61507581494b8a843370f228efdee6a887f2c4cf42'
base=PROFILE/'module_data/keycard_module'
before={str(p):p.read_bytes() for p in base.rglob('accounts.json')}
click('cardAdministration');wait('opened')
submit();assert 'PIN attempts left: 3' in value('message')
choose('check_identity');submit();assert 'identity verified' in value('message')
choose('set_name');setp('adminPin','text','123456');setp('adminData','text','UI test card');submit()
choose('status');submit();assert 'UI test card' in value('message')
choose('remove_key');setp('adminPin','text','123456')
assert not value('enabled','adminSubmit')
setp('adminConfirmation','text','ERASE');submit()
assert value('changed')
click('adminRefresh');wait('!changed')
choose('generate_phrase');setp('adminWordCount','currentIndex',4);setp('adminPin','text','123456');submit()
assert value('generated.length')==24
recovery=value('generated.join(" ")')
assert not value('enabled','adminSubmit'), 'Backup acknowledgement must be required'
setp('adminPin','text','123456');setp('adminBackup','checked',True)
submit();assert value('generated.length')==0
click('adminRefresh');wait('!changed')
choose('verify_phrase');setp('adminPin','text','123456');setp('adminPhrase','text',recovery);submit()
assert 'match this card' in value('message')
choose('factory_reset');assert not value('enabled','adminSubmit')
setp('adminConfirmation','text','RESET');submit()
click('adminRefresh');wait('!changed && action === "initialize"')
setp('adminNewPin','text','123456');setp('adminRepeatPin','text','123456')
setp('adminPuk','text','987654321098');setp('adminRepeatPuk','text','987654321098')
submit();click('adminRefresh');wait('selected.initialized && !changed')
for file in list((PROFILE/'module_data').rglob('*.json'))+[Path('/tmp/keycard-routing-ui/app.log')]:
    assert recovery.encode() not in file.read_bytes(), 'Recovery phrase was persisted or logged'
recovery=''
assert {str(p):p.read_bytes() for p in base.rglob('accounts.json')}==before, 'Saved accounts/names changed'
ev('close()');assert value('generated.length')==0
print('PASS: simulator administration UI: status/authenticity, card name, erase confirmation, 24 numbered words, backup gate, load, reset, setup; saved accounts/names preserved')
