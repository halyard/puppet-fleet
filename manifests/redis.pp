# @summary Configure Fleet MDM Redis instance
#
# @param password sets the password for Redis access
# @param ip sets the address of the Redis Docker container
# @param backup_watchdog sets the watchdog URL for redis dumps
class fleet::redis (
  String $password,
  String $ip = '172.17.0.3',
  Optional[String] $backup_watchdog = undef,
) {
  $redis_datadir = "${fleet::datadir}/redis"
  file { [
      $redis_datadir,
      "${redis_datadir}/data",
      "${redis_datadir}/config",
    ]:
      ensure => directory,
  }

  file { "${redis_datadir}/config/redis.conf":
    ensure  => file,
    content => template('redis/redis.conf.erb'),
    notify  => Service['container@redis'],
  }

  -> docker::container { 'redis':
    image => 'redis:8',
    args  => [
      "--ip ${ip}",
      "-v ${redis_datadir}/data:/data",
      "-v ${redis_datadir}/config:/usr/local/etc/redis",
    ],
    cmd   => 'redis-server /usr/local/etc/redis/redis.conf',
  }

  firewall { '101 allow cross container from fleet to redis':
    chain       => 'FORWARD',
    action      => 'accept',
    proto       => 'tcp',
    source      => $fleet::ip,
    destination => $ip,
    dport       => 6379,
  }

  if $fleet::backup_target != '' {
    backup::repo { 'redis':
      source        => "${redis_datadir}/data",
      target        => "${fleet::backup_target}/redis",
      watchdog_url  => $backup_watchdog,
      password      => $fleet::backup_password,
      environment   => $fleet::backup_environment,
      rclone_config => $fleet::backup_rclone,
    }
  }
}
