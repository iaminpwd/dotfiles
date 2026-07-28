" --- [인프라 엔지니어 Vim 필수 설정] ---
set number          " 줄 번호 표시
set cursorline      " 현재 줄 강조 표시
set ai              " 자동 들여쓰기
set si              " 스마트 들여쓰기
set ts=2            " 탭 간격
set sw=2            " Shift 간격
set expandtab       " 탭을 공백으로 변환 (YAML 필수)
set hlsearch        " 검색어 하이라이트
set incsearch       " 점진적 검색
set ignorecase      " 검색 시 대소문자 무시
set smartcase       " 소문자 검색 시 무시, 대문자 포함 시 구분
" 시스템 클립보드와 양방향 연동 (터미널 밖 복사/붙여넣기)
" unnamedplus 가 쓰는 + 레지스터는 X11 CLIPBOARD 셀렉션이라 리눅스 전용이다.
" macOS 는 + 레지스터가 없고 시스템 페이스트보드가 * 에 연결되므로 unnamed 를 써야 한다.
if has('macunix')
  set clipboard=unnamed
else
  set clipboard=unnamedplus
endif
set colorcolumn=80  " 80자 가이드라인 옅은 세로줄 표시
syntax on           " 구문 강조

" YAML 파일 작성 시 공백 에러 방지를 위한 강제 설정
" augroup + autocmd! 로 감싸는 이유: 맨 autocmd 는 :source ~/.vimrc 를 반복할 때마다
" 같은 훅이 중복 등록되어 파일을 열 때 여러 번 실행된다(vim 의 고전적 함정).
augroup infra_filetypes
  autocmd!
  autocmd FileType yaml setlocal ts=2 sts=2 sw=2 expandtab
augroup END
" ---------------------------------------
