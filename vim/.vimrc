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
set clipboard=unnamedplus " 시스템 클립보드와 양방향 연동 (터미널 밖 복사/붙여넣기)
set colorcolumn=80  " 80자 가이드라인 옅은 세로줄 표시
syntax on           " 구문 강조

" YAML 파일 작성 시 공백 에러 방지를 위한 강제 설정
autocmd FileType yaml setlocal ts=2 sts=2 sw=2 expandtab
" ---------------------------------------
