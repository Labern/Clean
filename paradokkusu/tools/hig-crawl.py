import json,os,subprocess,concurrent.futures as cf
B='https://developer.apple.com/tutorials/data'
P='/design/human-interface-guidelines'
seen={P};todo=[P];docs={}
def get(u):
    f='raw_'+(u[len(P):].strip('/').replace('/','__') or 'index')+'.json'
    if not os.path.exists(f) or os.path.getsize(f)<50:
        subprocess.run(['curl','-sL','-m','40',B+u+'.json','-o',f])
    try: return u,json.load(open(f))
    except Exception as e: return u,None
while todo:
    batch,todo=todo,[]
    with cf.ThreadPoolExecutor(12) as ex:
        for u,d in ex.map(get,batch):
            if not d: print('FAIL',u); continue
            docs[u]=d
            for v in d.get('references',{}).values():
                x=v.get('url','')
                if x.startswith(P+'/') and '#' not in x and x not in seen:
                    seen.add(x); todo.append(x)
print(len(docs))
def inl(a,refs):
    o=''
    for i in a or []:
        t=i.get('type')
        if t=='text': o+=i['text']
        elif t=='codeVoice': o+='`'+i['code']+'`'
        elif t in('emphasis','strong','newTerm','inlineHead'): o+=inl(i.get('inlineContent'),refs)
        elif t=='reference':
            r=refs.get(i['identifier'],{}); o+=r.get('title') or inl(i.get('overridingTitleInlineContent'),refs) or ''
        elif t=='image': pass
    return o
def blk(a,refs,d=0):
    o=[]
    for b in a or []:
        t=b.get('type')
        if t=='heading': o.append('\n'+'#'*(b['level']+1)+' '+b['text'])
        elif t=='paragraph':
            s=inl(b['inlineContent'],refs)
            if s.strip(): o.append(s)
        elif t in('unorderedList','orderedList'):
            for it in b['items']: o.append('  '*d+'- '+' '.join(blk(it['content'],refs,d+1)))
        elif t=='aside': o.append('> '+b.get('name',b.get('style',''))+': '+' '.join(blk(b['content'],refs)))
        elif t=='table':
            for row in b['rows']: o.append('| '+' | '.join(' '.join(blk(c,refs)) for c in row)+' |')
        elif t=='tabNavigator':
            for tab in b['tabs']: o.append('['+tab['title']+']'); o+=blk(tab['content'],refs)
        elif t=='row':
            for c in b['columns']: o+=blk(c['content'],refs)
        elif t=='termList':
            for it in b['items']: o.append('- '+inl(it['term']['inlineContent'],refs)+': '+' '.join(blk(it['definition']['content'],refs)))
        elif t in('links','video','codeListing','small','thematicBreak'): 
            if t=='small': o.append(inl(b['inlineContent'],refs))
        else: o.append('<<'+str(t)+'>>')
    return o
os.makedirs('md',exist_ok=True); tot=0
for u,d in sorted(docs.items()):
    refs=d.get('references',{})
    out=['# '+d['metadata'].get('title',u),inl(d.get('abstract'),refs)]
    for s in d.get('primaryContentSections',[]):
        if s.get('kind')=='content': out+=blk(s['content'],refs)
    txt='\n'.join(out); tot+=len(txt)
    open('md/'+(u[len(P):].strip('/').replace('/','__') or 'index')+'.md','w').write(txt)
print(tot)
