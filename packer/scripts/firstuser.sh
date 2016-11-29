#!/bin/bash
# Script to create the first user using localhost exception method.
# An authenticated https endpont must be defined and enabled
# in /opt/monorail/config.json
#
HTTP_URL=http://localhost:8080
HTTPS_URL=https://localhost:8443

# defaults
USER="admin"
PASS="admin123"
login() {
   echo `curl -k ${HTTPS_URL}/login -X POST \
        -H 'Content-Type:application/json' \
        -d '{"username": "'"${USER}"'", "password":"'"${PASS}"'"}'`
}


##########################################################
# retrieve NIC name via ```ip addr``` command, by given id
##########################################################
get_nic_name_by_index()
{
    tmp=$( ip addr|grep "^${1}:" | awk '{print $2}')
    if [[ "$tmp" == "" ]];
    then
        echo "[Error]: Invalid Parameter passed to get_nic_name_by_index(): NIC ID=$1";
        exit 1
    fi
    name=${tmp/:/}  # remove the ":" surrfix
    echo $name
}

#################################
# retrieve secondary NIC Name(control port of RackHD)
################################
get_secondary_nic_name()
{
    # By Default, the Control Port index is 3. say: eth1/enp0s8/ens33...
    Sec_NIC_Index=3;
    # if the index 1 is not loopback device, then eth0 may starts from index 1.
    NIC1=$(get_nic_name_by_index 1)
    if [[ $NIC1 != "lo" ]]; then
        Sec_NIC_Index=$(expr $Sec_NIC_Index - 1 )
    fi
    Sec_NIC=$(get_nic_name_by_index $Sec_NIC_Index)
    echo $Sec_NIC
}




# Include the on-* services in case we're installing from .deb packages
SERVICES="isc-dhcp-server rabbitmq-server mongodb postgresql \
    on-http on-taskgraph on-dhcp-proxy on-syslog on-tftp"
RACKHD_SERVICES="on-http on-taskgraph on-dhcp-proxy on-syslog on-tftp"

cleanServicesPIDs() {
    for srv in ${RACKHD_SERVICES}; do
        sudo rm /var/run/${srv}.pid -f
    done
    echo "PIDs cleaned"
}

startServices() {

  secondary_nic=$(get_secondary_nic_name)
  # Config the Secondary NIC IP to align with the default /opt/monorail/config.json IP setting
  sudo ifconfig $secondary_nic 172.31.128.1 netmask 255.255.255.0

  for srv in ${SERVICES}; do
    sudo service ${srv} start
  done
  # if installed from src code, assuming the code are in ~/src directory.then use PM2 to start RackHD
  if [ -d ~/src ]; then
    cd ~
    pids=`pidof node`
    if [ `expr length "$pids"` -eq "0" ]; then
       echo "starting rackhd ./src services..."
       sudo pm2 start rackhd-pm2-config.yml 
    fi
  fi
}

stopServices() {
    cd ~
    for srv in ${SERVICES}; do
        sudo service ${srv} stop
    done
    echo "services terminated"
}

waitForServices() {
  local attempt=0
  local maxto=20
  local url=${HTTP_URL}/swagger-ui
  echo "waiting for rackhd services.. "
  while [ ${attempt} != ${maxto} ]; do
    echo -ne "waited `expr $attempt \* 10` seconds\r"
    sleep 10
    wget -nv --retry-connrefused --waitretry=1 --read-timeout=20 --timeout=15 -t 1 --continue ${url}
    if [ $? = 0 ]; then
      echo "rackhd services are ready"
      break
    fi
    attempt=`expr ${attempt} + 1`
  done

  if [ ${attempt} == ${maxto} ]; then
    echo "timed out waiting for rackhd services (duration=`expr $maxto \* 10`sec)."
    exit 1
  fi
  rm -f nodes > /dev/null
}

createFirstUser() {
    local status=`curl -k -X POST -w '%{http_code}' \
        -H 'Content-Type: application/json' \
        -d '{"username": "'"${USER}"'", "password": "'"${PASS}"'", "role": "Administrator"}' \
        ${HTTPS_URL}/api/2.0/users`
    if [[ "${status}" == *"201"* ]]; then
      echo "user created"
    else
      echo "error creating user: ${status}"
      exit 1
   fi
}

checkFirstUser() {
   local status=$(login)
   if [[ "${status}" == *"Unauthorized"* ]]; then
       createFirstUser
       status=$(login)
   fi
   echo "${status}"
}

stopServices
cleanServicesPIDs
startServices
if [ $? -eq "0" ]; then
  waitForServices
fi
if [ $? -eq "0" ]; then
  checkFirstUser
fi
stopServices
