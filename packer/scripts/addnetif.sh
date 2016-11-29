#!/bin/bash
set -e
#######################################
# Force set Secondary NIC static IP
######################################
setIP(){

    SECONDARY_NIC=$1
    IP=172.31.128.1
    MASK=255.255.252.0

    echo -e "\nauto $SECONDARY_NIC\niface $SECONDARY_NIC inet static\n   address $IP\n   netmask $MASK" >> /etc/network/interfaces
}

##########################################################
# retrieve NIC name via ```ip addr``` command, by given id
###########################################################
get_nic_name_by_index()
{
    #######################
    # This script is to obtain and echo the NIC name (lo/eth0/eth1) by index(1/2/3) shown in ```ip addr```
    ########################
    tmp=$( ip addr|grep "^$1:" | awk '{print $2}')
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


    NIC1=$(get_nic_name_by_index 1)
   # if the index 1 is not loopback device, then eth0 may starts from index 1.
    if [[ $NIC1 != "lo" ]]; then
        Sec_NIC_Index=$(expr $Sec_NIC_Index - 1 )
    fi

    Sec_NIC=$(get_nic_name_by_index $Sec_NIC_Index)

    echo $Sec_NIC
}


########################################
# Set Secondary NIC IP to 172.31.128.1
#######################################
Control_NIC=$(get_secondary_nic_name) 
echo "Setting static IP 172.31.128.1 for ${Control_NIC}"
setIP ${Control_NIC}


