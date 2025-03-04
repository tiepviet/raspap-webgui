raspap_dir="/etc/raspap"
raspap_user="www-data"
version=`sed 's/\..*//' /etc/debian_version`

# Determine version, set default home location for lighttpd and 
# php package to install 
webroot_dir="/var/www/html" 
if [ $version -eq 9 ]; then 
    version_msg="Raspian 9.0 (Stretch)" 
    php_package="php7.0-cgi" 
elif [ $version -eq 8 ]; then 
    version_msg="Raspian 8.0 (Jessie)" 
    php_package="php5-cgi" 
else 
    version_msg="Raspian earlier than 8.0 (Wheezy)"
    webroot_dir="/var/www" 
    php_package="php5-cgi" 
fi

phpcgiconf=""
if [ "$php_package" = "php7.0-cgi" ]; then
    phpcgiconf="/etc/php/7.0/cgi/php.ini"
elif [ "$php_package" = "php5-cgi" ]; then
    phpcgiconf="/etc/php5/cgi/php.ini"
fi

# Outputs a RaspAP Install log line
function install_log() {
    echo -e "\033[1;32mRaspAP Install: $*\033[m"
}

# Outputs a RaspAP Install Error log line and exits with status code 1
function install_error() {
    echo -e "\033[1;37;41mRaspAP Install Error: $*\033[m"
    exit 1
}

# Outputs a RaspAP Warning line
function install_warning() {
    echo -e "\033[1;33mWarning: $*\033[m"
}

# Outputs a welcome message
function display_welcome() {
    raspberry='\033[0;35m'
    green='\033[1;32m'

    echo -e "${raspberry}\n"
    echo -e " 888888ba                              .d888888   888888ba" 
    echo -e " 88     8b                            d8     88   88     8b" 
    echo -e "a88aaaa8P' .d8888b. .d8888b. 88d888b. 88aaaaa88a a88aaaa8P" 
    echo -e " 88    8b. 88    88 Y8ooooo. 88    88 88     88   88" 
    echo -e " 88     88 88.  .88       88 88.  .88 88     88   88" 
    echo -e " dP     dP  88888P8  88888P  88Y888P  88     88   dP" 
    echo -e "                             88"                             
    echo -e "                             dP"                             
    echo -e "${green}"
    echo -e "The Quick Installer will guide you through a few easy steps\n\n"
}

### NOTE: all the below functions are overloadable for system-specific installs
### NOTE: some of the below functions MUST be overloaded due to system-specific installs

function config_installation() {
    install_log "Configure installation"
    echo "Detected ${version_msg}" 
    echo "Install directory: ${raspap_dir}"
    echo "Lighttpd directory: ${webroot_dir}"
    echo -n "Complete installation with these values? [y/N]: "
    read answer
    if [[ $answer != "y" ]]; then
        echo "Installation aborted."
        exit 0
    fi
}

# Runs a system software update to make sure we're using all fresh packages
function update_system_packages() {
    # OVERLOAD THIS
    install_error "No function definition for update_system_packages"
}

# Installs additional dependencies using system package manager
function install_dependencies() {
    # OVERLOAD THIS
    install_error "No function definition for install_dependencies"
}

# Enables PHP for lighttpd and restarts service for settings to take effect
function enable_php_lighttpd() {
    install_log "Enabling PHP for lighttpd"

    sudo lighttpd-enable-mod fastcgi-php    
    sudo service lighttpd force-reload
    sudo /etc/init.d/lighttpd restart || install_error "Unable to restart lighttpd"
}

# Verifies existence and permissions of RaspAP directory
function create_raspap_directories() {
    install_log "Creating RaspAP directories"
    if [ -d "$raspap_dir" ]; then
        sudo mv $raspap_dir "$raspap_dir.`date +%F-%R`" || install_error "Unable to move old '$raspap_dir' out of the way"
    fi
    sudo mkdir -p "$raspap_dir" || install_error "Unable to create directory '$raspap_dir'"

    # Create a directory for existing file backups.
    sudo mkdir -p "$raspap_dir/backups"

    # Create a directory to store networking configs
    sudo mkdir -p "$raspap_dir/networking"
    # Copy existing dhcpcd.conf to use as base config
    cat /etc/dhcpcd.conf | sudo tee -a /etc/raspap/networking/defaults

    sudo chown -R $raspap_user:$raspap_user "$raspap_dir" || install_error "Unable to change file ownership for '$raspap_dir'"
}

# Generate hostapd logging and service control scripts
function create_hostapd_scripts() {
    install_log "Creating hostapd logging & control scripts"
    sudo mkdir $raspap_dir/hostapd || install_error "Unable to create directory '$raspap_dir/hostapd'"

    # Move logging shell scripts 
    sudo mv "$webroot_dir/installers/"*log.sh "$raspap_dir/hostapd" || install_error "Unable to move logging scripts"
    # Move service control shell scripts
    sudo mv "$webroot_dir/installers/"service*.sh "$raspap_dir/hostapd" || install_error "Unable to move service control scripts"
    # Make enablelog.sh and disablelog.sh not writable by www-data group.
    sudo chown -c root:"$raspap_user" "$raspap_dir/hostapd/"*.sh || install_error "Unable change owner and/or group."
    sudo chmod 750 "$raspap_dir/hostapd/"*.sh || install_error "Unable to change file permissions."
}


# Fetches latest files from github to webroot
function download_latest_files() {
    if [ -d "$webroot_dir" ]; then
        sudo mv $webroot_dir "$webroot_dir.`date +%F-%R`" || install_error "Unable to remove old webroot directory"
    fi

    install_log "Cloning latest files from github"
    git clone --depth 1 https://github.com/tiepviet/raspap-webgui /tmp/raspap-webgui || install_error "Unable to download files from github"
    sudo mv /tmp/raspap-webgui $webroot_dir || install_error "Unable to move raspap-webgui to web root"

    # Move icons to webroot
    echo -n "Installing high-res favicons"
    sudo mv $webroot_dir/dist/icons/* $webroot_dir || install_error "Unable to move icons to web root"
}

# Sets files ownership in web root directory
function change_file_ownership() {
    if [ ! -d "$webroot_dir" ]; then
        install_error "Web root directory doesn't exist"
    fi

    install_log "Changing file ownership in web root directory"
    sudo chown -R $raspap_user:$raspap_user "$webroot_dir" || install_error "Unable to change file ownership for '$webroot_dir'"
}

# Check for existing /etc/network/interfaces and /etc/hostapd/hostapd.conf files
function check_for_old_configs() {
    if [ -f /etc/network/interfaces ]; then
        sudo cp /etc/network/interfaces "$raspap_dir/backups/interfaces.`date +%F-%R`"
        sudo ln -sf "$raspap_dir/backups/interfaces.`date +%F-%R`" "$raspap_dir/backups/interfaces"
    fi

    if [ -f /etc/hostapd/hostapd.conf ]; then
        sudo cp /etc/hostapd/hostapd.conf "$raspap_dir/backups/hostapd.conf.`date +%F-%R`"
        sudo ln -sf "$raspap_dir/backups/hostapd.conf.`date +%F-%R`" "$raspap_dir/backups/hostapd.conf"
    fi

    if [ -f /etc/dnsmasq.conf ]; then
        sudo cp /etc/dnsmasq.conf "$raspap_dir/backups/dnsmasq.conf.`date +%F-%R`"
        sudo ln -sf "$raspap_dir/backups/dnsmasq.conf.`date +%F-%R`" "$raspap_dir/backups/dnsmasq.conf"
    fi

    if [ -f /etc/dhcpcd.conf ]; then
        sudo cp /etc/dhcpcd.conf "$raspap_dir/backups/dhcpcd.conf.`date +%F-%R`"
        sudo ln -sf "$raspap_dir/backups/dhcpcd.conf.`date +%F-%R`" "$raspap_dir/backups/dhcpcd.conf"
    fi

    if [ -f /etc/rc.local ]; then
        sudo cp /etc/rc.local "$raspap_dir/backups/rc.local.`date +%F-%R`"
        sudo ln -sf "$raspap_dir/backups/rc.local.`date +%F-%R`" "$raspap_dir/backups/rc.local"
    fi
}

# Move configuration file to the correct location
function move_config_file() {
    if [ ! -d "$raspap_dir" ]; then
        install_error "'$raspap_dir' directory doesn't exist"
    fi

    install_log "Moving configuration file to '$raspap_dir'"
    sudo mv "$webroot_dir"/raspap.php "$raspap_dir" || install_error "Unable to move files to '$raspap_dir'"
    sudo chown -R $raspap_user:$raspap_user "$raspap_dir" || install_error "Unable to change file ownership for '$raspap_dir'"
}

# Set up default configuration
function default_configuration() {
    install_log "Setting up hostapd"
    if [ -f /etc/default/hostapd ]; then
        sudo mv /etc/default/hostapd /tmp/default_hostapd.old || install_error "Unable to remove old /etc/default/hostapd file"
    fi
    sudo mv $webroot_dir/config/default_hostapd /etc/default/hostapd || install_error "Unable to move hostapd defaults file"
    sudo mv $webroot_dir/config/hostapd.conf /etc/hostapd/hostapd.conf || install_error "Unable to move hostapd configuration file"
    sudo mv $webroot_dir/config/dnsmasq.conf /etc/dnsmasq.conf || install_error "Unable to move dnsmasq configuration file"
    sudo mv $webroot_dir/config/dhcpcd.conf /etc/dhcpcd.conf || install_error "Unable to move dhcpcd configuration file"

    # Generate required lines for Rasp AP to place into rc.local file.
    # #RASPAP is for removal script
    lines=(
    'echo 1 > \/proc\/sys\/net\/ipv4\/ip_forward #RASPAP'
    'iptables -t nat -A POSTROUTING -j MASQUERADE #RASPAP'
    'iptables -t nat -A POSTROUTING -s 192.168.50.0\/24 ! -d 192.168.50.0\/24 -j MASQUERADE #RASPAP'
    )
    
    for line in "${lines[@]}"; do
        if grep "$line" /etc/rc.local > /dev/null; then
            echo "$line: Line already added"
        else
            sudo sed -i "s/^exit 0$/$line\nexit 0/" /etc/rc.local
            echo "Adding line $line"
        fi
    done

    # Force a reload of new settings in /etc/rc.local
    sudo systemctl restart rc-local.service
    sudo systemctl daemon-reload

    # Install and enable RaspAP daemon
    echo -n "Enable RaspAP control service (Recommended)? [Y/n]: "
    read answer
    if [ "$answer" != 'n' ] && [ "$answer" != 'N' ]; then
        echo -n "Enabling RaspAP daemon. Disable with: sudo systemctl disable raspap.service"
        sudo mv $webroot_dir/installers/raspap.service /lib/systemd/system/ || install_error "Unable to move raspap.service file"
        sudo systemctl enable raspap.service || install_error "Failed to enable raspap.service"
    fi
}

# Add a single entry to the sudoers file
function sudo_add() {
    sudo bash -c "echo \"www-data ALL=(ALL) NOPASSWD:$1\" | (EDITOR=\"tee -a\" visudo)" \
        || install_error "Unable to patch /etc/sudoers"
}

# Adds www-data user to the sudoers file with restrictions on what the user can execute
function patch_system_files() {
    # add symlink to prevent wpa_cli cmds from breaking with multiple wlan interfaces
    install_log "symlinked wpa_supplicant hooks for multiple wlan interfaces"
    sudo ln -s /usr/share/dhcpcd/hooks/10-wpa_supplicant /etc/dhcp/dhclient-enter-hooks.d/
    # Set commands array
    cmds=(
        "/sbin/ifdown"
        "/sbin/ifup"
        "/bin/cat /etc/wpa_supplicant/wpa_supplicant.conf"
        "/bin/cat /etc/wpa_supplicant/wpa_supplicant-wlan[0-9].conf"
        "/bin/cp /tmp/wifidata /etc/wpa_supplicant/wpa_supplicant.conf"
        "/bin/cp /tmp/wifidata /etc/wpa_supplicant/wpa_supplicant-wlan[0-9].conf"
        "/sbin/wpa_cli -i wlan[0-9] scan_results"
        "/sbin/wpa_cli -i wlan[0-9] scan"
        "/sbin/wpa_cli -i wlan[0-9] reconfigure"
        "/sbin/wpa_cli -i wlan[0-9] select_network"
        "/bin/cp /tmp/hostapddata /etc/hostapd/hostapd.conf"
        "/etc/init.d/hostapd start"
        "/etc/init.d/hostapd stop"
        "/etc/init.d/dnsmasq start"
        "/etc/init.d/dnsmasq stop"
        "/bin/cp /tmp/dhcpddata /etc/dnsmasq.conf"
        "/bin/cp /tmp/dhcpddata /etc/dhcpcd.conf"
        "/sbin/shutdown -h now"
        "/sbin/reboot"
        "/sbin/ip link set wlan[0-9] down"
        "/sbin/ip link set wlan[0-9] up"
        "/sbin/ip -s a f label wlan[0-9]"
        "/bin/cp /etc/raspap/networking/dhcpcd.conf /etc/dhcpcd.conf"
        "/etc/raspap/hostapd/enablelog.sh"
        "/etc/raspap/hostapd/disablelog.sh"
        "/etc/raspap/hostapd/servicestart.sh"
    )

    # Check if sudoers needs patching
    if [ $(sudo grep -c www-data /etc/sudoers) -ne 28 ]
    then
        # Sudoers file has incorrect number of commands. Wiping them out.
        install_log "Cleaning sudoers file"
        sudo sed -i '/www-data/d' /etc/sudoers
        install_log "Patching system sudoers file"
        # patch /etc/sudoers file
        for cmd in "${cmds[@]}"
        do
            sudo_add $cmd
            IFS=$'\n'
        done
    else
        install_log "Sudoers file already patched"
    fi

    # Unmask and enable hostapd.service
    sudo systemctl unmask hostapd.service
    sudo systemctl enable hostapd.service
}


# Optimize configuration of php-cgi.
function optimize_php() {
    install_log "Optimize PHP configuration"
    if [ ! -f "$phpcgiconf" ]; then
        install_warning "PHP configuration could not be found."
        return
    fi

    # Backup php.ini and create symlink for restoring.
    datetimephpconf=$(date +%F-%R)
    sudo cp "$phpcgiconf" "$raspap_dir/backups/php.ini.$datetimephpconf"
    sudo ln -sf "$raspap_dir/backups/php.ini.$datetimephpconf" "$raspap_dir/backups/php.ini"

    echo -n "Enable HttpOnly for session cookies (Recommended)? [Y/n]: "
    read answer
    if [ "$answer" != 'n' ] && [ "$answer" != 'N' ]; then
        echo "Php-cgi enabling session.cookie_httponly."
        sudo sed -i -E 's/^session\.cookie_httponly\s*=\s*(0|([O|o]ff)|([F|f]alse)|([N|n]o))\s*$/session.cookie_httponly = 1/' "$phpcgiconf"
    fi

    if [ "$php_package" = "php7.0-cgi" ]; then
        echo -n "Enable PHP OPCache (Recommended)? [Y/n]: "
        read answer
        if [ "$answer" != 'n' ] && [ "$answer" != 'N' ]; then
            echo "Php-cgi enabling opcache.enable."
            sudo sed -i -E 's/^;?opcache\.enable\s*=\s*(0|([O|o]ff)|([F|f]alse)|([N|n]o))\s*$/opcache.enable = 1/' "$phpcgiconf"
            # Make sure opcache extension is turned on.
            if [ -f "/usr/sbin/phpenmod" ]; then
                sudo phpenmod opcache
            else
                install_warning "phpenmod not found."
            fi
        fi
    fi
}

function install_complete() {
    install_log "Installation completed!"

    # Prompt to reboot if wired ethernet (eth0) is connected.
    # With default_configuration this will create an active AP on restart.
    if ip a | grep -q ': eth0:.*state UP'; then
        echo -n "The system needs to be rebooted as a final step. Reboot now? [y/N]: "
        read answer
        if [[ $answer != "y" ]]; then
            echo "Installation reboot aborted."
            exit 0
        fi
        sudo shutdown -r now || install_error "Unable to execute shutdown"
    fi
}

function install_raspap() {
    display_welcome
    config_installation
    update_system_packages
    install_dependencies
    optimize_php
    enable_php_lighttpd
    create_raspap_directories
    check_for_old_configs
    download_latest_files
    change_file_ownership
    create_hostapd_scripts
    move_config_file
    default_configuration
    patch_system_files
    install_complete
}
