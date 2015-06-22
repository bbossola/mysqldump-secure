#!/bin/sh
#
# @author    Patrick Plocke <patrick@plocke.de>
# @gpg key   0x28BF179F
# @date      2015-07-13
# @licencse  MIT http://opensource.org/licenses/MIT
# @version   v0.3
#
# Script to dump databases one by one
#
# Features:
# ---------------------
# * Encryped output via public/private key (optional)
# * Compressed output via gzip (optional)
# * Database black list (optional)
# * Logfile (optional)
# * Custom mysqldump parameters
# * Dumping time, total time
# * Error handling
#
# Exit Codes
# ---------------------
# * 0: Success
# * 1: Script specific: (writeable directory, config file not found, wrong permissions)
# * 2: Required binary not found
# * 3: MySQL connection error
# * 4: MySQL Database dump error


################################################################################
#
# VARIABLES
#
################################################################################

# Configuration
CONFIG_NAME="mysqldump-secure.conf"
CONFIG_FILE="/etc/${CONFIG_NAME}"


# These command line arguments are considered insecure and can lead
# to compromising your data
MYSQL_EVIL_OPTS="--password -p"

# Do not allow to read any other file than the one specified in
# the configuration.
MYSQL_BAD_OPTS="--defaults-extra-file --defaults-file"



################################################################################
#
# HELPER FUNCTIONS
#
################################################################################

# Output to stdout and to file
output() {
	local MSG="${1}"		# Message to output
	local LOG="${2:-0}"		# Log? 1: yes 0: No (defaults to 0)
	local FILE="${3}"		# Logfile path

	printf "%s\n" "${MSG}"
	[ "${LOG}" = "1" ] && printf "%s %s %s\n" "$(date '+%Y-%m-%d')" "$(date '+%H:%M:%S')" "${MSG}" >> "${FILE}"
	return 0
}
# Inline Output to stdout and to file (no newline)
outputi() {
	local MSG="${1}"		# Message to output
	local LOG="${2:-0}"		# Log? 1: yes 0: No (defaults to 0)
	local FILE="${3}"		# Logfile path

	printf "%s" "${MSG}"
	[ "${LOG}" = "1" ] && printf "%s %s %s" "$(date '+%Y-%m-%d')" "$(date '+%H:%M:%S')" "${MSG}" >> "${FILE}"
	return 0
}
# Output to stdout and to file (no time)
outputn() {
	local MSG="${1}"		# Message to output
	local LOG="${2:-0}"		# Log? 1: yes 0: No (defaults to 0)
	local FILE="${3}"		# Logfile path

	printf "%s\n" "${MSG}"
	[ "${LOG}" = "1" ] && printf "%s\n" "${MSG}" >> "${FILE}"
	return 0
}

# Test if argument is an integer
# @return integer	0: is numer | 1 not a number
isint(){
	printf '%d' "$1" >/dev/null 2>&1 && return 0 || return 1;
}

permission() {
	local file
	local perm

	file="${1}"

	# e.g. 640
	if [ "$(uname)" = "Linux" ]; then
		perm="$(stat --format '%a' ${file})"
	else # Darwin or FreeBSD
		perm="$(stat -f "%OLp" ${file})"
	fi

	echo $perm
	return 0
}




################################################################################
#
# ENTRY POINT: ERROR CHECKING
#
################################################################################


############################################################
# Config FIle
############################################################

if [ ! -f "${CONFIG_FILE}" ]; then
	output "[ERR]  Configuration file not found in ${CONFIG_FILE}"
	output "Aborting"
	exit 1
fi
if [ ! -r "${CONFIG_FILE}" ]; then
	output "[ERR]  Configuration file is not readable in ${CONFIG_FILE}"
	output "Aborting"
	exit 1
fi
if [ "$(permission "${CONFIG_FILE}")" != "400" ]; then
	output "[ERR]  Configuration file ${CONFIG_FILE} has dangerous permissions: $(permission "${CONFIG_FILE}")."
	output "[INFO] Fix it to 400"
	output "Aborting"
	exit 1
fi

# Read config file
. "${CONFIG_FILE}"




############################################################
# Logging Options
############################################################

# Be really strict on checking if we are going to log to file
# or not. Also make sure that the logfile is writeable and
# that no other has read permissions to the file.
if [ -z ${LOG} ]; then
	output '[INFO] $LOG variable is empty or not set in ${CONFIG_FILE}'
	output "[INFO] Logging disabled"
	LOG=0
elif [ "${LOG}" = "1" ]; then
	if [ -z ${LOGFILE} ]; then
		output '[WARN] $LOGFILE variable is empty or not set in ${CONFIG_FILE}'
		output "[WARN] Logging disabled"
		LOG=0
	elif [ ! -f "${LOGFILE}" ]; then
		output "[WARN] Logfile does not exist in ${LOGFILE}"
		outputi "[INFO] Trying to create..."

		if ! touch "${LOGFILE}" > /dev/null 2>&1 ; then
			outputn "Failed"
			output  "[ERR]  Failed to create file ${LOGFILE}"
			output  "[WARN] Logging disabled"
			LOG=0
		else
			outputn "OK"
			output  "[INFO] Created file ${LOGFILE}"
			outputi "[INFO] Trying to chmod..."

			if ! chmod 600 "${LOGFILE}" > /dev/null 2>&1 ; then
				outputn "Failed"
				output  "[ERR]  Failed to chmod 600 ${LOGFILE}"
				output  "[WARN] Logging disabled"
				LOG=0
			else
				outputn "OK"
			fi
		fi
	elif [ ! -w "${LOGFILE}" ]; then
		output "[WARN] Logfile ${LOGFILE} not writeable"
		output "[WARN] Logging disabled"
		LOG=0
	elif [ "$(permission "${LOGFILE}")" != "600" ]; then
		output "[ERR]  Logfile has dangerous permissions: $(permission "${LOGFILE}")"
		output "[INFO] Fix it to 600"
		output "[WARN] Logging disabled"
		LOG=0
	else
		echo "" >> "${LOGFILE}"
		echo "---------------------------------------" >> "${LOGFILE}"
		echo "$(date '+%Y-%m-%d') $(date '+%H:%M:%S') Starting" >> "${LOGFILE}"
		output "[INFO] Logging enabled"
	fi
else
	output "[INFO] Logging not enabled in ${CONFIG_FILE}"
	LOG=0
fi




############################################################
# Destination Directory and Prefix
############################################################

# Check if destination dir exists
if [ -z ${TARGET} ]; then
	output '[ERR]  TARGET variable is empty or not set in ${CONFIG_FILE}' $LOG "${LOGFILE}"
	output "Aborting" $LOG "${LOGFILE}"
	exit 1
elif [ ! -d "${TARGET}" ]; then
	output  "[WARN] Destination dir ${TARGET} does not exist" $LOG "${LOGFILE}"
	outputi "[INFO] Trying to create... " $LOG "${LOGFILE}"
	if ! mkdir -p "${TARGET}" > /dev/null 2>&1 ; then
		outputn "Failed" $LOG "${LOGFILE}"
		output  "Aborting" $LOG "${LOGFILE}"
		exit 1
	else
		outputn "Done" $LOG "${LOGFILE}"
		output "[INFO] Adjusting file permissions on ${TARGET}" $LOG "${LOGFILE}"
		chmod 0700 "${TARGET}"
	fi
fi
# Check if destination dir is writeable
if [ ! -w "${TARGET}" ]; then
	output "[WARN] Destination dir ${TARGET} is not writeable" $LOG "${LOGFILE}"
	outputi "[INFO] Trying to chmod... " $LOG "${LOGFILE}"
	if ! chmod 0700 "${TARGET}" > /dev/null 2>&1 ; then
		outputn "Failed" $LOG "${LOGFILE}"
		output "Aborting" $LOG "${LOGFILE}"
		exit 1
	else
		outputn "Done" $LOG "${LOGFILE}"
	fi
	outputi "[INFO] Trying to chown... " $LOG "${LOGFILE}"
	if ! chown "$(whoami)" "${TARGET}" > /dev/null 2>&1 ; then
		outputn "Failed" $LOG "${LOGFILE}"
		output "Aborting" $LOG "${LOGFILE}"
		exit 1
	else
		outputn "Done" $LOG "${LOGFILE}"
	fi
fi
# Check correct permissions of destination dir
if [ "$(permission "${TARGET}")" != "700" ]; then
	output "[ERR]  Target directory has dangerous permissions: $(permission "${TARGET}")." $LOG "${LOGFILE}"
	output "[INFO] Fix it to 700" $LOG "${LOGFILE}"
	output "Aborting" $LOG "${LOGFILE}"
	exit 1
fi
# Check output Prefix
if [ -z ${PREFIX} ]; then
	output '[INFO] $PREFIX variable is empty not set in ${CONFIG_FILE}'$LOG "${LOGFILE}"
	output "[INFO] Using default 'date-time' prefix" $LOG "${LOGFILE}"
	PREFIX="$(date '+%Y-%m-%d')_$(date '+%H-%M')__"
fi



############################################################
# MySQL
############################################################
if [ -z ${MYSQL_CNF_FILE} ]; then
	output '[ERR]  $MYSQL_CNF_FILE variable is empty or not set in ${CONFIG_FILE}' $LOG "${LOGFILE}"
	output "Aborting" $LOG "${LOGFILE}"
	exit 1
fi
if [ ! -f "${MYSQL_CNF_FILE}" ]; then
	output "[ERR]  MySQL Configuration file not found in ${MYSQL_CNF_FILE}" $LOG "${LOGFILE}"
	output "Aborting" $LOG "${LOGFILE}"
	exit 1
fi
if [ ! -r "${MYSQL_CNF_FILE}" ]; then
	output "[ERR]  MySQL Configuration file is not readable in ${MYSQL_CNF_FILE}" $LOG "${LOGFILE}"
	output "Aborting" $LOG "${LOGFILE}"
	exit 1
fi
if [ "$(permission "${MYSQL_CNF_FILE}")" != "400" ]; then
	output "[ERR]  MySQL Configuration file ${MYSQL_CNF_FILE} has dangerous permissions: $(permission "${MYSQL_CNF_FILE}")." $LOG "${LOGFILE}"
	output "[ERR]  Fix it to 400" $LOG "${LOGFILE}"
	output "[ERR]  Change your database password!" $LOG "${LOGFILE}"
	output "Aborting" $LOG "${LOGFILE}"
	exit 1
fi
if ! command -v mysql > /dev/null 2>&1 ; then
	output "[ERR]  'mysql' not found" $LOG "${LOGFILE}"
	output "Aborting" $LOG "${LOGFILE}"
	exit 2
fi
if ! command -v mysqldump > /dev/null 2>&1 ; then
	output "[ERR]  'mysqldump' not found" $LOG "${LOGFILE}"
	output "Aborting" $LOG "${LOGFILE}"
	exit 2
fi
# Testing MySQL connection
if ! $(which mysql) --defaults-extra-file=${MYSQL_CNF_FILE} -e exit > /dev/null 2>&1 ; then
	output "[ERR]  Cannot connect to mysql database. Check credentials in ${MYSQL_CNF_FILE}" $LOG "${LOGFILE}"
	output "Aborting" $LOG "${LOGFILE}"
	exit 3
fi



############################################################
# Bad MySQL Opts
############################################################
for opt in ${MYSQL_OPTS}; do
	for evil in ${MYSQL_EVIL_OPTS}; do
		if [ "${opt}" = "${evil}" ]; then
			output "[ERR]  Insecure mysqldump option found in MYSQL_OPTS: '${evil}'" $LOG "${LOGFILE}"
			output "Aborting" $LOG "${LOGFILE}"
			exit 3
		fi
	done
	for bad in ${MYSQL_BAD_OPTS}; do
		if [ "${opt}" = "${evil}" ]; then
			output "[ERR]  Disallowed mysqldump option found in MYSQL_OPTS: '${bad}'" $LOG "${LOGFILE}"
			output "Aborting" $LOG "${LOGFILE}"
			exit 3
		fi
	done
done



############################################################
# Compression
############################################################
if [ -z ${COMPRESS} ]; then
	output '[INFO] $COMPRESS variable is empty or not set in ${CONFIG_FILE}' $LOG "${LOGFILE}"
	output "[INFO] Compression disabled" $LOG "${LOGFILE}"
	COMPRESS=0
fi
if [ "${COMPRESS}" = "1" ]; then
	if ! command -v gzip > /dev/null 2>&1 ; then
		output "[WARN] 'gzip' not found" $LOG "${LOGFILE}"
		output "[WARN] Disabling compression" $LOG "${LOGFILE}"
		COMPRESS=0
	fi
else
	output "[INFO] Compression not enabled in ${CONFIG_FILE}" $LOG "${LOGFILE}"
fi



############################################################
# Encryption
############################################################
if [ -z ${ENCRYPT} ]; then
	output "[INFO] \$ENCRYPT variable is empty or not set in ${CONFIG_FILE}" $LOG "${LOGFILE}"
	output "[INFO] Encryption disabled" $LOG "${LOGFILE}"
	ENCRYPT=0
fi
if [ "${ENCRYPT}" = "1" ]; then
	if ! command -v openssl > /dev/null 2>&1 ; then
		output "[ERR]  'openssl' not found" $LOG "${LOGFILE}"
		output "Aborting" $LOG "${LOGFILE}"
		exit 2
	fi
	if [ ! -f "${OPENSSL_PUBKEY_PEM}" ]; then
		output "[ERR]  OpenSSL pubkey not found in ${OPENSSL_PUBKEY_PEM}" $LOG "${LOGFILE}"
		output "Aborting" $LOG "${LOGFILE}"
		exit 2
	fi
	if [ -z ${OPENSSL_ALGO_ARG} ]; then
		output '[WARN] $OPENSSL_ALGO_ARG variable is empty not set in ${CONFIG_FILE}' $LOG "${LOGFILE}"
		output "[INFO] Encryption defaults to -aes256" $LOG "${LOGFILE}"
		OPENSSL_ALGO_ARG="-aes256"
	fi
	# Test openssl Algo
	if ! echo "test" | $(which openssl) smime -encrypt -binary -text -outform DER ${OPENSSL_ALGO_ARG} "${OPENSSL_PUBKEY_PEM}" > /dev/null 2>&1 ; then
		output '[ERR]  openssl encryption test failed. Validate $OPENSSL_ALGO_ARG' $LOG "${LOGFILE}"
		output "Aborting" $LOG "${LOGFILE}"
		exit 2
	fi
else
	output "[INFO] Encryption not enabled in ${CONFIG_FILE}" $LOG "${LOGFILE}"
fi



############################################################
# Deletion
############################################################
if [ -z ${DELETE} ]; then
	output '[INFO] $DELETE variable is empty or not set in ${CONFIG_FILE}' $LOG "${LOGFILE}"
	output "[INFO] Deletion of old files disabled" $LOG "${LOGFILE}"
	DELETE=0
fi
if [ "${DELETE}" = "1"  ]; then
	if [ -z ${DELETE_IF_OLDER} ]; then
		output '[WARN] $DELETE_IF_OLDER variable is empty or not set in ${CONFIG_FILE}' $LOG "${LOGFILE}"
		output "[WARN] Deletion of old files disabled" $LOG "${LOGFILE}"
		DELETE=0
	elif ! isint ${DELETE_IF_OLDER} > /dev/null 2>&1 ; then
		output '[WARN] $DELETE_IF_OLDER variable is not a valid integer' $LOG "${LOGFILE}"
		output "[WARN] Deletion of old files disabled" $LOG "${LOGFILE}"
		DELETE=0
	elif [ ${DELETE_IF_OLDER} -lt 1 ]; then
		output '[WARN] $DELETE_IF_OLDER is smaller than 1 hour' $LOG "${LOGFILE}"
		output "[WARN] Deletion of old files disabled" $LOG "${LOGFILE}"
		DELETE=0
	elif ! command -v tmpwatch > /dev/null 2>&1 ; then
		output "[WARN] 'tmpwatch' not found" $LOG "${LOGFILE}"
		output "[WARN] Deletion of old files disabled" $LOG "${LOGFILE}"
		DELETE=0
	fi
else
	output "[INFO] TMPWATCH deletion not enabled in ${CONFIG_FILE}" $LOG "${LOGFILE}"
fi








################################################################################
#
# ENTRY POINT: MAIN
#
################################################################################

# Binaries
MYSQL="$(which mysql)"
MYSQLDUMP="$(which mysqldump)"
GZIP="$(which gzip)"
OPENSSL="$(which openssl)"
TMPWATCH="$(which tmpwatch)"

ERROR=0


############################################################
# Get all databases
############################################################

# Get a list of all databases
outputi "[INFO] Retrieving list of databases... " $LOG "${LOGFILE}"
DATABASES="$( ${MYSQL} --defaults-extra-file=${MYSQL_CNF_FILE} --batch -e 'show databases;')"
DATABASES="$( echo "${DATABASES}" | sed 1d )"
NUM_DB="$(echo "${DATABASES}" | wc -l | tr -d ' ')"
outputn "${NUM_DB}" $LOG "${LOGFILE}"



############################################################
# Dump databases
############################################################

TOTAL_STARTTIME=$(date +%s)
output "[INFO] Backup directory: ${TARGET}" $LOG "${LOGFILE}"

for db in ${DATABASES}; do

	# Skip specified databases
	skip=0
	for ign_db in ${IGNORE}; do
		if [ "${ign_db}" = "${db}" ]; then
			skip=1
		fi
	done

	if [ ${skip} -eq 0 ]; then

		DB_SIZE="$( ${MYSQL} --defaults-extra-file=${MYSQL_CNF_FILE} --batch \
			-e "SELECT SUM(ROUND(((DATA_LENGTH + INDEX_LENGTH ) / 1024 / 1024),2)) AS Size
				FROM INFORMATION_SCHEMA.TABLES
				WHERE TABLE_SCHEMA = '${db}';")"
		DB_SIZE="$(echo "${DB_SIZE}" | tail -n1)"

		starttime=$(date +%s)
		ext=""	# file extension
		if [ ${COMPRESS} -eq 1 ]; then
			if [ ${ENCRYPT} -eq 1 ]; then
				ext=".sql.gz.pem"
				outputi "Dumping:  ${db} (${DB_SIZE} MB) (compressed) (encrypted) " $LOG "${LOGFILE}"
#				${MYSQLDUMP} --defaults-extra-file=${MYSQL_CNF_FILE} ${MYSQL_OPTS} "${db}" | ${GZIP} -9 | ${OPENSSL} smime -encrypt -binary -text -outform DER ${OPENSSL_ALGO_ARG} -out "${TARGET}/${PREFIX}${db}${ext}" "${OPENSSL_PUBKEY_PEM}"
				# execute with POSIX pipestatus emulation
				exec 4>&1
				error_statuses="`(
					(${MYSQLDUMP} --defaults-extra-file=${MYSQL_CNF_FILE} ${MYSQL_OPTS} "${db}" || echo "0:$?" >&3) |
					(${GZIP} -9 || echo "1:$?" >&3)
					(${OPENSSL} smime -encrypt -binary -text -outform DER ${OPENSSL_ALGO_ARG} -out "${TARGET}/${PREFIX}${db}${ext}" "${OPENSSL_PUBKEY_PEM}" || echo "2:$?" >&3)
				) 3>&1 >&4`"
				exec 4>&-
			else
				ext=".sql.gz"
				outputi "Dumping:  ${db} (${DB_SIZE} MB) (compressed) " $LOG "${LOGFILE}"
#				${MYSQLDUMP} --defaults-extra-file=${MYSQL_CNF_FILE} ${MYSQL_OPTS} "${db}" | ${GZIP} -9 > "${TARGET}/${PREFIX}${db}${ext}"
				# execute with POSIX pipestatus emulation
				exec 4>&1
				error_statuses="`(
					(${MYSQLDUMP} --defaults-extra-file=${MYSQL_CNF_FILE} ${MYSQL_OPTS} "${db}" || echo "0:$?" >&3) |
					(${GZIP} -9 > "${TARGET}/${PREFIX}${db}${ext}" || echo "1:$?" >&3)
				) 3>&1 >&4`"
				exec 4>&-


			fi
		else
			if [ ${ENCRYPT} -eq 1 ]; then
				ext=".sql.pem"
				outputi "Dumping:  ${db} (${DB_SIZE} MB) (encrypted) " $LOG "${LOGFILE}"
#				${MYSQLDUMP} --defaults-extra-file=${MYSQL_CNF_FILE} ${MYSQL_OPTS} "${db}" | ${OPENSSL} smime -encrypt -binary -text -outform DER ${OPENSSL_ALGO_ARG} -out "${TARGET}/${PREFIX}${db}${ext}" "${OPENSSL_PUBKEY_PEM}"
				exec 4>&1
				error_statuses="`(
					(${MYSQLDUMP} --defaults-extra-file=${MYSQL_CNF_FILE} ${MYSQL_OPTS} "${db}" || echo "0:$?" >&3) |
					(${OPENSSL} smime -encrypt -binary -text -outform DER ${OPENSSL_ALGO_ARG} -out "${TARGET}/${PREFIX}${db}${ext}" "${OPENSSL_PUBKEY_PEM}" || echo "1:$?" >&3)
				) 3>&1 >&4`"
				exec 4>&-
			else
				ext=".sql"
				outputi "Dumping:  ${db} (${DB_SIZE} MB) " $LOG "${LOGFILE}"
#				${MYSQLDUMP} --defaults-extra-file=${MYSQL_CNF_FILE} ${MYSQL_OPTS} "${db}" > "${TARGET}/${PREFIX}${db}${ext}"
				exec 4>&1
				error_statuses="`(
					(${MYSQLDUMP} --defaults-extra-file=${MYSQL_CNF_FILE} ${MYSQL_OPTS} "${db}" > "${TARGET}/${PREFIX}${db}${ext}" || echo "0:$?" >&3)
				) 3>&1 >&4`"
				exec 4>&-
			fi
		fi

		# We cannot check against $? as the first if uses a pipe | gzip and so we
		# need to check against the exit code of the first pipe status
		#
		# TODO: $PIPESTATUS is not POSIX conform
		# http://cfaj.ca/shell/cus-faq-2.html
		# check run()
#		if [ ${PIPESTATUS[0]} -ne 0 ]; then
#			outputn "ERROR" $LOG "${LOGFILE}"
#			ERROR=1
#		else
#			endtime=$(date +%s)
#			outputn "$(($endtime - $starttime)) sec" $LOG "${LOGFILE}"
#
#			chmod 600 "${TARGET}/${PREFIX}${db}${ext}"
#		fi

		# No errors in POSIX pipestatus emulation
		if [ -z "$error_statuses" ]; then
			endtime=$(date +%s)
			outputn "$(($endtime - $starttime)) sec" $LOG "${LOGFILE}"
			chmod 600 "${TARGET}/${PREFIX}${db}${ext}"
		else
			outputn "ERROR" $LOG "${LOGFILE}"
			ERROR=1
		fi


	else
		output "Skipping: ${db}" $LOG "${LOGFILE}"
	fi
done
TOTAL_ENDTIME=$(date +%s)

if [ $ERROR -ne 0 ]; then
	output "[ERR]  Some errors occured while dumping" $LOG "${LOGFILE}"
else
	output "[INFO] Dumping finished" $LOG "${LOGFILE}"
	output "[INFO] Took $(($TOTAL_ENDTIME - $TOTAL_STARTTIME)) seconds" $LOG "${LOGFILE}"
fi



############################################################
# Delete old Files
############################################################
if [ ${DELETE} -eq 1 ]; then
	output "[INFO] Deleting files older than ${DELETE_IF_OLDER} hours" $LOG "${LOGFILE}"
	DELETED="$(${TMPWATCH} -m ${DELETE_IF_OLDER} -v "${TARGET}/")"
	if [ $? -ne 0 ]; then
		ERROR=1
	fi
	output "${DELETED}" $LOG "${LOGFILE}"
fi



############################################################
# Exit
############################################################

if [ $ERROR -ne 0 ]; then
	# Send bad exit code
	output "[FAIL] Finished with errors" $LOG "${LOGFILE}"
	exit 4
else
	# Send good exit code
	output "[OK]   Finished successfully" $LOG "${LOGFILE}"
	exit 0
fi