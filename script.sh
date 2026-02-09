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
CHECK="[OK]"
CROSS="[FAIL]"
ARROW=">>"
BULLET="--"
SPINNER=('|' '/' '-' '\')

# ══════════════════════════════════════════════════════════════════════════════
# Funções de UI
# ══════════════════════════════════════════════════════════════════════════════
print_banner() {
  clear
  echo -e "${CYAN}"
  echo "  ┌─────────────────────────────────────────────────────────────────┐"
  echo "  │                     SMTP SECURITY AUDIT                         │"
  echo "  │                        Pentest Tool v1.0                        │"
  echo "  └─────────────────────────────────────────────────────────────────┘"
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
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Courier New', Courier, monospace;
      background: #0a0a0a;
      color: #00ff00;
      line-height: 1.5;
      padding: 20px;
      font-size: 14px;
    }
    .container { max-width: 1000px; margin: 0 auto; }
    header {
      border: 1px solid #00ff00;
      padding: 15px;
      margin-bottom: 20px;
    }
    header h1 {
      font-size: 1.2rem;
      font-weight: normal;
      margin-bottom: 5px;
    }
    header .meta { color: #888; font-size: 0.85rem; }
    .summary {
      display: flex;
      flex-wrap: wrap;
      gap: 20px;
      margin-bottom: 20px;
      padding: 15px;
      border: 1px dashed #444;
    }
    .summary-item { min-width: 150px; }
    .summary-item .label { color: #888; }
    .summary-item .value { font-weight: bold; }
    .summary-item .value.ok { color: #00ff00; }
    .summary-item .value.fail { color: #ff0000; }
    .summary-item .value.warn { color: #ffff00; }
    .server-block {
      border: 1px solid #333;
      margin-bottom: 15px;
    }
    .server-header {
      background: #111;
      padding: 10px 15px;
      border-bottom: 1px solid #333;
      display: flex;
      justify-content: space-between;
      flex-wrap: wrap;
      gap: 10px;
    }
    .server-header .name { color: #00ffff; }
    .server-header .ip { color: #888; }
    .server-header .badge {
      padding: 2px 8px;
      font-size: 0.8rem;
    }
    .server-header .badge.critical { color: #ff0000; border: 1px solid #ff0000; }
    .server-header .badge.safe { color: #00ff00; border: 1px solid #00ff00; }
    .server-body { padding: 15px; }
    .test-row {
      display: flex;
      padding: 8px 0;
      border-bottom: 1px dotted #222;
    }
    .test-row:last-child { border-bottom: none; }
    .test-label { width: 200px; color: #888; }
    .test-value { flex: 1; }
    .test-value.ok { color: #00ff00; }
    .test-value.fail { color: #ff0000; }
    .test-value.warn { color: #ffff00; }
    .test-value.unreachable { color: #666; }
    .details {
      margin-top: 5px;
      padding-left: 200px;
      color: #666;
      font-size: 0.85rem;
    }
    .vuln-box {
      background: #1a0000;
      border: 1px solid #ff0000;
      padding: 15px;
      margin-top: 15px;
    }
    .vuln-box h4 { color: #ff0000; margin-bottom: 10px; font-weight: normal; }
    .vuln-box ul { margin-left: 20px; color: #ff6666; }
    .vuln-box li { margin-bottom: 5px; }
    .recommendations {
      margin-top: 15px;
      padding-top: 15px;
      border-top: 1px dashed #333;
    }
    .recommendations h4 { color: #00ffff; margin-bottom: 10px; font-weight: normal; }
    .recommendations ul { margin-left: 20px; color: #888; }
    .collapsible {
      cursor: pointer;
      color: #00ffff;
      text-decoration: underline;
      margin-top: 10px;
      display: inline-block;
    }
    .collapsible:hover { color: #00ff00; }
    .collapsible-content {
      display: none;
      margin-top: 10px;
      padding: 10px;
      background: #050505;
      border: 1px solid #222;
      max-height: 300px;
      overflow: auto;
      white-space: pre-wrap;
      font-size: 0.8rem;
      color: #888;
    }
    .collapsible-content.show { display: block; }
    footer {
      text-align: center;
      padding: 20px;
      color: #444;
      font-size: 0.8rem;
      border-top: 1px solid #222;
      margin-top: 20px;
    }
    pre { white-space: pre-wrap; word-break: break-all; }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <h1>[ SMTP SECURITY AUDIT ]</h1>
HTMLHEAD

echo "      <p class=\"meta\">Target: $DOMAIN | Date: $(date '+%Y-%m-%d %H:%M:%S')</p>" >> "$OUTDIR/report.html"
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
  echo -e "    ${BOLD}Results:${NC}"
  
  if [ "$R25" = "ok" ]; then
    print_status ok "Relay port 25: ${GREEN}Protected${NC}"
  elif [ "$R25" = "fail" ]; then
    print_status fail "Relay port 25: ${RED}VULNERABLE (Open Relay)${NC}"
  else
    print_status unreachable "Relay port 25"
  fi

  if [ "$R587" = "ok" ]; then
    print_status ok "Relay port 587: ${GREEN}Protected${NC}"
  elif [ "$R587" = "fail" ]; then
    print_status fail "Relay port 587: ${RED}VULNERABLE (Open Relay)${NC}"
  else
    print_status unreachable "Relay port 587"
  fi

  if [ "$STARTTLS" = "ok" ]; then
    print_status ok "STARTTLS: ${GREEN}Enabled${NC}"
  else
    print_status warn "STARTTLS: ${YELLOW}Not detected${NC}"
  fi

  if [ "$NMAP_RELAY" = "fail" ]; then
    print_status fail "Nmap Open Relay: ${RED}DETECTED${NC}"
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
  SERVER_STATUS_TEXT="OK"
  [ $SERVER_VULNS -gt 0 ] && SERVER_STATUS_CLASS="critical" && SERVER_STATUS_TEXT="$SERVER_VULNS VULN"

  cat >> "$OUTDIR/report.html" << SERVERHTML
    <div class="server-block">
      <div class="server-header">
        <span class="name">$M</span>
        <span class="ip">$IP</span>
        <span class="badge $SERVER_STATUS_CLASS">[$SERVER_STATUS_TEXT]</span>
      </div>
      <div class="server-body">
        <div class="test-row">
          <span class="test-label">Relay Port 25:</span>
          <span class="test-value $R25">$([ "$R25" = "ok" ] && echo "[OK] Protected" || ([ "$R25" = "fail" ] && echo "[FAIL] VULNERABLE" || echo "[--] Unreachable"))</span>
        </div>
        <div class="details">$R25_DETAIL</div>
        
        <div class="test-row">
          <span class="test-label">Relay Port 587:</span>
          <span class="test-value $R587">$([ "$R587" = "ok" ] && echo "[OK] Protected" || ([ "$R587" = "fail" ] && echo "[FAIL] VULNERABLE" || echo "[--] Unreachable"))</span>
        </div>
        <div class="details">$R587_DETAIL</div>
        
        <div class="test-row">
          <span class="test-label">STARTTLS:</span>
          <span class="test-value $([ "$STARTTLS" = "ok" ] && echo "ok" || echo "warn")">$([ "$STARTTLS" = "ok" ] && echo "[OK] Enabled" || echo "[WARN] Not detected")</span>
        </div>
        
        <div class="test-row">
          <span class="test-label">Nmap Open Relay:</span>
          <span class="test-value $NMAP_RELAY">$([ "$NMAP_RELAY" = "ok" ] && echo "[OK] Not detected" || echo "[FAIL] DETECTED")</span>
        </div>
SERVERHTML

  # Adiciona seção de vulnerabilidades se houver
  if [ $SERVER_VULNS -gt 0 ]; then
    cat >> "$OUTDIR/report.html" << VULNHTML
        <div class="vuln-box">
          <h4>:: VULNERABILITIES DETECTED ::</h4>
          <ul>
VULNHTML
    [ "$R25" = "fail" ] && echo "            <li>Open Relay Port 25: $R25_DETAIL</li>" >> "$OUTDIR/report.html"
    [ "$R587" = "fail" ] && echo "            <li>Open Relay Port 587: $R587_DETAIL</li>" >> "$OUTDIR/report.html"
    [ "$NMAP_RELAY" = "fail" ] && echo "            <li>Nmap Open Relay: Script confirmed open relay</li>" >> "$OUTDIR/report.html"
    if [ -n "$NMAP_VULNS" ]; then
      echo "            <li>CVE Vulnerabilities:<pre>$(echo "$NMAP_VULNS" | sed 's/</\&lt;/g; s/>/\&gt;/g')</pre></li>" >> "$OUTDIR/report.html"
    fi
    cat >> "$OUTDIR/report.html" << VULNHTML2
          </ul>
          <div class="recommendations">
            <h4>:: RECOMMENDATIONS ::</h4>
            <ul>
              <li>Configure mandatory SMTP authentication for relay</li>
              <li>Restrict relay to authorized IPs/networks only</li>
              <li>Implement SPF, DKIM and DMARC</li>
              <li>Monitor mail logs for suspicious activity</li>
            </ul>
          </div>
        </div>
VULNHTML2
  fi

  # Adiciona output do nmap
  if [ -f "$OUTDIR/nmap-$IP.txt" ]; then
    cat >> "$OUTDIR/report.html" << NMAPHTML
        <span class="collapsible" onclick="this.nextElementSibling.classList.toggle('show')">[+] View Nmap output</span>
        <div class="collapsible-content">$(cat "$OUTDIR/nmap-$IP.txt" | sed 's/</\&lt;/g; s/>/\&gt;/g')</div>
        
        <span class="collapsible" onclick="this.nextElementSibling.classList.toggle('show')">[+] View SMTP Port 25 log</span>
        <div class="collapsible-content">$(cat "$OUTDIR/relay25-$IP.txt" 2>/dev/null | sed 's/</\&lt;/g; s/>/\&gt;/g')</div>
        
        <span class="collapsible" onclick="this.nextElementSibling.classList.toggle('show')">[+] View SMTP Port 587 log</span>
        <div class="collapsible-content">$(cat "$OUTDIR/relay587-$IP.txt" 2>/dev/null | sed 's/</\&lt;/g; s/>/\&gt;/g')</div>
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
      <div class="summary-item">
        <span class="label">MX Servers:</span>
        <span class="value">$MX_COUNT</span>
      </div>
      <div class="summary-item">
        <span class="label">Secure:</span>
        <span class="value ok">$SERVERS_OK</span>
      </div>
      <div class="summary-item">
        <span class="label">Vulnerable:</span>
        <span class="value $([ $SERVERS_FAIL -gt 0 ] && echo "fail" || echo "ok")">$SERVERS_FAIL</span>
      </div>
      <div class="summary-item">
        <span class="label">Total Vulns:</span>
        <span class="value $([ $TOTAL_VULNS -gt 0 ] && echo "fail" || echo "ok")">$TOTAL_VULNS</span>
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
      <p>Generated by SMTP Security Audit Tool | $(date '+%Y-%m-%d %H:%M:%S')</p>
      <p>Log files: $OUTDIR/</p>
    </footer>
  </div>
</body>
</html>
HTMLFOOTER

# ══════════════════════════════════════════════════════════════════════════════
# Resumo Final
# ══════════════════════════════════════════════════════════════════════════════
print_section "Summary"

echo -e "  ${GRAY}Output directory:${NC} ${BOLD}$OUTDIR${NC}"
echo ""
echo -e "  ${GRAY}Reports generated:${NC}"
print_status ok "report.html - Visual report (open in browser)"
print_status ok "report.md   - Markdown report"
print_status ok "report.json - Structured data"
echo ""
echo -e "  ${GRAY}Statistics:${NC}"
print_status info "Servers analyzed: $MX_COUNT"
print_status ok "Secure servers: $SERVERS_OK"
[ $SERVERS_FAIL -gt 0 ] && print_status fail "Vulnerable servers: $SERVERS_FAIL"
[ $TOTAL_VULNS -gt 0 ] && print_status fail "Total vulnerabilities: $TOTAL_VULNS"
echo ""

if [ $FAIL -eq 1 ]; then
  echo -e "  ${RED}┌────────────────────────────────────────────────────────────────┐${NC}"
  echo -e "  ${RED}│  [!] VULNERABILITIES DETECTED                                  │${NC}"
  echo -e "  ${RED}└────────────────────────────────────────────────────────────────┘${NC}"
  echo ""
  print_status fail "Check reports for details"
  echo ""
  echo -e "  ${YELLOW}Open HTML report:${NC}"
  echo -e "  ${CYAN}xdg-open $OUTDIR/report.html${NC}"
  echo ""
  exit 2
else
  echo -e "  ${GREEN}┌────────────────────────────────────────────────────────────────┐${NC}"
  echo -e "  ${GREEN}│  [OK] NO CRITICAL VULNERABILITIES DETECTED                    │${NC}"
  echo -e "  ${GREEN}└────────────────────────────────────────────────────────────────┘${NC}"
  echo ""
  print_status ok "Audit completed successfully"
  echo ""
  echo -e "  ${GRAY}Open HTML report:${NC}"
  echo -e "  ${CYAN}xdg-open $OUTDIR/report.html${NC}"
  echo ""
  exit 0
fi
