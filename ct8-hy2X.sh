#!/bin/bash

re="\033[0m"
red="\033[1;91m"
green="\e[1;32m"
yellow="\e[1;33m"
purple="\e[1;35m"
red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }
reading() { read -p "$(red "$1")" "$2"; }

# Função para verificar o status de um único IP (se está bloqueado)
check_ip_status() {
    local ip=$1
    local api_url="https://status.eooce.com/api"
    # Usa grep/cut para evitar a dependência do jq
    local response=$(curl -s --max-time 2 "${api_url}/${ip}")
    local status=$(echo "$response" | grep -o '"status":"[^"]*"' | cut -d':' -f2 | tr -d '"')

    if [[ "$status" == "Available" ]]; then
        echo "Available"
    else
        echo "Blocked"
    fi
}

# Função para exibir IPs e permitir que o usuário selecione um
select_ip_interactive() {
    purple "Buscando lista de IPs do servidor e verificando status..."
    local ip_list=($(devil vhost list | awk '/^[0-9]+/ {print $1}'))
    
    if [ ${#ip_list[@]} -eq 0 ]; then
        red "Não foi possível obter nenhum endereço IP do servidor."
        exit 1
    fi

    local statuses=()
    local first_available_index=-1

    # Preenche os status e encontra o primeiro IP disponível
    for i in "${!ip_list[@]}"; do
        local ip=${ip_list[$i]}
        local status=$(check_ip_status "$ip")
        statuses[$i]=$status
        if [[ "$status" == "Available" && $first_available_index -eq -1 ]]; then
            first_available_index=$i
        fi
    done

    # Exibe a lista para o usuário
    green "Por favor, selecione um IP para usar:"
    for i in "${!ip_list[@]}"; do
        local ip=${ip_list[$i]}
        local status=${statuses[$i]}
        local display_status=""
        if [[ "$status" == "Available" ]]; then
            display_status="$(green '(Disponível)')"
        else
            display_status="$(red '(Bloqueado)')"
        fi
        echo "$((i+1)). $ip ${display_status}"
    done

    if [ $first_available_index -eq -1 ]; then
        red "Nenhum IP disponível (não bloqueado) encontrado. Não é possível continuar."
        exit 1
    fi

    # Solicita a seleção
    local default_choice=$((first_available_index + 1))
    local choice
    reading "Digite o número do IP que deseja usar (padrão: $default_choice, o primeiro IP disponível): " choice
    choice=${choice:-$default_choice}

    # Validação da escolha (validação simples)
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#ip_list[@]} ]; then
        red "Seleção inválida. Usando o IP padrão."
        choice=$default_choice
    fi
    
    local selected_ip=${ip_list[$((choice-1))]}
    purple "Você selecionou: $selected_ip"
    echo "$selected_ip"
}


export LC_ALL=C
HOSTNAME=$(hostname)
NAME=$(echo $HOSTNAME | cut -d '.' -f 1)
PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 8)
REMARK=$(openssl rand -hex 10 | tr -dc '0-9' | head -c 5)
UUID=$(uuidgen)
hostname_number=$(hostname | sed 's/^s\([0-9]*\)\..*/\1/')

# Chama a função para selecionar o IP
SELECTED_IP=$(select_ip_interactive)
if [ -z "$SELECTED_IP" ]; then
    red "Falha na seleção de IP. Saindo."
    exit 1
fi

mkdir -p /home/$USER/web
pkill pyy.py
cat << EOF > /home/$USER/1.sh
#!/bin/bash
echo "ok"
EOF
chmod +x /home/$USER/1.sh

if /home/$USER/1.sh; then
  echo "Permissão de programa ativada"
else
  devil binexec on
  echo "Primeira execução, é necessário relogar no SSH, digite exit para sair do ssh"
  echo "Após relogar no SSH, execute o script mais uma vez"
  exit 0
fi

cd /home/$USER/web

rm -rf /home/$USER/web/*
sleep 1

# Deleta todas as portas UDP já abertas
devil port list | awk 'NR>1 && $1 ~ /^[0-9]+$/ { print $1, $2 }' | while read -r port type; do
    if [[ "$type" == "udp" ]]; then
        echo "Deletando porta UDP: $port"
        devil port del udp "$port"
    fi
done

# Adiciona 1 porta UDP
devil port add udp random

# Espera a porta ter efeito (se o devil tiver atraso)
sleep 2

udp_ports=($(devil port list | awk 'NR>1 && $2 == "udp" { print $1 }'))

if [[ ${#udp_ports[@]} -ge 1 ]]; then
    hy2=${udp_ports[0]}
    echo "hy2=$hy2"
else
    echo "Nenhuma porta UDP encontrada, não é possível atribuir hy2"
    exit 1
fi

cd /home/$USER/web

wget https://download.hysteria.network/app/latest/hysteria-freebsd-amd64
mv hysteria-freebsd-amd64 pyy.py
chmod +x pyy.py
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout web.key -out web.crt -subj "/CN=bing.com" -days 36500

cat << EOF > /home/$USER/web/web.yaml
listen: :$hy2

tls:
  cert: /home/$USER/web/web.crt
  key: /home/$USER/web/web.key

auth:
  type: password
  password: $PASSWORD
  
masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true
EOF

cat << EOF > /home/$USER/web/updateweb.sh
#!/bin/bash
if ps -aux | grep -v grep | grep -q "pyy.py"; then
	cd /home/$USER/web
    exit 0
else
    cd /home/$USER/web
    nohup ./pyy.py server -c web.yaml > /dev/null 2>&1 &
fi
EOF
chmod +x updateweb.sh
./updateweb.sh
cron_job="*/39 * * * * /home/$USER/web/updateweb.sh"
# Verifica se a tarefa já existe
if crontab -l | grep -q "updateweb.sh"; then
    echo "Tarefa de manutenção já existe, pulando adição."
else
    (crontab -l ; echo "$cron_job") | crontab -
    echo "Tarefa de manutenção adicionada ao crontab."
fi
red "Copie as informações do nó HY2 atual"
red "hysteria2://$PASSWORD@$SELECTED_IP:$hy2/?sni=www.bing.com&alpn=h3&insecure=1#$NAME@$USER-hy2"
red ""