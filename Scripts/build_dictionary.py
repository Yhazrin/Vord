"""Build Vord's bundled, read-only ECDICT dictionary. No third-party packages."""
import csv, hashlib, json, re, sqlite3, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / 'build' / 'dictionary-source'
OUTPUT = ROOT / 'Vord' / 'Resources'
COMMIT = '82c9872576b23118d7c42e920c11beb77f510ae2'
EXPECTED_BLOB = 'c4ade63ea08cf39d9c3475e96929036d64d94c94'
CACHE.mkdir(parents=True, exist_ok=True)
OUTPUT.mkdir(parents=True, exist_ok=True)
source = CACHE / 'ecdict.csv'
if not source.exists():
    req = urllib.request.Request(f'https://raw.githubusercontent.com/skywind3000/ECDICT/{COMMIT}/ecdict.csv', headers={'User-Agent':'Vord-dictionary-build'})
    temporary = source.with_suffix('.download')
    with urllib.request.urlopen(req, timeout=45) as response, temporary.open('wb') as out:
        while block := response.read(1024 * 1024): out.write(block)
    temporary.replace(source)
data = source.read_bytes()
blob = hashlib.sha1(f'blob {len(data)}\0'.encode()+data).hexdigest()
if blob != EXPECTED_BLOB: raise SystemExit('ECDICT checksum mismatch; dictionary not replaced.')

path = CACHE / 'lexicon.sqlite'
if path.exists(): path.unlink()
db = sqlite3.connect(path)
db.executescript('''
PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF;
CREATE TABLE lexicon(id INTEGER PRIMARY KEY, english TEXT NOT NULL, normalized TEXT NOT NULL UNIQUE,
 chinese TEXT NOT NULL, phonetic TEXT, pos TEXT, definition TEXT, rank INTEGER NOT NULL, search TEXT NOT NULL);
CREATE INDEX english_prefix ON lexicon(normalized);
CREATE TABLE forms(form TEXT NOT NULL, word_id INTEGER NOT NULL, PRIMARY KEY(form,word_id)) WITHOUT ROWID;
CREATE VIRTUAL TABLE chinese_search USING fts5(terms, content='', tokenize='unicode61');
CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
''')
seen = set()
counts = {'entries':0,'english_definitions':0,'aliases':0}

def chinese_terms(text):
    chunks = re.findall(r'[\u3400-\u9fff]+', text)
    terms = set()
    for chunk in chunks:
        terms.add(chunk)
        terms.update(chunk[i:i+2] for i in range(len(chunk)-1))
    return ' '.join(sorted(terms))

with source.open(encoding='utf-8-sig', newline='') as f:
    for row in csv.DictReader(f):
        word = row['word'].strip()
        normalized = word.lower()
        chinese = row['translation'].replace('\\n','\n').strip()
        if not word or not chinese or normalized in seen: continue
        seen.add(normalized)
        definition = row['definition'].replace('\\n','\n').strip()
        phonetic = row['phonetic'].strip()
        pos = ', '.join(re.findall(r'([a-z]+):',row['pos']))
        if not pos: pos = ', '.join(dict.fromkeys(re.findall(r'(?:^|\n)([a-z]+)\.', chinese)))
        ranks = [int(x) for x in [row['bnc'],row['frq']] if x.isdigit() and int(x)>0]
        rank = min(ranks) if ranks else 1000000
        if row['tag'].strip(): rank = min(rank,50000)
        cursor = db.execute('INSERT INTO lexicon(english,normalized,chinese,phonetic,pos,definition,rank,search) VALUES(?,?,?,?,?,?,?,?)',
            (word,normalized,chinese,phonetic or None,pos or None,definition or None,rank,chinese))
        word_id = cursor.lastrowid
        terms = chinese_terms(chinese)
        if terms: db.execute('INSERT INTO chinese_search(rowid,terms) VALUES(?,?)',(word_id,terms))
        for exchange in row['exchange'].split('/'):
            if ':' not in exchange: continue
            kind, values = exchange.split(':',1)
            if kind in {'p','d','i','3','r','t','s'}:
                for form in values.split(','):
                    form = form.strip().lower()
                    if form and form != normalized:
                        db.execute('INSERT OR IGNORE INTO forms(form,word_id) VALUES(?,?)',(form,word_id))
        counts['entries'] += 1
        counts['english_definitions'] += bool(definition)
db.execute("INSERT INTO chinese_search(chinese_search) VALUES('optimize')")
counts['aliases'] = db.execute('SELECT count(*) FROM forms').fetchone()[0]
metadata = {'source':'ECDICT','commit':COMMIT,'git_blob':blob,'schema_version':'1', **{k:str(v) for k,v in counts.items()}}
db.executemany('INSERT INTO metadata VALUES(?,?)',metadata.items())
db.commit(); db.execute('VACUUM'); db.close()
path.replace(OUTPUT / 'lexicon.sqlite')
(OUTPUT/'dictionary-info.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n')
req = urllib.request.Request('https://raw.githubusercontent.com/skywind3000/ECDICT/master/LICENSE',headers={'User-Agent':'Vord-dictionary-build'})
with urllib.request.urlopen(req,timeout=30) as response: license_text=response.read().decode()
(OUTPUT/'ECDICT-LICENSE.txt').write_text(license_text)
print(json.dumps({**counts,'database_mb':round((OUTPUT/'lexicon.sqlite').stat().st_size/1024**2,1)},ensure_ascii=False))
