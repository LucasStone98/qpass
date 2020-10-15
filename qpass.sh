#! /bin/bash 

# Script needs su-privaleges

if [[ $UID != 0 ]]; then
    echo "Please run this script with sudo:"
    echo "sudo $0 $*"
    exit 1
fi

# WSL doesnt have this dir

if [ -d "/dev/disk" ]; then
	clear
else
	clear
	echo "*** No Disks Found - Script Not Supported in WSL ***"
	exit
fi

# Check for chntpw, if not found - install with correct package manager

declare -A osInfo;
osInfo[/etc/debian_version]="apt install -y"
osInfo[/etc/arch-release]="pacman -S"
osInfo[/etc/fedora-release]="dnf install -y"

for f in ${!osInfo[@]}
do 
	if [[ -f $f ]];then
		package_manager=${osInfo[$f]}
	fi
done

if [[ $package_manager = "apt install -y" ]];then
	if [ -f "/etc/lsb-release" ] && grep -q "Ubuntu" /etc/lsb-release;then
		clear
		add-apt-repository universe
		clear
	fi
fi

package="chntpw"

function connection_check {

	wget -q --spider http://google.com

	if [ $? -eq 0 ]; then
		true
	else
		read -p "Please connect to the internet and run script again"
		exit
	fi
}

if [ ! -f "/usr/sbin/chntpw" ] 
then

	connection_check

	echo =========================================
	echo "chntpw not installed, installing..."
	echo =========================================
	${package_manager} ${package}
	clear

fi

# Cleanup on exit

function final {
	cd 
	umount /mnt/PassReset
	clear
	echo "Script Ended"
}

trap final EXIT

clear

# Populate DRIVES array with drive names and an index number

shopt -s extglob
declare -a DRIVES

number=1

for d in /dev/disk/by-id/!(*part*)
do
	dname=$(echo $d | cut -d'/' -f5-)
	if [[ $dname == *"wwn"* ]];then
		true
	else
		DRIVES[$number]+=$dname
	fi
	let number+=1
done

# List Drives - User chooses one

function list_drives {

	echo "Disks Found:"
	echo "---------------------"
	echo

	for KEY in "${!DRIVES[@]}"
	do
		hddsize=$(lsblk -M --output SIZE -n -d /dev/disk/by-id/${DRIVES[$KEY]})
		echo "$KEY : ${DRIVES[$KEY]} ($hddsize)"
	done

	echo
	echo "NOTE: CANNOT RESET USER LINKED WITH MS ACCOUNT - WINDOWS MIGHT BREAK IF YOU TRY TO CHANGE IT"
	echo
	read -n1 -p "Drive number?" doit
	echo

	if [[ $doit > ${#DRIVES[@]} ]];then
		clear
		echo "Invalid Value - Try Again"
		echo 
		list_drives
	fi
}


list_drives

# Get correct link for drive selected (ie. /dev/sda1, /dev/sdc3)


partpath="/dev/disk/by-id/"

if [ -n $doit ] && [ $doit -le ${#DRIVES[@]} ]
then
	partpath+="${DRIVES[$doit]}"
	rlinkpath=$(readlink -f $partpath )
	echo "$rlinkpath"
else 
	clear
	echo "No Windows Partitions Found - Please Try Again"
fi

if [[ $rlinkpath == *'/dev/sr'* ]]; then
	clear
	echo "NOT A HDD - Try Again"
	echo "sudo $0 $*"
	exit
fi

# Mount all partitions on drive and search for one with Windows folder

partnumb=$(ls -1q $rlinkpath* | wc -l)
skipnum=1
x=$partnumb

mkdir /mnt/PassReset

while [[ $x -gt 1 ]]; do
	
	mount $rlinkpath$skipnum /mnt/PassReset

	if [ -d /mnt/PassReset/Windows/ ] || [ -d /mnt/PassReset/WINDOWS/ ]; then
		break
	else
		clear
		umount /mnt/PassReset
	fi

	let skipnum+=1
	x=$(($x-1))

done

# Find device mounted to /mnt/PassReset

find_temp=$(findmnt -n -o SOURCE --target /mnt/PassReset)

# Check if read-only, then ntfsfix and remount

ro_check=$(awk '$4~/(^|,)ro($|,)/' /proc/mounts)

if [[ $ro_check == *'/mnt/PassReset'* ]];then
	umount /mnt/PassReset
	ntfsfix $find_temp
	ntfsfix $find_temp
	mount $find_temp /mnt/PassReset
else
	true
fi

clear

# Check for correct windows folder; Vista+ doesn't use all CAPS

if [ -d /mnt/PassReset/WINDOWS ];then
	localpath="WINDOWS/system32/config"
else	
	localpath="Windows/System32/config"
fi

clear

# Change directory to config and list all Users - select correct user

echo "Accessing ${DRIVES[$doit]}..."
cd /mnt/PassReset/$localpath
sleep 1
clear

function chnt_user {

	chntpw -l SAM
	echo

	IFS= read -r -p "Username (case sensitive): " usr0
	clear

	ucheck=$(chntpw -l SAM)

	if [[ $ucheck == *"$usr0"* ]]; then
		true
	else
		clear
		echo "Invalid User - Try Again"
		echo "--------------------------------"
		chnt_user

	fi

}

chnt_user

# Run chntpw on User

echo "Accesed User: $usr0"
echo
chntpw -u "$usr0" SAM
sleep 1
clear

echo "Done!"


cd 
umount /mnt/PassReset
sleep 1

# Final Steps

echo "Reboot Now?"

select yn in "Yes" "No"; 
do
	case $yn in
		Yes) reboot ;;
		No) break ;;
	esac
done

clear
exit

