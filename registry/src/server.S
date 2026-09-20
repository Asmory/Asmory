.intel_syntax noprefix
.global _start

.equ SYS_read,       0
.equ SYS_write,      1
.equ SYS_close,      3
.equ SYS_socket,    41
.equ SYS_accept,    43
.equ SYS_bind,      49
.equ SYS_listen,    50
.equ SYS_setsockopt,54
.equ SYS_exit,      60

.equ AF_INET,        2
.equ SOCK_STREAM,    1
.equ SOL_SOCKET,     1
.equ SO_REUSEADDR,   2

.section .bss
.align 16
request_buf:
    .skip 8192

.section .data
.align 8
sockaddr:
    .word AF_INET
    .word 0xa046              # htons(18080)
    .long 0                   # INADDR_ANY
    .quad 0

.section .rodata
hdr_html:
    .ascii "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\r\n"
hdr_html_end:
hdr_css:
    .ascii "HTTP/1.1 200 OK\r\nContent-Type: text/css; charset=utf-8\r\nConnection: close\r\nCache-Control: public, max-age=60\r\nX-Content-Type-Options: nosniff\r\n\r\n"
hdr_css_end:
hdr_js:
    .ascii "HTTP/1.1 200 OK\r\nContent-Type: application/javascript; charset=utf-8\r\nConnection: close\r\nCache-Control: public, max-age=60\r\nX-Content-Type-Options: nosniff\r\n\r\n"
hdr_js_end:
hdr_json:
    .ascii "HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\r\n"
hdr_json_end:
hdr_gzip:
    .ascii "HTTP/1.1 200 OK\r\nContent-Type: application/gzip\r\nContent-Disposition: attachment; filename=\"simd-dot-0.1.0.tar.gz\"\r\nConnection: close\r\nCache-Control: public, max-age=300\r\nX-Content-Type-Options: nosniff\r\n\r\n"
hdr_gzip_end:
hdr_404:
    .ascii "HTTP/1.1 404 Not Found\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
hdr_404_end:

.align 16
asset_index:
    .incbin "registry/static/index.html"
asset_index_end:
asset_packages:
    .incbin "registry/static/packages.html"
asset_packages_end:
asset_pkg:
    .incbin "registry/static/package-simd-dot.html"
asset_pkg_end:
asset_design:
    .incbin "registry/static/design.html"
asset_design_end:
asset_publishing:
    .incbin "registry/static/publishing.html"
asset_publishing_end:
asset_css:
    .incbin "registry/static/app.css"
asset_css_end:
asset_js:
    .incbin "registry/static/app.js"
asset_js_end:
asset_packages_json:
    .incbin "registry/data/packages.json"
asset_packages_json_end:
asset_pkg_json:
    .incbin "registry/data/simd-dot.json"
asset_pkg_json_end:
asset_versions_json:
    .incbin "registry/data/simd-dot-versions.json"
asset_versions_json_end:
asset_release_json:
    .incbin "build/registry-data/simd-dot-0.1.0.json"
asset_release_json_end:
asset_download:
    .incbin "build/packages/simd-dot-0.1.0.tar.gz"
asset_download_end:
not_found_html:
    .ascii "<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>404 · Asmory</title><style>body{margin:0;background:#090b0f;color:#d9dfe7;font:16px ui-monospace,monospace;display:grid;place-items:center;min-height:100vh}main{border:1px solid #29303a;border-radius:12px;padding:28px 32px;background:#0e1218}b,a{color:#f2b84b}</style></head><body><main><b>404</b> · symbol not found<br><br><a href='/'>return to Asmory</a></main></body></html>"
not_found_html_end:

pat_release_download: .ascii "GET /api/v1/packages/simd-dot/0.1.0/download "
pat_release_download_end:
pat_release_api: .ascii "GET /api/v1/packages/simd-dot/0.1.0 "
pat_release_api_end:
pat_versions_api: .ascii "GET /api/v1/packages/simd-dot/versions "
pat_versions_api_end:
pat_project_api: .ascii "GET /api/v1/packages/simd-dot "
pat_project_api_end:
pat_pkg_api:  .ascii "GET /api/v1/package/simd-dot "
pat_pkg_api_end:
pat_api:      .ascii "GET /api/v1/packages "
pat_api_end:
pat_download: .ascii "GET /download/simd-dot-0.1.0.tar.gz "
pat_download_end:
pat_css:      .ascii "GET /static/app.css "
pat_css_end:
pat_js:       .ascii "GET /static/app.js "
pat_js_end:
pat_pkg:      .ascii "GET /package/simd-dot "
pat_pkg_end:
pat_packages: .ascii "GET /packages "
pat_packages_end:
pat_design:   .ascii "GET /design "
pat_design_end:
pat_publishing: .ascii "GET /publishing "
pat_publishing_end:
pat_home:     .ascii "GET / "
pat_home_end:

.section .text

# rdi=fd, rsi=buf, rdx=len
send_all:
    push rbx
    mov rbx, rdi
.send_loop:
    test rdx, rdx
    jz .done
    mov rax, SYS_write
    mov rdi, rbx
    syscall
    test rax, rax
    jle .done
    add rsi, rax
    sub rdx, rax
    jmp .send_loop
.done:
    pop rbx
    ret

# rdi=accepted fd, rsi=header, rdx=header len, rcx=body, r8=body len
send_response:
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rcx
    mov r14, r8
    call send_all
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    call send_all
    pop r14
    pop r13
    pop r12
    ret

# rsi=request, rdi=pattern, rcx=len -> eax=1 on equal prefix
prefix_eq:
    push rsi
    push rdi
    push rcx
    repe cmpsb
    sete al
    movzx eax, al
    pop rcx
    pop rdi
    pop rsi
    ret

# macro-like helper convention implemented with direct route blocks below.
_start:
    cld

    mov rax, SYS_socket
    mov rdi, AF_INET
    mov rsi, SOCK_STREAM
    xor rdx, rdx
    syscall
    test rax, rax
    js fatal
    mov r12, rax

    sub rsp, 8
    mov dword ptr [rsp], 1
    mov rax, SYS_setsockopt
    mov rdi, r12
    mov rsi, SOL_SOCKET
    mov rdx, SO_REUSEADDR
    mov r10, rsp
    mov r8, 4
    syscall
    add rsp, 8

    mov rax, SYS_bind
    mov rdi, r12
    lea rsi, [rip + sockaddr]
    mov rdx, 16
    syscall
    test rax, rax
    js fatal_close

    mov rax, SYS_listen
    mov rdi, r12
    mov rsi, 128
    syscall
    test rax, rax
    js fatal_close

accept_loop:
    mov rax, SYS_accept
    mov rdi, r12
    xor rsi, rsi
    xor rdx, rdx
    syscall
    test rax, rax
    js accept_loop
    mov r13, rax

    mov rax, SYS_read
    mov rdi, r13
    lea rsi, [rip + request_buf]
    mov rdx, 8191
    syscall
    test rax, rax
    jle close_client

    lea rsi, [rip + request_buf]
    lea rdi, [rip + pat_release_download]
    mov rcx, pat_release_download_end - pat_release_download
    call prefix_eq
    test eax, eax
    jnz route_release_download

    lea rsi, [rip + request_buf]
    lea rdi, [rip + pat_release_api]
    mov rcx, pat_release_api_end - pat_release_api
    call prefix_eq
    test eax, eax
    jnz route_release_api

    lea rsi, [rip + request_buf]
    lea rdi, [rip + pat_versions_api]
    mov rcx, pat_versions_api_end - pat_versions_api
    call prefix_eq
    test eax, eax
    jnz route_versions_api

    lea rsi, [rip + request_buf]
    lea rdi, [rip + pat_project_api]
    mov rcx, pat_project_api_end - pat_project_api
    call prefix_eq
    test eax, eax
    jnz route_pkg_api

    lea rsi, [rip + request_buf]
    lea rdi, [rip + pat_pkg_api]
    mov rcx, pat_pkg_api_end - pat_pkg_api
    call prefix_eq
    test eax, eax
    jnz route_pkg_api

    lea rsi, [rip + request_buf]
    lea rdi, [rip + pat_api]
    mov rcx, pat_api_end - pat_api
    call prefix_eq
    test eax, eax
    jnz route_api

    lea rsi, [rip + request_buf]
    lea rdi, [rip + pat_download]
    mov rcx, pat_download_end - pat_download
    call prefix_eq
    test eax, eax
    jnz route_download

    lea rsi, [rip + request_buf]
    lea rdi, [rip + pat_css]
    mov rcx, pat_css_end - pat_css
    call prefix_eq
    test eax, eax
    jnz route_css

    lea rsi, [rip + request_buf]
    lea rdi, [rip + pat_js]
    mov rcx, pat_js_end - pat_js
    call prefix_eq
    test eax, eax
    jnz route_js

    lea rsi, [rip + request_buf]
    lea rdi, [rip + pat_pkg]
    mov rcx, pat_pkg_end - pat_pkg
    call prefix_eq
    test eax, eax
    jnz route_pkg

    lea rsi, [rip + request_buf]
    lea rdi, [rip + pat_packages]
    mov rcx, pat_packages_end - pat_packages
    call prefix_eq
    test eax, eax
    jnz route_packages

    lea rsi, [rip + request_buf]
    lea rdi, [rip + pat_publishing]
    mov rcx, pat_publishing_end - pat_publishing
    call prefix_eq
    test eax, eax
    jnz route_publishing

    lea rsi, [rip + request_buf]
    lea rdi, [rip + pat_design]
    mov rcx, pat_design_end - pat_design
    call prefix_eq
    test eax, eax
    jnz route_design

    lea rsi, [rip + request_buf]
    lea rdi, [rip + pat_home]
    mov rcx, pat_home_end - pat_home
    call prefix_eq
    test eax, eax
    jnz route_home

    jmp route_404

route_home:
    mov rdi, r13
    lea rsi, [rip + hdr_html]
    mov rdx, hdr_html_end - hdr_html
    lea rcx, [rip + asset_index]
    mov r8, asset_index_end - asset_index
    call send_response
    jmp close_client

route_packages:
    mov rdi, r13
    lea rsi, [rip + hdr_html]
    mov rdx, hdr_html_end - hdr_html
    lea rcx, [rip + asset_packages]
    mov r8, asset_packages_end - asset_packages
    call send_response
    jmp close_client

route_pkg:
    mov rdi, r13
    lea rsi, [rip + hdr_html]
    mov rdx, hdr_html_end - hdr_html
    lea rcx, [rip + asset_pkg]
    mov r8, asset_pkg_end - asset_pkg
    call send_response
    jmp close_client

route_publishing:
    mov rdi, r13
    lea rsi, [rip + hdr_html]
    mov rdx, hdr_html_end - hdr_html
    lea rcx, [rip + asset_publishing]
    mov r8, asset_publishing_end - asset_publishing
    call send_response
    jmp close_client

route_design:
    mov rdi, r13
    lea rsi, [rip + hdr_html]
    mov rdx, hdr_html_end - hdr_html
    lea rcx, [rip + asset_design]
    mov r8, asset_design_end - asset_design
    call send_response
    jmp close_client

route_css:
    mov rdi, r13
    lea rsi, [rip + hdr_css]
    mov rdx, hdr_css_end - hdr_css
    lea rcx, [rip + asset_css]
    mov r8, asset_css_end - asset_css
    call send_response
    jmp close_client

route_js:
    mov rdi, r13
    lea rsi, [rip + hdr_js]
    mov rdx, hdr_js_end - hdr_js
    lea rcx, [rip + asset_js]
    mov r8, asset_js_end - asset_js
    call send_response
    jmp close_client

route_api:
    mov rdi, r13
    lea rsi, [rip + hdr_json]
    mov rdx, hdr_json_end - hdr_json
    lea rcx, [rip + asset_packages_json]
    mov r8, asset_packages_json_end - asset_packages_json
    call send_response
    jmp close_client

route_versions_api:
    mov rdi, r13
    lea rsi, [rip + hdr_json]
    mov rdx, hdr_json_end - hdr_json
    lea rcx, [rip + asset_versions_json]
    mov r8, asset_versions_json_end - asset_versions_json
    call send_response
    jmp close_client

route_release_api:
    mov rdi, r13
    lea rsi, [rip + hdr_json]
    mov rdx, hdr_json_end - hdr_json
    lea rcx, [rip + asset_release_json]
    mov r8, asset_release_json_end - asset_release_json
    call send_response
    jmp close_client

route_pkg_api:
    mov rdi, r13
    lea rsi, [rip + hdr_json]
    mov rdx, hdr_json_end - hdr_json
    lea rcx, [rip + asset_pkg_json]
    mov r8, asset_pkg_json_end - asset_pkg_json
    call send_response
    jmp close_client

route_release_download:
    mov rdi, r13
    lea rsi, [rip + hdr_gzip]
    mov rdx, hdr_gzip_end - hdr_gzip
    lea rcx, [rip + asset_download]
    mov r8, asset_download_end - asset_download
    call send_response
    jmp close_client

route_download:
    mov rdi, r13
    lea rsi, [rip + hdr_gzip]
    mov rdx, hdr_gzip_end - hdr_gzip
    lea rcx, [rip + asset_download]
    mov r8, asset_download_end - asset_download
    call send_response
    jmp close_client

route_404:
    mov rdi, r13
    lea rsi, [rip + hdr_404]
    mov rdx, hdr_404_end - hdr_404
    lea rcx, [rip + not_found_html]
    mov r8, not_found_html_end - not_found_html
    call send_response

close_client:
    mov rax, SYS_close
    mov rdi, r13
    syscall
    jmp accept_loop

fatal_close:
    mov rax, SYS_close
    mov rdi, r12
    syscall
fatal:
    mov rax, SYS_exit
    mov rdi, 1
    syscall
