# appd_cfg_backup
A script that does backups of AppDynamics Configuration via the AppD API and Config Exporter API

Usage: appd_cfg_backup.sh [-h] [-v] [-r "command"] -m export|import -c config_file

Backup AppDynamics Configuration.

Available options:

-h, --help        Print this help and exit<br>
-v, --verbose     Print script debug info<br>
-r, --run         Command to run the Config Exporter. Do not set if it is already running.<br>
-m, --mode        Export or Import<br>
-c, --config      Path to config file<br>

Example:

./appd_cfg_backup.sh -m export -c appd_prod.cfg -r "java -jar /opt/tools/config_exporter/config-exporter-20.6.0.3.war"<br>

Content of the config file:<br>
appd_url='http://account.saas.appdynamics.com:443' # appd controller url<br>
appd_account='account' # appd account<br>
appd_api_user='' # appd api username<br>
appd_api_secret='' # appd api secret to retrieve appd oauth token. Set as empty string to enable basic authentication. Warning: oauth authentication is not compatible with dashboard backups!<br>
appd_api_password='' # appd api password for basic authentication. Set as empty string if using appd oauth authentication<br>
appd_proxy='' # proxy url for appd controller connection<br>
appd_application_names='.*' # application names regex<br>
appd_dashboard_names='.*' # dashboard names regex<br>
appd_application_config='scopes,rules,backend-detection,exit-points,info-points,health-rules,actions,policies,metric-baselines,bt-config,data-collectors,call-graph-settings,error-detection,jmx-rules,appagent-properties,service-endpoint-detection,slow-transaction-thresholds,eum-app-integration,async-config'<br>
appd_account_config='admin-settings,http-templates,email-templates,email-sms-config,license-rules,dashboards'<br>
output_dir='./output' # backup files output directory<br>
config_exporter_url='http://localhost:8282' # config exporter url. Make sure you have an instance running or use the --run option<br>
