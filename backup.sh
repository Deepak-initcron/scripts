#!/bin/bash

usage="$(basename "$0") [-h] [-s n]

where:
    -h  show this help text
Change the following variable
     db_instance_identifier  name of the temporary db instance
     db_snapshot_string sub string of db snapshot through which we will create a temp instance
     db_user username of db
     db_output_file the file which we will push to s3
     profile aws profile name
     "
while getopts ':hs:' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
  esac
done
set -e

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games"

profile=quintype

current_date=`date +%Y-%m-%d`
db_instance_identifier=backup-staging-french-castle-`date +%Y-%m-%d-%H-%M`
db_snapshot_string=rds:staging-french-castle
db_user=galahad
db_password=moXMVNAE98uR
db_dbname=french_castle_staging
db_output_file=staging-dump-`date +%Y%m%d%H%M`.sql.enc

db_snapshot_identifier=`sudo aws rds describe-db-snapshots --query 'DBSnapshots[*].DBSnapshotIdentifier' --profile ${profile} | grep ${db_snapshot_string}-${current_date} |awk 'NR==1{print $1}'| cut -d '"' -f 2`
status=creating

wait_till_db_instance_available () {
  while [ "$status" != "available" ]
  do
    status=`aws rds describe-db-instances --db-instance-identifier ${db_instance_identifier} --query 'DBInstances[*].DBInstanceStatus' --profile ${profile} | grep available| cut -d '"' -f 2`
    echo "db instance is not availabe yet"
    sleep 60
  done
}

restore_db_instance () {
sudo aws rds restore-db-instance-from-db-snapshot --db-instance-identifier ${db_instance_identifier}  --db-snapshot-identifier ${db_snapshot_identifier} --no-multi-az --publicly-accessible --db-instance-class db.t2.small  --port 5432 --profile ${profile}
  status=`aws rds describe-db-instances --db-instance-identifier ${db_instance_identifier} --query 'DBInstances[*].DBInstanceStatus' --profile ${profile} | grep available| cut -d '"' -f 2`
  wait_till_db_instance_available
}

delete_db_instance () {
  sudo aws rds delete-db-instance --db-instance-identifier ${db_instance_identifier} --skip-final-snapshot --profile ${profile}
}

restore_db_instance
echo $db_snapshot_identifier
db_instance_endpoint=`sudo aws rds describe-db-instances --db-instance-identifier ${db_instance_identifier} --query 'DBInstances[*].Endpoint.Address' --profile ${profile} | grep ${db_instance_identifier} |cut -d '"' -f 2`
db_instance_port=`sudo aws rds describe-db-instances --db-instance-identifier ${db_instance_identifier} --query 'DBInstances[*].Endpoint.Port' --profile ${profile} | grep ${db_instance_identifier} |cut -d '"' -f 2`
sudo aws rds modify-db-instance --db-instance-identifier ${db_instance_identifier} --vpc-security-group-ids sg-02111367 --backup-retention-period 0 --apply-immediately --profile ${profile}
sleep 100
wait_till_db_instance_available
#PGPASSWORD=${db_password} sudo pg_dump -h ${db_instance_endpoint} -F c -U ${db_user} ${db_dbname} -f output && openssl enc -aes-256-cbc -e -k facebookSucks -in output -out ${db_output_file} && rm output
sudo pg_dump --dbname=postgresql://${db_user}:${db_password}@${db_instance_endpoint}:5432/${db_dbname} -Fc -w -f output && openssl enc -aes-256-cbc -e -k facebookSucks -in output -out ${db_output_file} && rm output
aws s3 cp ${db_output_file} s3://${profile}-dumps/ --profile quintype && rm ${db_output_file}
delete_db_instance
