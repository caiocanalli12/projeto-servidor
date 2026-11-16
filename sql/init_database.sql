-- =============================================================================
-- Script de Inicialização do Banco de Dados MariaDB (cms_db)
-- Projeto Prático de Servidor Linux de Rede - IFSP
-- =============================================================================

ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket OR mysql_native_password USING PASSWORD('aa');

CREATE DATABASE IF NOT EXISTS cms_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'cms_user'@'localhost' IDENTIFIED BY 'aa';
GRANT ALL PRIVILEGES ON cms_db.* TO 'cms_user'@'localhost';
FLUSH PRIVILEGES;

USE cms_db;

CREATE TABLE IF NOT EXISTS ativos_rede (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nome_servico VARCHAR(100) NOT NULL,
    categoria VARCHAR(50) NOT NULL,
    endereco_ip VARCHAR(45) NOT NULL,
    porta_protocolo VARCHAR(30) NOT NULL,
    responsavel VARCHAR(80) NOT NULL,
    status_operacional VARCHAR(20) NOT NULL DEFAULT 'ATIVO',
    observacao VARCHAR(255),
    atualizado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS logs_auditoria_sql (
    id INT AUTO_INCREMENT PRIMARY KEY,
    operacao VARCHAR(30) NOT NULL,
    detalhe VARCHAR(255) NOT NULL,
    origem_ip VARCHAR(45) NOT NULL,
    criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO ativos_rede (nome_servico, categoria, endereco_ip, porta_protocolo, responsavel, status_operacional, observacao) VALUES
('MariaDB Server 11.8', 'SGBD', '127.0.0.1', '3306/TCP', 'systemd / mysql', 'ATIVO', 'Banco de dados relacional principal (cms_db)'),
('Apache Tomcat 10.1.8', 'Java Web', '0.0.0.0', '8080/TCP', 'vboxuser', 'ATIVO', 'Container Jakarta EE / Servlet & JSP com JDBC MariaDB'),
('Nginx Reverse & HTTP Server', 'HTTP / PHP', '0.0.0.0', '80/TCP', 'www-data', 'ATIVO', 'Servidor HTTP principal com FastCGI para PHP 8.4'),
('PHP 8.4-FPM (FastCGI)', 'HTTP / PHP', 'unix:/run/php', 'SOCK', 'www-data', 'ATIVO', 'Processador PHP com extensoes mysqli e pdo_mysql'),
('WordPress CMS Open Source', 'CMS', '0.0.0.0', '80/TCP', 'www-data', 'ATIVO', 'Aplicacao CMS hospedada em /var/www/html integrada ao cms_db'),
('OpenSSH Daemon (sshd)', 'Rede / SSH', '0.0.0.0', '22/TCP', 'root', 'ATIVO', 'Acesso administrativo remoto criptografado da VM Debian');

INSERT INTO logs_auditoria_sql (operacao, detalhe, origem_ip) VALUES
('INIT_SCHEMA', 'Tabelas ativos_rede e logs_auditoria_sql inicializadas no banco cms_db', '127.0.0.1');
