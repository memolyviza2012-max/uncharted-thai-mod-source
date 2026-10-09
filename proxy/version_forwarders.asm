; ABI-transparent tail jumps preserve all register and stack arguments.
; Targets are resolved from the absolute Windows system version.dll.
EXTERN versionTargets:QWORD
.code
PUBLIC Proxy_GetFileVersionInfoA
Proxy_GetFileVersionInfoA PROC
    jmp QWORD PTR [versionTargets+0]
Proxy_GetFileVersionInfoA ENDP
PUBLIC Proxy_GetFileVersionInfoByHandle
Proxy_GetFileVersionInfoByHandle PROC
    jmp QWORD PTR [versionTargets+8]
Proxy_GetFileVersionInfoByHandle ENDP
PUBLIC Proxy_GetFileVersionInfoExA
Proxy_GetFileVersionInfoExA PROC
    jmp QWORD PTR [versionTargets+16]
Proxy_GetFileVersionInfoExA ENDP
PUBLIC Proxy_GetFileVersionInfoExW
Proxy_GetFileVersionInfoExW PROC
    jmp QWORD PTR [versionTargets+24]
Proxy_GetFileVersionInfoExW ENDP
PUBLIC Proxy_GetFileVersionInfoSizeA
Proxy_GetFileVersionInfoSizeA PROC
    jmp QWORD PTR [versionTargets+32]
Proxy_GetFileVersionInfoSizeA ENDP
PUBLIC Proxy_GetFileVersionInfoSizeExA
Proxy_GetFileVersionInfoSizeExA PROC
    jmp QWORD PTR [versionTargets+40]
Proxy_GetFileVersionInfoSizeExA ENDP
PUBLIC Proxy_GetFileVersionInfoSizeExW
Proxy_GetFileVersionInfoSizeExW PROC
    jmp QWORD PTR [versionTargets+48]
Proxy_GetFileVersionInfoSizeExW ENDP
PUBLIC Proxy_GetFileVersionInfoSizeW
Proxy_GetFileVersionInfoSizeW PROC
    jmp QWORD PTR [versionTargets+56]
Proxy_GetFileVersionInfoSizeW ENDP
PUBLIC Proxy_GetFileVersionInfoW
Proxy_GetFileVersionInfoW PROC
    jmp QWORD PTR [versionTargets+64]
Proxy_GetFileVersionInfoW ENDP
PUBLIC Proxy_VerFindFileA
Proxy_VerFindFileA PROC
    jmp QWORD PTR [versionTargets+72]
Proxy_VerFindFileA ENDP
PUBLIC Proxy_VerFindFileW
Proxy_VerFindFileW PROC
    jmp QWORD PTR [versionTargets+80]
Proxy_VerFindFileW ENDP
PUBLIC Proxy_VerInstallFileA
Proxy_VerInstallFileA PROC
    jmp QWORD PTR [versionTargets+88]
Proxy_VerInstallFileA ENDP
PUBLIC Proxy_VerInstallFileW
Proxy_VerInstallFileW PROC
    jmp QWORD PTR [versionTargets+96]
Proxy_VerInstallFileW ENDP
PUBLIC Proxy_VerLanguageNameA
Proxy_VerLanguageNameA PROC
    jmp QWORD PTR [versionTargets+104]
Proxy_VerLanguageNameA ENDP
PUBLIC Proxy_VerLanguageNameW
Proxy_VerLanguageNameW PROC
    jmp QWORD PTR [versionTargets+112]
Proxy_VerLanguageNameW ENDP
PUBLIC Proxy_VerQueryValueA
Proxy_VerQueryValueA PROC
    jmp QWORD PTR [versionTargets+120]
Proxy_VerQueryValueA ENDP
PUBLIC Proxy_VerQueryValueW
Proxy_VerQueryValueW PROC
    jmp QWORD PTR [versionTargets+128]
Proxy_VerQueryValueW ENDP
END
