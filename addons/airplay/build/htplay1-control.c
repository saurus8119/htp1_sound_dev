#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

#define PORT 17821
#define ROOT "/var/lib/olympia/addons/airplay2"
#define CFG ROOT "/etc/shairport-sync.conf"
#define LOG ROOT "/www/logs.txt"
#define MAX_REQ 65536
#define MAX_CONFIG 32768

static int send_all(int fd, const char *p, size_t n) {
  while (n) { ssize_t k=send(fd,p,n,0); if(k<=0)return -1; p+=k; n-=(size_t)k; }
  return 0;
}
static void reply(int fd,int code,const char *type,const char *body,const char *origin) {
  const char *reason=code==200?"OK":code==400?"Bad Request":code==403?"Forbidden":code==404?"Not Found":code==405?"Method Not Allowed":code==413?"Payload Too Large":"Internal Server Error";
  char h[1200];
  int n=snprintf(h,sizeof h,"HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %zu\r\nCache-Control: no-store\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\n%s%s%s\r\n",code,reason,type,strlen(body),origin?"Access-Control-Allow-Origin: ":"",origin?origin:"",origin?"\r\nVary: Origin\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\n":"");
  if(n>0&&(size_t)n<sizeof h){send_all(fd,h,(size_t)n);send_all(fd,body,strlen(body));}
}
static int private_peer(struct sockaddr_in *a) {
  unsigned long x=ntohl(a->sin_addr.s_addr);
  return (x>>24)==10 || (x>>20)==0xac1 || (x>>16)==0xc0a8 || (x>>24)==127;
}
static int read_file(const char *p,char *b,size_t cap) {
  FILE *f=fopen(p,"rb"); if(!f)return -1;
  size_t n=fread(b,1,cap-1,f); int bad=ferror(f); fclose(f); if(bad)return -1; b[n]=0; return (int)n;
}
static void json_escape(char *o,size_t cap,const char *s) {
  size_t j=0; for(size_t i=0;s[i]&&j+2<cap;i++){unsigned char c=(unsigned char)s[i];
    if(c=='"'||c=='\\'){o[j++]='\\';o[j++]=(char)c;}
    else if(c=='\n'){o[j++]='\\';o[j++]='n';}
    else if(c=='\r'){o[j++]='\\';o[j++]='r';}
    else if(c=='\t'){o[j++]='\\';o[j++]='t';}
    else if(c>=32)o[j++]=(char)c;
  } o[j]=0;
}
static int service_active(const char *unit) {
  char cmd[128]; snprintf(cmd,sizeof cmd,"/bin/systemctl is-active --quiet %s",unit);
  return system(cmd)==0;
}
static int service_action(const char *action) {
  char cmd[128]; snprintf(cmd,sizeof cmd,"/bin/systemctl %s airplay2.service",action);
  return system(cmd)==0;
}
static int set_verbosity(int value) {
  char old[32768],next[32768],tmp[256],bak[256];
  int n=read_file(CFG,old,sizeof old); if(n<0)return -1;
  char *d=strstr(old,"diagnostics"); if(!d)return -2;
  char *end=strchr(d,'}'); char *k=strstr(d,"log_verbosity");
  if(!end||!k||k>end)return -2;
  char *eq=strchr(k,'='); char *semi=eq?strchr(eq,';'):NULL;
  if(!eq||!semi||semi>end)return -2;
  char val[24]; int vn=snprintf(val,sizeof val,"= %d;",value);
  size_t pre=(size_t)(eq-old),tail=strlen(semi+1);
  if(pre+(size_t)vn+tail>=sizeof next)return -1;
  memcpy(next,old,pre); memcpy(next+pre,val,(size_t)vn); memcpy(next+pre+(size_t)vn,semi+1,tail+1);
  snprintf(bak,sizeof bak,"%s/etc/shairport-sync.conf.bak",ROOT);
  snprintf(tmp,sizeof tmp,"%s/etc/.shairport-sync.conf.tmp",ROOT);
  FILE *f=fopen(bak,"wb"); if(!f)return -1;
  if(fwrite(old,1,(size_t)n,f)!=(size_t)n||fclose(f))return -1;
  chmod(bak,0600);
  f=fopen(tmp,"wb"); if(!f)return -1;
  size_t nn=strlen(next); if(fwrite(next,1,nn,f)!=nn||fclose(f)){unlink(tmp);return -1;}
  chmod(tmp,0644);
  if(rename(tmp,CFG)){unlink(tmp);return -1;}
  return 0;
}
static int save_config(const char *data,size_t len) {
  char bak[256],tmp[256];
  if(!len||len>MAX_CONFIG||memchr(data,'\0',len))return -2;
  snprintf(bak,sizeof bak,"%s/etc/shairport-sync.conf.bak",ROOT);
  snprintf(tmp,sizeof tmp,"%s/etc/.shairport-sync.conf.tmp",ROOT);
  FILE *src=fopen(CFG,"rb"); if(!src)return -1;
  FILE *dst=fopen(bak,"wb"); if(!dst){fclose(src);return -1;}
  char buf[4096]; size_t n; int failed=0;
  while((n=fread(buf,1,sizeof buf,src))>0)if(fwrite(buf,1,n,dst)!=n){failed=1;break;}
  if(ferror(src))failed=1;
  if(fclose(src))failed=1;
  if(fclose(dst))failed=1;
  if(failed)return -1;
  chmod(bak,0600);
  FILE *out=fopen(tmp,"wb"); if(!out)return -1;
  if(fwrite(data,1,len,out)!=len){fclose(out);unlink(tmp);return -1;}
  if(fclose(out)){unlink(tmp);return -1;}
  chmod(tmp,0644);
  if(rename(tmp,CFG)){unlink(tmp);return -1;}
  return 0;
}
static void handle(int fd) {
  char req[MAX_REQ+1]; size_t used=0;
  while(used<MAX_REQ){ssize_t n=recv(fd,req+used,MAX_REQ-used,0);if(n<=0)return;used+=(size_t)n;req[used]=0;if(strstr(req,"\r\n\r\n"))break;}
  char *sep=strstr(req,"\r\n\r\n"); if(!sep){reply(fd,400,"application/json","{\"error\":\"bad request\"}",NULL);return;}
  size_t header_len=(size_t)(sep-req)+4, content_len=0;
  char *cl=strcasestr(req,"\r\nContent-Length:");
  if(cl){char *v=strchr(cl,':')+1;while(*v==' '||*v=='\t')v++;char *e=NULL;unsigned long z=strtoul(v,&e,10);if(e==v||z>MAX_CONFIG){reply(fd,413,"application/json","{\"error\":\"request body too large\"}",NULL);return;}content_len=(size_t)z;}
  if(header_len+content_len>MAX_REQ){reply(fd,413,"application/json","{\"error\":\"request too large\"}",NULL);return;}
  while(used<header_len+content_len){ssize_t n=recv(fd,req+used,MAX_REQ-used,0);if(n<=0){reply(fd,400,"application/json","{\"error\":\"incomplete request body\"}",NULL);return;}used+=(size_t)n;req[used]=0;}
  *sep=0; char method[8]={0},path[256]={0},host[256]={0},origin[512]={0};
  if(sscanf(req,"%7s %255s",method,path)!=2){reply(fd,400,"application/json","{\"error\":\"bad request line\"}",NULL);return;}
  char *line=strstr(req,"\r\n");
  while(line){line+=2;if(!*line)break;char *next=strstr(line,"\r\n");if(next)*next=0;
    if(!strncasecmp(line,"Host:",5))snprintf(host,sizeof host,"%s",line+5);
    if(!strncasecmp(line,"Origin:",7))snprintf(origin,sizeof origin,"%s",line+7);
    if(!next) break;
    line=next;
  }
  while(*host==' '||*host=='\t')memmove(host,host+1,strlen(host));
  while(*origin==' '||*origin=='\t')memmove(origin,origin+1,strlen(origin));
  char *colon=strchr(host,':');if(colon)*colon=0;
  const char *cors=NULL;
  if(origin[0]){
    char expected[600];snprintf(expected,sizeof expected,"http://%s",host);
    if(strcmp(origin,expected)){snprintf(expected,sizeof expected,"https://%s",host);if(strcmp(origin,expected)){reply(fd,403,"application/json","{\"error\":\"origin rejected\"}",NULL);return;}}
    cors=origin;
  }
  char *body=sep+4; body[content_len]=0;
  if(!strcmp(method,"OPTIONS")){reply(fd,200,"text/plain","",cors);return;}
  if(!strcmp(method,"GET")&&!strcmp(path,"/api/status")){
    char b[256];snprintf(b,sizeof b,"{\"receiver\":\"%s\",\"nqptp\":\"%s\"}",service_active("airplay2.service")?"active":"inactive",service_active("nqptp-airplay2.service")?"active":"inactive");
    reply(fd,200,"application/json",b,cors);return;
  }
  if(!strcmp(method,"GET")&&(!strcmp(path,"/api/logs")||!strcmp(path,"/api/config"))){
    char raw[MAX_CONFIG+1],esc[(MAX_CONFIG*2)+1],out[(MAX_CONFIG*2)+128];const char *file=!strcmp(path,"/api/logs")?LOG:CFG;
    if(read_file(file,raw,sizeof raw)<0)snprintf(raw,sizeof raw,"Unable to read %s",file);
    json_escape(esc,sizeof esc,raw);
    snprintf(out,sizeof out,!strcmp(path,"/api/logs")?"{\"logs\":\"%s\"}":"{\"config\":\"%s\"}",esc);
    reply(fd,200,"application/json",out,cors);return;
  }
  if(!strcmp(method,"POST")&&(!strcmp(path,"/api/start")||!strcmp(path,"/api/stop")||!strcmp(path,"/api/restart"))){
    const char *a=!strcmp(path,"/api/start")?"start":!strcmp(path,"/api/stop")?"stop":"restart";
    int r=service_action(a);reply(fd,r?500:200,"application/json",r?"{\"error\":\"systemd operation failed\"}":"{\"ok\":true}",cors);return;
  }
  if(!strcmp(method,"POST")&&!strcmp(path,"/api/config")){
    int r=save_config(body,content_len);
    reply(fd,r==-2?400:r?500:200,"application/json",r==-2?"{\"error\":\"configuration is empty, too large, or contains NUL bytes\"}":r?"{\"error\":\"configuration save failed; previous file may be in backup\"}":"{\"ok\":true,\"backup\":\"shairport-sync.conf.bak\",\"restart_required\":true}",cors);return;
  }
  if(!strcmp(method,"POST")&&!strcmp(path,"/api/config/log-verbosity")){
    char *v=strstr(body,"\"value\"");int x=-1;if(v&&(v=strchr(v,':')))x=atoi(v+1);
    if(x<0||x>2){reply(fd,400,"application/json","{\"error\":\"verbosity must be 0, 1 or 2\"}",cors);return;}
    int r=set_verbosity(x);reply(fd,r?500:200,"application/json",r?"{\"error\":\"config update failed; inspect config and backup\"}":"{\"ok\":true,\"backup\":\"shairport-sync.conf.bak\",\"restart_required\":true}",cors);return;
  }
  reply(fd,404,"application/json","{\"error\":\"unknown endpoint\"}",cors);
}
int main(void) {
  signal(SIGPIPE,SIG_IGN);int s=socket(AF_INET,SOCK_STREAM,0);if(s<0)return 1;
  int one=1;setsockopt(s,SOL_SOCKET,SO_REUSEADDR,&one,sizeof one);
  struct sockaddr_in a;memset(&a,0,sizeof a);a.sin_family=AF_INET;a.sin_addr.s_addr=htonl(INADDR_ANY);a.sin_port=htons(PORT);
  if(bind(s,(struct sockaddr*)&a,sizeof a)||listen(s,8))return 2;
  for(;;){struct sockaddr_in peer;socklen_t len=sizeof peer;int fd=accept(s,(struct sockaddr*)&peer,&len);if(fd<0){if(errno==EINTR)continue;break;}
    struct timeval tv={3,0};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&tv,sizeof tv);setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&tv,sizeof tv);
    if(private_peer(&peer))handle(fd);else reply(fd,403,"application/json","{\"error\":\"private LAN clients only\"}",NULL);
    close(fd);
  }
  close(s);return 0;
}