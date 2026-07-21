# @summary Configure Fleet MDM MySQL instance
#
# @param service_password sets the Fleet password for MySQL
# @param root_password sets the root password for MySQL
# @param ip sets the address of the MySQL Docker container
# @param backup_ip sets the address of the MySQL-backup Docker container
# @param backup_watchdog sets the watchdog URL for mysql dumps
class fleet::mysql (
  String $service_password,
  String $root_password,
  String $ip = '172.17.0.4',
  String $backup_ip = '172.17.0.5',
  Optional[String] $backup_watchdog = undef,
) {
  $mysql_datadir = "${fleet::datadir}/mysql"
  file { [
      $mysql_datadir,
      "${mysql_datadir}/data",
    ]:
      ensure => directory,
  }

  -> file { "${mysql_datadir}/backup":
    ensure => directory,
    owner  => 1005,
  }

  -> docker::container { 'mysql':
    image => 'mysql:8',
    args  => [
      "--ip ${ip}",
      "-v ${mysql_datadir}/data:/var/lib/mysql",
      '-e MYSQL_DATABASE=fleet',
      '-e MYSQL_USER=fleet',
      "-e MYSQL_PASSWORD=${service_password}",
      "-e MYSQL_ROOT_PASSWORD=${root_password}",
    ],
    cmd   => '',
  }

  firewall { '101 allow cross container from fleet to mysql':
    chain       => 'FORWARD',
    action      => 'accept',
    proto       => 'tcp',
    source      => $fleet::ip,
    destination => $ip,
    dport       => 3306,
  }

  firewall { '101 allow cross container from mysql-backup to mysql':
    chain       => 'FORWARD',
    action      => 'accept',
    proto       => 'tcp',
    source      => $backup_ip,
    destination => $ip,
    dport       => 3306,
  }

  docker::container { 'mysql_backup':
    image => 'databack/mysql-backup:latest',
    args  => [
      "--ip ${backup_ip}",
      "-v ${mysql_datadir}/backup:/db",
      '-e DB_DUMP_TARGET=/db',
      '-e DB_DUMP_FREQUENCY=60',
      "-e DB_SERVER=${ip}",
      '-e DB_USER=fleet',
      "-e DB_PASS=${service_password}",
      '-e DB_DUMP_INCLUDE=fleet',
    ],
    cmd   => 'dump',
  }

  if $fleet::backup_target != '' {
    backup::repo { 'mysql':
      source        => "${mysql_datadir}/data",
      target        => "${fleet::backup_target}/mysql",
      watchdog_url  => $backup_watchdog,
      password      => $fleet::backup_password,
      environment   => $fleet::backup_environment,
      rclone_config => $fleet::backup_rclone,
    }
  }
}
