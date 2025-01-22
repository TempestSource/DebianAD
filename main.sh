#!/bin/bash

# Install required programs
source install.sh

#########################
# AUTHENTICATE KERBEROS #
#########################

echo -e "\nAuthenticating Kerberos"
echo "-----------------------"

# Initialize Kerberos Ticket
echo -n "Domain admin name (default: Administrator): "
read adminName
if [[ -z "$adminName" ]]; then
	kinit Administrator
else
	kinit $adminName
fi
# Check for ticket
if ! klist -s ;then
	echo "No valid kerberos ticket, aborting"
	exit 1
fi

######################
# DOMAIN INFORMATION #
######################

echo -e "\nGetting domain information"
echo "--------------------------"

# Get information about domain / host
domain=$(hostname -d)
domainUp=${domain^^}
echo -n "Domain Controller 1 hostname: "
read dchost1
echo -n "Domain Controller 2 hostname (optional): "
read dchost2
# Check DC hosts
if [[ -z "$dchost1" ]]; then
	echo "No valid DC1, aborting"
	exit 1
fi

##################
# MODIFY CONFIGS #
##################

echo -e "\nPreparing Configs"
echo "-----------------"

# sssd & krb5
tmpdir="/tmp/kerbsetup"
mkdir -p "$tmpdir"
cp -r configs "$tmpdir/configs"

# DC
sed -i "s/kdc01/$dchost1/g" $tmpdir/configs/krb5.conf
if [[ -z "$dchost2" ]]; then
	sed -i "s/,kdc02.example.com//g" $tmpdir/configs/krb5.conf
else
	sed -i "s/kdc02/$dchost2/g" $tmpdir/configs/krb5.conf
fi
# Domain
sed -i "s/example.com/$domain/g" $tmpdir/configs/krb5.conf
sed -i "s/EXAMPLE.COM/$domainUp/g" $tmpdir/configs/{sssd.conf,krb5.conf}

# Sudo
echo -n "Enter name of sudo group: "
read sudoGroup
if [[ -z "$sudoGroup" ]]; then
	echo "No sudo group entered"
	exit 1
fi
sudoGroup=$(sed "s/ /\\\\\\\\\ /g" <<< $sudoGroup)
sed -i "s|sudogroup|${sudoGroup}|g" $tmpdir/configs/domainAdmin

# Samba Config
wgvar=$(awk '{split($1, a, "."); print a[1]}' <<< ${domain^^})
sed -i "s/WORKGROUP/$wgvar/" $tmpdir/configs/smb.conf
sed -i "s/EXAMPLE.COM/$domainUp/" $tmpdir/configs/smb.conf

################
# COPY CONFIGS #
################
# Also enables required services

echo -e "\nEnabling Configs and Services"
echo "-----------------------------"

# SSSD
cp $tmpdir/configs/sssd.conf /etc/sssd/sssd.conf
chown root:root /etc/sssd/sssd.conf
chmod 0600 /etc/sssd/sssd.conf
systemctl start sssd

# Kerberos Config
cp $tmpdir/configs/krb5.conf /etc/krb5.conf

# Sudo
cp $tmpdir/configs/domainAdmin /etc/sudoers.d/domainAdmin

# Smb
cp $tmpdir/configs/smb.conf /etc/samba/smb.conf
systemctl restart smbd
systemctl enable smbd

# Pam
cp $tmpdir/configs/pamAD /usr/share/pam-configs/pamAD
pam-auth-update --package

###############
# JOIN DOMAIN #
###############
echo -e "\nJoining domain"
echo "--------------"
net ads join -k

systemctl restart sssd
systemctl enable sssd


###########
# CLEANUP #
###########
echo -e "\nRunning Cleanup"
echo "---------------"
rm -rf $tmpdir/
