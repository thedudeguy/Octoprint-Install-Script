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
installed_touchui=0

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
    'Select features to install'  10 90 2 \
    'OctoPrint' 'The snappy web interface for your 3D printer.' ON \
    'TouchUI' 'A touch friendly interface for Mobile and TFT touch modules' ON \
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
        TouchUI) install_touchui
        ;;
      esac
    done < results
    rm -f results

    if [ $installed_octoprint = 1 ]
    then
        start_octoprint
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

  begin_command_group "Setting up user"
  add_command useradd --system --shell /bin/bash --create-home /home/octoprint
  add_command usermod -a -G tty octoprint
  add_command usermod -a -G dialout octoprint
  run_command_group

  begin_command_group "Setting up folder structure"
  add_command mkdir -p /var/octoprint
  add_command chown root:octoprint /var/octoprint
  add_command mkdir -p /etc/octoprint
  add_command chown root:octoprint /etc/octoprint
  add_command mkdir -p /opt/octoprint
  add_command chown root:octoprint /opt/octoprint
  add_command mkdir -p /opt/octoprint/src
  add_command mkdir -p /opt/octoprint/bin
  run_command_group

  run_apt_install python-pip python-dev python-setuptools python-virtualenv git libyaml-dev build-essential

  begin_command_group "Setting up virtualenv"
  add_command cd /opt/octoprint
  add_command virtualenv venv
  add_command /opt/octoprint/venv/bin/pip install pip --upgrade
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
  run_command_group

  installed_octoprint=1
  logwrite " "
  logwrite "***** OctoPrint Installed *****"

}

# TouchUI installation
# Reference: https://github.com/foosel/OctoPrint/wiki/Setup-on-a-Raspberry-Pi-running-Raspbian
install_touchui() {
  logwrite " "
  logwrite "----- Installing TouchUI -----"

  begin_command_group "Installing TouchUI Plugin"
  add_command /opt/octoprint/venv/bin/pip install "https://github.com/BillyBlaze/OctoPrint-TouchUI/archive/master.zip"
  run_command_group



  installed_touchui=1
  logwrite " "
  logwrite "***** TouchUI Installed *****"
}

start_octoprint() {
  logwrite " "
  logwrite "===== Starting Octoprint ====="
  begin_command_group "Starting Octoprint"
  add_command update-rc.d octoprint defaults
  add_command service octoprint stop
  add_command service octoprint start
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

add_command_in_dir() {
  echo 'ya'
}

run_command_group() {
  wd="."
  total_commands=${#command_group_queue[@]}
  current_command_index=0
  completion=0
  logwrite " "
  logwrite "## Running Command Group: $command_group_name"
  {
    for command in "${command_group_queue[@]}"
    do
      logwrite $(printf ">> (%d/%d) %s" $(($current_command_index+1)) $total_commands "$command")
      completion=$(( (100*($current_command_index))/$total_commands ))
      echo XXX
      echo $completion
      echo "$(printf " %s (%d/%d)" "$command_group_name" $(($current_command_index+1)) $total_commands)"
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

  } |$DIALOG "${title_args[@]/#/}" --gauge " " 6 78 0
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

init_main
