set -x

Uri=${1}
HANAVER=${2}
HANAUSR=${3}
HANAPWD=${4}
HANASID=${5}
HANANUMBER=${6}
vmSize=${7}
SUBEMAIL=${8}
SUBID=${9}
SUBURL=${10}

#if needed, register the machine
if [ "$SUBEMAIL" != "" ]; then
  if [ "$SUBURL" != "" ]; then 
   SUSEConnect -e $SUBEMAIL -r $SUBID --url $SUBURL
  else 
   SUSEConnect -e $SUBEMAIL -r $SUBID
  fi
fi

#decode hana version parameter
HANAVER=${HANAVER^^}


#get the VM size via the instance api
VMSIZE=`curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2017-08-01&format=text"`


#install hana prereqs
zypper install -y glibc-2.22-51.6
zypper install -y systemd-228-142.1
zypper install -y unrar
zypper install -y sapconf
zypper install -y saptune
mkdir /etc/systemd/login.conf.d
mkdir /hana
mkdir /hana/data
mkdir /hana/log
mkdir /hana/shared
mkdir /hana/backup
mkdir /usr/sap

#VG & LV naming comvention
sharedvgname="sap""$HANASID""vg"
sharedlvname="lvsap""$HANASID""01"
usrlvname="lvsap""$HANASID""02"
backupvgname="sap""$HANASID""bvg"
backuplvname="lvsap""$HANASID""b01"
datavgname="sap""$HANASID""dvg"
logvgname="sap""$HANASID""lvg"
datalvname="lvsap""$HANASID""d01"
loglvname="lvsap""$HANASID""l01"

hdatapart="/dev/""$datavgname""/""$datalvname"
hsharedpart="/dev/""$sharedvgname""/""$sharedlvname"
hlogpart="/dev/""$logvgname""/""$loglvname"
husrpart="/dev/""$sharedvgname""/""$usrlvname"
hbackuppart="/dev/""$backupvgname""/""$backuplvname"

###debug
echo $hsharedpart >> /tmp/parameter.txt
echo $hbackuppart >> /tmp/parameter.txt
echo $husrpart >> /tmp/parameter.txt
echo $hdatapart >> /tmp/parameter.txt
echo $hlogpart >> /tmp/parameter.txt

zypper in -t pattern -y sap-hana
saptune solution apply HANA
saptune daemon start

# step2
echo $Uri >> /tmp/url.txt

cp -f /etc/waagent.conf /etc/waagent.conf.orig
sedcmd="s/ResourceDisk.EnableSwap=n/ResourceDisk.EnableSwap=y/g"
sedcmd2="s/ResourceDisk.SwapSizeMB=0/ResourceDisk.SwapSizeMB=2048/g"
cat /etc/waagent.conf | sed $sedcmd | sed $sedcmd2 > /etc/waagent.conf.new
cp -f /etc/waagent.conf.new /etc/waagent.conf

#don't restart waagent, as this will kill the custom script.
#service waagent restart

if [ "$VMSIZE" == "Standard_M32ts" ] || [ "$VMSIZE" == "Standard_M32ls" ] || [ "$VMSIZE" == "Standard_M64ls" ] || [ $VMSIZE == "Standard_DS14_v2" ] ; then
echo "logicalvols start" >> /tmp/parameter.txt
  # this assumes that 5 disks are attached at lun 0 through 4
  echo "Creating partitions and physical volumes"
  pvcreate -ff -y /dev/disk/azure/scsi1/lun0   
  pvcreate -ff -y  /dev/disk/azure/scsi1/lun1
  pvcreate -ff -y  /dev/disk/azure/scsi1/lun2
  pvcreate -ff -y  /dev/disk/azure/scsi1/lun3

  #shared volume creation
  sharedvglun="/dev/disk/azure/scsi1/lun0"
  vgcreate $sharedvgname $sharedvglun
  lvcreate -l 50%FREE -n $sharedlvname $sharedvgname 
 
  #usr volume creation
  #usrsapvglun="/dev/disk/azure/scsi1/lun0"
  #vgcreate $sharedvgname $usrsapvglun  
  lvcreate -l 100%FREE -n $usrlvname $sharedvgname

  #backup volume creation
  backupvglun="/dev/disk/azure/scsi1/lun1"  
  vgcreate backupvg $backupvglun
  lvcreate -l 100%FREE -n $backuplvname $backupvgname 

  #data volume creation
  datavglun="/dev/disk/azure/scsi1/lun2"
  logvglun="/dev/disk/azure/scsi1/lun3"
  vgcreate $datavgname $datavglun 
  vgcreate $logvgname $logvglun
  #PHYSVOLUMES=3
  #STRIPESIZE=64
  #lvcreate -i$PHYSVOLUMES -I$STRIPESIZE -l 70%FREE -n datalv datavg
  #lvcreate -i$PHYSVOLUMES -I$STRIPESIZE -l 100%FREE -n loglv datavg
  lvcreate -l 100%FREE -n $datalvname $datavgname
  lvcreate -l 100%FREE -n $loglvname $logvgname


  mkfs -t xfs /dev/$datavgname/$datalvname
  mkfs -t xfs /dev/$logvgname/$loglvname
  mkfs -t xfs /dev/$sharedvgname/$sharedlvname
  mkfs -t xfs /dev/$backupvgname/$backuplvname 
  mkfs -t xfs /dev/$sharedvgname/$usrlvname
    
echo "logicalvols end" >> /tmp/parameter.txt
fi

#insert more VMs here from Backup


#!/bin/bash
echo "mounthanashared start" >> /tmp/parameter.txt
##debug
echo $hsharedpart >> /tmp/parameter.txt
echo $hbackuppart >> /tmp/parameter.txt
echo $husrpart >> /tmp/parameter.txt
echo $hdatapart >> /tmp/parameter.txt
echo $hlogpart >> /tmp/parameter.txt
###
mount -t xfs $hsharedpart /hana/shared
mount -t xfs $hbackuppart /hana/backup 
mount -t xfs $husrpart /usr/sap
mount -t xfs $hdatapart /hana/data
mount -t xfs $hlogpart /hana/log
echo "mounthanashared end" >> /tmp/parameter.txt

echo "write to fstab start" >> /tmp/parameter.txt
echo "$hdatapart"" /hana/data xfs defaults 0 0" >> /etc/fstab
echo "$hsharedpart"" /hana/shared xfs defaults 0 0" >> /etc/fstab
echo "$hbackuppart"" /hana/backup xfs defaults 0 0" >> /etc/fstab
echo "$husrpart"" /usr/sap xfs defaults 0 0" >> /etc/fstab
echo "$hlogpart"" /hana/log xfs defaults 0 0" >> /etc/fstab
echo "write to fstab end" >> /tmp/parameter.txt

