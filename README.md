# Projeto Prático: Servidor Linux de Rede (IFSP)

Repositório com os arquivos de configuração, código-fonte da aplicação Java Web, scripts SQL, automação de provisionamento e documentação passo a passo do **Servidor Linux de Rede** desenvolvido para a disciplina de Redes de Computadores no **IFSP**.

---

## 1. Visão Geral e Requisitos Atendidos

O objetivo do projeto é instalar, configurar e disponibilizar em rede local (acessível pelas bancadas do laboratório de informática do campus) um servidor Linux completo integrando banco de dados relacional, container de aplicações Java Web e servidor HTTP com suporte a PHP hospedando um sistema Open Source (CMS).

| Requisito do Projeto | Solução Implementada | Porta / Protocolo | Serviço (`systemd`) |
| :--- | :--- | :--- | :--- |
| **Sistema Operacional Linux/BSD** | **Debian GNU/Linux 13 (Trixie)** (`Servidor-Redes-Projeto`) | `22/TCP` (SSH) | `ssh.service` |
| **Servidor Acessível via Rede** | Interface `enp0s3` em **Modo Bridge** (VirtualBox) com DHCP automático | Todas | `NetworkManager` |
| **SGBD Instalado e Funcionando** | **MariaDB Server 11.8** (`cms_db`) | `3306/TCP` | `mariadb.service` |
| **Suporte a Java Web + Acesso a BD** | **Apache Tomcat 10.1.8** + OpenJDK + Driver `mariadb-java-client-3.3.3.jar` | `8080/TCP` | `tomcat.service` |
| **Aplicação Java Web com Consultas SQL** | Console **Inventário de Serviços de Rede e Auditoria SGBD** (`/projeto-rede/index.jsp`) | `8080/TCP` | `tomcat.service` |
| **Servidor HTTP com Suporte a PHP e BD** | **Nginx** + **PHP 8.4-FPM** (`mysqli`, `pdo_mysql`) | `80/TCP` | `nginx.service` / `php8.4-fpm.service` |
| **Aplicação Web Open Source (CMS)** | **WordPress CMS** em `/var/www/html` integrado ao banco `cms_db` | `80/TCP` | `nginx.service` |

---

## 2. Estrutura do Repositório

```text
projeto-servidor/
├── README.md                           # Documentação passo a passo e guia de execução
├── webapp/
│   └── projeto-rede/
│       └── index.jsp                   # Aplicação Java Web (Jakarta JSP + JDBC MariaDB)
├── sql/
│   └── init_database.sql               # Criação do banco cms_db, usuário cms_user e tabelas iniciais
├── config/
│   ├── systemd/
│   │   └── tomcat.service              # Unit file do Apache Tomcat 10 para o Systemd
│   ├── nginx/
│   │   └── default                     # VirtualHost do Nginx com FastCGI (PHP 8.4-FPM)
│   └── wordpress/
│       └── wp-config.php               # Configuração do WordPress com resolução dinâmica de IP
└── scripts/
    └── setup_servidor.sh               # Script automatizado para instalação completa do zero
```

---

## 3. Como Executar (Instalação Rápida Automatizada)

Caso queira reproduzir toda a instalação em uma máquina virtual Debian limpa com um único comando:

```bash
git clone https://github.com/caiocanalli12/projeto-servidor.git
cd projeto-servidor
chmod +x scripts/setup_servidor.sh
./scripts/setup_servidor.sh
```

---

## 4. Passo a Passo Completo das Ações Realizadas (Instalação Manual)

Abaixo está o roteiro detalhado de todos os comandos executados na construção do servidor, servindo como documentação técnica de entrega da atividade.

### Passo 1: Preparação e Limpeza de Serviços Anteriores
Para garantir uma instalação limpa, sem processos órfãos ou arquivos residuais corrompidos:

```bash
sudo systemctl stop mariadb tomcat nginx php8.4-fpm 2>/dev/null || true
sudo killall -9 mysqld_safe mariadbd mysqld 2>/dev/null || true
sudo apt purge 'mariadb*' 'mysql*' -y
sudo apt autoremove --purge -y
sudo rm -rf /var/lib/mysql /etc/mysql /run/mysqld
```

### Passo 2: Instalação e Ativação do SGBD MariaDB
Atualização dos repositórios APT e instalação limpa do servidor MariaDB:

```bash
sudo apt update
sudo apt install mariadb-server mariadb-client -y
sudo systemctl start mariadb
sudo systemctl enable mariadb
```

### Passo 3: Configuração do Banco de Dados (`cms_db`) e Credenciais
Criação do banco `cms_db` (compartilhado entre a aplicação Java Web e o WordPress CMS) e do usuário padronizado `cms_user`:

```bash
sudo mariadb -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket OR mysql_native_password USING PASSWORD('aa');"
sudo mariadb -e "CREATE DATABASE IF NOT EXISTS cms_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
sudo mariadb -e "CREATE USER IF NOT EXISTS 'cms_user'@'localhost' IDENTIFIED BY 'aa';"
sudo mariadb -e "GRANT ALL PRIVILEGES ON cms_db.* TO 'cms_user'@'localhost';"
sudo mariadb -e "FLUSH PRIVILEGES;"
```

### Passo 4: Instalação do Ambiente Java e Apache Tomcat 10.1.8
Instalação do JDK padrão do Debian e extração do container Apache Tomcat 10 em `/opt/tomcat` sob o usuário `vboxuser`:

```bash
sudo apt install default-jdk wget tar -y
sudo rm -rf /opt/tomcat
sudo useradd -m -d /opt/tomcat -U -s /bin/false tomcat 2>/dev/null || true
cd /tmp
wget -nc https://archive.apache.org/dist/tomcat/tomcat-10/v10.1.8/bin/apache-tomcat-10.1.8.tar.gz
sudo mkdir -p /opt/tomcat
sudo tar xzvf apache-tomcat-10.1.8.tar.gz -C /opt/tomcat --strip-components=1
sudo chown -R vboxuser:vboxuser /opt/tomcat/
```

### Passo 5: Estrutura da Aplicação Java Web (`projeto-rede`) e Driver JDBC
Criação do diretório da aplicação web no Tomcat e download do driver oficial **MariaDB Connector/J (`3.3.3`)**:

```bash
sudo mkdir -p /opt/tomcat/webapps/projeto-rede/WEB-INF/lib
cd /tmp
wget -nc https://repo1.maven.org/maven2/org/mariadb/jdbc/mariadb-java-client/3.3.3/mariadb-java-client-3.3.3.jar
sudo cp mariadb-java-client-3.3.3.jar /opt/tomcat/webapps/projeto-rede/WEB-INF/lib/
```

Em seguida, copia-se o arquivo [`webapp/projeto-rede/index.jsp`](webapp/projeto-rede/index.jsp) para `/opt/tomcat/webapps/projeto-rede/index.jsp` e ajustam-se as permissões:

```bash
sudo cp webapp/projeto-rede/index.jsp /opt/tomcat/webapps/projeto-rede/index.jsp
sudo chown -R vboxuser:vboxuser /opt/tomcat/webapps/projeto-rede
```

### Passo 6: Criação do Serviço Systemd para o Apache Tomcat
Criação do arquivo `/etc/systemd/system/tomcat.service` (disponível em [`config/systemd/tomcat.service`](config/systemd/tomcat.service)):

```ini
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking
User=vboxuser
Group=vboxuser
Environment="JAVA_HOME=/usr/lib/jvm/default-java"
Environment="CATALINA_PID=/opt/tomcat/temp/tomcat.pid"
Environment="CATALINA_HOME=/opt/tomcat"
Environment="CATALINA_BASE=/opt/tomcat"
ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh
RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
```

Ativação do serviço no `systemd`:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now tomcat
```

### Passo 7: Configuração do Servidor HTTP (Nginx) + PHP 8.4-FPM + WordPress CMS
Instalação do Nginx e do PHP-FPM com o módulo MySQL/MariaDB:

```bash
sudo apt install nginx php-fpm php-mysql -y
```

Configuração do bloco `server` no arquivo `/etc/nginx/sites-available/default` (disponível em [`config/nginx/default`](config/nginx/default)) apontando arquivos `.php` para o socket `unix:/run/php/php8.4-fpm.sock`:

```nginx
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.php index.html index.htm;

    server_name _;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.4-fpm.sock;
    }
}
```

Instalação do **WordPress CMS** em `/var/www/html` conectado ao banco `cms_db` via `wp-config.php`, incluindo suporte dinâmico a múltiplos IPs de rede (`WP_HOME` e `WP_SITEURL` baseados em `$_SERVER['HTTP_HOST']`):

```php
if ( isset( $_SERVER['HTTP_HOST'] ) ) {
    define( 'WP_HOME', 'http://' . $_SERVER['HTTP_HOST'] );
    define( 'WP_SITEURL', 'http://' . $_SERVER['HTTP_HOST'] );
}
```

Ativação dos serviços HTTP e PHP no boot:

```bash
sudo systemctl enable --now php8.4-fpm nginx
sudo systemctl restart mariadb php8.4-fpm nginx tomcat
```

---

## 5. Detalhes da Aplicação Java Web (`/projeto-rede/`)

A aplicação Java Web desenvolvida em `webapp/projeto-rede/index.jsp` funciona como um **Console de Inventário de Serviços de Rede e Auditoria SGBD**, realizando **5 consultas SQL em tempo real** no MariaDB:

1. **Telemetria e Metadados do Servidor (`SELECT VERSION()`, `DATABASE()`, `CURRENT_USER()`, `@@hostname`, `@@port`, `@@character_set_server`, `NOW()`):** Exibe os dados da instância ativa do SGBD.
2. **Variáveis de Status Global (`SHOW GLOBAL STATUS`):** Consulta `Uptime`, `Connections` e `Questions` (total de queries executadas pelo servidor).
3. **Catálogo Interativo de Serviços de Rede (`cms_db.ativos_rede`):**
   - Filtro de pesquisa e seleção por categoria/status utilizando `PreparedStatement` parametrizado (exibindo na interface a string SQL exata executada e o tempo de resposta em `ms`).
   - Formulário para **inserção (`INSERT`)** de novos ativos/serviços de rede.
   - Botões de ação para **alternar status operacional (`UPDATE`)** entre `ATIVO` e `MANUTENCAO` e **excluir registros (`DELETE`)**.
4. **Inspeção do Esquema do Banco (`information_schema.tables`):** Lista todas as tabelas presentes em `cms_db` (mostrando as tabelas Java `ativos_rede` e `logs_auditoria_sql` lado a lado com as 12 tabelas `wp_*` do WordPress CMS, com engine `InnoDB`, contagem de linhas e tamanho em KB).
5. **Log de Auditoria SQL (`cms_db.logs_auditoria_sql`):** Exibe as últimas operações de escrita realizadas na aplicação com o endereço IP do cliente e timestamp.

---

## 6. Guia de Acesso e Apresentação na Rede do Laboratório (IFSP)

### 6.1. Configuração de Rede no VirtualBox
1. Na janela do **Oracle VirtualBox**, acesse **Configurações da VM -> Rede -> Adaptador 1**.
2. Certifique-se de que está conectado a **Placa em modo Bridge (Bridged Adapter)**.
3. Em **Nome**, selecione a interface física ativa do computador:
   - **Cabo de rede (Ethernet):** selecione o adaptador Gigabit/Ethernet da máquina.
   - **Wi-Fi (Notebook):** selecione o adaptador Wireless/Wi-Fi.

### 6.2. Descobrindo o IP do Servidor no Laboratório
No terminal da máquina virtual Debian, execute:

```bash
ip -4 -br a
# ou
hostname -I
```

*(Caso tenha trocado o cabo de rede com a VM já ligada, renove a concessão DHCP com `sudo dhclient -r && sudo dhclient`).*

### 6.3. Endereços de Acesso pela Rede (em qualquer computador do laboratório)

Substitua `<IP_DO_SERVIDOR>` pelo IP retornado no comando acima (ex.: `192.168.15.4` ou o IP atribuído pelo DHCP do laboratório):

- **Aplicação Java Web (Tomcat 10 + MariaDB):**
  - URL: `http://<IP_DO_SERVIDOR>:8080/projeto-rede/`
- **Aplicação Open Source CMS — WordPress (Nginx + PHP 8.4-FPM + MariaDB):**
  - Portal Público: `http://<IP_DO_SERVIDOR>/`
  - Painel Administrativo: `http://<IP_DO_SERVIDOR>/wp-admin/`

### 6.4. Credenciais Padronizadas do Ambiente

| Componente | Usuário | Senha | Observação |
| :--- | :--- | :--- | :--- |
| **Linux (SSH / Sudo)** | `vboxuser` | `aa` | Porta `22/TCP` |
| **MariaDB (Root)** | `root` | `aa` | `localhost` (`unix_socket` / senha) |
| **MariaDB (Aplicações)** | `cms_user` | `aa` | Banco de dados: `cms_db` |
| **WordPress (`/wp-admin/`)** | `admin` | `aa` | E-mail: `admin@ifsp.edu.br` |

### 6.5. Comandos Úteis de Verificação Técnica (Terminal)

```bash
# Verificar status de todos os serviços do projeto
sudo systemctl status mariadb tomcat nginx php8.4-fpm

# Verificar portas TCP abertas e ouvindo na rede (22, 80, 3306, 8080)
sudo ss -tulpn | grep -E '22|80|3306|8080'

# Consultar diretamente as tabelas do banco cms_db via CLI
sudo mariadb -u cms_user -paa cms_db -e "SHOW TABLES; SELECT * FROM ativos_rede;"
```
