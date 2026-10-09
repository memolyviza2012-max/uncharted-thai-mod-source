#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <bcrypt.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#pragma comment(lib,"bcrypt.lib")
struct Patch {uint32_t rva; uint8_t size,offset,length;uint32_t value;uint8_t relative;uint8_t expected[16];};
struct Profile {const wchar_t* name;uint8_t sha[32];uint32_t timestamp,imageSize,manager,ctor,ctorCall,refresh;uint8_t callBytes[5];const Patch* patches;size_t count;};
#include "profiles.h"
static unsigned char* image;
static unsigned char* manager;
static const Profile* active;
static HMODULE originalVersion;
static bool constructed=false;
static const char thaiName[]="thai";
static const char thaiCode[]="tha";
static const char thaiLabel[]="LANGUAGE_THAI";
static const wchar_t logPath[]=L"E:\\Mod_Workspace\\UNCHARTED_Legacy_of_Thieves_Collection\\05_Scripts_and_Tools\\native_language_extension\\runtime.log";
static void Log(const char* text) { HANDLE f=CreateFileW(logPath,FILE_APPEND_DATA,FILE_SHARE_READ|FILE_SHARE_WRITE,nullptr,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);if(f!=INVALID_HANDLE_VALUE){DWORD written;WriteFile(f,text,(DWORD)strlen(text),&written,nullptr);WriteFile(f,"\r\n",2,&written,nullptr);CloseHandle(f);} }
static bool WriteMemory(void* dst,const void* src,size_t length){DWORD old;if(!VirtualProtect(dst,length,PAGE_EXECUTE_READWRITE,&old))return false;memcpy(dst,src,length);FlushInstructionCache(GetCurrentProcess(),dst,length);DWORD ignore;return VirtualProtect(dst,length,old,&ignore)!=0;}
static void Construct() {
    // Native constructor always sees its original compact layout. Expand only after it returns.
    if(constructed){Log("Language constructor called twice; extension refused to reconstruct live state");return;}
    reinterpret_cast<void(*)()>(image+active->ctor)();
    unsigned char tail[0x1c8];memcpy(tail,manager+0x9c8,sizeof(tail));
    memset(manager+0x9c8,0,0xc70-0x9c8);
    for(int k=0;k<4;++k)memcpy(manager+0xa98+k*104,tail+k*100,100);
    memcpy(manager+0xc38,tail+400,56);
    // ID 24 remains the native invalid sentinel. Thai uses ID 25; original IDs are untouched.
    unsigned char* d=manager+8+25*104;memcpy(d,manager+8,104);
    *reinterpret_cast<uint32_t*>(d)=25;*reinterpret_cast<uint32_t*>(d+4)=0x4e5647d8;
    *reinterpret_cast<uint32_t*>(d+0x20)=25;*reinterpret_cast<uint32_t*>(d+0x24)=0;
    *reinterpret_cast<const char**>(d+0x30)=thaiCode;*reinterpret_cast<const char**>(d+0x38)=thaiLabel;
    *reinterpret_cast<const char**>(d+0x40)=thaiName;
    *reinterpret_cast<uint16_t*>(d+0x58)=0x041e;
    d[0x60]=1;d[0x61]=0;
    for(int kind=1;kind<=3;kind+=2){uint32_t* list=reinterpret_cast<uint32_t*>(manager+0xa98+kind*104);if(list[0]>24){Log("Original language count exceeds supported capacity");return;}list[1+list[0]]=25;++list[0];}
    constructed=true;Log("Native Thai ID 25 ready; all original language IDs retained; text/subtitle lists extended");
}
static bool Initialize(unsigned char* module,const Profile* p) {
    if(active)return false;
    auto dos=reinterpret_cast<IMAGE_DOS_HEADER*>(module);auto nt=reinterpret_cast<IMAGE_NT_HEADERS64*>(module+dos->e_lfanew);
    if(dos->e_magic!=IMAGE_DOS_SIGNATURE||nt->Signature!=IMAGE_NT_SIGNATURE||nt->FileHeader.TimeDateStamp!=p->timestamp||nt->OptionalHeader.SizeOfImage!=p->imageSize)return false;
    for(size_t n=0;n<p->count;++n){auto& x=p->patches[n];if(memcmp(module+x.rva,x.expected,x.size)){Log("Executable signature mismatch; no patches applied");return false;}}
    if(memcmp(module+p->ctorCall,p->callBytes,5))return false;
    // A nearby allocation permits all native RIP-relative instructions to retain their length.
    unsigned char* area=nullptr;uintptr_t start=reinterpret_cast<uintptr_t>(module);
    for(uintptr_t distance=0x10000000;distance<0x70000000&&!area;distance+=0x10000){area=static_cast<unsigned char*>(VirtualAlloc(reinterpret_cast<void*>(start+distance),0x10000,MEM_RESERVE|MEM_COMMIT,PAGE_READWRITE));}
    if(!area){Log("No nearby allocation available; no patches applied");return false;}
    memcpy(area,module+p->manager,0xb90);
    // Validate every replacement and relative displacement before the first code write.
    for(size_t n=0;n<p->count;++n){auto& x=p->patches[n];if(x.relative){intptr_t rel=(area+x.value)-(module+(x.relative==1?x.rva+x.size:0));if(rel<INT32_MIN||rel>INT32_MAX){VirtualFree(area,0,MEM_RELEASE);return false;}}}
    unsigned char* thunk=area+0xf000;unsigned char jump[14]={0xff,0x25,0,0,0,0};void* target=reinterpret_cast<void*>(&Construct);memcpy(jump+6,&target,8);memcpy(thunk,jump,14);DWORD old;if(!VirtualProtect(thunk,0x1000,PAGE_EXECUTE_READ,&old)){VirtualFree(area,0,MEM_RELEASE);return false;}
    image=module;manager=area;active=p;
    size_t applied=0;
    for(;applied<p->count;++applied){auto& x=p->patches[applied];unsigned char bytes[16];memcpy(bytes,x.expected,x.size);int64_t value=x.relative?(area+x.value)-(module+(x.relative==1?x.rva+x.size:0)):x.value;memcpy(bytes+x.offset,&value,x.length);if(!WriteMemory(module+x.rva,bytes,x.size))break;}
    unsigned char call[5]={0xe8};int32_t disp=static_cast<int32_t>(thunk-(module+p->ctorCall+5));memcpy(call+1,&disp,4);
    if(applied!=p->count||!WriteMemory(module+p->ctorCall,call,5)){while(applied){auto& x=p->patches[--applied];WriteMemory(module+x.rva,x.expected,x.size);}WriteMemory(module+p->ctorCall,p->callBytes,5);active=nullptr;manager=nullptr;VirtualFree(area,0,MEM_RELEASE);Log("Patch failed and original bytes restored");return false;}
    Log("Exact executable build verified; native table relocation and selector capacity patches installed");return true;
}
static bool HashFile(const wchar_t* path,unsigned char hash[32]) {
    HANDLE file=CreateFileW(path,GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);if(file==INVALID_HANDLE_VALUE)return false;
    BCRYPT_ALG_HANDLE alg=nullptr;BCRYPT_HASH_HANDLE state=nullptr;bool ok=false;
    if(BCryptOpenAlgorithmProvider(&alg,BCRYPT_SHA256_ALGORITHM,nullptr,0)>=0&&BCryptCreateHash(alg,&state,nullptr,0,nullptr,0,0)>=0){unsigned char buffer[65536];DWORD count;ok=true;while(ReadFile(file,buffer,sizeof(buffer),&count,nullptr)&&count){if(BCryptHashData(state,buffer,count,0)<0){ok=false;break;}}if(ok)ok=BCryptFinishHash(state,hash,32,0)>=0;}
    if(state)BCryptDestroyHash(state);if(alg)BCryptCloseAlgorithmProvider(alg,0);CloseHandle(file);return ok;
}
extern "C" __declspec(dllexport) bool ThaiTestInitialize(void* module,int profile) {return profile>=0&&profile<4&&Initialize(static_cast<unsigned char*>(module),&profiles[profile]);}
extern "C" __declspec(dllexport) void* ThaiTestConstruct(){if(active)Construct();return manager;}
extern "C" __declspec(dllexport) unsigned ThaiTestRefreshRva(){return active?active->refresh:0;}
static FARPROC VersionProc(const char* name){return originalVersion?GetProcAddress(originalVersion,name):nullptr;}
extern "C" BOOL WINAPI Proxy_GetFileVersionInfoW(LPCWSTR a,DWORD b,DWORD c,LPVOID d){auto f=reinterpret_cast<decltype(&GetFileVersionInfoW)>(VersionProc("GetFileVersionInfoW"));return f?f(a,b,c,d):FALSE;}
extern "C" BOOL WINAPI Proxy_GetFileVersionInfoA(LPCSTR a,DWORD b,DWORD c,LPVOID d){auto f=reinterpret_cast<decltype(&GetFileVersionInfoA)>(VersionProc("GetFileVersionInfoA"));return f?f(a,b,c,d):FALSE;}
extern "C" DWORD WINAPI Proxy_GetFileVersionInfoSizeW(LPCWSTR a,LPDWORD b){auto f=reinterpret_cast<decltype(&GetFileVersionInfoSizeW)>(VersionProc("GetFileVersionInfoSizeW"));return f?f(a,b):0;}
extern "C" DWORD WINAPI Proxy_GetFileVersionInfoSizeA(LPCSTR a,LPDWORD b){auto f=reinterpret_cast<decltype(&GetFileVersionInfoSizeA)>(VersionProc("GetFileVersionInfoSizeA"));return f?f(a,b):0;}
extern "C" BOOL WINAPI Proxy_VerQueryValueW(LPCVOID a,LPCWSTR b,LPVOID* c,PUINT d){auto f=reinterpret_cast<decltype(&VerQueryValueW)>(VersionProc("VerQueryValueW"));return f?f(a,b,c,d):FALSE;}
extern "C" BOOL WINAPI Proxy_VerQueryValueA(LPCVOID a,LPCSTR b,LPVOID* c,PUINT d){auto f=reinterpret_cast<decltype(&VerQueryValueA)>(VersionProc("VerQueryValueA"));return f?f(a,b,c,d):FALSE;}
BOOL WINAPI DllMain(HINSTANCE instance,DWORD reason,LPVOID){if(reason==DLL_PROCESS_ATTACH){DisableThreadLibraryCalls(instance);wchar_t system[MAX_PATH];GetSystemDirectoryW(system,MAX_PATH);wcscat_s(system,L"\\version.dll");originalVersion=LoadLibraryExW(system,nullptr,LOAD_LIBRARY_SEARCH_SYSTEM32);wchar_t exe[MAX_PATH];GetModuleFileNameW(nullptr,exe,MAX_PATH);const wchar_t* name=wcsrchr(exe,L'\\');name=name?name+1:exe;for(auto& p:profiles){if(!_wcsicmp(name,p.name)){unsigned char hash[32];if(HashFile(exe,hash)&&!memcmp(hash,p.sha,32))Initialize(reinterpret_cast<unsigned char*>(GetModuleHandleW(nullptr)),&p);else Log("Unsupported executable SHA-256; extension disabled");break;}}}return TRUE;}
