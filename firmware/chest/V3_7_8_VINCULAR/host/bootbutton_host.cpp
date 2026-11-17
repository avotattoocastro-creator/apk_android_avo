#include "avo_input.h"
#include <cstdio>
#include <initializer_list>
#include <utility>
using namespace avo;
int fails=0;
#define C(x) do{ if(!(x)){printf("FAIL %d %s\n",__LINE__,#x); fails++;} }while(0)
static BootButton::Event run(BootButton& b, uint32_t& t, std::initializer_list<std::pair<bool,uint32_t>> seq, BootButton::Event* last=nullptr){
  BootButton::Event got=BootButton::NONE;
  for (auto& s: seq){ for(uint32_t i=0;i<s.second;i++){ auto e=b.update(s.first,t++); if(e) got=e; } }
  return got;
}
int main(){
  { BootButton b; uint32_t t=0; C(run(b,t,{{false,50},{true,80},{false,500}})==BootButton::SHORT); }
  { BootButton b; uint32_t t=0; C(run(b,t,{{false,50},{true,80},{false,150},{true,80},{false,500}})==BootButton::DOUBLE); }
  { BootButton b; uint32_t t=0; C(run(b,t,{{false,50},{true,80},{false,150},{true,80},{false,150},{true,80},{false,500}})==BootButton::TRIPLE); }
  { BootButton b; uint32_t t=0; C(run(b,t,{{false,50},{true,2100},{false,500}})==BootButton::LONG); }
  { BootButton b; uint32_t t=0; int n=0; for(int k=0;k<3;k++){ for(int i=0;i<80;i++) if(b.update(true,t++)) n++; for(int i=0;i<150;i++) if(b.update(false,t++)) n++; } for(int i=0;i<500;i++) if(b.update(false,t++)) n++; C(n==1); }
  printf("bootbutton host: %s\n", fails? "FAIL":"OK"); return fails;
}
