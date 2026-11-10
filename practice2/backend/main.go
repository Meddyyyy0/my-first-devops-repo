package main
import (
 "database/sql"
 "encoding/json"
 "log"
 "net/http"
 "net/url"
 "os"
 "time"
 _ "github.com/lib/pq"
)
type Item struct { ID int `json:"id"`; Name string `json:"name"` }
func env(k,d string) string { if v:=os.Getenv(k); v!="" {return v}; return d }
func main(){
 u:=url.URL{Scheme:"postgres",Host:env("DB_HOST","db")+":"+env("DB_PORT","5432"),Path:env("DB_NAME","appdb"),User:url.UserPassword(env("DB_USER","app"),os.Getenv("DB_PASSWORD"))}
 q:=u.Query(); q.Set("sslmode","disable"); u.RawQuery=q.Encode()
 db,err:=sql.Open("postgres",u.String()); if err!=nil {log.Fatal(err)}; defer db.Close()
 db.SetMaxOpenConns(10)
 mux:=http.NewServeMux()
 mux.HandleFunc("/api/items",func(w http.ResponseWriter,r *http.Request){
 if r.Method!="GET" {w.WriteHeader(http.StatusMethodNotAllowed);return}
 rows,err:=db.QueryContext(r.Context(),"SELECT id,name FROM items ORDER BY id"); if err!=nil {http.Error(w,"database unavailable",503);return}; defer rows.Close()
 items:=[]Item{}; for rows.Next(){var it Item;if err:=rows.Scan(&it.ID,&it.Name);err!=nil {http.Error(w,"read error",500);return};items=append(items,it)}
 if err:=rows.Err();err!=nil {http.Error(w,"read error",500);return}
 w.Header().Set("Content-Type","application/json");json.NewEncoder(w).Encode(items)
 })
 mux.HandleFunc("/healthz",func(w http.ResponseWriter,r *http.Request){if err:=db.PingContext(r.Context());err!=nil {http.Error(w,"not ready",503);return};w.Write([]byte("ok"))})
 mux.Handle("/",http.FileServer(http.Dir(env("STATIC_DIR","/app/static"))))
 s:=http.Server{Addr:":8080",Handler:mux,ReadHeaderTimeout:5*time.Second,WriteTimeout:15*time.Second}
 log.Println("listening on :8080");log.Fatal(s.ListenAndServe())
}
