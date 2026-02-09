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
echo "Data: $(date '+%Y-%m-%d %H:%M:%S')" >> "$OUTDIR/report.md"
echo "" >> "$OUTDIR/report.md"

echo "{" >> "$OUTDIR/report.json"
echo "  \"domain\": \"$DOMAIN\"," >> "$OUTDIR/report.json"
echo "  \"date\": \"$(date '+%Y-%m-%d %H:%M:%S')\"," >> "$OUTDIR/report.json"
echo "  \"servers\": [" >> "$OUTDIR/report.json"

# Inicializa HTML
cat > "$OUTDIR/report.html" << 'HTMLHEAD'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>SMTP Security Audit Report</title>
  <style>
    :root {
      --bg-dark: #0d1117;
      --bg-card: #161b22;
      --bg-card-hover: #1c2129;
      --border: #30363d;
      --text: #e6edf3;
      --text-muted: #8b949e;
      --green: #3fb950;
      --red: #f85149;
      --yellow: #d29922;
      --blue: #58a6ff;
      --cyan: #39c5cf;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
      background: var(--bg-dark);
      color: var(--text);
      line-height: 1.6;
      padding: 2rem;
    }
    .container { max-width: 1200px; margin: 0 auto; }
    header {
      text-align: center;
      padding: 2rem;
      background: linear-gradient(135deg, #1a1f29 0%, #0d1117 100%);
      border: 1px solid var(--border);
      border-radius: 12px;
      margin-bottom: 2rem;
    }
    header h1 {
      font-size: 2.5rem;
      background: linear-gradient(90deg, var(--cyan), var(--blue));
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      margin-bottom: 0.5rem;
    }
    header .meta { color: var(--text-muted); font-size: 0.9rem; }
    .summary {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
      gap: 1rem;
      margin-bottom: 2rem;
    }
    .summary-card {
      background: var(--bg-card);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 1.5rem;
      text-align: center;
    }
    .summary-card .number { font-size: 2.5rem; font-weight: bold; }
    .summary-card .label { color: var(--text-muted); font-size: 0.85rem; text-transform: uppercase; }
    .summary-card.ok .number { color: var(--green); }
    .summary-card.fail .number { color: var(--red); }
    .summary-card.warn .number { color: var(--yellow); }
    .summary-card.info .number { color: var(--blue); }
    .server-card {
      background: var(--bg-card);
      border: 1px solid var(--border);
      border-radius: 12px;
      margin-bottom: 1.5rem;
      overflow: hidden;
      transition: transform 0.2s, box-shadow 0.2s;
    }
    .server-card:hover {
      transform: translateY(-2px);
      box-shadow: 0 8px 30px rgba(0,0,0,0.3);
    }
    .server-header {
      background: var(--bg-card-hover);
      padding: 1rem 1.5rem;
      border-bottom: 1px solid var(--border);
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .server-header h2 { font-size: 1.1rem; color: var(--cyan); }
    .server-header .ip { color: var(--text-muted); font-family: monospace; }
    .server-body { padding: 1.5rem; }
    .test-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 1rem; }
    .test-item {
      background: var(--bg-dark);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 1rem;
    }
    .test-item h3 {
      font-size: 0.85rem;
      color: var(--text-muted);
      text-transform: uppercase;
      margin-bottom: 0.5rem;
    }
    .test-item .status {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      font-size: 1.1rem;
      font-weight: 600;
    }
    .test-item .status.ok { color: var(--green); }
    .test-item .status.fail { color: var(--red); }
    .test-item .status.warn { color: var(--yellow); }
    .test-item .status.unreachable { color: var(--text-muted); }
    .test-item .details {
      margin-top: 0.75rem;
      padding-top: 0.75rem;
      border-top: 1px solid var(--border);
      font-size: 0.85rem;
      color: var(--text-muted);
    }
    .test-item .details code {
      display: block;
      background: #0d1117;
      padding: 0.5rem;
      border-radius: 4px;
      margin-top: 0.5rem;
      font-family: 'Fira Code', monospace;
      font-size: 0.8rem;
      overflow-x: auto;
      white-space: pre-wrap;
      word-break: break-all;
    }
    .vuln-detail {
      background: rgba(248, 81, 73, 0.1);
      border: 1px solid var(--red);
      border-radius: 8px;
      padding: 1rem;
      margin-top: 1rem;
    }
    .vuln-detail h4 { color: var(--red); margin-bottom: 0.5rem; }
    .vuln-detail ul { margin-left: 1.5rem; }
    .vuln-detail li { margin-bottom: 0.25rem; }
    .collapsible { cursor: pointer; user-select: none; }
    .collapsible::before { content: '▶ '; font-size: 0.7rem; }
    .collapsible.active::before { content: '▼ '; }
    .collapsible-content { display: none; margin-top: 0.5rem; }
    .collapsible-content.show { display: block; }
    .nmap-output {
      background: #0d1117;
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 1rem;
      margin-top: 1rem;
      font-family: 'Fira Code', monospace;
      font-size: 0.8rem;
      overflow-x: auto;
      white-space: pre-wrap;
      max-height: 400px;
      overflow-y: auto;
    }
    .badge {
      display: inline-block;
      padding: 0.25rem 0.5rem;
      border-radius: 4px;
      font-size: 0.75rem;
      font-weight: 600;
      text-transform: uppercase;
    }
    .badge.critical { background: var(--red); color: white; }
    .badge.warning { background: var(--yellow); color: black; }
    .badge.safe { background: var(--green); color: white; }
    footer {
      text-align: center;
      padding: 2rem;
      color: var(--text-muted);
      font-size: 0.85rem;
    }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <h1>🔒 SMTP Security Audit</h1>
HTMLHEAD

echo "      <p class=\"meta\">Domínio: <strong>$DOMAIN</strong> | Data: $(date '+%Y-%m-%d %H:%M:%S')</p>" >> "$OUTDIR/report.html"
echo "    </header>" >> "$OUTDIR/report.html"

print_section "Auditoria SMTP"

FAIL=0
FIRST=1
CURRENT=0
TOTAL_VULNS=0
SERVERS_OK=0
SERVERS_FAIL=0

# Array para armazenar dados HTML dos servidores
declare -a HTML_SERVERS

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
    R25_DETAIL="Porta 25 não está acessível (timeout ou conexão recusada)"
  elif grep -q "250 OK" "$OUTDIR/relay25-$IP.txt"; then
    R25="fail"
    FAIL=1
    TOTAL_VULNS=$((TOTAL_VULNS + 1))
    R25_DETAIL="CRÍTICO: Servidor aceita relay sem autenticação na porta 25. Resposta '250 OK' ao RCPT TO externo. Atacantes podem usar este servidor para enviar spam."
  else
    R25="ok"
    R25_DETAIL="Servidor rejeitou corretamente tentativa de relay não autenticado"
  fi

  if grep -q "Connection timed out\|Connection refused" "$OUTDIR/relay587-$IP.txt"; then
    R587="unreachable"
    R587_DETAIL="Porta 587 não está acessível (timeout ou conexão recusada)"
  elif grep -q "250 OK" "$OUTDIR/relay587-$IP.txt"; then
    R587="fail"
    FAIL=1
    TOTAL_VULNS=$((TOTAL_VULNS + 1))
    R587_DETAIL="CRÍTICO: Servidor aceita relay sem autenticação na porta 587. Resposta '250 OK' ao RCPT TO externo."
  else
    R587="ok"
    R587_DETAIL="Servidor rejeitou corretamente tentativa de relay não autenticado"
  fi

  # Extrai detalhes do swaks para relatório
  SWAKS25_RESPONSE=$(grep -E "^[<>~]" "$OUTDIR/relay25-$IP.txt" 2>/dev/null | tail -10)
  SWAKS587_RESPONSE=$(grep -E "^[<>~]" "$OUTDIR/relay587-$IP.txt" 2>/dev/null | tail -10)

  # Extrai vulnerabilidades do nmap
  NMAP_VULNS=""
  if grep -q "VULNERABLE" "$OUTDIR/nmap-$IP.txt" 2>/dev/null; then
    NMAP_VULNS=$(grep -A5 "VULNERABLE" "$OUTDIR/nmap-$IP.txt" 2>/dev/null)
    FAIL=1
    TOTAL_VULNS=$((TOTAL_VULNS + 1))
  fi

  # Extrai comandos SMTP disponíveis
  SMTP_COMMANDS=$(grep -A10 "smtp-commands:" "$OUTDIR/nmap-$IP.txt" 2>/dev/null | head -5)

  # Verifica se há usuários enumerados
  ENUM_USERS=""
  if grep -q "smtp-enum-users" "$OUTDIR/nmap-$IP.txt" 2>/dev/null; then
    ENUM_USERS=$(grep -A10 "smtp-enum-users:" "$OUTDIR/nmap-$IP.txt" 2>/dev/null)
  fi

  # Conta vulnerabilidades deste servidor
  SERVER_VULNS=0
  [ "$R25" = "fail" ] && SERVER_VULNS=$((SERVER_VULNS + 1))
  [ "$R587" = "fail" ] && SERVER_VULNS=$((SERVER_VULNS + 1))
  [ "$NMAP_RELAY" = "fail" ] && SERVER_VULNS=$((SERVER_VULNS + 1))
  [ -n "$NMAP_VULNS" ] && SERVER_VULNS=$((SERVER_VULNS + 1))

  if [ $SERVER_VULNS -gt 0 ]; then
    SERVERS_FAIL=$((SERVERS_FAIL + 1))
  else
    SERVERS_OK=$((SERVERS_OK + 1))
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

  # ════════════════════════════════════════════════════════════════════════════
  # Gera relatório Markdown detalhado
  # ════════════════════════════════════════════════════════════════════════════
  echo "## $M ($IP)" >> "$OUTDIR/report.md"
  echo "" >> "$OUTDIR/report.md"
  echo "### Resultados dos Testes" >> "$OUTDIR/report.md"
  echo "" >> "$OUTDIR/report.md"
  echo "| Teste | Status | Detalhes |" >> "$OUTDIR/report.md"
  echo "|-------|--------|----------|" >> "$OUTDIR/report.md"
  echo "| Relay Porta 25 | $R25 | $R25_DETAIL |" >> "$OUTDIR/report.md"
  echo "| Relay Porta 587 | $R587 | $R587_DETAIL |" >> "$OUTDIR/report.md"
  echo "| STARTTLS | $STARTTLS | $([ "$STARTTLS" = "ok" ] && echo "TLS habilitado" || echo "TLS não detectado - comunicação pode estar em texto plano") |" >> "$OUTDIR/report.md"
  echo "| Nmap Open Relay | $NMAP_RELAY | $([ "$NMAP_RELAY" = "fail" ] && echo "Nmap detectou servidor como open relay" || echo "Nmap não detectou open relay") |" >> "$OUTDIR/report.md"
  echo "" >> "$OUTDIR/report.md"

  if [ "$R25" = "fail" ] || [ "$R587" = "fail" ] || [ "$NMAP_RELAY" = "fail" ] || [ -n "$NMAP_VULNS" ]; then
    echo "### ⚠️ Vulnerabilidades Detectadas" >> "$OUTDIR/report.md"
    echo "" >> "$OUTDIR/report.md"
    [ "$R25" = "fail" ] && echo "- **Open Relay Porta 25**: $R25_DETAIL" >> "$OUTDIR/report.md"
    [ "$R587" = "fail" ] && echo "- **Open Relay Porta 587**: $R587_DETAIL" >> "$OUTDIR/report.md"
    [ "$NMAP_RELAY" = "fail" ] && echo "- **Nmap Open Relay**: Script nmap detectou servidor como open relay" >> "$OUTDIR/report.md"
    [ -n "$NMAP_VULNS" ] && echo -e "- **Vulnerabilidades Nmap**:\n\`\`\`\n$NMAP_VULNS\n\`\`\`" >> "$OUTDIR/report.md"
    echo "" >> "$OUTDIR/report.md"
    echo "### Recomendações" >> "$OUTDIR/report.md"
    echo "" >> "$OUTDIR/report.md"
    echo "1. Configure autenticação SMTP obrigatória para relay" >> "$OUTDIR/report.md"
    echo "2. Restrinja relay apenas para IPs/redes autorizadas" >> "$OUTDIR/report.md"
    echo "3. Implemente SPF, DKIM e DMARC" >> "$OUTDIR/report.md"
    echo "4. Monitore logs de envio de e-mail para atividades suspeitas" >> "$OUTDIR/report.md"
    echo "" >> "$OUTDIR/report.md"
  fi

  if [ -n "$SMTP_COMMANDS" ]; then
    echo "### Comandos SMTP Disponíveis" >> "$OUTDIR/report.md"
    echo "\`\`\`" >> "$OUTDIR/report.md"
    echo "$SMTP_COMMANDS" >> "$OUTDIR/report.md"
    echo "\`\`\`" >> "$OUTDIR/report.md"
    echo "" >> "$OUTDIR/report.md"
  fi

  echo "### Log do Teste Porta 25" >> "$OUTDIR/report.md"
  echo "\`\`\`" >> "$OUTDIR/report.md"
  cat "$OUTDIR/relay25-$IP.txt" >> "$OUTDIR/report.md" 2>/dev/null
  echo "\`\`\`" >> "$OUTDIR/report.md"
  echo "" >> "$OUTDIR/report.md"

  echo "### Log do Teste Porta 587" >> "$OUTDIR/report.md"
  echo "\`\`\`" >> "$OUTDIR/report.md"
  cat "$OUTDIR/relay587-$IP.txt" >> "$OUTDIR/report.md" 2>/dev/null
  echo "\`\`\`" >> "$OUTDIR/report.md"
  echo "" >> "$OUTDIR/report.md"
  echo "---" >> "$OUTDIR/report.md"
  echo "" >> "$OUTDIR/report.md"

  # ════════════════════════════════════════════════════════════════════════════
  # Gera HTML para este servidor
  # ════════════════════════════════════════════════════════════════════════════
  SERVER_STATUS_CLASS="safe"
  SERVER_STATUS_TEXT="Seguro"
  [ $SERVER_VULNS -gt 0 ] && SERVER_STATUS_CLASS="critical" && SERVER_STATUS_TEXT="$SERVER_VULNS Vulnerabilidade(s)"

  cat >> "$OUTDIR/report.html" << SERVERHTML
    <div class="server-card">
      <div class="server-header">
        <h2>📧 $M</h2>
        <span class="ip">$IP</span>
        <span class="badge $SERVER_STATUS_CLASS">$SERVER_STATUS_TEXT</span>
      </div>
      <div class="server-body">
        <div class="test-grid">
          <div class="test-item">
            <h3>Relay Porta 25</h3>
            <div class="status $R25">$([ "$R25" = "ok" ] && echo "✓ Protegido" || ([ "$R25" = "fail" ] && echo "✗ VULNERÁVEL" || echo "• Inacessível"))</div>
            <div class="details">
              $R25_DETAIL
              <span class="collapsible" onclick="this.classList.toggle('active'); this.nextElementSibling.classList.toggle('show')">Ver resposta SMTP</span>
              <code class="collapsible-content">$(cat "$OUTDIR/relay25-$IP.txt" 2>/dev/null | sed 's/</\&lt;/g; s/>/\&gt;/g' | head -20)</code>
            </div>
          </div>
          <div class="test-item">
            <h3>Relay Porta 587</h3>
            <div class="status $R587">$([ "$R587" = "ok" ] && echo "✓ Protegido" || ([ "$R587" = "fail" ] && echo "✗ VULNERÁVEL" || echo "• Inacessível"))</div>
            <div class="details">
              $R587_DETAIL
              <span class="collapsible" onclick="this.classList.toggle('active'); this.nextElementSibling.classList.toggle('show')">Ver resposta SMTP</span>
              <code class="collapsible-content">$(cat "$OUTDIR/relay587-$IP.txt" 2>/dev/null | sed 's/</\&lt;/g; s/>/\&gt;/g' | head -20)</code>
            </div>
          </div>
          <div class="test-item">
            <h3>STARTTLS</h3>
            <div class="status $([ "$STARTTLS" = "ok" ] && echo "ok" || echo "warn")">$([ "$STARTTLS" = "ok" ] && echo "✓ Habilitado" || echo "• Não detectado")</div>
            <div class="details">$([ "$STARTTLS" = "ok" ] && echo "Servidor suporta criptografia TLS" || echo "Servidor pode estar transmitindo em texto plano")</div>
          </div>
          <div class="test-item">
            <h3>Nmap Open Relay</h3>
            <div class="status $NMAP_RELAY">$([ "$NMAP_RELAY" = "ok" ] && echo "✓ Não detectado" || echo "✗ DETECTADO")</div>
            <div class="details">Verificação via script nmap smtp-open-relay</div>
          </div>
        </div>
SERVERHTML

  # Adiciona seção de vulnerabilidades se houver
  if [ $SERVER_VULNS -gt 0 ]; then
    cat >> "$OUTDIR/report.html" << VULNHTML
        <div class="vuln-detail">
          <h4>⚠️ Detalhes das Vulnerabilidades</h4>
          <ul>
VULNHTML
    [ "$R25" = "fail" ] && echo "            <li><strong>Open Relay Porta 25:</strong> $R25_DETAIL</li>" >> "$OUTDIR/report.html"
    [ "$R587" = "fail" ] && echo "            <li><strong>Open Relay Porta 587:</strong> $R587_DETAIL</li>" >> "$OUTDIR/report.html"
    [ "$NMAP_RELAY" = "fail" ] && echo "            <li><strong>Nmap Open Relay:</strong> Script nmap confirmou servidor como open relay</li>" >> "$OUTDIR/report.html"
    if [ -n "$NMAP_VULNS" ]; then
      echo "            <li><strong>Vulnerabilidades CVE detectadas:</strong><pre>$(echo "$NMAP_VULNS" | sed 's/</\&lt;/g; s/>/\&gt;/g')</pre></li>" >> "$OUTDIR/report.html"
    fi
    cat >> "$OUTDIR/report.html" << VULNHTML2
          </ul>
          <h4 style="margin-top: 1rem;">🛡️ Recomendações</h4>
          <ul>
            <li>Configure autenticação SMTP obrigatória para relay</li>
            <li>Restrinja relay apenas para IPs/redes autorizadas</li>
            <li>Implemente SPF, DKIM e DMARC</li>
            <li>Monitore logs de envio para atividades suspeitas</li>
          </ul>
        </div>
VULNHTML2
  fi

  # Adiciona output do nmap
  if [ -f "$OUTDIR/nmap-$IP.txt" ]; then
    cat >> "$OUTDIR/report.html" << NMAPHTML
        <div style="margin-top: 1rem;">
          <span class="collapsible" onclick="this.classList.toggle('active'); this.nextElementSibling.classList.toggle('show')">📋 Ver output completo do Nmap</span>
          <div class="nmap-output collapsible-content">$(cat "$OUTDIR/nmap-$IP.txt" | sed 's/</\&lt;/g; s/>/\&gt;/g')</div>
        </div>
NMAPHTML
  fi

  echo "      </div>" >> "$OUTDIR/report.html"
  echo "    </div>" >> "$OUTDIR/report.html"

  [ $FIRST -eq 0 ] && echo "," >> "$OUTDIR/report.json"
  FIRST=0

  # JSON detalhado
  cat >> "$OUTDIR/report.json" << JSONSERVER
    {
      "mx": "$M",
      "ip": "$IP",
      "relay25": {
        "status": "$R25",
        "detail": "$R25_DETAIL"
      },
      "relay587": {
        "status": "$R587",
        "detail": "$R587_DETAIL"
      },
      "starttls": "$STARTTLS",
      "nmap_relay": "$NMAP_RELAY",
      "vulnerabilities_count": $SERVER_VULNS
    }
JSONSERVER

done

echo "  ]," >> "$OUTDIR/report.json"
echo "  \"summary\": {" >> "$OUTDIR/report.json"
echo "    \"total_servers\": $MX_COUNT," >> "$OUTDIR/report.json"
echo "    \"servers_ok\": $SERVERS_OK," >> "$OUTDIR/report.json"
echo "    \"servers_vulnerable\": $SERVERS_FAIL," >> "$OUTDIR/report.json"
echo "    \"total_vulnerabilities\": $TOTAL_VULNS" >> "$OUTDIR/report.json"
echo "  }" >> "$OUTDIR/report.json"
echo "}" >> "$OUTDIR/report.json"

# ════════════════════════════════════════════════════════════════════════════
# Finaliza HTML com resumo
# ════════════════════════════════════════════════════════════════════════════
# Insere summary cards no início (após header)
SUMMARY_HTML=$(cat << SUMMARYEOF
    <div class="summary">
      <div class="summary-card info">
        <div class="number">$MX_COUNT</div>
        <div class="label">Servidores MX</div>
      </div>
      <div class="summary-card ok">
        <div class="number">$SERVERS_OK</div>
        <div class="label">Seguros</div>
      </div>
      <div class="summary-card fail">
        <div class="number">$SERVERS_FAIL</div>
        <div class="label">Vulneráveis</div>
      </div>
      <div class="summary-card $([ $TOTAL_VULNS -gt 0 ] && echo "fail" || echo "ok")">
        <div class="number">$TOTAL_VULNS</div>
        <div class="label">Vulnerabilidades</div>
      </div>
    </div>
SUMMARYEOF
)

# Cria arquivo temporário com summary inserido
{
  head -n $(grep -n "</header>" "$OUTDIR/report.html" | cut -d: -f1) "$OUTDIR/report.html"
  echo "$SUMMARY_HTML"
  tail -n +$(($(grep -n "</header>" "$OUTDIR/report.html" | cut -d: -f1) + 1)) "$OUTDIR/report.html"
} > "$OUTDIR/report.html.tmp" && mv "$OUTDIR/report.html.tmp" "$OUTDIR/report.html"

# Adiciona footer
cat >> "$OUTDIR/report.html" << HTMLFOOTER
    <footer>
      <p>Gerado por SMTP Security Audit Tool | $(date '+%Y-%m-%d %H:%M:%S')</p>
      <p>Arquivos de log disponíveis no diretório: $OUTDIR</p>
    </footer>
  </div>
  <script>
    // Auto-expand vulnerabilities on page load
    document.querySelectorAll('.vuln-detail').forEach(el => {
      el.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    });
  </script>
</body>
</html>
HTMLFOOTER

# ══════════════════════════════════════════════════════════════════════════════
# Resumo Final
# ══════════════════════════════════════════════════════════════════════════════
print_section "Resumo"

echo -e "  ${GRAY}Diretório de saída:${NC} ${BOLD}$OUTDIR${NC}"
echo ""
echo -e "  ${GRAY}Relatórios gerados:${NC}"
print_status ok "report.html - Relatório visual (abra no navegador)"
print_status ok "report.md   - Relatório Markdown"
print_status ok "report.json - Dados estruturados"
echo ""
echo -e "  ${GRAY}Estatísticas:${NC}"
print_status info "Servidores analisados: $MX_COUNT"
print_status ok "Servidores seguros: $SERVERS_OK"
[ $SERVERS_FAIL -gt 0 ] && print_status fail "Servidores vulneráveis: $SERVERS_FAIL"
[ $TOTAL_VULNS -gt 0 ] && print_status fail "Total de vulnerabilidades: $TOTAL_VULNS"
echo ""

if [ $FAIL -eq 1 ]; then
  echo -e "  ${RED}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "  ${RED}${BOLD}║  ⚠  VULNERABILIDADES DETECTADAS                               ║${NC}"
  echo -e "  ${RED}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  print_status fail "Verifique os relatórios para detalhes"
  echo ""
  echo -e "  ${YELLOW}Abra o relatório HTML:${NC}"
  echo -e "  ${CYAN}xdg-open $OUTDIR/report.html${NC}"
  echo ""
  exit 2
else
  echo -e "  ${GREEN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "  ${GREEN}${BOLD}║  ✓  NENHUMA VULNERABILIDADE CRÍTICA DETECTADA                 ║${NC}"
  echo -e "  ${GREEN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  print_status ok "Auditoria concluída com sucesso"
  echo ""
  echo -e "  ${GRAY}Abra o relatório HTML:${NC}"
  echo -e "  ${CYAN}xdg-open $OUTDIR/report.html${NC}"
  echo ""
  exit 0
fi
