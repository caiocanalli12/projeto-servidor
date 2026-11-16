#!/bin/bash
# =============================================================================
# Script de Provisionamento Automatizado - Servidor Linux Debian (IFSP)
# Componentes: MariaDB + Apache Tomcat 10 (Java Web/JSP) + Nginx + PHP 8.4 + WordPress CMS
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "[1/8] Parando servicos anteriores caso existam..."
sudo systemctl stop mariadb tomcat nginx php8.4-fpm 2>/dev/null || true
sudo killall -9 mysqld_safe mariadbd mysqld 2>/dev/null || true

echo "[2/8] Instalando pacotes base (MariaDB, Nginx, PHP-FPM, OpenJDK, Wget)..."
sudo apt update
sudo apt install -y mariadb-server mariadb-client nginx php-fpm php-mysql default-jdk wget tar

echo "[3/8] Iniciando e habilitando o SGBD MariaDB..."
sudo systemctl start mariadb
sudo systemctl enable mariadb

echo "[4/8] Configurando credenciais, banco cms_db e tabelas iniciais..."
sudo mariadb < "$REPO_ROOT/sql/init_database.sql"

echo "[5/8] Instalando e configurando o Apache Tomcat 10.1.8 em /opt/tomcat..."
sudo rm -rf /opt/tomcat
sudo useradd -m -d /opt/tomcat -U -s /bin/false tomcat 2>/dev/null || true
cd /tmp
wget -nc https://archive.apache.org/dist/tomcat/tomcat-10/v10.1.8/bin/apache-tomcat-10.1.8.tar.gz
sudo mkdir -p /opt/tomcat
sudo tar xzvf apache-tomcat-10.1.8.tar.gz -C /opt/tomcat --strip-components=1 > /dev/null
sudo chown -R vboxuser:vboxuser /opt/tomcat/

echo "[6/8] Configurando aplicacao Java Web (projeto-rede) e Driver JDBC MariaDB 3.3.3..."
sudo mkdir -p /opt/tomcat/webapps/projeto-rede/WEB-INF/lib
cd /tmp
wget -nc https://repo1.maven.org/maven2/org/mariadb/jdbc/mariadb-java-client/3.3.3/mariadb-java-client-3.3.3.jar
sudo cp mariadb-java-client-3.3.3.jar /opt/tomcat/webapps/projeto-rede/WEB-INF/lib/
sudo cp "$REPO_ROOT/webapp/projeto-rede/index.jsp" /opt/tomcat/webapps/projeto-rede/index.jsp
sudo chown -R vboxuser:vboxuser /opt/tomcat/webapps/projeto-rede

echo "[7/8] Configurando servico Systemd do Tomcat e Nginx + WordPress..."
sudo cp "$REPO_ROOT/config/systemd/tomcat.service" /etc/systemd/system/tomcat.service
sudo cp "$REPO_ROOT/config/nginx/default" /etc/nginx/sites-available/default

if [ ! -f /var/www/html/wp-login.php ]; then
    cd /tmp
    wget -nc https://wordpress.org/latest.tar.gz
    sudo rm -rf /var/www/html/*
    sudo tar xzvf latest.tar.gz -C /var/www/html --strip-components=1 > /dev/null
    sudo cp "$REPO_ROOT/config/wordpress/wp-config.php" /var/www/html/wp-config.php
    sudo chown -R www-data:www-data /var/www/html
fi

echo "[8/8] Recarregando Systemd e iniciando todos os servicos..."
sudo systemctl daemon-reload
sudo systemctl enable --now mariadb
sudo systemctl enable --now php8.4-fpm
sudo systemctl enable --now nginx
sudo systemctl enable --now tomcat
sudo systemctl restart mariadb php8.4-fpm nginx tomcat

echo "============================================================================="
echo "PROVISIONAMENTO CONCLUIDO COM SUCESSO!"
echo "IPs ativos do servidor: $(hostname -I)"
echo " - Aplicacao Java Web (Tomcat): http://$(hostname -I | awk '{print $1}'):8080/projeto-rede/"
echo " - WordPress CMS (Nginx/PHP):   http://$(hostname -I | awk '{print $1}')/"
echo "============================================================================="
