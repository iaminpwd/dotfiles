import os

# 스크립트 위치(bin/utils/)에서 세 단계 상위 디렉토리가 저장소 루트
# bin/utils/replace-legacy-setup.py → dirname → bin/utils → dirname → bin → dirname → dotfiles
repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
files_to_replace = [
    'contexts/drawio-gen/scripts/layout_toolkit.py',
    'contexts/dotfiles/tests/run.sh',
    'contexts/dotfiles/references/050-dotfiles-security-standard.md',
    'contexts/dotfiles/references/020-project-planning-template.md',
    'contexts/dotfiles/SKILL.md',
    'contexts/pre-flight-check/tests/lib/tf-fixture-lib.sh',
    'contexts/README.md',
    'contexts/prompt-architect/evals/routing/cases.tsv',
    'contexts/prompt-architect/evals/routing/run.sh',
    'contexts/prompt-architect/references/020-shell-scripting-standard.md'
]

for rel_path in files_to_replace:
    abs_path = os.path.join(repo_root, rel_path)
    if os.path.exists(abs_path):
        with open(abs_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # 문맥에 맞게 replace 수행
        new_content = content
        if "layout_toolkit.py" in rel_path:
            new_content = new_content.replace("setup.sh", "bootstrap.sh/ansible")
        elif "SKILL.md" in rel_path and "dotfiles" in rel_path:
            new_content = new_content.replace("setup.sh", "bootstrap.sh, ansible")
        elif "020-project-planning-template.md" in rel_path:
            new_content = new_content.replace("`setup.sh`", "`just setup`")
            new_content = new_content.replace("setup.sh", "just setup")
        elif "tf-fixture-lib.sh" in rel_path:
            new_content = new_content.replace("setup.sh", "Ansible 셋업 과정")
        elif "README.md" in rel_path:
            new_content = new_content.replace("`setup.sh` 실행 시", "`just setup`(Ansible) 실행 시")
        elif "evals/routing" in rel_path:
            new_content = new_content.replace("setup.sh 의", "Ansible 셋업의")
            new_content = new_content.replace("setup.sh", "ansible 셋업")
        elif "020-shell-scripting-standard.md" in rel_path:
            new_content = new_content.replace("setup.sh", "bootstrap.sh")
        else:
            new_content = new_content.replace("setup.sh", "bootstrap.sh")

        with open(abs_path, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"Replaced setup.sh in {rel_path}")
