<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" import="java.sql.*, java.util.*, java.net.*" %>
<%
    request.setCharacterEncoding("UTF-8");

    String dbUrl = "jdbc:mariadb://127.0.0.1:3306/cms_db?useUnicode=true&characterEncoding=UTF-8";
    String dbUser = "cms_user";
    String dbPass = "aa";

    boolean dbConnected = false;
    String dbError = null;

    String sgbdVersion = "-";
    String sgbdHost = "-";
    String sgbdDatabase = "-";
    String sgbdUser = "-";
    String sgbdPort = "-";
    String sgbdCharset = "-";
    String serverNow = "-";
    long sgbdUptimeSec = 0;
    long sgbdConnections = 0;
    long sgbdQuestions = 0;

    String flashMsg = null;
    String flashType = "info";
    String executedSql = "";
    long queryTimeMs = 0;

    String filtroBusca = request.getParameter("q") != null ? request.getParameter("q").trim() : "";
    String filtroCategoria = request.getParameter("categoria") != null ? request.getParameter("categoria").trim() : "";
    String filtroStatus = request.getParameter("status") != null ? request.getParameter("status").trim() : "";

    String hostHeader = request.getServerName();
    String cmsUrl = "http://" + hostHeader + "/";
    String cmsAdminUrl = "http://" + hostHeader + "/wp-admin/";

    List<Map<String, String>> listaAtivos = new ArrayList<>();
    List<Map<String, String>> listaTabelas = new ArrayList<>();
    List<Map<String, String>> listaLogs = new ArrayList<>();

    long tStart = System.currentTimeMillis();

    try {
        Class.forName("org.mariadb.jdbc.Driver");
        try (Connection con = DriverManager.getConnection(dbUrl, dbUser, dbPass)) {
            dbConnected = true;

            // 1. Inicializar tabelas da aplicação Java caso não existam
            try (Statement initStmt = con.createStatement()) {
                initStmt.executeUpdate(
                    "CREATE TABLE IF NOT EXISTS ativos_rede (" +
                    "  id INT AUTO_INCREMENT PRIMARY KEY," +
                    "  nome_servico VARCHAR(100) NOT NULL," +
                    "  categoria VARCHAR(50) NOT NULL," +
                    "  endereco_ip VARCHAR(45) NOT NULL," +
                    "  porta_protocolo VARCHAR(30) NOT NULL," +
                    "  responsavel VARCHAR(80) NOT NULL," +
                    "  status_operacional VARCHAR(20) NOT NULL DEFAULT 'ATIVO'," +
                    "  observacao VARCHAR(255)," +
                    "  atualizado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP" +
                    ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;"
                );

                initStmt.executeUpdate(
                    "CREATE TABLE IF NOT EXISTS logs_auditoria_sql (" +
                    "  id INT AUTO_INCREMENT PRIMARY KEY," +
                    "  operacao VARCHAR(30) NOT NULL," +
                    "  detalhe VARCHAR(255) NOT NULL," +
                    "  origem_ip VARCHAR(45) NOT NULL," +
                    "  criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP" +
                    ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;"
                );

                try (ResultSet rsCount = initStmt.executeQuery("SELECT COUNT(*) FROM ativos_rede")) {
                    if (rsCount.next() && rsCount.getInt(1) == 0) {
                        initStmt.executeUpdate(
                            "INSERT INTO ativos_rede (nome_servico, categoria, endereco_ip, porta_protocolo, responsavel, status_operacional, observacao) VALUES " +
                            "('MariaDB Server 11.8', 'SGBD', '127.0.0.1', '3306/TCP', 'systemd / mysql', 'ATIVO', 'Banco de dados relacional principal (cms_db)')," +
                            "('Apache Tomcat 10.1.8', 'Java Web', '0.0.0.0', '8080/TCP', 'vboxuser', 'ATIVO', 'Container Jakarta EE / Servlet & JSP com JDBC MariaDB')," +
                            "('Nginx Reverse & HTTP Server', 'HTTP / PHP', '0.0.0.0', '80/TCP', 'www-data', 'ATIVO', 'Servidor HTTP principal com FastCGI para PHP 8.4')," +
                            "('PHP 8.4-FPM (FastCGI)', 'HTTP / PHP', 'unix:/run/php', 'SOCK', 'www-data', 'ATIVO', 'Processador PHP com extensoes mysqli e pdo_mysql')," +
                            "('WordPress CMS Open Source', 'CMS', '0.0.0.0', '80/TCP', 'www-data', 'ATIVO', 'Aplicacao CMS hospedada em /var/www/html integrada ao cms_db')," +
                            "('OpenSSH Daemon (sshd)', 'Rede / SSH', '0.0.0.0', '22/TCP', 'root', 'ATIVO', 'Acesso administrativo remoto criptografado da VM Debian')"
                        );
                        initStmt.executeUpdate(
                            "INSERT INTO logs_auditoria_sql (operacao, detalhe, origem_ip) VALUES " +
                            "('INIT_SCHEMA', 'Tabelas ativos_rede e logs_auditoria_sql inicializadas no banco cms_db', '127.0.0.1')"
                        );
                    }
                }
            }

            // 2. Processar ações POST (INSERT, UPDATE, DELETE)
            if ("POST".equalsIgnoreCase(request.getMethod())) {
                String acao = request.getParameter("acao");
                String clientIp = request.getRemoteAddr();

                if ("inserir".equals(acao)) {
                    String nome = request.getParameter("nome_servico");
                    String cat = request.getParameter("categoria_form");
                    String ip = request.getParameter("endereco_ip");
                    String porta = request.getParameter("porta_protocolo");
                    String resp = request.getParameter("responsavel");
                    String obs = request.getParameter("observacao");

                    if (nome != null && !nome.trim().isEmpty() && porta != null && !porta.trim().isEmpty()) {
                        String sqlInsert = "INSERT INTO ativos_rede (nome_servico, categoria, endereco_ip, porta_protocolo, responsavel, status_operacional, observacao) VALUES (?, ?, ?, ?, ?, 'ATIVO', ?)";
                        try (PreparedStatement ps = con.prepareStatement(sqlInsert)) {
                            ps.setString(1, nome.trim());
                            ps.setString(2, (cat != null && !cat.isEmpty()) ? cat.trim() : "Infraestrutura");
                            ps.setString(3, (ip != null && !ip.isEmpty()) ? ip.trim() : hostHeader);
                            ps.setString(4, porta.trim());
                            ps.setString(5, (resp != null && !resp.isEmpty()) ? resp.trim() : "vboxuser");
                            ps.setString(6, (obs != null) ? obs.trim() : "");
                            ps.executeUpdate();
                        }
                        try (PreparedStatement psLog = con.prepareStatement("INSERT INTO logs_auditoria_sql (operacao, detalhe, origem_ip) VALUES ('INSERT', ?, ?)")) {
                            psLog.setString(1, "Novo servico registrado: " + nome.trim() + " (" + porta.trim() + ")");
                            psLog.setString(2, clientIp);
                            psLog.executeUpdate();
                        }
                        flashMsg = "Registro inserido com sucesso na tabela cms_db.ativos_rede.";
                        flashType = "success";
                    }
                } else if ("alternar_status".equals(acao)) {
                    String idStr = request.getParameter("id");
                    if (idStr != null) {
                        int id = Integer.parseInt(idStr);
                        String sqlToggle = "UPDATE ativos_rede SET status_operacional = CASE WHEN status_operacional = 'ATIVO' THEN 'MANUTENCAO' ELSE 'ATIVO' END WHERE id = ?";
                        try (PreparedStatement ps = con.prepareStatement(sqlToggle)) {
                            ps.setInt(1, id);
                            ps.executeUpdate();
                        }
                        try (PreparedStatement psLog = con.prepareStatement("INSERT INTO logs_auditoria_sql (operacao, detalhe, origem_ip) VALUES ('UPDATE', ?, ?)")) {
                            psLog.setString(1, "Status operacional alternado para o registro ID #" + id);
                            psLog.setString(2, clientIp);
                            psLog.executeUpdate();
                        }
                        flashMsg = "Status do ativo #" + id + " atualizado no banco de dados.";
                        flashType = "success";
                    }
                } else if ("excluir".equals(acao)) {
                    String idStr = request.getParameter("id");
                    if (idStr != null) {
                        int id = Integer.parseInt(idStr);
                        try (PreparedStatement ps = con.prepareStatement("DELETE FROM ativos_rede WHERE id = ?")) {
                            ps.setInt(1, id);
                            ps.executeUpdate();
                        }
                        try (PreparedStatement psLog = con.prepareStatement("INSERT INTO logs_auditoria_sql (operacao, detalhe, origem_ip) VALUES ('DELETE', ?, ?)")) {
                            psLog.setString(1, "Registro ID #" + id + " removido de ativos_rede");
                            psLog.setString(2, clientIp);
                            psLog.executeUpdate();
                        }
                        flashMsg = "Registro #" + id + " removido da tabela ativos_rede.";
                        flashType = "info";
                    }
                }
            }

            // 3. Consulta 1: Telemetria e Metadados do SGBD MariaDB
            try (Statement stMeta = con.createStatement();
                 ResultSet rsMeta = stMeta.executeQuery(
                     "SELECT VERSION() AS versao, DATABASE() AS banco, CURRENT_USER() AS usuario, " +
                     "@@hostname AS host_servidor, @@port AS porta_tcp, @@character_set_server AS charset_srv, " +
                     "DATE_FORMAT(NOW(), '%d/%m/%Y %H:%i:%s') AS horario_atual"
                 )) {
                if (rsMeta.next()) {
                    sgbdVersion = rsMeta.getString("versao");
                    sgbdDatabase = rsMeta.getString("banco");
                    sgbdUser = rsMeta.getString("usuario");
                    sgbdHost = rsMeta.getString("host_servidor");
                    sgbdPort = rsMeta.getString("porta_tcp");
                    sgbdCharset = rsMeta.getString("charset_srv");
                    serverNow = rsMeta.getString("horario_atual");
                }
            }

            // 4. Consulta 2: Variáveis de Status Global do MariaDB
            try (Statement stStatus = con.createStatement();
                 ResultSet rsStatus = stStatus.executeQuery(
                     "SHOW GLOBAL STATUS WHERE Variable_name IN ('Uptime', 'Connections', 'Questions')"
                 )) {
                while (rsStatus.next()) {
                    String varName = rsStatus.getString("Variable_name");
                    long val = rsStatus.getLong("Value");
                    if ("Uptime".equalsIgnoreCase(varName)) sgbdUptimeSec = val;
                    else if ("Connections".equalsIgnoreCase(varName)) sgbdConnections = val;
                    else if ("Questions".equalsIgnoreCase(varName)) sgbdQuestions = val;
                }
            }

            // 5. Consulta 3: Listagem filtrada de Ativos e Serviços de Rede
            StringBuilder sqlBuilder = new StringBuilder(
                "SELECT id, nome_servico, categoria, endereco_ip, porta_protocolo, responsavel, status_operacional, " +
                "observacao, DATE_FORMAT(atualizado_em, '%d/%m/%Y %H:%i:%s') AS dt_fmt " +
                "FROM ativos_rede WHERE 1=1"
            );
            List<String> params = new ArrayList<>();

            if (!filtroBusca.isEmpty()) {
                sqlBuilder.append(" AND (nome_servico LIKE ? OR observacao LIKE ? OR porta_protocolo LIKE ? OR endereco_ip LIKE ?)");
                String likeVal = "%" + filtroBusca + "%";
                params.add(likeVal);
                params.add(likeVal);
                params.add(likeVal);
                params.add(likeVal);
            }
            if (!filtroCategoria.isEmpty()) {
                sqlBuilder.append(" AND categoria = ?");
                params.add(filtroCategoria);
            }
            if (!filtroStatus.isEmpty()) {
                sqlBuilder.append(" AND status_operacional = ?");
                params.add(filtroStatus);
            }
            sqlBuilder.append(" ORDER BY id ASC");
            executedSql = sqlBuilder.toString();

            try (PreparedStatement psAtivos = con.prepareStatement(executedSql)) {
                for (int i = 0; i < params.size(); i++) {
                    psAtivos.setString(i + 1, params.get(i));
                }
                try (ResultSet rsAtivos = psAtivos.executeQuery()) {
                    while (rsAtivos.next()) {
                        Map<String, String> row = new HashMap<>();
                        row.put("id", String.valueOf(rsAtivos.getInt("id")));
                        row.put("nome_servico", rsAtivos.getString("nome_servico"));
                        row.put("categoria", rsAtivos.getString("categoria"));
                        row.put("endereco_ip", rsAtivos.getString("endereco_ip"));
                        row.put("porta_protocolo", rsAtivos.getString("porta_protocolo"));
                        row.put("responsavel", rsAtivos.getString("responsavel"));
                        row.put("status_operacional", rsAtivos.getString("status_operacional"));
                        row.put("observacao", rsAtivos.getString("observacao"));
                        row.put("atualizado_em", rsAtivos.getString("dt_fmt"));
                        listaAtivos.add(row);
                    }
                }
            }

            // 6. Consulta 4: Catálogo de Tabelas em cms_db (information_schema)
            String sqlSchema =
                "SELECT table_name, engine, table_rows, " +
                "ROUND((data_length + index_length) / 1024, 2) AS tamanho_kb, " +
                "table_collation " +
                "FROM information_schema.tables " +
                "WHERE table_schema = 'cms_db' " +
                "ORDER BY table_name ASC";
            try (Statement stSchema = con.createStatement();
                 ResultSet rsSchema = stSchema.executeQuery(sqlSchema)) {
                while (rsSchema.next()) {
                    Map<String, String> tbl = new HashMap<>();
                    tbl.put("table_name", rsSchema.getString("table_name"));
                    tbl.put("engine", rsSchema.getString("engine"));
                    tbl.put("table_rows", rsSchema.getString("table_rows"));
                    tbl.put("tamanho_kb", rsSchema.getString("tamanho_kb"));
                    tbl.put("table_collation", rsSchema.getString("table_collation"));
                    listaTabelas.add(tbl);
                }
            }

            // 7. Consulta 5: Últimos Logs de Auditoria SQL
            try (Statement stLogs = con.createStatement();
                 ResultSet rsLogs = stLogs.executeQuery(
                     "SELECT id, operacao, detalhe, origem_ip, DATE_FORMAT(criado_em, '%d/%m/%Y %H:%i:%s') AS dt " +
                     "FROM logs_auditoria_sql ORDER BY id DESC LIMIT 6"
                 )) {
                while (rsLogs.next()) {
                    Map<String, String> lg = new HashMap<>();
                    lg.put("id", rsLogs.getString("id"));
                    lg.put("operacao", rsLogs.getString("operacao"));
                    lg.put("detalhe", rsLogs.getString("detalhe"));
                    lg.put("origem_ip", rsLogs.getString("origem_ip"));
                    lg.put("dt", rsLogs.getString("dt"));
                    listaLogs.add(lg);
                }
            }
        }
    } catch (Exception e) {
        dbError = e.getClass().getName() + ": " + e.getMessage();
    }

    queryTimeMs = System.currentTimeMillis() - tStart;
    long uptimeMin = sgbdUptimeSec / 60;
    long uptimeSecRem = sgbdUptimeSec % 60;
%>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Console de Infraestrutura e SGBD | Servidor Debian - IFSP</title>
    <style>
        :root {
            --bg-page: #f3f4f6;
            --bg-surface: #ffffff;
            --bg-subtle: #f9fafb;
            --bg-header: #111827;
            --text-primary: #111827;
            --text-secondary: #4b5563;
            --text-muted: #6b7280;
            --border-color: #d1d5db;
            --border-subtle: #e5e7eb;
            --accent-primary: #1d4ed8;
            --accent-hover: #1e40af;
            --status-ok-bg: #ecfdf5;
            --status-ok-text: #065f46;
            --status-ok-border: #a7f3d0;
            --status-warn-bg: #fffbeb;
            --status-warn-text: #92400e;
            --status-warn-border: #fde68a;
            --status-err-bg: #fef2f2;
            --status-err-text: #991b1b;
            --status-err-border: #fecaca;
            --font-sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            --font-mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        body {
            background-color: var(--bg-page);
            color: var(--text-primary);
            font-family: var(--font-sans);
            font-size: 14px;
            line-height: 1.5;
            -webkit-font-smoothing: antialiased;
        }

        /* Top Navigation Bar */
        .topbar {
            background-color: var(--bg-header);
            color: #f9fafb;
            border-bottom: 1px solid #1f2937;
            padding: 0 24px;
            height: 54px;
            display: flex;
            align-items: center;
            justify-content: space-between;
        }

        .topbar-brand {
            display: flex;
            align-items: center;
            gap: 12px;
        }

        .topbar-title {
            font-size: 15px;
            font-weight: 600;
            letter-spacing: -0.01em;
            color: #ffffff;
        }

        .topbar-divider {
            color: #4b5563;
        }

        .topbar-subtitle {
            font-family: var(--font-mono);
            font-size: 12px;
            color: #9ca3af;
        }

        .topbar-right {
            display: flex;
            align-items: center;
            gap: 14px;
        }

        .topbar-link {
            color: #d1d5db;
            text-decoration: none;
            font-size: 12.5px;
            padding: 5px 10px;
            border: 1px solid #374151;
            border-radius: 4px;
            background: #1f2937;
            transition: background 0.15s, color 0.15s;
        }

        .topbar-link:hover {
            background: #374151;
            color: #ffffff;
        }

        .conn-indicator {
            display: inline-flex;
            align-items: center;
            gap: 7px;
            font-family: var(--font-mono);
            font-size: 12px;
            padding: 4px 10px;
            border-radius: 4px;
            font-weight: 500;
        }

        .conn-indicator.online {
            background: rgba(16, 185, 129, 0.15);
            color: #34d399;
            border: 1px solid rgba(16, 185, 129, 0.3);
        }

        .conn-indicator.offline {
            background: rgba(239, 68, 68, 0.15);
            color: #f87171;
            border: 1px solid rgba(239, 68, 68, 0.3);
        }

        .dot {
            width: 7px;
            height: 7px;
            border-radius: 50%;
            background-color: currentColor;
        }

        /* Main Container */
        .container {
            max-width: 1280px;
            margin: 0 auto;
            padding: 20px 24px 40px;
        }

        /* Context Header */
        .page-header {
            display: flex;
            flex-wrap: wrap;
            justify-content: space-between;
            align-items: flex-end;
            gap: 16px;
            margin-bottom: 18px;
            padding-bottom: 14px;
            border-bottom: 1px solid var(--border-color);
        }

        .page-header h1 {
            font-size: 20px;
            font-weight: 600;
            color: var(--text-primary);
            letter-spacing: -0.015em;
        }

        .page-header p {
            color: var(--text-secondary);
            font-size: 13px;
            margin-top: 2px;
        }

        .meta-strip {
            display: flex;
            gap: 16px;
            font-family: var(--font-mono);
            font-size: 12px;
            color: var(--text-secondary);
            background: var(--bg-surface);
            padding: 6px 12px;
            border: 1px solid var(--border-color);
            border-radius: 4px;
        }

        /* Alert Banner */
        .alert {
            padding: 10px 14px;
            border-radius: 4px;
            margin-bottom: 16px;
            font-size: 13px;
            border: 1px solid transparent;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        .alert-success {
            background-color: var(--status-ok-bg);
            color: var(--status-ok-text);
            border-color: var(--status-ok-border);
        }

        .alert-info {
            background-color: #eff6ff;
            color: #1e40af;
            border-color: #bfdbfe;
        }

        .alert-error {
            background-color: var(--status-err-bg);
            color: var(--status-err-text);
            border-color: var(--status-err-border);
            font-family: var(--font-mono);
        }

        /* Telemetry Grid */
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 12px;
            margin-bottom: 20px;
        }

        .metric-card {
            background: var(--bg-surface);
            border: 1px solid var(--border-color);
            border-radius: 4px;
            padding: 12px 14px;
        }

        .metric-label {
            font-size: 11px;
            text-transform: uppercase;
            letter-spacing: 0.04em;
            color: var(--text-muted);
            font-weight: 600;
            margin-bottom: 4px;
        }

        .metric-value {
            font-family: var(--font-mono);
            font-size: 15px;
            font-weight: 600;
            color: var(--text-primary);
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .metric-sub {
            font-size: 11.5px;
            color: var(--text-secondary);
            margin-top: 3px;
            font-family: var(--font-mono);
        }

        /* Panels */
        .panel {
            background: var(--bg-surface);
            border: 1px solid var(--border-color);
            border-radius: 4px;
            margin-bottom: 20px;
        }

        .panel-header {
            padding: 12px 16px;
            border-bottom: 1px solid var(--border-color);
            background-color: var(--bg-subtle);
            display: flex;
            flex-wrap: wrap;
            justify-content: space-between;
            align-items: center;
            gap: 10px;
        }

        .panel-title {
            font-size: 14px;
            font-weight: 600;
            color: var(--text-primary);
        }

        .panel-badge {
            font-family: var(--font-mono);
            font-size: 11.5px;
            color: var(--text-secondary);
            background: #e5e7eb;
            padding: 2px 8px;
            border-radius: 3px;
        }

        .panel-body {
            padding: 16px;
        }

        /* Filter Bar */
        .filter-bar {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            padding: 12px 16px;
            border-bottom: 1px solid var(--border-subtle);
            background: #ffffff;
            align-items: center;
        }

        .input-text, .select-box {
            height: 32px;
            padding: 0 10px;
            border: 1px solid var(--border-color);
            border-radius: 4px;
            font-size: 13px;
            font-family: var(--font-sans);
            color: var(--text-primary);
            background: #ffffff;
        }

        .input-text:focus, .select-box:focus {
            outline: none;
            border-color: var(--accent-primary);
        }

        .btn {
            height: 32px;
            padding: 0 12px;
            border-radius: 4px;
            font-size: 12.5px;
            font-weight: 500;
            cursor: pointer;
            border: 1px solid transparent;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            text-decoration: none;
            font-family: var(--font-sans);
        }

        .btn-primary {
            background-color: var(--accent-primary);
            color: #ffffff;
        }

        .btn-primary:hover {
            background-color: var(--accent-hover);
        }

        .btn-secondary {
            background-color: #ffffff;
            color: var(--text-secondary);
            border-color: var(--border-color);
        }

        .btn-secondary:hover {
            background-color: var(--bg-subtle);
            color: var(--text-primary);
        }

        .btn-sm {
            height: 24px;
            padding: 0 8px;
            font-size: 11.5px;
        }

        .btn-danger-outline {
            background-color: #ffffff;
            color: #b91c1c;
            border-color: #fca5a5;
        }

        .btn-danger-outline:hover {
            background-color: #fef2f2;
        }

        /* SQL Trace Box */
        .sql-box {
            background-color: #1e293b;
            color: #e2e8f0;
            font-family: var(--font-mono);
            font-size: 12px;
            padding: 9px 16px;
            border-bottom: 1px solid var(--border-color);
            display: flex;
            justify-content: space-between;
            align-items: center;
            gap: 12px;
            overflow-x: auto;
        }

        .sql-box code {
            color: #93c5fd;
        }

        .sql-meta {
            color: #94a3b8;
            white-space: nowrap;
            font-size: 11px;
        }

        /* Tables */
        .table-wrapper {
            overflow-x: auto;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            text-align: left;
            font-size: 13px;
        }

        th {
            background-color: var(--bg-subtle);
            color: var(--text-secondary);
            font-weight: 600;
            font-size: 11.5px;
            text-transform: uppercase;
            letter-spacing: 0.03em;
            padding: 9px 14px;
            border-bottom: 1px solid var(--border-color);
            white-space: nowrap;
        }

        td {
            padding: 9px 14px;
            border-bottom: 1px solid var(--border-subtle);
            color: var(--text-primary);
            vertical-align: middle;
        }

        tr:last-child td {
            border-bottom: none;
        }

        tr:hover td {
            background-color: #f8fafc;
        }

        .mono {
            font-family: var(--font-mono);
            font-size: 12px;
        }

        /* Status Pills */
        .badge {
            display: inline-block;
            padding: 2px 7px;
            font-family: var(--font-mono);
            font-size: 11px;
            font-weight: 600;
            border-radius: 3px;
        }

        .badge-ok {
            background-color: var(--status-ok-bg);
            color: var(--status-ok-text);
            border: 1px solid var(--status-ok-border);
        }

        .badge-warn {
            background-color: var(--status-warn-bg);
            color: var(--status-warn-text);
            border: 1px solid var(--status-warn-border);
        }

        .badge-cat {
            background-color: #f3f4f6;
            color: #374151;
            border: 1px solid #d1d5db;
        }

        /* Two Column Lower Layout */
        .grid-2col {
            display: grid;
            grid-template-columns: 1.25fr 1fr;
            gap: 20px;
        }

        @media (max-width: 960px) {
            .grid-2col {
                grid-template-columns: 1fr;
            }
        }

        /* Form Grid */
        .form-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(170px, 1fr));
            gap: 10px;
            align-items: end;
        }

        .form-group label {
            display: block;
            font-size: 11.5px;
            font-weight: 600;
            color: var(--text-secondary);
            margin-bottom: 4px;
        }

        .form-group input, .form-group select {
            width: 100%;
        }

        .actions-cell {
            display: flex;
            gap: 6px;
            align-items: center;
        }

        .footer {
            margin-top: 28px;
            padding-top: 14px;
            border-top: 1px solid var(--border-color);
            display: flex;
            justify-content: space-between;
            color: var(--text-muted);
            font-size: 12px;
            font-family: var(--font-mono);
        }
    </style>
</head>
<body>

<header class="topbar">
    <div class="topbar-brand">
        <span class="topbar-title">IFSP · Servidor Linux de Rede</span>
        <span class="topbar-divider">/</span>
        <span class="topbar-subtitle"><%= sgbdHost %> (<%= hostHeader %>)</span>
    </div>
    <div class="topbar-right">
        <a class="topbar-link" href="<%= cmsUrl %>" target="_blank">Abrir WordPress CMS (Porta 80)</a>
        <a class="topbar-link" href="<%= cmsAdminUrl %>" target="_blank">Painel WP-Admin</a>
        <% if (dbConnected) { %>
            <span class="conn-indicator online">
                <span class="dot"></span> JDBC MARIADB CONECTADO
            </span>
        <% } else { %>
            <span class="conn-indicator offline">
                <span class="dot"></span> ERRO DE CONEXÃO JDBC
            </span>
        <% } %>
    </div>
</header>

<main class="container">

    <div class="page-header">
        <div>
            <h1>Inventário de Serviços de Rede e Auditoria SGBD</h1>
            <p>Aplicação Java Web (Jakarta JSP + MariaDB JDBC Driver 3.3.3) hospedada no Apache Tomcat 10.1.8</p>
        </div>
        <div class="meta-strip">
            <span>Host: <strong><%= request.getLocalAddr() %>:<%= request.getLocalPort() %></strong></span>
            <span>|</span>
            <span>Tempo SQL: <strong><%= queryTimeMs %> ms</strong></span>
            <span>|</span>
            <span>Consulta: <strong><%= serverNow %></strong></span>
        </div>
    </div>

    <% if (dbError != null) { %>
        <div class="alert alert-error">
            <span><strong>Falha na comunicação JDBC:</strong> <%= dbError %></span>
        </div>
    <% } %>

    <% if (flashMsg != null) { %>
        <div class="alert <%= "success".equals(flashType) ? "alert-success" : "alert-info" %>">
            <span><%= flashMsg %></span>
            <a href="index.jsp" class="btn btn-secondary btn-sm">Fechar aviso</a>
        </div>
    <% } %>

    <!-- Telemetria em Tempo Real do SGBD -->
    <section class="metrics-grid">
        <div class="metric-card">
            <div class="metric-label">Versão do SGBD (SELECT VERSION())</div>
            <div class="metric-value" title="<%= sgbdVersion %>"><%= sgbdVersion %></div>
            <div class="metric-sub">Driver: org.mariadb.jdbc.Driver</div>
        </div>
        <div class="metric-card">
            <div class="metric-label">Banco Ativo / Credencial</div>
            <div class="metric-value"><%= sgbdDatabase %></div>
            <div class="metric-sub">Usuário: <%= sgbdUser %></div>
        </div>
        <div class="metric-card">
            <div class="metric-label">Socket TCP / Charset</div>
            <div class="metric-value">127.0.0.1:<%= sgbdPort %></div>
            <div class="metric-sub">Charset: <%= sgbdCharset %></div>
        </div>
        <div class="metric-card">
            <div class="metric-label">Atividade Global MariaDB</div>
            <div class="metric-value"><%= sgbdQuestions %> queries</div>
            <div class="metric-sub">Uptime: <%= uptimeMin %>m <%= uptimeSecRem %>s · <%= sgbdConnections %> conexões</div>
        </div>
        <div class="metric-card">
            <div class="metric-label">Runtime Java / Container</div>
            <div class="metric-value">Java <%= System.getProperty("java.version") %></div>
            <div class="metric-sub"><%= application.getServerInfo() %></div>
        </div>
    </section>

    <!-- Painel Principal: Catálogo de Ativos e Serviços de Rede -->
    <section class="panel">
        <div class="panel-header">
            <span class="panel-title">1. Serviços e Ativos do Servidor (Tabela: <code>cms_db.ativos_rede</code>)</span>
            <span class="panel-badge"><%= listaAtivos.size() %> registro(s) retornado(s)</span>
        </div>

        <form method="get" action="index.jsp" class="filter-bar">
            <input type="text" name="q" class="input-text" style="min-width: 240px;"
                   placeholder="Buscar por serviço, porta, IP ou descrição..."
                   value="<%= filtroBusca %>">

            <select name="categoria" class="select-box">
                <option value="">Todas as categorias</option>
                <option value="SGBD" <%= "SGBD".equals(filtroCategoria) ? "selected" : "" %>>SGBD</option>
                <option value="Java Web" <%= "Java Web".equals(filtroCategoria) ? "selected" : "" %>>Java Web</option>
                <option value="HTTP / PHP" <%= "HTTP / PHP".equals(filtroCategoria) ? "selected" : "" %>>HTTP / PHP</option>
                <option value="CMS" <%= "CMS".equals(filtroCategoria) ? "selected" : "" %>>CMS</option>
                <option value="Rede / SSH" <%= "Rede / SSH".equals(filtroCategoria) ? "selected" : "" %>>Rede / SSH</option>
                <option value="Infraestrutura" <%= "Infraestrutura".equals(filtroCategoria) ? "selected" : "" %>>Infraestrutura</option>
            </select>

            <select name="status" class="select-box">
                <option value="">Todos os status</option>
                <option value="ATIVO" <%= "ATIVO".equals(filtroStatus) ? "selected" : "" %>>ATIVO</option>
                <option value="MANUTENCAO" <%= "MANUTENCAO".equals(filtroStatus) ? "selected" : "" %>>MANUTENCAO</option>
            </select>

            <button type="submit" class="btn btn-primary">Executar Consulta SQL</button>
            <% if (!filtroBusca.isEmpty() || !filtroCategoria.isEmpty() || !filtroStatus.isEmpty()) { %>
                <a href="index.jsp" class="btn btn-secondary">Limpar Filtros</a>
            <% } %>
        </form>

        <div class="sql-box">
            <div>
                <span>SQL executado: </span>
                <code><%= executedSql %></code>
            </div>
            <span class="sql-meta">PreparedStatement · <%= listaAtivos.size() %> linha(s)</span>
        </div>

        <div class="table-wrapper">
            <table>
                <thead>
                    <tr>
                        <th>ID</th>
                        <th>Serviço / Componente</th>
                        <th>Categoria</th>
                        <th>Endereço / Bind</th>
                        <th>Porta / Proto</th>
                        <th>Usuário SO</th>
                        <th>Status</th>
                        <th>Descrição Técnica</th>
                        <th>Ações no Banco</th>
                    </tr>
                </thead>
                <tbody>
                    <% if (listaAtivos.isEmpty()) { %>
                        <tr>
                            <td colspan="9" style="text-align:center; padding: 20px; color: var(--text-muted);">
                                Nenhum serviço encontrado para os critérios informados na consulta SQL.
                            </td>
                        </tr>
                    <% } else {
                        for (Map<String, String> item : listaAtivos) {
                            boolean isAtivo = "ATIVO".equalsIgnoreCase(item.get("status_operacional"));
                    %>
                        <tr>
                            <td class="mono">#<%= item.get("id") %></td>
                            <td><strong><%= item.get("nome_servico") %></strong></td>
                            <td><span class="badge badge-cat"><%= item.get("categoria") %></span></td>
                            <td class="mono"><%= item.get("endereco_ip") %></td>
                            <td class="mono"><strong><%= item.get("porta_protocolo") %></strong></td>
                            <td class="mono"><%= item.get("responsavel") %></td>
                            <td>
                                <span class="badge <%= isAtivo ? "badge-ok" : "badge-warn" %>">
                                    <%= item.get("status_operacional") %>
                                </span>
                            </td>
                            <td style="color: var(--text-secondary);"><%= item.get("observacao") %></td>
                            <td>
                                <div class="actions-cell">
                                    <form method="post" action="index.jsp" style="display:inline;">
                                        <input type="hidden" name="acao" value="alternar_status">
                                        <input type="hidden" name="id" value="<%= item.get("id") %>">
                                        <button type="submit" class="btn btn-secondary btn-sm" title="Executar UPDATE de status no MariaDB">
                                            Alternar
                                        </button>
                                    </form>
                                    <form method="post" action="index.jsp" style="display:inline;">
                                        <input type="hidden" name="acao" value="excluir">
                                        <input type="hidden" name="id" value="<%= item.get("id") %>">
                                        <button type="submit" class="btn btn-danger-outline btn-sm" title="Executar DELETE no MariaDB">
                                            Excluir
                                        </button>
                                    </form>
                                </div>
                            </td>
                        </tr>
                    <%  }
                       } %>
                </tbody>
            </table>
        </div>

        <!-- Formulário de Inserção (INSERT INTO ativos_rede) -->
        <div class="panel-body" style="border-top: 1px solid var(--border-color); background: var(--bg-subtle);">
            <div style="font-size: 12px; font-weight: 600; color: var(--text-secondary); margin-bottom: 10px; text-transform: uppercase; letter-spacing: 0.03em;">
                Registrar Novo Serviço / Host no Banco de Dados (INSERT INTO ativos_rede)
            </div>
            <form method="post" action="index.jsp" class="form-grid">
                <input type="hidden" name="acao" value="inserir">
                <div class="form-group">
                    <label>Nome do Serviço *</label>
                    <input type="text" name="nome_servico" class="input-text" placeholder="Ex: Servidor DNS Bind9" required>
                </div>
                <div class="form-group">
                    <label>Categoria</label>
                    <select name="categoria_form" class="select-box">
                        <option value="Infraestrutura">Infraestrutura</option>
                        <option value="SGBD">SGBD</option>
                        <option value="Java Web">Java Web</option>
                        <option value="HTTP / PHP">HTTP / PHP</option>
                        <option value="CMS">CMS</option>
                        <option value="Rede / SSH">Rede / SSH</option>
                    </select>
                </div>
                <div class="form-group">
                    <label>Endereço IP / Bind</label>
                    <input type="text" name="endereco_ip" class="input-text" value="<%= hostHeader %>">
                </div>
                <div class="form-group">
                    <label>Porta / Protocolo *</label>
                    <input type="text" name="porta_protocolo" class="input-text" placeholder="Ex: 53/UDP" required>
                </div>
                <div class="form-group">
                    <label>Usuário / Daemon</label>
                    <input type="text" name="responsavel" class="input-text" placeholder="Ex: bind" value="vboxuser">
                </div>
                <div class="form-group" style="grid-column: span 2;">
                    <label>Observação Técnica</label>
                    <input type="text" name="observacao" class="input-text" placeholder="Descrição da função na topologia do laboratório">
                </div>
                <div class="form-group">
                    <button type="submit" class="btn btn-primary" style="width:100%;">Gravar no MariaDB</button>
                </div>
            </form>
        </div>
    </section>

    <!-- Seção Inferior: Catálogo information_schema + Logs de Auditoria -->
    <div class="grid-2col">

        <!-- Inspeção do Esquema cms_db -->
        <section class="panel" style="margin-bottom: 0;">
            <div class="panel-header">
                <span class="panel-title">2. Estrutura do Banco <code>cms_db</code> (<code>information_schema.tables</code>)</span>
                <span class="panel-badge"><%= listaTabelas.size() %> tabelas</span>
            </div>
            <div class="sql-box">
                <code>SELECT table_name, engine, table_rows, size_kb FROM information_schema.tables WHERE table_schema='cms_db'</code>
            </div>
            <div class="table-wrapper" style="max-height: 320px; overflow-y: auto;">
                <table>
                    <thead>
                        <tr>
                            <th>Tabela</th>
                            <th>Engine</th>
                            <th>Linhas (Est.)</th>
                            <th>Tamanho</th>
                            <th>Collation</th>
                        </tr>
                    </thead>
                    <tbody>
                        <% for (Map<String, String> t : listaTabelas) {
                            String tName = t.get("table_name");
                            boolean isJavaTable = "ativos_rede".equals(tName) || "logs_auditoria_sql".equals(tName);
                        %>
                            <tr>
                                <td class="mono">
                                    <strong><%= tName %></strong>
                                    <% if (isJavaTable) { %>
                                        <span class="badge badge-ok" style="margin-left:4px; font-size:10px;">JAVA APP</span>
                                    <% } else { %>
                                        <span class="badge badge-cat" style="margin-left:4px; font-size:10px;">WP CMS</span>
                                    <% } %>
                                </td>
                                <td class="mono"><%= t.get("engine") %></td>
                                <td class="mono"><%= t.get("table_rows") %></td>
                                <td class="mono"><%= t.get("tamanho_kb") %> KB</td>
                                <td class="mono" style="color: var(--text-muted);"><%= t.get("table_collation") %></td>
                            </tr>
                        <% } %>
                    </tbody>
                </table>
            </div>
        </section>

        <!-- Histórico de Operações SQL -->
        <section class="panel" style="margin-bottom: 0;">
            <div class="panel-header">
                <span class="panel-title">3. Registro de Auditoria SQL (<code>cms_db.logs_auditoria_sql</code>)</span>
                <span class="panel-badge">Últimos eventos</span>
            </div>
            <div class="sql-box">
                <code>SELECT id, operacao, detalhe, origem_ip, criado_em FROM logs_auditoria_sql ORDER BY id DESC LIMIT 6</code>
            </div>
            <div class="table-wrapper">
                <table>
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>Operação</th>
                            <th>Detalhe da Transação</th>
                            <th>IP Cliente</th>
                            <th>Horário</th>
                        </tr>
                    </thead>
                    <tbody>
                        <% for (Map<String, String> lg : listaLogs) { %>
                            <tr>
                                <td class="mono">#<%= lg.get("id") %></td>
                                <td><span class="badge badge-cat"><%= lg.get("operacao") %></span></td>
                                <td><%= lg.get("detalhe") %></td>
                                <td class="mono"><%= lg.get("origem_ip") %></td>
                                <td class="mono" style="color: var(--text-muted); white-space: nowrap;"><%= lg.get("dt") %></td>
                            </tr>
                        <% } %>
                    </tbody>
                </table>
            </div>
        </section>

    </div>

    <footer class="footer">
        <span>Servidor Linux Debian 13 (Trixie) · SGBD MariaDB 11.8 · Apache Tomcat 10.1.8 · Nginx + PHP 8.4-FPM</span>
        <span>Projeto Prático de Redes de Computadores — IFSP</span>
    </footer>

</main>

</body>
</html>
