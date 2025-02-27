class homebrew::install {

  case $::facts[kernel] {
    /^Linux*/: {
      $brew_root          = $homebrew::root
      $inst_dir           = $brew_root
      $link_bin           = false
      $brew_folders_extra = []
      $stat_flags = '-c \'%a\''
      $group_stat_flags = '-c \'%G\''
      $chown = '/usr/bin/chown'
      $chmod_permissions = 'g+rwx'
      $default_permissions = $homebrew::multiuser ? {
        false => '750',
        true  => '775',
      }
    }
    default: {
      case $::facts[processors][models][0] {
        # brew complains if it finds its bin in /usr/local/bin on Apple Silicon
        # so we should put brew where it expects to be
        /^Apple*/: {
          $brew_root          = '/opt/homebrew'
          $inst_dir           = $brew_root
          $link_bin           = false
          $brew_folders_extra = []
          $stat_flags = '-f \'%OLp\''
          $group_stat_flags = '-f \'%Sg\''
          $chown = '/usr/sbin/chown'
          $chmod_permissions = '+a \'group:primarygroup:allow list,add_file,search,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity,file_inherit,directory_inherit\''
      $default_permissions = $homebrew::multiuser ? {
        false => '755',
        true  => '775',
      }
        }
        /^Intel*/: {
          $brew_root          = '/usr/local'
          $inst_dir           = "${brew_root}/Homebrew"
          $link_bin           = true
          $brew_folders_extra = ["${brew_root}/Homebrew",]
          $stat_flags = '-f \'%OLp\''
          $group_stat_flags = '-f \'%Sg\''
          $chown = '/usr/sbin/chown'
          $chmod_permissions = '+a \'group:primarygroup:allow list,add_file,search,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity,file_inherit,directory_inherit\''
      $default_permissions = $homebrew::multiuser ? {
        false => '755',
        true  => '775',
      }
        }
        default:   { fail("unknown arch for processor ${::facts[processors][models][0]}") }
      }
    }
  }

  $root_tree = split($brew_root, /\//)

  $root_tree_list = $root_tree[1,-1].reduce([]) |$memo, $value| {
     $memo << "${memo[-1]}/${value}"
  }

  $root_tree_list.each | String $brew_root_sys_folder | {
    if !defined(File[$brew_root_sys_folder]) {
      file { $brew_root_sys_folder:
        ensure => directory,
      }
    }
  }

  $brew_sys_folders = [
    "${brew_root}/bin",
    "${brew_root}/etc",
    "${brew_root}/Frameworks",
    "${brew_root}/include",
    "${brew_root}/lib",
    "${brew_root}/lib/pkgconfig",
    "${brew_root}/var",
  ]
  $brew_sys_folders.each | String $brew_sys_folder | {
    if !defined(File[$brew_sys_folder]) {
      file { $brew_sys_folder:
        ensure => directory,
        owner  => $homebrew::user,
        group  => $homebrew::group,
      }
    }
  }

  $brew_sys_chmod_folders = [
    "${brew_root}",
    "${brew_root}/bin",
    "${brew_root}/include",
    "${brew_root}/lib",
    "${brew_root}/etc",
    "${brew_root}/Frameworks",
    "${brew_root}/var",
  ]
  $brew_sys_chmod_folders.each | String $brew_sys_chmod_folder | {
    exec { "brew-chmod-sys-${brew_sys_chmod_folder}":
      command => "/bin/chmod -R 775 ${brew_sys_chmod_folder}",
      unless  => "/usr/bin/stat ${stat_flags} ${brew_sys_chmod_folder} | /usr/bin/grep -w '${default_permissions}'",
      notify  => Exec["set-${brew_sys_chmod_folder}-directory-inherit"],
    }
    exec { "set-${brew_sys_chmod_folder}-directory-inherit":
      command     => "/bin/chmod -R ${chmod_permissions} ${brew_sys_chmod_folder}",
      refreshonly => true,
    }
  }

  $brew_folders = flatten(
    $brew_folders_extra,
    [
    "${brew_root}/opt",
    "${brew_root}/Caskroom",
    "${brew_root}/Cellar",
    "${brew_root}/var/homebrew",
    "${brew_root}/share",
    "${brew_root}/share/doc",
    "${brew_root}/share/info",
    "${brew_root}/share/man",
    "${brew_root}/share/man1",
    "${brew_root}/share/man2",
    "${brew_root}/share/man3",
    "${brew_root}/share/man4",
    "${brew_root}/share/man5",
    "${brew_root}/share/man6",
    "${brew_root}/share/man7",
    "${brew_root}/share/man8",
  ])

  file { $brew_folders:
    ensure => directory,
    owner  => $homebrew::user,
    group  => $homebrew::group,
  }

  if $homebrew::multiuser == true {
    $brew_folders.each | String $brew_folder | {
      exec { "chmod-${brew_folder}":
        command => "/bin/chmod -R 775 ${brew_folder}",
        unless  => "/usr/bin/stat ${stat_flags} '${brew_folder}' | /usr/bin/grep -w '${default_permissions}'",
        notify  => Exec["set-${brew_folder}-directory-inherit"]
      }
      exec { "chown-${brew_folder}":
        command => "${chown} -R :${homebrew::group} ${brew_folder}'",
        unless  => "/usr/bin/stat ${group_stat_flags} '${brew_folder}' | /usr/bin/grep -w '${homebrew::group}'",
      }
      exec { "set-${brew_folder}-directory-inherit":
        command     => "/bin/chmod -R ${chmod_permissions} ${brew_folder}",
        refreshonly => true,
      }
    }
  }

  exec { 'install-homebrew':
    cwd       => $inst_dir,
    command   => "/usr/bin/su ${homebrew::user} -c '/bin/bash -o pipefail -c \"/usr/bin/curl -skSfL https://github.com/homebrew/brew/tarball/master | /usr/bin/tar xz -m --strip 1\"'",
    creates   => "${inst_dir}/bin/brew",
    logoutput => on_failure,
    timeout   => 0,
  }
  if $link_bin {
    file { "${brew_root}/bin/brew":
      ensure => 'link',
      target => "${inst_dir}/bin/brew",
      owner  => $homebrew::user,
      group  => $homebrew::group,
    }
  }

}
