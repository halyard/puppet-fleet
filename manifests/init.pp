# @summary Configure Fleet MDM instance
#
# @param hostname sets the hostname for Fleet instance
# @param datadir sets where the data is persisted
# @param private_key sets the random session key used by Fleet
# @param aws_access_key_id sets the AWS key to use for Route53 challenge
# @param aws_secret_access_key sets the AWS secret key to use for the Route53 challenge
# @param email sets the contact address for the certificate
# @param ip sets the address of the Docker container
# @param backup_target sets the target repo for backups
# @param backup_password sets the encryption key for backup snapshots
# @param backup_environment sets the env vars to use for backups
# @param backup_rclone sets the config for an rclone backend
class fleet (
  String $hostname,
  String $datadir,
  String $private_key,
  String $aws_access_key_id,
  String $aws_secret_access_key,
  String $email,
  String $ip = '172.17.0.2',
  Optional[String] $backup_target = undef,
  Optional[String] $backup_password = undef,
  Optional[Hash[String, String]] $backup_environment = undef,
  Optional[String] $backup_rclone = undef,
) {
  include fleet::mysql
  include fleet::redis

  $hook_script =  "#!/usr/bin/env bash
cp \$LEGO_HOOK_CERT_PATH ${datadir}/certs/cert
cp \$LEGO_HOOK_CERT_KEY_PATH ${datadir}/certs/key
/usr/bin/systemctl restart container@fleet"

  file { [
      $datadir,
      "${datadir}/certs",
    ]:
      ensure => directory,
  }

  -> acme::certificate { $hostname:
    hook_script           => $hook_script,
    aws_access_key_id     => $aws_access_key_id,
    aws_secret_access_key => $aws_secret_access_key,
    email                 => $email,
  }

  -> firewall { '100 dnat for fleet web':
    chain  => 'DOCKER_EXPOSE',
    jump   => 'DNAT',
    proto  => 'tcp',
    dport  => 443,
    todest => "${ip}:8080",
    table  => 'nat',
  }

  -> docker::container { 'fleet':
    image => 'fleetdm/fleet:main',
    args  => [
      "--ip ${ip}",
      "-v ${datadir}/certs:/certs",
      "-e FLEET_REDIS_ADDRESS=${fleet::redis::ip}",
      "-e FLEET_REDIS_PASSWORD=${fleet::redis::password}",
      "-e FLEET_MYSQL_ADDRESS=${fleet::mysql::ip}",
      '-e FLEET_MYSQL_DATABASE=fleet',
      '-e FLEET_MYSQL_USERNAME=fleet',
      "-e FLEET_MYSQL_PASSWORD=${fleet::mysql::service_password}",
      '-e FLEET_SERVER_ADDRESS=0.0.0.0:8080',
      '-e FLEET_SERVER_CERT=/certs/cert',
      '-e FLEET_SERVER_KEY=/certs/key',
      "-e FLEET_SERVER_PRIVATE_KEY=${private_key}",
    ],
    cmd   => '/usr/bin/fleet serve',
  }
}
