#!/bin/bash

DIALOG="whiptail"
LOG="octoprint_setup.log"

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root."
  exit 1
fi

window_title=""
back_title=""
title_args=()

command_group_queue=()
command_group_name=""

touch $LOG
logpath=$(realpath $LOG)

installed_octoprint=0
installed_haproxy=0
installed_touchui=0
installed_bootsplash=0

logwrite() {
  date=$(date '+%Y-%m-%d %H:%M:%S')
  info=${@/#/}
  echo "[$date] $info" >> $logpath
}

set_back_title() {
  back_title="$1"
  build_title_args
}

set_window_title() {
  window_title="$1"
  build_title_args
}

build_title_args() {
  title_args=()
  if [ ! -z "$back_title" ]
  then
    title_args+=(--backtitle)
    title_args+=("${back_title}")
  fi
  if [ ! -z "$window_title" ]
  then
    title_args+=(--title)
    title_args+=("${window_title}")
  fi
}

init_main() {
  set_window_title "Feature Selection"
  set_back_title "Octoprint Setup Utility"

  $DIALOG "${title_args[@]/#/}" --checklist --separate-output \
    'Select features to install'  10 90 4 \
    'OctoPrint' 'The snappy web interface for your 3D printer.' ON \
    'HAProxy'  'Allows both Octoprint and Webcam Stream accessibility on port 80' ON \
    'TouchUI' 'A touch friendly interface for Mobile and TFT touch modules' ON \
    'BootSplash' 'A cooler animated bootsplash' ON \
    2>results

  exitstatus=$?
  if [ $exitstatus = 0 ]
  then
    install_init
    while read choice
    do
      case $choice in
        OctoPrint) install_octoprint
        ;;
        HAProxy) install_haproxy
        ;;
        TouchUI) install_touchui
        ;;
        BootSplash) install_bootsplash
        ;;
      esac
    done < results
    rm -f results

    if [ $installed_octoprint = 1 ]
    then
      start_octoprint
    fi

    if [ $installed_haproxy = 1 ]
    then
      start_haproxy
    fi
  fi
}

install_init() {
  logwrite " "
  logwrite "%%%%% Running Installation %%%%%"
  set_window_title "Checking for updates"
  run_apt_update
  set_window_title "Updating"
  run_apt_upgrade
  run_apt_install git
}

# Octoprint installation
# Reference: https://github.com/foosel/OctoPrint/wiki/Setup-on-a-Raspberry-Pi-running-Raspbian
install_octoprint() {
  logwrite " "
  logwrite "----- Installing Octoprint -----"

  set_window_title "Installing OctoPrint"

  run_apt_install virtualenv python-pip python-dev python-setuptools python-virtualenv libyaml-dev build-essential

  begin_command_group "Setting up user"
  add_command useradd --system --shell /bin/bash --create-home --home-dir /home/octoprint octoprint
  add_command usermod -a -G tty octoprint
  add_command usermod -a -G dialout octoprint
  run_command_group

  begin_command_group "Setting up folder structure"
  add_command mkdir -p /var/octoprint
  add_command chown root:octoprint /var/octoprint
  add_command chmod 775 /var/octoprint
  add_command mkdir -p /etc/octoprint
  add_command chown root:octoprint /etc/octoprint
  add_command chmod 775 /etc/octoprint
  add_command mkdir -p /opt/octoprint
  add_command chown root:octoprint /opt/octoprint
  add_command chmod 775 /opt/octoprint
  add_command mkdir -p /opt/octoprint/src
  add_command mkdir -p /opt/octoprint/bin
  run_command_group

  begin_command_group "Setting up virtualenv"
  add_command cd /opt/octoprint
  add_command sudo -u octoprint virtualenv venv
  add_command sudo -u octoprint /opt/octoprint/venv/bin/pip install pip --upgrade
  run_command_group

  run_git_clone https://github.com/foosel/OctoPrint.git /opt/octoprint/src

  begin_command_group "Setting up Octoprint"
  add_command cd /opt/octoprint/src
  add_command git pull
  add_command /opt/octoprint/venv/bin/python setup.py clean
  add_command /opt/octoprint/venv/bin/python setup.py install
  add_command cd /opt/octoprint/bin
  add_command ln -s ../venv/bin/octoprint
  run_command_group

  defaults_file_url="https://raw.githubusercontent.com/thedudeguy/Octoprint-Install-Script/master/assets/octoprint.default"
  defaults_file_path="/opt/octoprint/octoprint.default"
  run_wget "$defaults_file_url" "$defaults_file_path"

  begin_command_group "Installing startup scripts"
  add_command cp /opt/octoprint/src/scripts/octoprint.init /etc/init.d/octoprint
  add_command chmod +x /etc/init.d/octoprint
  add_command cp /opt/octoprint/octoprint.default /etc/default/octoprint
  add_command update-rc.d octoprint defaults
  run_command_group

  installed_octoprint=1
  logwrite " "
  logwrite "***** OctoPrint Installed *****"

}

# HAProxy Installation#
# Reference: https://github.com/foosel/OctoPrint/wiki/Setup-on-a-Raspberry-Pi-running-Raspbian
install_haproxy() {
  logwrite " "
  logwrite "----- Installing HAProxy -----"

  set_window_title "Installing HAProxy"

  run_apt_install haproxy

  config_url="https://raw.githubusercontent.com/thedudeguy/Octoprint-Install-Script/master/assets/haproxy.cfg"
  config_path="/etc/haproxy/haproxy.cfg"
  run_wget "$config_url" "$config_path"

  installed_haproxy=1
  logwrite " "
  logwrite "***** HAProxy Installed *****"
}

# TouchUI installation
# References:
#    https://github.com/foosel/OctoPrint/wiki/Setup-on-a-Raspberry-Pi-running-Raspbian
#    https://scribles.net/setting-up-raspberry-pi-web-kiosk/
install_touchui() {
  logwrite " "
  logwrite "----- Installing TouchUI -----"
  set_window_title "Installing TouchUI"

  run_apt_install xinit chromium-browser

  touch /home/pi/.hushlogin
  chown pi:pi /home/pi/.hushlogin

  # setup xinitc
  xinit_file="/home/pi/.xinitrc"
  touch $xinit_file
  chown pi:pi $xinit_file

  echo "#!/bin/sh" > $xinit_file

  echo 'check_octoprint() {'  >> $xinit_file
  echo '  pgrep -n octoprint > /dev/null'  >> $xinit_file
  echo '  return $?'  >> $xinit_file
  echo '}'  >> $xinit_file
  echo 'stop_bannerd() {'  >> $xinit_file
  echo "bpid=\$(sudo ps aux | grep bannerd | awk '{print \$2}' | head -n1)"  >> $xinit_file
  echo 'if [ ! -z "$bpid" ]'  >> $xinit_file
  echo 'then'  >> $xinit_file
  echo 'sudo kill -9 "$bpid"'  >> $xinit_file
  echo 'fi'  >> $xinit_file
  echo '}'  >> $xinit_file
  echo ''  >> $xinit_file
  echo 'until check_octoprint'  >> $xinit_file
  echo 'do'  >> $xinit_file
  echo '  sleep 5'  >> $xinit_file
  echo 'done'  >> $xinit_file
  echo ''  >> $xinit_file
  echo 'sleep 5s'  >> $xinit_file
  echo 'stop_bannerd' >> $xinit_file
  echo "" >> $xinit_file
  echo "# disable blank screen" >> $xinit_file
  echo "xset s off" >> $xinit_file
  echo "xset -dpms" >> $xinit_file
  echo "xset s noblank" >> $xinit_file
  echo "" >> $xinit_file
  echo "# launch browser" >> $xinit_file
  echo 'exec chromium-browser \'  >> $xinit_file
  echo ' --window-size=800,480 \'  >> $xinit_file
  echo ' --enabled \' >> $xinit_file
  echo ' --touch-events \' >> $xinit_file
  echo ' --disable-bundled-ppapi-flash \' >> $xinit_file
  echo ' --incognito \' >> $xinit_file
  echo ' --kiosk \' >> $xinit_file
  echo ' --window-position=0,0 \' >> $xinit_file
  echo ' --start-fullscreen \' >> $xinit_file
  echo ' --start-maximized \' >> $xinit_file
  echo ' http://127.0.0.1:5000' >> $xinit_file

  #maybe useful switches
  # --edge-touch-filtering
  # --touch-devices
  # --touch-calibration
  # --enable-hardware-overlays single-fullscreen

  # setup bashrc
  bashrc_file="/home/pi/.bashrc"
  sed -i '/## TouchUI Settings ##/,/## End TouchUI Settings ##/d' $bashrc_file
  echo '## TouchUI Settings ##' >> $bashrc_file
  echo 'if [ -z "${SSH_TTY}" ]' >> $bashrc_file
  echo 'then' >> $bashrc_file
  echo 'startx -- -nocursor > /dev/null 2>&1' >> $bashrc_file
  echo 'fi' >> $bashrc_file
  echo '## End TouchUI Settings ##' >> $bashrc_file

  begin_command_group "Installing TouchUI Plugin"
  add_command /opt/octoprint/venv/bin/pip install "https://github.com/BillyBlaze/OctoPrint-TouchUI/archive/master.zip"
  run_command_group

  systemctl set-default multi-user.target
  sed /etc/systemd/system/autologin@.service -i -e 's#^ExecStart=.*#ExecStart=-/sbin/agetty --skip-login --noclear --noissue --login-options "-f pi" %I $TERM#'
  ln -fs /etc/systemd/system/autologin@.service /etc/systemd/system/getty.target.wants/getty@tty1.service

  installed_touchui=1
  logwrite " "
  logwrite "***** TouchUI Installed *****"
}

# BootSplash installation
# References:
#    https://yingtongli.me/blog/2016/12/21/splash.html
#    https://scribles.net/silent-boot-up-on-raspbian-stretch/
install_bootsplash() {
  logwrite " "
  logwrite "----- Installing BootSplash -----"
  set_window_title "Installing BootSplash"

  begin_command_group "Setting up folder structure"
  add_command mkdir -p /opt/bannerd
  add_command mkdir -p /opt/bannerd/src
  add_command mkdir -p /opt/bannerd/bin
  add_command mkdir -p /opt/bannerd/frames
  add_command mkdir -p /opt/bannerd/frames/landscape
  add_command mkdir -p /opt/bannerd/frames/portrait
  run_command_group

  frames_zip_url_landscape="https://github.com/thedudeguy/Octoprint-Install-Script/raw/master/assets/bootsplash_landscape.zip"
  frames_path_landscape="/opt/bannerd/frames/landscape"
  frames_zip_path_landscape="/opt/bannerd/frames/bootsplash_landscape.zip"

  frames_zip_url_portrait="https://github.com/thedudeguy/Octoprint-Install-Script/raw/master/assets/bootsplash_portrait.zip"
  frames_path_portrait="/opt/bannerd/frames/portrait"
  frames_zip_path_portrait="/opt/bannerd/frames/bootsplash_portrait.zip"

  run_wget "$frames_zip_url_landscape" "$frames_zip_path_landscape"
  run_unzip "$frames_zip_path_landscape" "$frames_path_landscape"

  run_wget "$frames_zip_url_portrait" "$frames_zip_path_portrait"
  run_unzip "$frames_zip_path_portrait" "$frames_path_portrait"

  bannerd_repo="https://github.com/alukichev/bannerd.git"
  bannerd_src_path="/opt/bannerd/src"
  run_git_clone "$bannerd_repo" "$bannerd_src_path"

  begin_command_group "Building Bannerd"
  add_command cd "$bannerd_src_path"
  add_command make
  add_command cd /opt/bannerd/bin
  add_command ln -s ../src/bannerd
  run_command_group

  config_file="/boot/config.txt"
  bak_config_file="/boot/config.txt.bak"
  cmdline_file="/boot/cmdline.txt"
  bak_cmdline_file="/boot/cmdline.txt.bak"

  if [ ! -f "$bak_config_file" ]
  then
    cp "$config_file" "$bak_config_file"
  fi
  if [ ! -f "$bak_cmdline_file" ]
  then
    cp "$cmdline_file" "$bak_cmdline_file"
  fi
  # remove bootsplash block
  sed -i '/## BootSplash Settings ##/,/## End BootSplash Settings ##/d' $config_file
  # comment out setting we'll be changing - if they exist in config currently
  sed -i '/^#/! {/disable_splash/ s/^/#/}' $config_file
  sed -i '/^#/! {/disable_overscan/ s/^/#/}' $config_file
  # add setting overrides
  echo "## BootSplash Settings ##"                  >> $config_file
  echo "disable_splash=1"                           >> $config_file
  echo "disable_overscan=1"                         >> $config_file
  echo "## End BootSplash Settings ##"              >> $config_file

  # remove from commands
  sed -i 's/logo.nologo//g' $cmdline_file
  sed -i 's/vt.global_cursor_default=[[:digit:]]//g' $cmdline_file
  sed -i 's/consoleblank=[[:digit:]]//g' $cmdline_file
  sed -i 's/loglevel=[[:digit:]]//g' $cmdline_file
  sed -i 's/quiet//g' $cmdline_file
  # re-add to commands
  sed -i 's/$/\ logo.nologo/' $cmdline_file
  sed -i 's/$/\ vt.global_cursor_default=0/' $cmdline_file
  sed -i 's/$/\ consoleblank=0/' $cmdline_file
  sed -i 's/$/\ loglevel=1/' $cmdline_file
  sed -i 's/$/\ quiet/' $cmdline_file
  # cleanup spacing
  sed -i 's/\ \ */\ /g' $cmdline_file

  bannerd_service_file="/etc/systemd/system/splashscreen.service"
  echo "[Unit]"                                                                         > $bannerd_service_file
  echo "Description=Splash screen"                                                      >> $bannerd_service_file
  echo "DefaultDependencies=no"                                                         >> $bannerd_service_file
  echo "After=local-fs.target"                                                          >> $bannerd_service_file
  echo ""                                                                               >> $bannerd_service_file
  echo "[Service]"                                                                      >> $bannerd_service_file
  echo 'Type=forking' >> $bannerd_service_file
  echo "ExecStart=/bin/sh -c '/opt/bannerd/bin/bannerd /opt/bannerd/frames/landscape/*.bmp'"  >> $bannerd_service_file
  echo "StandardInput=tty"                                                              >> $bannerd_service_file
  echo "StandardOutput=tty"                                                             >> $bannerd_service_file
  echo ""                                                                               >> $bannerd_service_file
  echo "[Install]"                                                                      >> $bannerd_service_file
  echo "WantedBy=sysinit.target"                                                        >> $bannerd_service_file

  begin_command_group "Enabling Bannerd Service"
  add_command systemctl mask plymouth-start.service
  add_command systemctl disable splashscreen
  add_command systemctl enable splashscreen
  run_command_group

  installed_bootsplash=1
  logwrite " "
  logwrite "***** BootSplash Installed *****"
}

start_octoprint() {
  logwrite " "
  logwrite "===== Starting Octoprint ====="
  set_window_title "Starting Octoprint"

  begin_command_group "Starting Octoprint"
  add_command service octoprint stop
  add_command service octoprint start
  run_command_group
}

start_haproxy() {
  logwrite " "
  logwrite "===== Starting HAProxy ====="
  set_window_title "Starting HAProxy"

  begin_command_group "Starting HAProxy"
  add_command service haproxy stop
  add_command service haproxy start
  run_command_group
}

begin_command_group() {
  command_group_name=$1
  command_group_queue=()
}

add_command() {
  command=${@/#/}
  command_group_queue+=("$command")
}

run_command_group() {
  wd="."
  total_commands=${#command_group_queue[@]}
  current_command_index=0
  completion=0
  current_status=""
  logwrite " "
  logwrite "## Running Command Group: $command_group_name"
  {
    for command in "${command_group_queue[@]}"
    do
      logwrite $(printf ">> (%d/%d) %s" $(($current_command_index+1)) $total_commands "$command")
      completion=$(( (100*($current_command_index))/$total_commands ))
      current_status=$(printf " %s (%d/%d)" "$command_group_name" $(($current_command_index+1)) $total_commands)
      echo XXX
      echo $completion
      echo "$current_status"
      echo XXX

      ckey=$(echo $command | awk '{print $1}')
      if [ "$ckey" = "cd" ]
      then
        logwrite "== Changing Directory: $wd"
        wd=$(echo $command | awk '{$1=""; print $0}')
        continue
      fi

      pushd $wd
      $command 2>&1 |{
        while read response
        do
          logwrite "-- $response"
        done
      }
      popd
      current_command_index=$(($current_command_index+1))
    done

    echo XXX
    echo 100
    echo " $command_group_name - Done"
    echo XXX
    logwrite "** Group $command_group_name finished"
    sleep 1

  } |$DIALOG "${title_args[@]/#/}" --gauge " " 7 78 0
}

run_apt_command() {
  command="apt-get $@ --yes --option APT::Status-Fd=1"
  logwrite ">> $command"

  completion=0
  current_item=""
  $command |\
    stdbuf -o0 tr '[:cntrl:]' '\n' |\
    stdbuf -o0 sed -e 's/^[[:space:]]*//' |\
    stdbuf -o0 sed -e 's/[[:space:]]*$//' |\
    {
      while read item
      do
        logwrite "-- $item"
        type=$(echo $item | cut -d':' -f1)
        if [ "$type" == "dlstatus" ]
        then
          completion=$(echo $item | cut -d':' -f3 | awk '{printf("%.0f", $0)}')
          current_item=$(echo $item | cut -d':' -f4)
        elif [ "$type" == "pmstatus" ]
        then
          completion=$(echo $item | cut -d':' -f3 | awk '{printf("%.0f", $0)}')
          package=$(echo $item | cut -d':' -f2)
          description=$(echo $item | cut -d':' -f4)
          current_item="$package -- $description"
        else
          current_item="$item"
        fi

        echo XXX
        echo $completion
        echo $current_item
        echo XXX
      done

      echo XXX
      echo 100
      echo "Done"
      echo XXX

      logwrite "** Done"
    } |$DIALOG "${title_args[@]/#/}" --gauge " " 6 78 0
}

run_apt_update() {
  logwrite " "
  logwrite "## Running Apt Update"
  run_apt_command update
}

run_apt_upgrade() {
  logwrite " "
  logwrite "## Running Apt Upgrade"
  run_apt_command dist-upgrade
}

run_apt_install() {
  logwrite " "
  logwrite "## Running Apt Install"
  run_apt_command install $@
}

run_git_clone() {
  logwrite " "
  logwrite "## Cloning  Git Repository"

  repo="$1"
  dir="$2"

  command="git clone --progress $repo $dir"
  logwrite ">> $command"

  completion=0
  current_status="Cloning Git Repository"

  $command 2>&1 |stdbuf -o0 tr '[:cntrl:]' '\n' |\
    {
      while read line
      do
        logwrite "-- $line"
        if [[ $line = *"%"* ]]
        then
          completion=$(echo $line | cut -d":" -f2 | tr -d '[:space:]' | cut -d"%" -f1)
          extra=$(echo $line | cut -d":" -f2 | tr -d '[:space:]' | cut -d"%" -f2)
          current_status=" $(echo $line | cut -d":" -f1): $extra"
        else
          current_status="$line"
        fi

        echo XXX
        echo $completion
        echo "$current_status"
        echo XXX
      done

      echo XXX
      echo 100
      echo "Git Repo Cloned"
      echo XXX
      logwrite "** Done"
    } |$DIALOG "${title_args[@]/#/}" --gauge " Cloning Git Repo" 6 78 0
}

run_wget() {
  logwrite " "
  logwrite "## Downloading file"

  durl="$1"
  opath="$2"

  logwrite "== download url: $durl"
  logwrite "== download to: $opath"

  completion=0
  current_status="Preparing Download"
  wget_command="wget --show-progress --progress=dot --user-agent=Octoprint-Install-Script --no-cache --no-cookies --output-document=$opath $durl"

  logwrite ">> $wget_command"

  $wget_command 2>&1 | \
    {
      while read line
      do
        logwrite "-- $line"
        if [[ $line = *[![:space:]]* ]]
        then
          if [[ $line = *"%"* ]]
          then
            completion=$(echo  $line | sed -u -e "s,\.,,g" | awk '{print $2}' | sed -u -e "s,\%,,g")
          else
            current_status=$line
          fi
        fi

        echo XXX
        echo $completion
        echo "$current_status"
        echo XXX

      done

      echo XXX
      echo 100
      echo "Done"
      echo XXX
      logwrite "** Done"

    } |$DIALOG "${title_args[@]/#/}" --gauge "Preparing Download" 6 78 0
}

run_unzip() {
  zip_file="$1"
  extract_path="$2"

  logwrite " "
  logwrite "## Unzipping file"

  total_count=$(unzip -Z $zip_file | tail -n1 | cut -d"," -f1 | tr -d [:alpha:])
  current_count=0
  current_status=""

  unzip_cmd="unzip -o $zip_file -d $extract_path"
  logwrite ">> $unzip_cmd"
  $unzip_cmd 2>&1 |  \
    {
      while read line
      do
        logwrite "-- $line"

        current_count=$(($current_count + 1))
        completion=$(( (100*($current_count-1))/$total_count ))
        current_status="$line ($current_count/$total_count)"

        echo XXX
        echo $completion
        echo "$current_status"
        echo XXX
      done
      echo XXX
      echo 100
      echo "Extraction Complete"
      echo XXX
      logwrite "** Done"
    } |$DIALOG "${title_args[@]/#/}" --gauge "Preparing to Extract Zip" 6 78 0
}

init_main
