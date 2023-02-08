# appd_cfg_backup
A script that does backups of AppDynamics Configuration via the AppD API and Config Exporter API

Usage: appd_cfg_backup.sh [-h] [-v] [-r "command"] -m export|import -c config_file

Backup AppDynamics Configuration (Skandia).

Available options:

-h, --help        Print this help and exit
-v, --verbose     Print script debug info
-r, --run         Command to run the Config Exporter. Do not set if it is already running.
-m, --mode        Export or Import
-c, --config      Path to config file

Example:
./appd_cfg_backup.sh -m export -c appd_prod.cfg -r "java -jar /opt/tools/config_exporter/config-exporter-20.6.0.3.war"

Content of the config file:
appd_url='http://account.saas.appdynamics.com:443' # appd controller url
appd_account='account' # appd account
appd_api_user='' # appd api username
appd_api_secret='' # appd api secret to retrieve appd oauth token. Set as empty string to enable basic authentication
appd_api_password='' # appd api password for basic authentication. Set as empty string if using appd oauth authentication
appd_proxy='' # proxy url for appd controller connection
appd_application_names='.*' # application names regex
appd_application_config='scopes,rules,backend-detection,exit-points,info-points,health-rules,actions,policies,metric-baselines,bt-config,data-collectors,call-graph-settings,error-detection,jmx-rules,appagent-properties,service-endpoint-detection,slow-transaction-thresholds,eum-app-integration,async-config'
appd_account_config='admin-settings,http-templates,email-templates,email-sms-config,license-rules,dashboards'
output_dir='./output' # backup files output directory
config_exporter_url='http://localhost:8282' # config exporter url. Make sure you have an instance running or use the --run option
