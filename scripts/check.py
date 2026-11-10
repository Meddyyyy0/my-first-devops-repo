import json,subprocess,urllib.request,pathlib
base="http://localhost:8083"
assert urllib.request.urlopen(base+"/healthz").read()==b"ok"
items=json.load(urllib.request.urlopen(base+"/api/items"))
sql="SELECT coalesce(json_agg(t), '[]'::json) FROM (SELECT id,name FROM items ORDER BY id) t;"
db=json.loads(subprocess.check_output(["docker","compose","exec","-T","db","psql","-U","app","-d","appdb","-tAc",sql]))
assert items==db and len(items)>0,(items,db)
assert urllib.request.urlopen(base+"/").status==200
pathlib.Path("verification/test-report.json").write_text(json.dumps({"health":"ok","database":db,"api":items,"exact_match":True},ensure_ascii=False,indent=2))
print("PASS: health, web page, database connection, exact database/API equality")
