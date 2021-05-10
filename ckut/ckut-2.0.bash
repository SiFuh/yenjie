#!/bin/bash
#
#    ckut - a simple shell script for updating the Linux kernel
#
#    Copyright (c) 2020 by Lin SiFuh
#
#    *************************************************************************
#    *                                                                       *
#    * This program is free software; you can redistribute it and/or modify  *
#    * it under the terms of the GNU General Public License as published by  *
#    * the Free Software Foundation; either version 2 of the License, or     *
#    * (at your option) any later version.                                   *
#    *                                                                       *
#    *************************************************************************
#
#   **** USE AT YOUR OWN RISK ****
#

# To use this script the following programs need to be installed
# dialog (display dialog boxes from shell scripts)
# pv     (monitor the progress of data through a pipe)
# lynx   (text based web browser)
# curl   (tool for transfering files with URL synta)

VERSION="v2.0"
TITLE="CRUX Kernel Update Tool ${VERSION}    ${MESSAGE}"
CONFIG="/etc/ckut.conf"
KERNEL_OLD="$(uname -r)"
KERNEL="NONE"
TMPDIR="$(mktemp -d /tmp/ckut.XXXXXXXXXX)"

DIALOG_CANCEL=1
DIALOG_ESC=255
HEIGHT=0
WIDTH=0

MESSAGE1="Kernel Version Selected is"

# Clean up on exit
trap 'rm -rf "${TMPDIR}" && clear' EXIT

if [[ "root" != "$USER" ]]; then
  dialog --backtitle "${TITLE}" --ok-label "Nope" --msgbox "Got root?" 5 13
  exit 0
fi

# Create log file
touch "${TMPDIR}/ckut.log"

# Load configuration file
if [ -f "${CONFIG}" ]; then
  . ${CONFIG}
else
  echo ""
  echo "No configuration file found!"
  echo ""
  read -n 1 -r -s -p $'Press any key to exit...'
  exit 0
fi

# Convert MAKEFLAGS into an array
eval MAKEFLAGS="($MAKEFLAGS)"

eval DOWNLOAD="(${DOWNLOAD_PROG} ${DOWNLOAD_FLAGS})"

# Whinge if something is amiss
error_message() {
  dialog --aspect 50 --backtitle "${TITLE}" --title "Error!" --msgbox "${MESSAGE}" "${HEIGHT}" "${WIDTH}"
  error=1
}

# Verify if the user has selected a kernel version
check_kernel() {
  unset error
  if [[ "${KERNEL}" == "NONE" ]]; then
    MESSAGE="Select a kernel first"
    error_message
  fi
}

# Check to see if the kernel archive exists in /usr/src
check_archive() {
  unset error
  if [[ ! -f "/usr/src/linux-${KERNEL}.tar.xz" ]]; then
    MESSAGE="Cannot find ${DOWNLOAD_LOCATION}/linux-${KERNEL}.tar.xz"
    error_message
  fi
}

# Check to see if it downloaded to /usr/src
check_download () {
  unset error
  if [[ ! -f "/usr/src/linux-${KERNEL}.tar.xz" ]]; then
    MESSAGE="Error! linux-${KERNEL}.tar.xz is missing or invalid"
    error_message
  fi
}

# See if the archive has already been extracted to /usr/src
check_folder() {
  unset error
  if [[ ! -d "/usr/src/linux-${KERNEL}" ]]; then
    MESSAGE="Directory ${DOWNLOAD_LOCATION}/linux-${KERNEL} does not exist"
    error_message
  fi
}

# Have a look if CONFIG_LOCALVERSION is set in the kernel config
check_localversion() {
  unset LOCALVERSION
  cd "/usr/src/linux-${KERNEL}" || return
  LOCALVERSION=$(grep "CONFIG_LOCALVERSION=" .config | cut -d \" -f 2)
}

# Try to find an old kernel configuration file
check_kernelconfig() {
  if [[ -f "${KERNEL_LOCATION}/config-${KERNEL_OLD}" ]]; then
    cp "${KERNEL_LOCATION}/config-${KERNEL_OLD}" .config
    { echo -ne "cp ${KERNEL_LOCATION}/config-${KERNEL_OLD}"
      echo -e " /usr/src/linux-${KERNEL}/.config"
    }>> "${TMPDIR}/ckut.log"
  elif [[ -f "/usr/src/linux-${KERNEL_OLD}/.config" ]]; then
    cp  "/usr/src/linux-${KERNEL_OLD}/.config" .config
    { echo -ne "cp /usr/src/linux-${KERNEL_OLD}/.config"
      echo -e " /usr/src/linux-${KERNEL}/.config"
    }>> "${TMPDIR}/ckut.log"
  else
    missing_message
    error_message
    unset error
  fi
}

# Message informing that an old .config cannot be found
missing_message(){
  MESSAGE="  Could not find an old configuration file for ${KERNEL_OLD}.\n
  Either find it and copy it to /usr/src/linux-${KERNEL}/.config\n
  or run menuconfig to create and configure a new .config file\n\n
  Continuing without it..."
}

# Download the kernel
download_kernel() {
  if [[ -f "/usr/src/linux-${KERNEL}.tar.xz" ]]; then
    MESSAGE="Already downloaded. Would you like to skip this step?"
    dialog --yesno "${MESSAGE}"  "${HEIGHT}" "${WIDTH}" && skip=1
  fi
  if  [[ -z "${manual}" ]]; then
    URL=$(awk '/'"${KERNEL}"'/ { print $2 }' < "${TMPDIR}/ckut.list")
  else
    URL="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL:0:1}.x/linux-${KERNEL}.tar.xz"
  fi
  if [[ "${skip}" -eq 1  ]]; then
    unset skip
  else
    cd "${DOWNLOAD_LOCATION}" || return
    "${DOWNLOAD[@]}" "${URL}" 2>&1 |                              \
      grep "%" | sed -u -e "s,\.,,g" | awk '{print $2}' |         \
      sed -u -e "s,\%,,g" | dialog --backtitle "${TITLE}" --title \
      "Downloading linux-${KERNEL} to ${DOWNLOAD_LOCATION}"       \
      --gauge "Linux ${KERNEL}" "${HEIGHT}" "${WIDTH}"
    echo "${DOWNLOAD[*]} ${URL}" >> "${TMPDIR}/ckut.log"
  fi
}

# Extract the kernel
extract_kernel() {
  if [[ -d ${DOWNLOAD_LOCATION}/linux-${KERNEL} ]]; then
    MESSAGE="Already extracted. Would you like to skip this step? Warning: \
      selecting [ No ] will cause the removal of the existing folder"
    dialog --yesno "${MESSAGE}"  "${HEIGHT}" "${WIDTH}" && skip=1
    if [[ "${skip}" -eq 1  ]]; then
      :
    else
      rm -r ${DOWNLOAD_LOCATION}/linux-${KERNEL} &&                              \
      echo "rm -rf ${DOWNLOAD_LOCATION}/linux-${KERNEL}" >> "${TMPDIR}/ckut.log"
      cd /usr/src/ || return
      MESSAGE4="Extracting linux-${KERNEL} to ${DOWNLOAD_LOCATION}"
      (pv -n "${DOWNLOAD_LOCATION}/linux-${KERNEL}.tar.xz" |                              \
        tar -J -xf -)2>&1 | dialog --backtitle "${TITLE}"                                 \
                                   --title "${MESSAGE4}"                                  \
                                   --gauge "Please wait..." 10 70 0 &&                    \
        echo "tar -xf ${DOWNLOAD_LOCATION}/linux-${KERNEL}.tar.xz" >> "${TMPDIR}/ckut.log"
    fi
  else
    cd /usr/src/ || return
    MESSAGE4="Extracting linux-${KERNEL} to ${DOWNLOAD_LOCATION}"
    (pv -n "${DOWNLOAD_LOCATION}/linux-${KERNEL}.tar.xz" |        \
      tar -J -xf -)2>&1 | dialog --backtitle "${TITLE}"           \
                                 --title "${MESSAGE4}"            \
                                 --gauge "Please wait..." 10 70 0 
      echo "tar -xf ${DOWNLOAD_LOCATION}/linux-${KERNEL}.tar.xz" >> "${TMPDIR}/ckut.log"
  fi
}

# Compile the kernel
compile_kernel() {
  cd "/usr/src/linux-${KERNEL}" || return
  clear
  make "${MAKEFLAGS[@]}" all
  { echo -e "make ${MAKEFLAGS[*]} all"
  } >> "${TMPDIR}/ckut.log"
  read -n 1 -r -s -p $'Press enter to continue...'
}

# Install the kernel
install_kernel() {
  cd "/usr/src/linux-${KERNEL}" || return
  clear
  make "${MAKEFLAGS[@]}" modules_install
  { echo -e "make ${MAKEFLAGS[*]} modules_install"
  } >> "${TMPDIR}/ckut.log"
  read -n 1 -r -s -p $'Press enter to continue...'
  check_localversion 
  dialog --prgbox "cp -v arch/$(uname -m)/boot/bzImage                 \
          \"${KERNEL_LOCATION}/vmlinuz-${KERNEL}${LOCALVERSION}\" ;    \
          cp -v System.map                                             \
          \"${KERNEL_LOCATION}/System.map-${KERNEL}${LOCALVERSION}\" ; \
          cp -v .config                                                \
          \"${KERNEL_LOCATION}/config-${KERNEL}${LOCALVERSION}\"" 10 90
  { echo -e "cp bzImage ${KERNEL_LOCATION}/vmlinuz-${KERNEL}${LOCALVERSION}"
    echo -e "cp System.map ${KERNEL_LOCATION}/System.map-${KERNEL}${LOCALVERSION}"
    echo -e "cp .config ${KERNEL_LOCATION}/config-${KERNEL}${LOCALVERSION}"
  } >> "${TMPDIR}/ckut.log"
}

# Download the web-page https://www.kernel.org then pipe the latest versions
# and URLs into ckut.list with the format <version> <url>
download_list() {
  for list in $(curl -s https://www.kernel.org |                \
    grep -Po 'href="\K.*?z(?=")' |                              \
    grep -v patch |                                             \
    sort -ur); do v=${list##*\x-} ; v=${v%%.tar*} ;             \
    echo -n "$v $(printf ' %.0s' {0..10})" |                    \
    head -c 10 ; echo " ${list}" ; done > "${TMPDIR}/ckut.list"
}

# If the editor in the configuration file doesn't exist 
# then fall back to one that does exist as a failsafe
failsafe_editor() {
if [[ ! -x "${EDITOR}" ]]; then
  echo "ERROR: Selected editor doesn't exist" >> "${TMPDIR}/ckut.log"
  E=(vim vi nano emacs ed)
  for i in "${E[@]}";do
    if [ -n "$(command -v ${i})" ];then
      EDITOR="$(which ${i})"
      break
    fi
  done
fi
}
failsafe_editor

# Have a look to see what programs the system may have installed
# This way the menu doesn't display the missing program features
if [[ -x /usr/bin/dracut ]]; then
  DRACUT_MENU="d Dracut"
fi

if [[ -x /usr/sbin/grub-mkconfig ]]; then
  GRUB_MENU="g Grub"
fi

if [[ -x /sbin/lilo ]]; then
  LILO_MENU="l Lilo"
fi

if [[ -x /usr/bin/syslinux ]]; then
  SYSLINUX_MENU="s Syslinux"
fi

if [[ -x /usr/bin/lynx ]]; then
  LYNX_MENU="w www.kernel.org"
fi

# First menu the main page
while true; do
  exec 3>&1
  selection=$(dialog --clear                                                     \
                     --backtitle "${TITLE}"                                      \
                     --title "${KERNEL_OLD}"                                     \
                     --cancel-label "Exit"                                       \
                     --menu "\n${MESSAGE1} [${KERNEL}]" "${HEIGHT}" "${WIDTH}" 9 \
                     v " Kernel Version [${KERNEL}]"                             \
                     o " Manual Kernel Version"                                  \
                     d " Download"                                               \
                     e " Extract"                                                \
                     p " Prepare"                                                \
                     m " Run Menuconfig"                                         \
                     c " Compile"                                                \
                     i " Install"                                                \
                     l " Command Log"                                            \
                     x " Expert Menu"                                            \
                     q " Exit"                                                   \
                     2>&1 1>&3)
  exit_status=$?
  exec 3>&-
  case $exit_status in
    "${DIALOG_CANCEL}")
      clear
      echo "Program terminated."
      exit
    ;;
    "${DIALOG_ESC}")
      clear
      echo "Program aborted." >&2
      exit 1
    ;;
  esac
  case ${selection} in
    0 )
      clear
      echo "Program terminated."
    ;;
    v )
      # Check if we have already downloaded the list. If not we grab a copy
      if [[ ! -f "${TMPDIR}/ckut.list" ]]; then
        download_list
      fi
      # Here we take ckut.list file and make it into an array so that we can
      # use the kernel versions we obtained above and place them in a nice
      # menu list
      while true; do
        declare -a array
        i=1
        j=1
        while read -r line; do
          exec 3>&1
          array[ $i ]=$j
          (( j++ ))
          array[ ($i + 1) ]=$line
          (( i=(i+2) ))
        done < <(awk '{print $1 }' "${TMPDIR}/ckut.list" )
        MESSAGE2="Select a kernel version"
        selection=$(dialog --clear                                         \
                           --backtitle "${TITLE}"                          \
                           --title "${KERNEL_OLD}"                         \
                           --menu "\n${MESSAGE2}" "${HEIGHT}" "${WIDTH}" 9 \
                           "${array[@]}"                                   \
                           r "Refresh"                                     \
                           2>&1 1>&3) 
        exec 3>&-
        case ${selection} in
          r )
            download_list
          ;;
          [0-9]* )
            if [[ -n "${selection}" ]]; then
              KERNEL="$(sed -n "${selection}p" "${TMPDIR}/ckut.list"| awk '{print $1 }')"
              break
            fi
          ;;
          * )
            if [[ -z "${selection}" ]]; then
              break
            fi
          ;;
        esac
      done
    ;;
    # Just in case we wish to use an older version of the kernel we
    # can now manually input it in here
    o )
      MESSAGE3="Enter a kernel version"
      KERNEL=$(dialog --stdout                                           \
                      --backtitle "${TITLE}"                             \
                      --title "${KERNEL_OLD}"                            \
                      --inputbox "\n${MESSAGE3}" "${HEIGHT}" "${WIDTH}")
      if [ -z "${KERNEL}" ]; then
        KERNEL="NONE"
        unset manual
      else
        manual="1"
      fi
    ;;
    # This is where we download the actual kernel if it has been selected
    d )
      if check_kernel && [[ "${error}" -eq 1 ]]; then
        :
      else
        download_kernel && check_download
      fi
    ;;
    # Extract the kernel if it exists
    e )
      if check_kernel && [[ "${error}" -eq 1 ]]; then
        :
      elif
        check_archive && [[  "${error}" -eq 1 ]]; then
          :
      else
        unset skip
        extract_kernel
      fi
    ;;
    # Prepare the kernel as in make mrproper and if exists copy the appropriate
    # configuration over to the kernel we plan to build
    p )
      if check_kernel && [[ "${error}" -eq 1 ]]; then
        :
      elif
        check_folder && [[  "${error}" -eq 1 ]]; then
          :
      else
        check_kernelconfig
      fi
    ;;
    # The option to run make menuconfig in the case that the kernel may need
    # to be tweaked
    m )
      if check_kernel && [[ "${error}" -eq 1 ]]; then
        :
      elif
        check_folder && [[  "${error}" -eq 1 ]]; then
        :
      else
        cd "/usr/src/linux-${KERNEL}" || return
        clear
        make "${MAKEFLAGS[@]}" menuconfig
        echo "make ${MAKEFLAGS[*]} menuconfig" >> "${TMPDIR}/ckut.log"
      fi
    ;;
    # The actual compilation of the kernel is here.
    c )
      if check_kernel && [[ "${error}" -eq 1 ]]; then
        :
      elif
        check_folder && [[  "${error}" -eq 1 ]]; then
        :
      else
        compile_kernel
      fi
    ;;
    # Attempt to install the modules, kernel, System.map and configuration
    # files to the place where the bootable kernel should be located
    i )
      if check_kernel && [[ "${error}" -eq 1 ]]; then
        :
      elif
        check_folder && [[  "${error}" -eq 1 ]]; then
        :
      else
        install_kernel
      fi
    ;;
    # Show a list of all the commands that were run during the install
    l )
      dialog --no-shadow                          \
             --backtitle "${TITLE}"               \
             --title "Command Log"                \
             --scrolltext                         \
             --textbox "${TMPDIR}/ckut.log" 18 78
    ;;
    # Open an advanced menu with a couple of extra features added. Mostly for
    # myself but can be expanded upon in the future.
    x )
      while true; do
        exec 3>&1
        selection=$(dialog --clear                                                     \
                           --backtitle "${TITLE}"                                      \
                           --title "${KERNEL_OLD} - Expert Menu"                       \
                           --cancel-label "Exit"                                       \
                           --menu "\n${MESSAGE1} [${KERNEL}]" "${HEIGHT}" "${WIDTH}" 9 \
                           e "Run Everything"                                          \
                           ${DRACUT_MENU}                                              \
                           b "Boot Loader Menu"                                        \
                           l "Command Log"                                             \
                           c "Configure CKUT"                                          \
                           r "Reload Configuration"                                    \
                           ${LYNX_MENU}                                                \
                           2>&1 1>&3)
        exec 3>&-
        case ${selection} in
          # Run the command lynx to open the Linux kernel website
          w )
            export LYNX_SAVE_SPACE="${DOWNLOAD_LOCATION}"
            lynx "https://www.kernel.org/"
            unset LYNX_SAVE_SPACE
          ;;
          # For the lazy who know exactly what they need. This will run most of the kernel
          # compilation as well as download and extract it
          e )
            MESSAGE="This feature will download, extract, prepare, compile and               \
              install the kernel with almost no human intervention. You are expected         \
              to have a working configuration located either in /usr/src/linux-${KERNEL_OLD} \
              or as ${KERNEL_LOCATION}/config-${KERNEL_OLD}, otherwise it will               \
              continue without it. Proceed only if you know what you are doing"
            dialog --yes-label "Continue"                                         \
                   --no-label "Abort"                                             \
                   --backtitle "${TITLE}"                                         \
                   --title "Warning!"                                             \
                   --yesno "${MESSAGE}" "${HEIGHT}" "${WIDTH}" && check_kernel && \
            if [[ "${error}" -eq 1 ]]; then
              :
            else
              download_kernel && check_download
              extract_kernel
              cd "/usr/src/linux-${KERNEL}" || return
              clear
              make "${MAKEFLAGS[@]}" mrproper
              echo -e "make ${MAKEFLAGS[*]} mrproper" >> "${TMPDIR}/ckut.log"
              check_kernelconfig
              make "${MAKEFLAGS[@]}" menuconfig
                compile_kernel && install_kernel
            fi
          ;;
          # Run dracut to create an initrd if used
          d )
            if [[ -x /usr/bin/dracut ]]; then
              clear
              check_localversion
              unset skip
              if [[ -f "${KERNEL_LOCATION}/initramfs-${KERNEL}${LOCALVERSION}.img" ]]; then
                MESSAGE="The image exists already. Would you like to skip this step?"
                dialog --yesno "${MESSAGE}"  "${HEIGHT}" "${WIDTH}" && skip=1
                if [[ ! "${skip}" -eq 1  ]]; then
                  dracut --force --kver "${KERNEL}${LOCALVERSION}"              \
                    "${KERNEL_LOCATION}/initramfs-${KERNEL}${LOCALVERSION}.img"
                  read -n 1 -r -s -p $'Press enter to continue...'
                  { echo -ne "dracut --force --kver ${KERNEL}${LOCALVERSION}"
                    echo -e " ${KERNEL_LOCATION}/initramfs-${KERNEL}${LOCALVERSION}.img"
                  } >> "${TMPDIR}/ckut.log"
                fi
              else
                dracut --kver "${KERNEL}${LOCALVERSION}"                      \
                  "${KERNEL_LOCATION}/initramfs-${KERNEL}${LOCALVERSION}.img"
                read -n 1 -r -s -p $'Press enter to continue...'
                { echo -ne "dracut --kver ${KERNEL}${LOCALVERSION}"
                  echo -e " ${KERNEL_LOCATION}/initramfs-${KERNEL}${LOCALVERSION}.img"
                } >> "${TMPDIR}/ckut.log"
              fi
            fi
          ;;
          # Edit the configuration file for ckut
          c ) 
            "${EDITOR}" "${CONFIG}"
            echo "${EDITOR} ${CONFIG}" >> "${TMPDIR}/ckut.log"
            unset skip
            MESSAGE="Reload the new settings?"
            dialog --yesno "${MESSAGE}"  "${HEIGHT}" "${WIDTH}" && skip=1
            if [[ "${skip}" -eq 1  ]]; then
              # Load configuration file
              . ${CONFIG}
              echo ". ${CONFIG} " >> "${TMPDIR}/ckut.log"
              # Convert MAKEFLAGS and DOWNLOAD into an array
              eval MAKEFLAGS="($MAKEFLAGS)"
              eval DOWNLOAD="(${DOWNLOAD_PROG} ${DOWNLOAD_FLAGS})"
              failsafe_editor
            else
              :
            fi
          ;;
          # Show a list of all the commands that were run during the install
          l )
            dialog --no-shadow                          \
                   --backtitle "${TITLE}"               \
                   --title "Command Log"                \
                   --scrolltext                         \
                   --textbox "${TMPDIR}/ckut.log" 18 78
          ;;
          # Reload the configuration file
          r )
            . ${CONFIG}
            echo ". ${CONFIG} " >> "${TMPDIR}/ckut.log"
            # Convert MAKEFLAGS and DOWNLOAD into an array
            eval MAKEFLAGS="($MAKEFLAGS)"
            eval DOWNLOAD="(${DOWNLOAD_PROG} ${DOWNLOAD_FLAGS})"
          ;;
          # I use syslinux and nothing else so I have added this feature for my own reasons.
          # However, the option to edit grub and lilo have also been added.
          b )
            while true; do
              exec 3>&1
              selection=$(dialog --clear                                                     \
                                 --backtitle "${TITLE}"                                      \
                                 --title "${KERNEL_OLD} - Boot Loader Menu"                  \
                                 --cancel-label "Exit"                                       \
                                 --menu "\n${MESSAGE1} [${KERNEL}]" "${HEIGHT}" "${WIDTH}" 9 \
                                 ${GRUB_MENU}                                                \
                                 ${LILO_MENU}                                                \
                                 ${SYSLINUX_MENU}                                            \
                               2>&1 1>&3)
              exec 3>&-
              case ${selection} in
                g )
                  while true; do
                    exec 3>&1
                    selection=$(dialog --clear                                                    \
                                       --backtitle "${TITLE}"                                     \
                                       --title "${KERNEL_OLD} - Boot Loader Menu"                 \
                                       --cancel-label "Exit"                                      \
                                       --menu "\n${MESSAGE} [${KERNEL}]" "${HEIGHT}" "${WIDTH}" 9 \
                                       b "Edit /boot/grub/grub.cfg"                               \
                                       g "Run grub-mkconfig"                                      \
                                       2>&1 1>&3)
                    exec 3>&-
                    case ${selection} in
                      b )
                        if [[ ! -d /boot/grub ]]; then
                          mkdir -p /boot/grub
                          echo "mkdir -p /boot/grub" >> "${TMPDIR}/ckut.log"
                        fi
                          "${EDITOR}" /boot/grub/grub.cfg
                          echo "${EDITOR} /boot/grub/grub.cfg" >> "${TMPDIR}/ckut.log"
                      ;;
                      g )
                        dialog --clear                                                         \
                               --backtitle "${TITLE}"                                          \
                               --title "Please wait ..."                                       \
                               --prgbox "/usr/sbin/grub-mkconfig -o /boot/grub/grub.cfg" 30 90
                        echo "/usr/sbin/grub-mkconfig -o \
                              /boot/grub/grub.cfg" >> "${TMPDIR}/ckut.log"
                      ;;
                      * )
                        if [[ -z "${selection}" ]]; then
                           break
                        fi
                      ;;
                    esac
                  done
                ;;
                l )
                  while true; do
                    exec 3>&1
                    selection=$(dialog --clear                                                    \
                                       --backtitle "${TITLE}"                                     \
                                       --title "${KERNEL_OLD} - Boot Loader Menu"                 \
                                       --cancel-label "Exit"                                      \
                                       --menu "\n${MESSAGE} [${KERNEL}]" "${HEIGHT}" "${WIDTH}" 9 \
                                       e "Edit /etc/lilo.conf"                                    \
                                       l "Run lilo"                                               \
                                       2>&1 1>&3)
                     exec 3>&-
                     case ${selection} in
                       e )
                         if [[ -f /etc/lilo.conf ]]; then
                           "${EDITOR}" /etc/lilo.conf
                           echo "${EDITOR} /etc/lilo.conf" >> "${TMPDIR}/ckut.log"
                         fi
                       ;;
                       l )
                         dialog --clear                          \
                                --backtitle "${TITLE}"           \
                                --title "Please wait ..."        \
                                --prgbox "/sbin/lilo -v 2" 30 90
                         echo "/sbin/lilo" >> "${TMPDIR}/ckut.log"
                       ;;
                       * )
                         if [[ -z "${selection}" ]]; then
                           break
                         fi
                       ;;
                     esac
                  done
                ;;
                s )
                  if [[ ! -d "${SYSLINUX_LOCATION}" ]]; then
                    mkdir -p "${SYSLINUX_LOCATION}"
                    echo "mkdir -p ${SYSLINUX_LOCATION}" >> "${TMPDIR}/ckut.log"
                  fi
                    "${EDITOR}" ${SYSLINUX_LOCATION}/syslinux.cfg
                    echo "${EDITOR} ${SYSLINUX_LOCATION}/syslinux.cfg" >> "${TMPDIR}/ckut.log"
                ;;
                * )
                  if [[ -z "${selection}" ]]; then
                    break
                  fi
                ;;
              esac
            done
          ;;
          * )
            if [[ -z "${selection}" ]]; then
              break
            fi
          ;;
        esac
      done
    ;;
    # Exit the program
    q ) 
      exit 0 
    ;;
  esac
done
