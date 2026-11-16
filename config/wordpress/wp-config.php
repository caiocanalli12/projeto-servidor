<?php
/**
 * Configuração do WordPress (CMS Open Source) para o Servidor de Redes IFSP
 * Inclui resolução dinâmica de WP_HOME e WP_SITEURL via HTTP_HOST para
 * funcionamento automático em qualquer faixa de IP (DHCP / Modo Bridge).
 */

define( 'DB_NAME', 'cms_db' );
define( 'DB_USER', 'cms_user' );
define( 'DB_PASSWORD', 'aa' );
define( 'DB_HOST', 'localhost' );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', '' );

$table_prefix = 'wp_';

define( 'WP_DEBUG', false );

/* Suporte dinâmico a múltiplos IPs de rede (Casa / Laboratório IFSP) */
if ( isset( $_SERVER['HTTP_HOST'] ) ) {
    define( 'WP_HOME', 'http://' . $_SERVER['HTTP_HOST'] );
    define( 'WP_SITEURL', 'http://' . $_SERVER['HTTP_HOST'] );
}

if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}

require_once ABSPATH . 'wp-settings.php';
