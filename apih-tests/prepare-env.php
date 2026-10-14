<?php
// Copy the encryption key needed by the restored database, then isolate all services.
$env = require '/tmp/demo-env.php';
if (empty($env['crypt']['key']) || !getenv('INTEGRATION_DB_PASSWORD')) {
    throw new RuntimeException('Missing demo encryption key or integration database password.');
}
$env['db']['connection']['default']['host'] = 'integration-db';
$env['db']['connection']['default']['dbname'] = 'magento_integration';
$env['db']['connection']['default']['username'] = 'magento_integration';
$env['db']['connection']['default']['password'] = getenv('INTEGRATION_DB_PASSWORD');
$env['system']['default']['web']['unsecure']['base_url'] = 'http://localhost:8081/';
$env['system']['default']['web']['secure']['base_url'] = 'http://localhost:8081/';
$env['system']['default']['catalog']['search'] = [
    'engine' => 'opensearch',
    'opensearch_server_hostname' => 'integration-search',
    'opensearch_server_port' => '9200',
    'opensearch_enable_auth' => '0',
    'opensearch_index_prefix' => 'magento_integration',
];
foreach (['default', 'page_cache'] as $cache) {
    $env['cache']['frontend'][$cache]['id_prefix'] = 'apih_';
}
file_put_contents('app/etc/env.php', "<?php\nreturn " . var_export($env, true) . ";\n");
chmod('app/etc/env.php', 0600);
