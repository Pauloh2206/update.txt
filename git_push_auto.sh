#!/bin/bash

VERSION="79"

NC='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'

BRANCH_NAME="main"
LARGE_FILE_SIZE_MB=50
REMOTE_SCRIPT_URL="https://raw.githubusercontent.com/Pauloh2206/script-auto-push/refs/heads/main/git_push_auto.sh"

GIT_USERNAME_STORE=""
GIT_PASSWORD_STORE=""
GITHUB_API_URL="https://api.github.com"

# ==========================================================
# FUNÇÕES DE SEGURANÇA E ERRO
# ==========================================================

# Limpeza interativa de credenciais e opção de Logout do GitHub CLI
function interactive_cleanup() {
    # Verifica se a variável de credencial foi preenchida durante a execução
    if [ -n "$GIT_PASSWORD_STORE" ]; then
        echo -e "\n${YELLOW}==========================================================${NC}"
        echo -e "${CYAN}SEGURANÇA: As credenciais (PAT) foram carregadas para a memória temporária do script.${NC}"
        
        # 1. Limpa a memória temporária do script
        read -r -p "$(echo -e "${RED}Deseja limpar as credenciais da memória do script AGORA? (S/n) [S]: ${NC}")" CLEANUP_CHOICE
        CLEANUP_CHOICE=${CLEANUP_CHOICE:-S}

        if [[ "$CLEANUP_CHOICE" =~ ^[Ss]$ ]]; then
            GIT_PASSWORD_STORE=""
            GIT_USERNAME_STORE=""
            echo -e "${GREEN}✅ Credenciais temporárias (PAT) removidas da memória do script.${NC}" >&2

            # 2. Oferece a opção de deslogar do armazenamento persistente do GitHub CLI
            echo -e "\n${BLUE}⚙️ O GitHub CLI (gh) armazena o token de forma persistente. Deseja deslogar completamente?${NC}"
            read -r -p "$(echo -e "${YELLOW}Isso executa 'gh auth logout' e exige novo login na próxima execução. (S/n) [n]: ${NC}")" LOGOUT_GH_CHOICE
            LOGOUT_GH_CHOICE=${LOGOUT_GH_CHOICE:-n}

            if [[ "$LOGOUT_GH_CHOICE" =~ ^[Ss]$ ]]; then
                echo -e "${RED}🚨 Executando 'gh auth logout'...${NC}"
                # Desloga silenciosamente, impedindo que o script se logue automaticamente na próxima execução
                gh auth logout -h github.com &> /dev/null
                echo -e "${GREEN}✅ Logout completo do GitHub CLI realizado.${NC}"
            else
                echo -e "${YELLOW}⚠️ O GitHub CLI (gh) permanece logado. O script se logará automaticamente na próxima vez.${NC}"
            fi

        else
            echo -e "${YELLOW}⚠️ Credenciais mantidas até o encerramento natural do shell script.${NC}" >&2
        fi
        echo -e "${YELLOW}==========================================================${NC}"
    fi
}

function handle_fatal_error() {
    local error_message="$1"
    echo -e "${RED}❌ ERRO FATAL: $error_message${NC}" >&2
    echo -e "${RED}❌ O script será encerrado.${NC}" >&2
    interactive_cleanup # Chama a limpeza interativa antes de sair
    exit 1
}

function check_dependencies() {
    local missing_deps=()
    local deps=("git" "curl" "cmp" "jq" "gh")

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        handle_fatal_error "Dependências ausentes: ${missing_deps[*]} | Instale com: pkg install git curl coreutils jq gh"
    fi
}

function github_api_call() {
    local endpoint="$1"
    local method="${2:-GET}"
    local data="$3"
    
    local url="${GITHUB_API_URL}${endpoint}"
    local auth_header="Authorization: token ${GIT_PASSWORD_STORE}"
    local headers=(-H "$auth_header" -H "Accept: application/vnd.github.v3+json")
    local curl_command="curl -s --max-time 30"
    local response

    if [ "$method" = "POST" ] || [ "$method" = "PATCH" ]; then
        headers+=(-H "Content-Type: application/json")
        response=$($curl_command -X "$method" "${headers[@]}" -d "$data" "$url")
    else
        response=$($curl_command -X "$method" "${headers[@]}" "$url")
    fi
    
    local curl_exit_code=$?
    if [ $curl_exit_code -ne 0 ]; then
           echo "❌ Falha crítica no comando cURL (Timeout de 30s ou erro de conexão). (Exit: $curl_exit_code)" >&2
           return 1
    fi
    
    if echo "$response" | grep -q '{"message":'; then
        if echo "$response" | grep -q "Bad credentials"; then
            echo "❌ ERRO DE API: Credenciais Inválidas (PAT/Token). Refaça o 'gh auth login'." >&2
            return 2
        fi
        echo -e "❌ ERRO DE API: $(echo "$response" | jq -r '.message')" >&2
        return 4
    fi

    echo "$response"
    return 0
}

function get_github_pat_and_user() {
    echo -e "\n${CYAN}📌 PASSO 1/5: AUTENTICAÇÃO VIA GITHUB CLI (gh)${NC}"
    
    # Loop para tentar autenticar até que seja bem-sucedido ou fatal
    while ! gh auth status &> /dev/null; do
        echo -e "${RED}❌ Não autenticado via 'gh'. Iniciando processo de login interativo...${NC}"
        echo -e "${YELLOW}🚨 Siga as instruções no terminal para completar o login (será necessário usar um navegador).${NC}"
        
        # Inicia o login interativo
        if gh auth login --scopes repo; then
            echo -e "${GREEN}✅ Tentativa de Login concluída. Verificando status...${NC}"
        else
            # O gh auth login falhou por algum motivo (e.g., cancelado, erro de rede)
            echo -e "${RED}❌ O processo 'gh auth login' falhou ou foi cancelado.${NC}"
            read -r -p "$(echo -e "${YELLOW}Deseja TENTAR NOVAMENTE o login do GitHub CLI? (S/n) [S]: ${NC}")" RETRY_LOGIN
            RETRY_LOGIN=${RETRY_LOGIN:-S}

            if [[ ! "$RETRY_LOGIN" =~ ^[Ss]$ ]]; then
                handle_fatal_error "Login do GitHub CLI não foi concluído. Operação cancelada."
            fi
            continue # Volta para o início do loop
        fi
        
        # Uma pausa para dar tempo do gh atualizar o status após a conclusão do login
        sleep 2

        if ! gh auth status &> /dev/null; then
            echo -e "${RED}❌ Falha na verificação de status após o login. Verifique as mensagens de erro acima.${NC}"
            read -r -p "$(echo -e "${YELLOW}Pressione [Enter] para tentar novamente o Login, ou 'n' para sair: ${NC}")" FINAL_CHECK_RETRY
            FINAL_CHECK_RETRY=${FINAL_CHECK_RETRY:-S}
            if [[ ! "$FINAL_CHECK_RETRY" =~ ^[Ss]$ ]]; then
                handle_fatal_error "Falha persistente na autenticação do GitHub CLI."
            fi
        fi
    done

    # Se saiu do loop, o status é OK. Procede para obter as credenciais.
    
    echo -e "${BLUE}⚙️ Obtendo Personal Access Token (PAT)...${NC}"
    GIT_PASSWORD_STORE=$(gh auth token)

    if [ -z "$GIT_PASSWORD_STORE" ]; then
        handle_fatal_error "Falha ao obter o PAT. Verifique se você está logado."
    fi

    echo -e "${BLUE}⚙️ Obtendo nome de usuário...${NC}"
    local user_response
    user_response=$(github_api_call "/user" "GET")

    if [ $? -ne 0 ]; then
        handle_fatal_error "Falha ao obter o nome de usuário via API. PAT inválido/expirado ou timeout."
    fi
    
    # Armazena o usuário logado dinamicamente
    GIT_USERNAME_STORE=$(echo "$user_response" | jq -r '.login')

    if [ -z "$GIT_USERNAME_STORE" ] || [ "$GIT_USERNAME_STORE" = "null" ]; then
        handle_fatal_error "Não foi possível extrair o nome de usuário."
    fi

    echo -e "${GREEN}✅ Autenticado como: ${CYAN}${GIT_USERNAME_STORE}${NC}"
}

function create_new_repo() {
    echo -e "\n${CYAN}🛠️ CRIAÇÃO DE NOVO REPOSITÓRIO NO GITHUB${NC}" >&2
    
    while true; do
        read -r -p "$(echo -e "${YELLOW}Digite o NOME do novo repositório: ${NC}")" REPO_NAME
        [ -n "$REPO_NAME" ] && break || echo -e "${RED}🚨 O nome não pode ser vazio.${NC}" >&2
    done

    read -r -p "$(echo -e "${YELLOW}O repositório será PRIVADO? (S/n) [S]: ${NC}")" IS_PRIVATE
    IS_PRIVATE=${IS_PRIVATE:-S}
    
    local private_flag
    if [[ "$IS_PRIVATE" =~ ^[Nn]$ ]]; then
        private_flag="false"
    else
        private_flag="true"
    fi
    
    local create_data="{\"name\":\"${REPO_NAME}\", \"private\":${private_flag}, \"auto_init\":false}"
    
    echo -e "${BLUE}⚙️ Enviando requisição para criar repositório '${REPO_NAME}'...${NC}" >&2

    local new_repo_json
    new_repo_json=$(github_api_call "/user/repos" "POST" "$create_data")

    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Falha ao criar o repositório. Tente um nome diferente.${NC}" >&2
        return 1
    fi
    
    local new_repo_url
    new_repo_url=$(echo "$new_repo_json" | jq -r '.clone_url')
    
    if [ -n "$new_repo_url" ] && [ "$new_repo_url" != "null" ]; then
        echo -e "${GREEN}✅ Repositório '${REPO_NAME}' criado com sucesso!${NC}" >&2
        echo "$new_repo_url"
        return 0
    else
        echo -e "${RED}❌ Erro inesperado após a criação.${NC}" >&2
        return 1
    fi
}

function perform_git_cleanup() {
    echo -e "${BLUE}⚙️ Executando Limpeza Proativa do Git (git gc --prune=now)...${NC}"
    if git gc --prune=now 2>/dev/null; then
        echo -e "${GREEN}✅ Limpeza (Garbage Collection) concluída.${NC}"
    else
        echo -e "${YELLOW}⚠️ Falha na limpeza do Git, mas prosseguindo.${NC}"
    fi

    if git status 2>&1 | grep -q "You are currently rebasing"; then
        echo -e "${BLUE}⚙️ Abortando Rebase Pendente...${NC}"
        git rebase --abort 2>/dev/null
        echo -e "${GREEN}✅ Rebase abortado.${NC}"
    fi

    if git status 2>&1 | grep -q "You have unmerged paths"; then
        echo -e "${BLUE}⚙️ Abortando Merge Pendente...${NC}"
        git merge --abort 2>/dev/null
        echo -e "${GREEN}✅ Merge abortado.${NC}"
    fi
}

function check_for_update() {
    local REMOTE_FILE
    if ! REMOTE_FILE=$(mktemp); then
        echo -e "${RED}❌ ERRO CRÍTICO: Falha ao criar arquivo temporário. Prosseguindo com V${VERSION}.${NC}"
        return 1
    fi
    
    trap "rm -f $REMOTE_FILE" EXIT INT

    echo -e "${BLUE}🔎 Verificando por atualizações (Timeout: 20s)... Versão local: V${VERSION}${NC}"
    
    if curl --max-time 20 -s "$REMOTE_SCRIPT_URL" > "$REMOTE_FILE"; then
        if [ -s "$REMOTE_FILE" ]; then
            local REMOTE_VERSION
            REMOTE_VERSION=$(grep '^VERSION=' "$REMOTE_FILE" | head -n 1 | cut -d'"' -f 2)
            UPDATE_PROCEED=0

            if [ -n "$REMOTE_VERSION" ] && [ "$REMOTE_VERSION" -gt "$VERSION" ]; then
                echo -e "${YELLOW}🚨 ATUALIZAÇÃO DISPONÍVEL! (V${REMOTE_VERSION})${NC}"
                UPDATE_PROCEED=1
            else
                echo -e "${GREEN}✅ Script já está na versão mais recente (V${VERSION}).${NC}"
            fi

            if [ "$UPDATE_PROCEED" -eq 1 ]; then
                read -r -p "$(echo -e "${YELLOW}Deseja ATUALIZAR AGORA? (S/n): ${NC}")" UPDATE_CHOICE
                
                if [[ "$UPDATE_CHOICE" =~ ^[Ss]$ ]]; then
                    mv "$REMOTE_FILE" "$0"
                    chmod +x "$0"
                    echo -e "${GREEN}🚀 Script atualizado! Re-executando para aplicar as mudanças...${NC}"
                    trap - EXIT INT
                    exec bash "$0" --auto-start
                else
                    echo -e "${YELLOW}⚠️ Atualização ignorada. Prosseguindo com V${VERSION}.${NC}"
                fi
            fi
        else
            echo -e "${RED}❌ ERRO: O download falhou ou o arquivo remoto está vazio. Prosseguindo com V${VERSION}.${NC}"
        fi
    else
        echo -e "${RED}❌ ERRO DE REDE: Não foi possível verificar atualizações. Prosseguindo com V${VERSION}.${NC}"
    fi
    
    trap - EXIT INT
}

function main_menu() {
    
    while true; do
        echo -e "\n${YELLOW}=========================================================="
        echo -e "       MENU INICIAL - AUTOMAÇÃO GIT (V${VERSION})         "
        echo -e "=========================================================="
        echo -e "${CYAN}Escolha uma opção:${NC}"
        echo -e "1) ${GREEN}INICIAR PUSH/SINCRONIZAÇÃO${NC} (🆗)"
        echo -e "2) ${BLUE}VERIFICAR E ATUALIZAR SCRIPT${NC} (🔄)"
        echo -e "3) ${RED}SAIR${NC} (❌)"
        
        read -r -p "$(echo -e "${YELLOW}Opção (1, 2 ou 3) [1]: ${NC}")" MENU_CHOICE
        MENU_CHOICE=${MENU_CHOICE:-1}

        case "$MENU_CHOICE" in
            1) break ;;
            2) check_for_update ;;
            3) echo -e "${RED}❌ Operação cancelada pelo usuário.${NC}"; interactive_cleanup; exit 0 ;;
            *) echo -e "${RED}❌ Opção inválida. Escolha 1, 2 ou 3.${NC}" ;;
        esac
    done
    echo -e "${YELLOW}----------------------------------------------------------${NC}"
}

# ==========================================================
# INÍCIO DO FLUXO PRINCIPAL
# ==========================================================
check_dependencies

if [ "$1" != "--auto-start" ]; then
    main_menu
fi

echo -e "\n${YELLOW}=========================================================="
echo -e "          INÍCIO DO ENVIO SIMPLIFICADO AO GITHUB (V${VERSION})          "
echo -e "${YELLOW}=========================================================="
sleep 1

# 0. PRÉ-VERIFICAÇÃO E INICIALIZAÇÃO GIT
# ----------------------------------------------------------
echo -e "\n${YELLOW}🚨 Você deve estar DENTRO da pasta raiz do seu projeto. Diretório: ${CYAN}$(pwd)${NC}"
read -r -p "$(echo -e "${YELLOW}CONFIRMA que está na pasta do projeto? (S/n): ${NC}")" CONFIRMATION
if [[ ! "$CONFIRMATION" =~ ^[Ss]$ && ! -z "$CONFIRMATION" ]]; then handle_fatal_error "Operação cancelada na confirmação do diretório."; fi

if [ ! -d ".git" ]; then
    echo -e "${BLUE}⚙️ Inicializando Git (git init)...${NC}"
    git init || handle_fatal_error "Falha crítica ao inicializar o Git."
    echo -e "${GREEN}✅ Repositório Git inicializado.${NC}"
else
    echo -e "${GREEN}✅ Repositório Git já inicializado.${NC}"
fi

echo -e "${YELLOW}----------------------------------------------------------${NC}"

# 1. AUTENTICAÇÃO E CONFIGURAÇÃO DE REPOSITÓRIO REMOTO
# ----------------------------------------------------------
get_github_pat_and_user

REMOTE_URL=$(git remote get-url origin 2>/dev/null)
NEW_REPO_URL=""

if [ -z "$REMOTE_URL" ]; then
    echo -e "\n${CYAN}📌 PASSO 2/5: CONFIGURAÇÃO DO REPOSITÓRIO REMOTO${NC}"
    
    while true; do
        echo -e "\n${CYAN}Nenhum repositório remoto configurado ('origin'). Escolha uma ação:${NC}"
        echo -e "1) ${YELLOW}Criar um Novo Repositório no GitHub${NC}"
        echo -e "2) ${BLUE}Listar e Escolher um Repositório Existente${NC}"  # NOVA OPÇÃO
        echo -e "3) ${RED}Inserir URL Manualmente${NC}"
        
        read -r -p "$(echo -e "${YELLOW}Opção (1, 2 ou 3) [1]: ${NC}")" REPO_ACTION
        REPO_ACTION=${REPO_ACTION:-1}

        if [ "$REPO_ACTION" == "1" ]; then
            # Lógica para Criar Novo Repositório
            create_output=$(create_new_repo)
            create_exit_code=$?
            
            NEW_REPO_URL="$create_output"
            
            if [ $create_exit_code -eq 0 ] && [ -n "$NEW_REPO_URL" ] && [ "$NEW_REPO_URL" != "null" ]; then
                echo -e "${GREEN}✅ URL do Novo Repositório capturado com sucesso.${NC}" >&2
                break
            else
                echo -e "${RED}❌ Falha na criação do repositório. Tentando novamente...${NC}" >&2
            fi
        
        elif [ "$REPO_ACTION" == "2" ]; then
            # Lógica para Listar e Escolher Repositório (NOVA LÓGICA)
            echo -e "${BLUE}⚙️ Listando repositórios ativos do usuário ${GIT_USERNAME_STORE}...${NC}"
            
            # Pega a lista (gh repo list $USUARIO_LOGADO)
            REPOS=$(gh repo list "$GIT_USERNAME_STORE" --limit 50 --json name,url | jq -r '.[] | .name + " (" + .url + ")"')
            
            if [ -z "$REPOS" ]; then
                echo -e "${RED}❌ Não foram encontrados repositórios. Tente criar um novo ou inserir a URL manualmente.${NC}" >&2
                continue
            fi

            echo -e "\n${CYAN}🔢 REPOSITÓRIOS ENCONTRADOS (Max 50):${NC}"
            # Cria um array com apenas os nomes para o 'select'
            REPO_NAMES=()
            while IFS= read -r line; do
                REPO_NAMES+=("$(echo "$line" | cut -d' ' -f1)")
            done <<< "$REPOS"

            # Adiciona uma opção de cancelamento
            REPO_NAMES+=("CANCELAR e voltar ao menu anterior")

            select SELECTED_REPO in "${REPO_NAMES[@]}"; do
                if [ "$SELECTED_REPO" == "CANCELAR e voltar ao menu anterior" ]; then
                    echo -e "${YELLOW}⚠️ Seleção cancelada. Voltando ao menu de ações.${NC}"
                    break 
                elif [ -n "$SELECTED_REPO" ]; then
                    # Encontra a URL completa com base no nome selecionado
                    NEW_REPO_URL=$(echo "$REPOS" | grep "^$SELECTED_REPO (" | head -n 1 | cut -d' ' -f2 | tr -d '()')
                    echo -e "${GREEN}✅ Repositório selecionado: ${CYAN}$SELECTED_REPO${NC}" >&2
                    echo -e "${GREEN}✅ URL capturada: ${CYAN}$NEW_REPO_URL${NC}" >&2
                    break 2 # Sai do select E do while true
                else
                    echo -e "${RED}❌ Opção inválida. Tente novamente.${NC}"
                fi
            done
            if [ -n "$NEW_REPO_URL" ]; then
                break # Sai do loop de configuração remota se a URL foi definida
            fi

        elif [ "$REPO_ACTION" == "3" ]; then
            # Lógica para Inserir URL Manualmente
            break
        else
            echo -e "${RED}❌ Opção inválida. Escolha 1, 2 ou 3.${NC}"
        fi
    done
    
    # Esta parte é a mesma do seu código:
    if [ -z "$NEW_REPO_URL" ]; then
        echo -e "\n${CYAN}🔗 Modo de Configuração Manual Ativado.${NC}"
        while true; do
            read -r -p "$(echo -e "${CYAN}🔗 COLE A URL HTTPS DO SEU REPOSITÓRIO NO GITHUB AQUI: ${NC}")" NEW_REPO_URL
            if [[ "$NEW_REPO_URL" =~ ^https://github.com/.*\.git$ ]]; then break; fi
            echo -e "${RED}🚨 URL inválida. O link deve ser HTTPS e terminar em .git.${NC}"
        done
    fi

    # >>> INÍCIO DO BLOCO DE CORREÇÃO AUTOMÁTICA DE SEGURANÇA <<<
    
    # Tenta adicionar o remoto, capturando a saída de erro
    ADD_REMOTE_OUTPUT=$(git remote add origin "$NEW_REPO_URL" 2>&1)
    ADD_REMOTE_EXIT_CODE=$?

    if [ $ADD_REMOTE_EXIT_CODE -ne 0 ]; then
        # Falhou. Verifica se foi um erro de "dubious ownership"
        if echo "$ADD_REMOTE_OUTPUT" | grep -q "dubious ownership"; then
            echo -e "\n${YELLOW}⚠️ ERRO DE SEGURANÇA DETECTADO (Dubious Ownership). Tentando correção automática...${NC}"
            
            # Adiciona o diretório atual ($(pwd)) à lista segura do Git globalmente.
            git config --global --add safe.directory "$(pwd)"
            echo -e "${GREEN}✅ Diretório '$(pwd)' adicionado à lista segura do Git.${NC}"
            
            # Tenta novamente adicionar o remoto (deve funcionar agora)
            ADD_REMOTE_RETRY_OUTPUT=$(git remote add origin "$NEW_REPO_URL" 2>&1)
            if [ $? -ne 0 ]; then
                # Se falhar novamente (por outra razão), é um erro fatal
                handle_fatal_error "Falha persistente ao adicionar o remoto, mesmo após correção de segurança. (Erro: $ADD_REMOTE_RETRY_OUTPUT)"
            fi
        else
            # Falhou por um motivo diferente
            handle_fatal_error "Falha ao adicionar o remoto. (Erro: $ADD_REMOTE_OUTPUT)"
        fi
    fi
    
    # Se chegou até aqui, o remoto foi adicionado com sucesso (na 1ª ou 2ª tentativa)
    REMOTE_URL="$NEW_REPO_URL"
    echo -e "${GREEN}✅ Repositório remoto configurado.${NC}"
    # >>> FIM DO BLOCO DE CORREÇÃO AUTOMÁTICA DE SEGURANÇA <<<
    
else
    echo -e "${GREEN}✅ Remoto configurado com: ${CYAN}$REMOTE_URL${NC}"
fi

PULL_URL="https://${GIT_USERNAME_STORE}:${GIT_PASSWORD_STORE}@${REMOTE_URL#https://}"

echo -e "${YELLOW}----------------------------------------------------------${NC}"

# 2. LIMPEZA PROATIVA
# ----------------------------------------------------------
echo -e "${CYAN}📌 PASSO 3/5: LIMPEZA PROATIVA DO REPOSITÓRIO LOCAL${NC}"
perform_git_cleanup
echo -e "${YELLOW}----------------------------------------------------------${NC}"


# 3. SINCRONIZAÇÃO PROATIVA (git pull --rebase)
# ----------------------------------------------------------
echo -e "${CYAN}📌 PASSO 4/5: SINCRONIZAÇÃO PROATIVA (git pull --rebase)${NC}"
read -p "$(echo -e "${BLUE}✅ Pressione [Enter] para sincronizar e trazer mudanças remotas...${NC}")"

STASH_NEEDED=0
LOCAL_CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

# =========================================================================
# >> LÓGICA DE INICIALIZAÇÃO DE REPOSITÓRIO E CORREÇÃO DE BRANCH LOCAL <<

# 1. Trata repositório 'Unborn' (sem commits) e renomeia a branch local para 'main'
if ! git rev-parse --verify HEAD >/dev/null 2>&1 || [ "$LOCAL_CURRENT_BRANCH" = "HEAD" ]; then
    echo -e "${YELLOW}⚠️ ALERTA: Repositório é 'Unborn' (sem commits). Criando commit inicial forçado...${NC}"
    
    git add .
    
    if git commit -m "commit: Initial repository setup (Auto-generated by V${VERSION})" 2>/dev/null; then
        echo -e "${GREEN}✅ Commit inicial criado.${NC}"
        LOCAL_CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    else
        echo -e "${YELLOW}⚠️ Aviso: Sem arquivos para o commit inicial. Prosseguindo...${NC}"
    fi

    if [ "$LOCAL_CURRENT_BRANCH" != "$BRANCH_NAME" ]; then
        echo -e "${BLUE}⚙️ Renomeando branch local de '${LOCAL_CURRENT_BRANCH}' para '$BRANCH_NAME'...${NC}"
        git branch -M $BRANCH_NAME || handle_fatal_error "Falha ao renomear a branch."
        LOCAL_CURRENT_BRANCH="$BRANCH_NAME"
        echo -e "${GREEN}✅ Branch local definida como '$BRANCH_NAME'.${NC}"
    fi
else
    # Se já tem commits, faz stash e renomeia a branch
    if git stash push -u -m "Auto-Stash antes do Pull Proativo V${VERSION}" 2>/dev/null; then
        STASH_NEEDED=1
        echo -e "${GREEN}✅ Alterações locais guardadas temporariamente (Stash).${NC}"
    fi
    
    if [ "$LOCAL_CURRENT_BRANCH" != "$BRANCH_NAME" ]; then
        echo -e "${BLUE}⚙️ Renomeando branch local de '${LOCAL_CURRENT_BRANCH}' para '$BRANCH_NAME'...${NC}"
        # Se for o Termux/Android, adiciona o safe.directory
        if git status 2>&1 | grep -q "dubious ownership"; then
            git config --global --add safe.directory "$(pwd)"
        fi
        git branch -M $BRANCH_NAME 2>/dev/null || handle_fatal_error "Falha ao renomear a branch local."
        LOCAL_CURRENT_BRANCH="$BRANCH_NAME"
        echo -e "${GREEN}✅ Branch local definida como '$BRANCH_NAME'.${NC}"
    fi
fi

# =========================================================================
# >> CORREÇÃO: VERIFICA SE O REPOSITÓRIO REMOTO ESTÁ VAZIO <<

REMOTE_HAS_COMMITS=0
# O 'git ls-remote' verifica se a branch 'main' existe no servidor.
if git ls-remote --exit-code "$PULL_URL" "$BRANCH_NAME" >/dev/null 2>&1; then
    REMOTE_HAS_COMMITS=1
fi

if [ "$REMOTE_HAS_COMMITS" -eq 0 ]; then
    echo -e "${YELLOW}⚠️ ALERTA: Repositório remoto '${BRANCH_NAME}' não existe (vazio). Pulando Pull/Rebase.${NC}"
    echo -e "${BLUE}⚙️ O primeiro 'push' criará a branch remota.${NC}"
    # Se não há commits remotos, não há o que puxar/sincronizar.
    
    if [ $STASH_NEEDED -eq 1 ]; then
        echo -e "${BLUE}⚙️ Restaurando alterações locais (Stash Pop)...${NC}"
        if ! git stash pop --index; then
            handle_fatal_error "ERRO ao restaurar alterações (Stash Pop)! Conflito local, resolva e use 'git stash drop'."
        fi
        echo -e "${GREEN}✅ Alterações locais restauradas.${NC}"
    fi

else
    # Se houver commits remotos, executa a sincronização normal
    echo -e "${BLUE}⚙️ Executando 'git pull --rebase $PULL_URL $BRANCH_NAME' para sincronizar...${NC}"

    if git pull --rebase "$PULL_URL" "$BRANCH_NAME"; then
        echo -e "${GREEN}✅ Sincronização Proativa concluída. Histórico alinhado.${NC}"
        
        if [ $STASH_NEEDED -eq 1 ]; then
            echo -e "${BLUE}⚙️ Restaurando alterações locais (Stash Pop)...${NC}"
            if ! git stash pop --index; then
                handle_fatal_error "ERRO ao restaurar alterações (Stash Pop)! Conflito local, resolva e use 'git stash drop'."
            fi
            echo -e "${GREEN}✅ Alterações locais restauradas.${NC}"
        fi

    else
        # Tratamento de CONFLITOS REAIS
        echo -e "${RED}❌ ERRO NO PULL/REBASE! O Git parou devido a CONFLITOS.${NC}"
        
        while true; do
            echo -e "\n${YELLOW}ESCOLHA AÇÃO DE CORREÇÃO AUTOMÁTICA:${NC}"
            echo -e "1) ${GREEN}PULAR/DESCARTAR o Commit Inicial Conflitante${NC}"
            echo -e "2) ${RED}SAIR${NC} e resolver manualmente."
            
            read -r -p "$(echo -e "${YELLOW}Opção (1 ou 2) [1]: ${NC}")" CONFLICT_ACTION
            CONFLICT_ACTION=${CONFLICT_ACTION:-1}

            if [ "$CONFLICT_ACTION" == "1" ]; then
                echo -e "${BLUE}⚙️ Tentando pular o commit problemático (git rebase --skip)...${NC}"
                if git rebase --skip; then
                    echo -e "${GREEN}✅ Commit inicial pulado com sucesso!${NC}"
                    break
                else
                    handle_fatal_error "ERRO CRÍTICO: O 'git rebase --skip' falhou. Ação manual é inevitável."
                fi
            elif [ "$CONFLICT_ACTION" == "2" ]; then
                handle_fatal_error "Operação cancelada. Ação manual necessária."
            else
                echo -e "${RED}❌ Opção inválida.${NC}"
            fi
        done
    fi

fi
# O fluxo agora continua no Passo 5
echo -e "${YELLOW}----------------------------------------------------------${NC}"


# 4. VERIFICAÇÕES DE SEGURANÇA E EFICIÊNCIA
# -------------------------------------------------------------------------
echo -e "${CYAN}📌 PASSO 5/5: VERIFICAÇÕES DE SEGURANÇA E EFICIÊNCIA...${NC}"

SENSITIVE_FILES=$(git ls-files -o --exclude-standard | grep -E "\.(env|key|pem)$|^credentials\." | sed 's/^/  - /')
if [ -n "$SENSITIVE_FILES" ]; then
    echo -e "${RED}\n🚨 ALERTA DE SEGURANÇA: Arquivos potencialmente COMPROMETEDORES detectados!${NC}"
    
    while true; do
        echo -e "1) ${RED}PARAR o processo${NC} (Revisão Manual/Excluir)."
        echo -e "2) ${GREEN}Adicionar ao .gitignore e Continuar${NC}."
        
        read -r -p "$(echo -e "${YELLOW}Opção (1 ou 2) [1]: ${NC}")" SECURITY_ACTION_CHOICE
        SECURITY_ACTION_CHOICE=${SECURITY_ACTION_CHOICE:-1}

        if [ "$SECURITY_ACTION_CHOICE" == "1" ]; then
            handle_fatal_error "Operação INTERROMPIDA. Arquivos sensíveis detectados."
        elif [ "$SECURITY_ACTION_CHOICE" == "2" ]; then
            echo -e "${BLUE}⚙️ Adicionando arquivos sensíveis ao .gitignore...${NC}"
            echo "$SENSITIVE_FILES" | sed 's/^  - //' | while read -r FILE; do
                if [ -n "$FILE" ]; then
                    echo "$FILE" >> .gitignore
                    git rm --cached "$FILE" 2>/dev/null
                fi
            done
            echo -e "${GREEN}✅ Arquivos ignorados. Prosseguindo.${NC}"
            break
        else
            echo -e "${RED}❌ Opção inválida.${NC}"
        fi
    done
fi

if [ -d "node_modules" ] && ! grep -q "node_modules" .gitignore 2>/dev/null; then
    echo -e "${BLUE}⚙️ CORREÇÃO: Pasta 'node_modules' detectada. Adicionando ao .gitignore...${NC}"
    echo -e "\nnode_modules/" >> .gitignore
    git rm -r --cached node_modules 2>/dev/null
    echo -e "${GREEN}✅ 'node_modules/' adicionado ao .gitignore.${NC}"
fi

echo -e "${GREEN}\n✅ Verificações concluídas.${NC}"
echo -e "${YELLOW}----------------------------------------------------------${NC}"

# 5. ADICIONAR E COMMITAR
# ----------------------------------------------------------
read -p "$(echo -e "${YELLOW}✅ Pressione [Enter] para adicionar todos os arquivos (git add .)...${NC}")"
git add .

if git status --porcelain | grep -q '^\(M\|A\|D\|R\|C\|U\|\?\?\)' ; then
    echo -e "\n${YELLOW}📝 SELEÇÃO DA MENSAGEM DO COMMIT:${NC}"
    COMMIT_OPTIONS=("feat: Nova Funcionalidade" "fix: Correção de Bug" "chore: Tarefa de Rotina/Build" "refactor: Melhoria de Código" "docs: Atualização de Documentação" "custom: Escrever Mensagem Completa")

    select COMMIT_TYPE_CHOICE in "${COMMIT_OPTIONS[@]}"; do
        case "$COMMIT_TYPE_CHOICE" in
            "feat: Nova Funcionalidade") COMMIT_PREFIX="feat"; break;;
            "fix: Correção de Bug") COMMIT_PREFIX="fix"; break;;
            "chore: Tarefa de Rotina/Build") COMMIT_PREFIX="chore"; break;;
            "refactor: Melhoria de Código") COMMIT_PREFIX="refactor"; break;;
            "docs: Atualização de Documentação") COMMIT_PREFIX="docs"; break;;
            *) COMMIT_PREFIX=""; break;;
        esac
    done

    while true; do
        if [ -n "$COMMIT_PREFIX" ]; then
            read -r -p "$(echo -e "${YELLOW}➡️ Descrição (ex: Adicionada validação): ${NC}")" COMMIT_DESCRIPTION
            COMMIT_MESSAGE="$COMMIT_PREFIX: $COMMIT_DESCRIPTION"
        else
            read -r -p "$(echo -e "${YELLOW}➡️ MENSAGEM DO COMMIT completa: ${NC}")" COMMIT_MESSAGE
        fi
        [ -n "$COMMIT_MESSAGE" ] && break || echo -e "${RED}🚨 A mensagem não pode ser vazia.${NC}"
    done

    echo -e "${BLUE}⚙️ Executando commit: ${CYAN}${COMMIT_MESSAGE}${NC}"
    git commit -m "$COMMIT_MESSAGE" || handle_fatal_error "Falha ao criar o commit."
    echo -e "${GREEN}✅ Commit criado com sucesso.${NC}"
else
    echo -e "${YELLOW}⚠️ Não há alterações para commitar. Prosseguindo para o PUSH...${NC}"
fi
echo -e "${YELLOW}----------------------------------------------------------${NC}"


# 6. ENVIAR PARA O GITHUB (Push)
# ----------------------------------------------------------
while true; do
    PUSH_COMMAND="git push -u $PULL_URL $BRANCH_NAME"

    read -p "$(echo -e "${GREEN}✅ Pressione [Enter] para executar o PUSH...${NC}")"
    echo -e "${BLUE}📡 Iniciando o envio. Aguarde o resultado...${NC}"

    PUSH_OUTPUT=$(eval "$PUSH_COMMAND" 2>&1)
    PUSH_EXIT_CODE=$?

    if [ $PUSH_EXIT_CODE -eq 0 ]; then
        echo -e "\n${GREEN}==========================================================${NC}"
        echo -e "${GREEN}🚀 SUCESSO! SEU PROJETO ESTÁ ONLINE NO GITHUB. 🎉${NC}"
        echo -e "${GREEN}==========================================================${NC}"
        break
    else
        echo -e "\n${YELLOW}----------------------------------------------------------${NC}"
        echo -e "${CYAN}Saída Completa do Git (Diagnóstico):\n${PUSH_OUTPUT}${NC}"
        echo -e "${YELLOW}----------------------------------------------------------${NC}"

        if echo "$PUSH_OUTPUT" | grep -q "fatal: Authentication failed" || echo "$PUSH_OUTPUT" | grep -q "Invalid username or token"; then
            echo -e "${RED}❌ FALHA NO PUSH: ERRO DE AUTENTICAÇÃO. (PAT/Token incorreto).${NC}"
            handle_fatal_error "Erro de Autenticação Crítico."
        
        elif echo "$PUSH_OUTPUT" | grep -q "remote unpack failed" || echo "$PUSH_OUTPUT" | grep -q "did not receive expected object"; then
             echo -e "${RED}❌ FALHA NO PUSH: ERRO DE OBJETO / DESEMPACOTAMENTO. (Rede ou cache Git).${NC}"
             read -r -p "$(echo -e "${YELLOW}Deseja TENTAR NOVAMENTE APÓS CORREÇÃO BÁSICA (git gc)? (S/n) [S]: ${NC}")" RETRY_OBJECT
             if [[ ${RETRY_OBJECT:-S} =~ ^[Ss]$ ]]; then git gc --prune=now && continue; else exit 1; fi
            
        elif echo "$PUSH_OUTPUT" | grep -q "GH013: Repository rule violations found"; then
            echo -e "${RED}❌ FALHA NO PUSH: REJEITADO POR CONTER SEGREDO (GH013).${NC}"
            handle_fatal_error "O GitHub detectou uma Chave de API em seu histórico."

        else
            echo -e "${RED}❌ FALHA NO PUSH! Erro genérico. Consulte o diagnóstico acima.${NC}"
            read -r -p "$(echo -e "${YELLOW}Deseja TENTAR NOVAMENTE? (S/n) [S]: ${NC}")" RETRY_GENERIC
            if [[ ${RETRY_GENERIC:-S} =~ ^[Ss]$ ]]; then continue; else exit 1; fi
        fi
    fi
done

# ==========================================================
# CRÉDITOS FINAIS E LIMPEZA
# ==========================================================
echo -e "\n${YELLOW}=========================================================="
echo -e "FIM DO PROCESSO GIT INTERATIVO (V${VERSION})"
echo -e "=========================================================="
echo -e "${GREEN}✅ AUTOR: Paulo Hernani${NC}"
echo -e "${GREEN}🤝 ASSISTÊNCIA NO SCRIPT: Gemini${NC}"
echo -e "${CYAN}📷 Siga no Instagram: @eu_paulo_ti${NC}"
echo -e "${YELLOW}==========================================================${NC}"

interactive_cleanup # Chama a limpeza interativa após sucesso
exit 0
