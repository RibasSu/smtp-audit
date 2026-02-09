#!/bin/bash

# ══════════════════════════════════════════════════════════════════════════════
# Cores e formatação
# ══════════════════════════════════════════════════════════════════════════════
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Símbolos
CHECK="✓"
CROSS="✗"
ARROW="→"
BULLET="•"
SPINNER=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

# ══════════════════════════════════════════════════════════════════════════════
# Funções de UI
# ══════════════════════════════════════════════════════════════════════════════
print_banner() {
  clear
  echo -e "${CYAN}${BOLD}"
  echo "  ╔═══════════════════════════════════════════════════════════════╗"
  echo "  ║                     SMTP SECURITY AUDIT                       ║"
  echo "  ║                        Pentest Tool                           ║"
  echo "  ╚═══════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

print_section() {
  echo -e "\n${BLUE}${BOLD}┌──────────────────────────────────────────────────────────────────┐${NC}"
  echo -e "${BLUE}${BOLD}│${NC} ${CYAN}$1${NC}"
  echo -e "${BLUE}${BOLD}└──────────────────────────────────────────────────────────────────┘${NC}"
}

print_subsection() {
  echo -e "\n  ${YELLOW}${BOLD}$1${NC}"
  echo -e "  ${GRAY}────────────────────────────────────────${NC}"
}

print_status() {
  local status="$1"
  local message="$2"
  case "$status" in
    ok)      echo -e "    ${GREEN}${CHECK}${NC} $message" ;;
    fail)    echo -e "    ${RED}${CROSS}${NC} $message" ;;
    warn)    echo -e "    ${YELLOW}${BULLET}${NC} $message" ;;
    info)    echo -e "    ${BLUE}${ARROW}${NC} $message" ;;
    unreachable) echo -e "    ${GRAY}${BULLET}${NC} $message ${DIM}(unreachable)${NC}" ;;
  esac
}

spin() {
  local pid=$1
  local msg="$2"
  local i=0
  tput civis  # Esconde cursor
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r    ${CYAN}${SPINNER[$i]}${NC} ${DIM}%s${NC}" "$msg"
    i=$(( (i+1) % ${#SPINNER[@]} ))
    sleep 0.1
  done
  tput cnorm  # Mostra cursor
  printf "\r\033[K"  # Limpa linha
}

progress_bar() {
  local current=$1
  local total=$2
  local width=40
  local percent=$((current * 100 / total))
  local filled=$((current * width / total))
  local empty=$((width - filled))
  
  printf "\r  ${GRAY}[${NC}"
  printf "${GREEN}%${filled}s${NC}" | tr ' ' '█'
  printf "${GRAY}%${empty}s${NC}" | tr ' ' '░'
  printf "${GRAY}]${NC} ${BOLD}%3d%%${NC}" "$percent"
}

# ══════════════════════════════════════════════════════════════════════════════
# Configuração
# ══════════════════════════════════════════════════════════════════════════════
DOMAIN="$1"
DATE="$(date +%Y%m%d-%H%M%S)"
OUTDIR="smtp-audit-$DOMAIN-$DATE"

if [ -z "$DOMAIN" ]; then
  echo -e "${RED}${CROSS} Uso: $0 <domínio>${NC}"
  exit 1
fi

print_banner
echo -e "  ${GRAY}Alvo:${NC} ${BOLD}$DOMAIN${NC}"
echo -e "  ${GRAY}Data:${NC} $(date '+%Y-%m-%d %H:%M:%S')"

if [ -f /etc/debian_version ]; then
  PM_INSTALL="apt-get install -y"
  PM_UPDATE="apt-get update"
  PKG_DIG="dnsutils"
  PKG_SWAKS="swaks"
elif [ -f /etc/redhat-release ]; then
  PM_INSTALL="dnf install -y"
  PM_UPDATE="dnf makecache"
  PKG_DIG="bind-utils"
  PKG_SWAKS="swaks"
else
  exit 1
fi

print_section "Verificando Dependências"

install_if_missing() {
  local BIN="$1"
  local PKG="$2"
  if ! command -v "$BIN" >/dev/null 2>&1; then
    print_status info "Instalando $PKG..."
    sudo $PM_INSTALL "$PKG" >/dev/null 2>&1 &
    spin $! "Instalando $PKG"
    if ! command -v "$BIN" >/dev/null 2>&1; then
      print_status fail "Erro ao instalar $PKG"
      exit 1
    fi
    print_status ok "$PKG instalado"
  else
    print_status ok "$BIN já disponível"
  fi
}

# Atualiza repositórios uma vez
NEED_UPDATE=0
for BIN in dig nmap swaks grep awk; do
  command -v "$BIN" >/dev/null 2>&1 || NEED_UPDATE=1
done

if [ "$NEED_UPDATE" = "1" ]; then
  print_status info "Atualizando repositórios..."
  sudo $PM_UPDATE >/dev/null 2>&1 &
  spin $! "Atualizando repositórios"
  [ -f /etc/redhat-release ] && sudo $PM_INSTALL epel-release >/dev/null 2>&1
fi

install_if_missing "dig" "$PKG_DIG"
install_if_missing "nmap" "nmap"
install_if_missing "swaks" "$PKG_SWAKS"
install_if_missing "grep" "grep"
install_if_missing "awk" "gawk"

# Verificação final
echo ""
for BIN in dig nmap swaks grep awk; do
  if ! command -v "$BIN" >/dev/null 2>&1; then
    print_status fail "$BIN não encontrado após instalação"
    exit 1
  fi
done
print_status ok "Todas as dependências satisfeitas"

print_section "Resolução DNS"

mkdir -p "$OUTDIR"

MX=$(dig MX "$DOMAIN" +short | awk '{print $2}')
MX_COUNT=$(echo "$MX" | grep -c .)

if [ -z "$MX" ] || [ "$MX_COUNT" -eq 0 ]; then
  print_status fail "Nenhum registro MX encontrado para $DOMAIN"
  exit 1
fi

print_status ok "Encontrados $MX_COUNT servidores MX"
for M in $MX; do
  print_status info "$M"
done

> "$OUTDIR/report.md"
> "$OUTDIR/report.json"

echo "# SMTP Audit - $DOMAIN" >> "$OUTDIR/report.md"
echo "{" >> "$OUTDIR/report.json"
echo "  \"domain\": \"$DOMAIN\"," >> "$OUTDIR/report.json"
echo "  \"servers\": [" >> "$OUTDIR/report.json"

print_section "Auditoria SMTP"

FAIL=0
FIRST=1
CURRENT=0

for M in $MX; do
  CURRENT=$((CURRENT + 1))
  IP=$(dig A "$M" +short | head -n1)
  [ -z "$IP" ] && continue

  print_subsection "Servidor $CURRENT/$MX_COUNT: $M"
  print_status info "IP: $IP"

  # Scan nmap nas portas SMTP
  echo ""
  nmap -Pn -sV -sC -p25,465,587 --script=smtp-commands,smtp-enum-users,smtp-open-relay,smtp-vuln-cve2010-4344,smtp-vuln-cve2011-1720,smtp-vuln-cve2011-1764 "$IP" -oN "$OUTDIR/nmap-$IP.txt" -oX "$OUTDIR/nmap-$IP.xml" >/dev/null 2>&1 &
  spin $! "Executando nmap scan"
  print_status ok "Nmap scan completo"

  # Verifica STARTTLS
  STARTTLS="fail"
  if grep -q "STARTTLS" "$OUTDIR/nmap-$IP.txt" 2>/dev/null; then
    STARTTLS="ok"
  fi

  # Verifica open relay detectado pelo nmap
  if grep -q "Server is an open relay" "$OUTDIR/nmap-$IP.txt" 2>/dev/null; then
    NMAP_RELAY="fail"
    FAIL=1
  else
    NMAP_RELAY="ok"
  fi

  # Testes de relay com swaks
  swaks --server "$IP" --port 25 \
    --from auditor@"$DOMAIN" \
    --to auditor@externo-teste.com \
    --ehlo "$DOMAIN" \
    --quit-after RCPT > "$OUTDIR/relay25-$IP.txt" 2>&1 &
  spin $! "Testando relay porta 25"

  swaks --server "$IP" --port 587 \
    --from auditor@"$DOMAIN" \
    --to auditor@externo-teste.com \
    --ehlo "$DOMAIN" \
    --quit-after RCPT > "$OUTDIR/relay587-$IP.txt" 2>&1 &
  spin $! "Testando relay porta 587"

  if grep -q "Connection timed out\|Connection refused" "$OUTDIR/relay25-$IP.txt"; then
    R25="unreachable"
  elif grep -q "250 OK" "$OUTDIR/relay25-$IP.txt"; then
    R25="fail"
    FAIL=1
  else
    R25="ok"
  fi

  if grep -q "Connection timed out\|Connection refused" "$OUTDIR/relay587-$IP.txt"; then
    R587="unreachable"
  elif grep -q "250 OK" "$OUTDIR/relay587-$IP.txt"; then
    R587="fail"
    FAIL=1
  else
    R587="ok"
  fi

  # Exibe resultados
  echo ""
  echo -e "    ${BOLD}Resultados:${NC}"
  
  if [ "$R25" = "ok" ]; then
    print_status ok "Relay porta 25: ${GREEN}Protegido${NC}"
  elif [ "$R25" = "fail" ]; then
    print_status fail "Relay porta 25: ${RED}VULNERÁVEL (Open Relay)${NC}"
  else
    print_status unreachable "Relay porta 25"
  fi

  if [ "$R587" = "ok" ]; then
    print_status ok "Relay porta 587: ${GREEN}Protegido${NC}"
  elif [ "$R587" = "fail" ]; then
    print_status fail "Relay porta 587: ${RED}VULNERÁVEL (Open Relay)${NC}"
  else
    print_status unreachable "Relay porta 587"
  fi

  if [ "$STARTTLS" = "ok" ]; then
    print_status ok "STARTTLS: ${GREEN}Habilitado${NC}"
  else
    print_status warn "STARTTLS: ${YELLOW}Não detectado${NC}"
  fi

  if [ "$NMAP_RELAY" = "fail" ]; then
    print_status fail "Nmap Open Relay: ${RED}DETECTADO${NC}"
  fi

  echo "## $M ($IP)" >> "$OUTDIR/report.md"
  echo "- Relay 25: $R25" >> "$OUTDIR/report.md"
  echo "- Relay 587: $R587" >> "$OUTDIR/report.md"
  echo "- STARTTLS: $STARTTLS" >> "$OUTDIR/report.md"
  echo "" >> "$OUTDIR/report.md"

  [ $FIRST -eq 0 ] && echo "," >> "$OUTDIR/report.json"
  FIRST=0

  echo "    {\"mx\":\"$M\",\"ip\":\"$IP\",\"relay25\":\"$R25\",\"relay587\":\"$R587\",\"starttls\":\"$STARTTLS\"}" >> "$OUTDIR/report.json"

done

echo "  ]" >> "$OUTDIR/report.json"
echo "}" >> "$OUTDIR/report.json"

# ══════════════════════════════════════════════════════════════════════════════
# Resumo Final
# ══════════════════════════════════════════════════════════════════════════════
print_section "Resumo"

echo -e "  ${GRAY}Diretório de saída:${NC} ${BOLD}$OUTDIR${NC}"
echo ""

if [ $FAIL -eq 1 ]; then
  echo -e "  ${RED}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "  ${RED}${BOLD}║  ⚠  VULNERABILIDADES DETECTADAS                               ║${NC}"
  echo -e "  ${RED}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  print_status fail "Verifique os relatórios para detalhes"
  echo ""
  exit 2
else
  echo -e "  ${GREEN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "  ${GREEN}${BOLD}║  ✓  NENHUMA VULNERABILIDADE CRÍTICA DETECTADA                 ║${NC}"
  echo -e "  ${GREEN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  print_status ok "Auditoria concluída com sucesso"
  echo ""
  exit 0
fi
