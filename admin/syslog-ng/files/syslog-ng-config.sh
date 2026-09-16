#!/bin/sh
# syslog-ng-config — UCI-driven configuration generator for syslog-ng
#
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
#
# Reads /etc/config/syslog-ng and dynamically generates:
#   /etc/syslog-ng.conf
#   /etc/logrotate.d/syslog-ng.conf
# Usage:
#   syslog-ng-config apply                        regenerate + reload (no reboot)
#   syslog-ng-config generate                     regenerate configs only
#   syslog-ng-config add-source <name> [opts]     add custom log source + apply
#   syslog-ng-config remove-source <name>         remove custom source + apply
#   syslog-ng-config add-filter <name> [opts]     add subsystem filter + apply
#   syslog-ng-config remove-filter <name>         remove filter + apply
#   syslog-ng-config list                         show active sources, filters, remote config
#   syslog-ng-config set-remote <host> [opts]     configure remote forwarding
#   syslog-ng-config disable-remote               disable remote forwarding + apply
#   syslog-ng-config set-logrotate [opts]         change global logrotate settings

. /lib/functions.sh

SYSLOG_CONF="/etc/syslog-ng.conf"
LOGROTATE_CONF="/etc/logrotate.d/syslog-ng.conf"
CRON_FILE="/etc/crontabs/root"
UCI_PKG="syslog-ng"

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "$(date '+%b %d %H:%M:%S') $*"; }

# Validate a UCI section name: only alphanumeric, underscore, hyphen allowed.
# UCI section names with other characters cause silent failures or injection.
validate_name() {
	local val="$1" label="${2:-name}"
	[ -n "$val" ] || die "$label must not be empty"
	echo "$val" | grep -qE '^[a-zA-Z0-9_][a-zA-Z0-9_-]*$' || \
		die "$label '$val' is invalid — only alphanumeric, underscore, and hyphen are allowed"
}

# Validate a UCI option value: reject empty strings, double quotes (would break
# generated syslog-ng config syntax), single quotes (would break UCI quoting),
# and common shell injection characters.
validate_value() {
	local val="$1" label="${2:-value}"
	[ -n "$val" ] || die "$label must not be empty"
	case "$val" in
		*\'*|*\"*|*\`*|*\$\(*|*\$\{*)
			die "$label contains unsafe characters (quote, backtick, or command substitution)" ;;
	esac
}

# ─────────────────────────────────────────────────────────────────────────────
# syslog-ng.conf generation
# ─────────────────────────────────────────────────────────────────────────────

_gen_options() {
	local chain_hostnames create_dirs keep_hostname log_fifo_size
	local log_msg_size stats_freq flush_lines use_fqdn keep_timestamp threaded

	config_get chain_hostnames  global chain_hostnames  "no"
	config_get create_dirs      global create_dirs      "yes"
	config_get keep_hostname    global keep_hostname    "yes"
	config_get log_fifo_size    global log_fifo_size    "256"
	config_get log_msg_size     global log_msg_size     "1024"
	config_get stats_freq       global stats_freq       "0"
	config_get flush_lines      global flush_lines      "0"
	config_get use_fqdn         global use_fqdn         "no"
	config_get keep_timestamp   global keep_timestamp   "no"
	config_get threaded         global threaded         "no"

	cat <<EOF
options {
	chain_hostnames($chain_hostnames);
	create_dirs($create_dirs);
	keep_hostname($keep_hostname);
	log_fifo_size($log_fifo_size);
	log_msg_size($log_msg_size);
	stats(freq($stats_freq));
	flush_lines($flush_lines);
	use_fqdn($use_fqdn);
	keep_timestamp($keep_timestamp);
	threaded($threaded);
};

EOF
}

_gen_default_sources() {
	cat <<'EOF'
source src {
	internal();
	unix-dgram("/dev/log");
};

source kernel {
	file("/proc/kmsg" program_override("kernel"));
};

EOF
}

_gen_default_destination() {
	cat <<'EOF'
destination messages {
	file("/var/log/messages");
};

EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# Custom source generation
# ─────────────────────────────────────────────────────────────────────────────

# Accumulator: space-separated list of enabled custom source names
# Used to include them in log rules
_custom_source_list=""

# Called by config_foreach for each 'source' section — emits source block
_gen_custom_source() {
	local section="$1"
	local enabled name type path program_override

	config_get_bool enabled "$section" enabled 1
	[ "$enabled" = "0" ] && return

	config_get name             "$section" name             "$section"
	config_get type             "$section" type             "file"
	config_get path             "$section" path             ""
	config_get program_override "$section" program_override ""

	[ -z "$path" ] && {
		echo "# WARNING: source '${name}' has no path — skipped" >&2
		return
	}

	# Accumulate source name for use in log rules
	_custom_source_list="${_custom_source_list} ${name}"

	case "$type" in
		file)
			if [ -n "$program_override" ]; then
				printf 'source %s {\n\tfile("%s" program_override("%s"));\n};\n\n' \
					"$name" "$path" "$program_override" >> "$TMPCONF"
			else
				printf 'source %s {\n\tfile("%s");\n};\n\n' \
					"$name" "$path" >> "$TMPCONF"
			fi
			;;
		unix_dgram|unix-dgram)
			printf 'source %s {\n\tunix-dgram("%s");\n};\n\n' \
				"$name" "$path" >> "$TMPCONF"
			;;
		network)
			local port transport
			config_get port      "$section" port      "514"
			config_get transport "$section" transport "udp"
			printf 'source %s {\n\tnetwork(ip("%s") port(%s) transport("%s"));\n};\n\n' \
				"$name" "$path" "$port" "$transport" >> "$TMPCONF"
			;;
		*)
			echo "# WARNING: source '${name}' has unknown type '${type}' — skipped" >&2
			;;
	esac
}

# Build the source() lines for a log rule (default + custom sources)
_gen_log_rule_sources() {
	printf '\tsource(src);\n'
	printf '\tsource(kernel);\n'
	local src
	# Use ${_custom_source_list# } to strip the leading space added during
	# accumulation, preventing an empty token on the first loop iteration
	# which would emit a bare source(); and break syslog-ng config parsing.
	for src in ${_custom_source_list# }; do
		[ -n "$src" ] && printf '\tsource(%s);\n' "$src"
	done
}

# ─────────────────────────────────────────────────────────────────────────────
# Filter generation
# ─────────────────────────────────────────────────────────────────────────────

# Accumulator for facility list values, populated by config_list_foreach
_facility_list=""
_collect_facility() {
	local fac="$1"
	if [ -z "$_facility_list" ]; then
		_facility_list="$fac"
	else
		_facility_list="${_facility_list}, ${fac}"
	fi
}

# Called by config_foreach for each 'filter' section — emits filter + destination blocks
_gen_filter_block() {
	local section="$1"
	local enabled name match program level logfile

	config_get_bool enabled "$section" enabled 1
	[ "$enabled" = "0" ] && return

	config_get name    "$section" name    "$section"
	config_get match   "$section" match   ""
	config_get program "$section" program ""
	config_get level   "$section" level   ""
	config_get logfile "$section" logfile "/var/log/${name}_messages"

	_facility_list=""
	config_list_foreach "$section" facility _collect_facility

	local criteria="" sep=""

	if [ -n "$_facility_list" ]; then
		criteria="${criteria}${sep}facility(${_facility_list})"
		sep=" and "
	fi

	if [ -n "$level" ]; then
		criteria="${criteria}${sep}level(${level})"
		sep=" and "
	fi

	if [ -n "$program" ]; then
		criteria="${criteria}${sep}program(\"${program}\")"
		sep=" and "
	fi

	if [ -n "$match" ]; then
		criteria="${criteria}${sep}match(\"${match}\" value(\"MESSAGE\"))"
		sep=" and "
	fi

	[ -z "$criteria" ] && {
		echo "# WARNING: filter '${name}' has no matching criteria — skipped" >&2
		return
	}

	printf 'filter f_%s {\n\t%s;\n};\n\n' "$name" "$criteria" >> "$TMPCONF"
	printf 'destination %s_messages {\n\tfile("%s");\n};\n\n' "$name" "$logfile" >> "$TMPCONF"
}

# Called by config_foreach for each 'filter' section — emits its log rule
# Includes all custom sources alongside src and kernel
_gen_filter_log_rule() {
	local section="$1"
	local enabled name

	config_get_bool enabled "$section" enabled 1
	[ "$enabled" = "0" ] && return

	config_get name "$section" name "$section"

	{
		printf 'log {\n'
		_gen_log_rule_sources
		printf '\tfilter(f_%s);\n' "$name"
		printf '\tdestination(%s_messages);\n' "$name"
		printf '};\n\n'
	} >> "$TMPCONF"
}

_gen_remote_destination() {
	local enabled type host port

	config_get_bool enabled remote enabled 0
	[ "$enabled" = "0" ] && return

	config_get type remote type "udp"
	config_get host remote host ""
	config_get port remote port "514"

	[ -z "$host" ] && {
		echo "# WARNING: remote forwarding enabled but no host configured — skipped" >&2
		return
	}

	case "$type" in
		tcp|udp)
			printf 'destination remote {\n\tnetwork("%s" port(%s) transport("%s"));\n};\n\n' \
				"$host" "$port" "$type" >> "$TMPCONF"
			;;
		*)
			echo "# WARNING: remote type '${type}' is not supported — skipped" >&2
			;;
	esac
}

_gen_remote_log_rule() {
	local enabled host

	config_get_bool enabled remote enabled 0
	[ "$enabled" = "0" ] && return

	config_get host remote host ""
	[ -z "$host" ] && return

	{
		printf 'log {\n'
		_gen_log_rule_sources
		printf '\tdestination(remote);\n'
		printf '};\n\n'
	} >> "$TMPCONF"
}

generate_syslog_conf() {
	config_load "$UCI_PKG"

	# Reset custom source accumulator before each generation
	_custom_source_list=""

	# Use a distinct variable name to avoid clobbering the logrotate TMPCONF
	# if generate_logrotate_conf is ever called concurrently or out of order.
	TMPCONF=$(mktemp /tmp/syslog-ng-conf-XXXXXX) || die "cannot create temp file"

	{
		printf '# syslog-ng configuration — auto-generated by syslog-ng-config\n'
		printf '# Do not edit manually. Use: syslog-ng-config apply\n'
		printf '# Source of truth: /etc/config/syslog-ng\n\n'
		printf '@version: current\n'
		printf '@include "scl.conf"\n\n'
	} >> "$TMPCONF"

	_gen_options >> "$TMPCONF"

	# Default sources (always present)
	_gen_default_sources >> "$TMPCONF"

	# Custom sources from UCI — also populates _custom_source_list
	config_foreach _gen_custom_source source

	_gen_default_destination >> "$TMPCONF"

	# Filter blocks + destinations
	config_foreach _gen_filter_block filter

	# Remote destination (if enabled)
	_gen_remote_destination

	# Default log rule — ALL sources → /var/log/messages (always present, never removed)
	{
		printf 'log {\n'
		_gen_log_rule_sources
		printf '\tdestination(messages);\n'
		printf '};\n\n'
	} >> "$TMPCONF"

	# Per-filter log rules
	config_foreach _gen_filter_log_rule filter

	# Remote log rule (if enabled)
	_gen_remote_log_rule

	printf '@include "/etc/syslog-ng.d/"\n' >> "$TMPCONF"

	mv "$TMPCONF" "$SYSLOG_CONF" || {
		rm -f "$TMPCONF"
		die "cannot write $SYSLOG_CONF"
	}
	echo "Generated $SYSLOG_CONF"
}

# ─────────────────────────────────────────────────────────────────────────────
# logrotate config generation
# ─────────────────────────────────────────────────────────────────────────────

_gen_logrotate_stanza() {
	local logfile="$1"
	local maxsize="$2"
	local rotate="$3"
	local compress="$4"
	local copytruncate="$5"
	local notifempty="$6"
	local missingok="$7"
	local rotate_when="$8"

	printf '%s {\n' "$logfile"
	printf '\tsu root root\n'
	[ "$compress"     = "1" ] && printf '\tcompress\n'
	[ "$copytruncate" = "1" ] && printf '\tcopytruncate\n'
	[ "$notifempty"   = "1" ] && printf '\tnotifempty\n'
	printf '\tmaxsize %s\n' "$maxsize"
	[ "$missingok"    = "1" ] && printf '\tmissingok\n'
	[ -n "$rotate_when" ]     && printf '\t%s\n' "$rotate_when"
	printf '\tpostrotate\n'
	printf '\t\t/usr/sbin/syslog-ng-ctl reload > /dev/null\n'
	printf '\tendscript\n'
	printf '\trotate %s\n' "$rotate"
	printf '}\n'
}

_gen_filter_logrotate_stanza() {
	local section="$1"
	local enabled name logfile f_maxsize f_rotate

	config_get_bool enabled "$section" enabled 1
	[ "$enabled" = "0" ] && return

	config_get name    "$section" name    "$section"
	config_get logfile "$section" logfile "/var/log/${name}_messages"

	config_get f_maxsize "$section" maxsize "$lr_maxsize"
	config_get f_rotate  "$section" rotate  "$lr_rotate"

	printf '\n' >> "$TMPCONF"
	_gen_logrotate_stanza \
		"$logfile" \
		"$f_maxsize" "$f_rotate" "$lr_compress" "$lr_copytruncate" \
		"$lr_notifempty" "$lr_missingok" "$lr_rotate_when" >> "$TMPCONF"
}

generate_logrotate_conf() {
	local lr_enabled

	config_load "$UCI_PKG"

	config_get_bool lr_enabled logrotate enabled 1
	[ "$lr_enabled" = "0" ] && {
		echo "Logrotate disabled — skipping logrotate config generation."
		rm -f "$LOGROTATE_CONF"
		return
	}

	config_get lr_maxsize      logrotate maxsize      "300K"
	config_get lr_rotate       logrotate rotate       "2"
	config_get lr_compress     logrotate compress     "1"
	config_get lr_copytruncate logrotate copytruncate "1"
	config_get lr_notifempty   logrotate notifempty   "1"
	config_get lr_missingok    logrotate missingok    "1"
	config_get lr_rotate_when  logrotate rotate_when  ""

	mkdir -p "$(dirname "$LOGROTATE_CONF")"
	# Use a distinct variable name to avoid clobbering the syslog-ng TMPCONF.
	TMPCONF=$(mktemp /tmp/syslog-ng-lr-XXXXXX) || die "cannot create temp file"

	{
		printf '# syslog-ng logrotate configuration\n'
		printf '# AUTO-GENERATED by syslog-ng-config — do not edit manually.\n\n'
	} >> "$TMPCONF"

	_gen_logrotate_stanza \
		"/var/log/messages" \
		"$lr_maxsize" "$lr_rotate" "$lr_compress" "$lr_copytruncate" \
		"$lr_notifempty" "$lr_missingok" "$lr_rotate_when" >> "$TMPCONF"

	config_foreach _gen_filter_logrotate_stanza filter

	mv "$TMPCONF" "$LOGROTATE_CONF" || {
		rm -f "$TMPCONF"
		die "cannot write $LOGROTATE_CONF"
	}
	echo "Generated $LOGROTATE_CONF"
}

# ─────────────────────────────────────────────────────────────────────────────
# Cron management
# ─────────────────────────────────────────────────────────────────────────────

update_cron() {
	local lr_enabled schedule cron_expr new_entry existing_entry

	config_load "$UCI_PKG"
	config_get_bool lr_enabled logrotate enabled 1
	config_get schedule logrotate schedule "minutely"

	case "$schedule" in
		minutely) cron_expr="*/1 * * * *" ;;
		hourly)   cron_expr="0 * * * *"   ;;
		daily)    cron_expr="0 0 * * *"   ;;
		weekly)   cron_expr="0 0 * * 0"   ;;
		monthly)  cron_expr="0 0 1 * *"   ;;
		*)        cron_expr="$schedule"   ;;
	esac

	new_entry="$cron_expr logrotate $LOGROTATE_CONF"

	# Ensure /etc/crontabs/ directory and file exist before any operations
	mkdir -p "$(dirname "$CRON_FILE")"
	touch "$CRON_FILE" 2>/dev/null

	# Check if the correct entry already exists BEFORE removing it
	existing_entry=$(grep -F "$new_entry" "$CRON_FILE" 2>/dev/null)

	# Remove any existing logrotate entry (old schedule or current)
	sed -i "\|logrotate ${LOGROTATE_CONF}|d" "$CRON_FILE" 2>/dev/null

	[ "$lr_enabled" = "0" ] && return

	# Always re-add the entry (was just removed by sed above)
	echo "$new_entry" >> "$CRON_FILE"

	# Only restart cron if the entry was not already correct (i.e. schedule changed)
	if [ -z "$existing_entry" ]; then
		uci -q set system.@system[0].cronloglevel='9' 2>/dev/null
		uci -q commit system 2>/dev/null
		/etc/init.d/cron restart 2>/dev/null
		echo "Logrotate cron job set: $cron_expr"
	fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Reload syslog-ng
# ─────────────────────────────────────────────────────────────────────────────

reload_syslog_ng() {
	local reload_output reload_rc

	if pidof syslog-ng >/dev/null 2>&1; then
		# Capture both stdout/stderr and exit code. syslog-ng-ctl can exit 0
		# even when the daemon rejects the new config and reverts to the
		# previous one — the failure is only visible in the output text
		# (e.g. "Config reload failed, reverted to previous config").
		# Blindly printing "reloaded" here would silently hide such failures.
		reload_output=$(/usr/sbin/syslog-ng-ctl reload 2>&1)
		reload_rc=$?

		if [ "$reload_rc" -ne 0 ] || echo "$reload_output" | grep -qi "fail\|error\|revert"; then
			[ -n "$reload_output" ] && echo "$reload_output" >&2
			return 1
		fi

		[ -n "$reload_output" ] && echo "$reload_output"
		echo "syslog-ng reloaded"
	else
		info "syslog-ng not running — skipping reload"
	fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Auto-rollback on invalid configuration
# ─────────────────────────────────────────────────────────────────────────────
# If a newly added/changed section makes syslog-ng reject the generated
# config (e.g. a network() source bound to an address the device doesn't
# own), the daemon itself reverts to the last known-good config — but our
# UCI store still has the bad section, so every future 'apply' keeps
# regenerating and re-failing on the same entry. These helpers detect that
# failure right after the change is made and automatically undo the change
# in UCI, restoring a working configuration without user intervention.

_rollback_delete_section() {
	local section="$1"
	uci -q delete "${UCI_PKG}.${section}" 2>/dev/null
	uci commit "$UCI_PKG"
}

_rollback_disable_remote() {
	uci -q set "${UCI_PKG}.remote.enabled"='0' 2>/dev/null
	uci commit "$UCI_PKG"
}

# _apply_or_rollback <description> <rollback_function> [rollback_arg]
# Regenerates configs and reloads syslog-ng. On failure, invokes the given
# rollback function to undo the just-made UCI change, re-applies, and exits
# with a clear message. On success, returns normally.
_apply_or_rollback() {
	local desc="$1" rollback_func="$2" rollback_arg="$3"

	cmd_generate
	if reload_syslog_ng; then
		return 0
	fi

	echo "ERROR: '$desc' caused syslog-ng to reject the generated config." >&2
	echo "Rolling back automatically ..." >&2
	"$rollback_func" "$rollback_arg"

	cmd_generate
	if reload_syslog_ng; then
		echo "Rollback successful — syslog-ng is running with the previous known-good configuration." >&2
	else
		echo "WARNING: rollback did not fully restore a working config." >&2
		echo "Run 'syslog-ng-config list' and inspect /etc/config/syslog-ng manually." >&2
	fi

	die "'$desc' was invalid and has been removed automatically."
}

# ─────────────────────────────────────────────────────────────────────────────
# Top-level commands
# ─────────────────────────────────────────────────────────────────────────────

cmd_generate() {
	generate_syslog_conf
	generate_logrotate_conf
	update_cron
}

cmd_apply() {
	cmd_generate
	if ! reload_syslog_ng; then
		echo "ERROR: syslog-ng rejected the regenerated config and reverted to the previous one." >&2
		echo "Run 'syslog-ng-config list' to review sources/filters/remote settings," >&2
		echo "identify the invalid entry, and remove or fix it with one of:" >&2
		echo "  syslog-ng-config remove-source <name>" >&2
		echo "  syslog-ng-config remove-filter <name>" >&2
		echo "  syslog-ng-config disable-remote" >&2
		return 1
	fi
}

cmd_list() {
	config_load "$UCI_PKG"

	echo "== Global options =="
	config_get chain_hostnames global chain_hostnames "no"
	config_get log_fifo_size   global log_fifo_size   "64"
	config_get log_msg_size    global log_msg_size    "1024"
	echo "  chain_hostnames=$chain_hostnames log_fifo_size=$log_fifo_size log_msg_size=$log_msg_size"

	echo "== Sources =="
	echo "  [src]    enabled=1  internal() + unix-dgram(/dev/log)  [built-in]"
	echo "  [kernel] enabled=1  file(/proc/kmsg)                   [built-in]"
	_print_source() {
		local section="$1"
		local enabled name type path program_override
		config_get_bool enabled         "$section" enabled         1
		config_get name                 "$section" name            "$section"
		config_get type                 "$section" type            "file"
		config_get path                 "$section" path            ""
		config_get program_override     "$section" program_override ""
		echo "  [$name] enabled=$enabled type=$type path=$path${program_override:+ program_override=$program_override}"
	}
	config_foreach _print_source source

	echo "== Filters =="
	_print_filter() {
		local section="$1"
		local enabled name match program level logfile

		config_get_bool enabled "$section" enabled 1
		config_get name    "$section" name    "$section"
		config_get match   "$section" match   ""
		config_get program "$section" program ""
		config_get level   "$section" level   ""
		config_get logfile "$section" logfile "/var/log/${name}_messages"

		_facility_list=""
		config_list_foreach "$section" facility _collect_facility

		echo "  [$name] enabled=$enabled logfile=$logfile"
		[ -n "$match" ]          && echo "      match=$match"
		[ -n "$program" ]        && echo "      program=$program"
		[ -n "$_facility_list" ] && echo "      facility=$_facility_list"
		[ -n "$level" ]          && echo "      level=$level"
	}
	config_foreach _print_filter filter

	echo "== Remote forwarding =="
	config_get_bool r_enabled remote enabled 0
	config_get r_type   remote type   "udp"
	config_get r_host   remote host   ""
	config_get r_port   remote port   "514"
	echo "  enabled=$r_enabled type=$r_type host=$r_host port=$r_port"

	echo "== Logrotate =="
	config_get_bool lr_enabled logrotate enabled 1
	config_get lr_maxsize  logrotate maxsize   "300K"
	config_get lr_rotate   logrotate rotate    "2"
	config_get lr_schedule logrotate schedule  "minutely"
	echo "  enabled=$lr_enabled maxsize=$lr_maxsize rotate=$lr_rotate schedule=$lr_schedule"
}

cmd_add_source() {
	local name="$1"
	[ -n "$name" ] || die "usage: add-source <name> [opts]"
	validate_name "$name" "source name"
	shift

	local type="file" path="" program_override=""

	while [ "$#" -gt 0 ]; do
		case "$1" in
			--type)             type="$2";             shift 2 ;;
			--path)             path="$2";             shift 2 ;;
			--program-override) program_override="$2"; shift 2 ;;
			*) die "unknown option: $1" ;;
		esac
	done

	[ -z "$path" ] && die "usage: add-source <name> --path <path> [--type file|unix-dgram|network] [--program-override <name>]"
	validate_value "$path" "path"
	[ -n "$program_override" ] && validate_name "$program_override" "program-override"

	uci -q batch <<-EOF
	set ${UCI_PKG}.${name}='source'
	set ${UCI_PKG}.${name}.enabled='1'
	set ${UCI_PKG}.${name}.name='${name}'
	set ${UCI_PKG}.${name}.type='${type}'
	set ${UCI_PKG}.${name}.path='${path}'
	EOF

	[ -n "$program_override" ] && uci -q set ${UCI_PKG}.${name}.program_override="$program_override"

	uci commit "$UCI_PKG"
	echo "Added source '$name' (type=$type path=$path)"
	_apply_or_rollback "source '$name'" _rollback_delete_section "$name"
}

cmd_remove_source() {
	local name="$1"
	[ -n "$name" ] || die "usage: remove-source <name>"
	validate_name "$name" "source name"

	uci -q delete ${UCI_PKG}.${name}
	uci commit "$UCI_PKG"
	echo "Removed source '$name'"
	cmd_apply
}

cmd_add_filter() {
	local name="$1"
	[ -n "$name" ] || die "usage: add-filter <name> [opts]"
	validate_name "$name" "filter name"
	shift

	local match="" program="" level="" logfile="" maxsize="" rotate=""
	local facilities=""

	while [ "$#" -gt 0 ]; do
		case "$1" in
			--match)    match="$2"; shift 2 ;;
			--program)  program="$2"; shift 2 ;;
			--facility) facilities="${facilities} $2"; shift 2 ;;
			--level)    level="$2"; shift 2 ;;
			--logfile)  logfile="$2"; shift 2 ;;
			--maxsize)  maxsize="$2"; shift 2 ;;
			--rotate)   rotate="$2"; shift 2 ;;
			*) die "unknown option: $1" ;;
		esac
	done

	[ -z "$match" ] && [ -z "$program" ] && [ -z "$facilities" ] && [ -z "$level" ] && match="$name"
	[ -n "$match" ]   && validate_value "$match"   "match pattern"
	[ -n "$program" ] && validate_value "$program" "program name"
	[ -n "$logfile" ] && validate_value "$logfile" "logfile path"

	uci -q batch <<-EOF
	set ${UCI_PKG}.${name}='filter'
	set ${UCI_PKG}.${name}.enabled='1'
	EOF

	[ -n "$match" ]    && uci -q set ${UCI_PKG}.${name}.match="$match"
	[ -n "$program" ]  && uci -q set ${UCI_PKG}.${name}.program="$program"
	[ -n "$level" ]    && uci -q set ${UCI_PKG}.${name}.level="$level"
	[ -n "$logfile" ]  && uci -q set ${UCI_PKG}.${name}.logfile="$logfile"
	[ -n "$maxsize" ]  && uci -q set ${UCI_PKG}.${name}.maxsize="$maxsize"
	[ -n "$rotate" ]   && uci -q set ${UCI_PKG}.${name}.rotate="$rotate"

	if [ -n "$facilities" ]; then
		uci -q delete ${UCI_PKG}.${name}.facility 2>/dev/null
		local fac
		for fac in $facilities; do
			uci -q add_list ${UCI_PKG}.${name}.facility="$fac"
		done
	fi

	uci commit "$UCI_PKG"
	echo "Added filter '$name'"
	_apply_or_rollback "filter '$name'" _rollback_delete_section "$name"
}

cmd_remove_filter() {
	local name="$1"
	[ -n "$name" ] || die "usage: remove-filter <name>"
	validate_name "$name" "filter name"

	uci -q delete ${UCI_PKG}.${name}
	uci commit "$UCI_PKG"
	echo "Removed filter '$name'"
	cmd_apply
}

cmd_set_remote() {
	local host="$1"
	[ -n "$host" ] || die "usage: set-remote <host> [opts]"
	validate_value "$host" "host"
	shift

	local type="udp" port="514"

	while [ "$#" -gt 0 ]; do
		case "$1" in
			--type) type="$2"; shift 2 ;;
			--port) port="$2"; shift 2 ;;
			*) die "unknown option: $1" ;;
		esac
	done

	case "$type" in
		udp|tcp) ;;
		*) die "unsupported remote type '$type' — only udp and tcp are supported" ;;
	esac

	# Ensure the remote section exists before setting options.
	# On a fresh install where the section was deleted, uci set on a
	# non-existent section fails silently with -q.
	uci -q set ${UCI_PKG}.remote='remote' 2>/dev/null
	uci -q set ${UCI_PKG}.remote.enabled='1'
	uci -q set ${UCI_PKG}.remote.host="$host"
	uci -q set ${UCI_PKG}.remote.type="$type"
	uci -q set ${UCI_PKG}.remote.port="$port"

	uci commit "$UCI_PKG"
	echo "Remote forwarding configured: $host ($type:$port)"
	_apply_or_rollback "remote forwarding to '$host'" _rollback_disable_remote ""
}

cmd_disable_remote() {
	uci -q set ${UCI_PKG}.remote.enabled='0'
	uci commit "$UCI_PKG"
	echo "Remote forwarding disabled"
	cmd_apply
}

cmd_set_logrotate() {
	while [ "$#" -gt 0 ]; do
		case "$1" in
			--maxsize)     uci -q set ${UCI_PKG}.logrotate.maxsize="$2"; shift 2 ;;
			--rotate)      uci -q set ${UCI_PKG}.logrotate.rotate="$2"; shift 2 ;;
			--schedule)    uci -q set ${UCI_PKG}.logrotate.schedule="$2"; shift 2 ;;
			--rotate-when) uci -q set ${UCI_PKG}.logrotate.rotate_when="$2"; shift 2 ;;
			*) die "unknown option: $1" ;;
		esac
	done

	uci commit "$UCI_PKG"
	echo "Logrotate settings updated"
	cmd_apply
}

usage() {
	cat <<EOF
Usage: syslog-ng-config <command> [args]

Commands:
  apply                              regenerate configs + reload syslog-ng + update cron
  generate                           regenerate configs only (no reload)

  add-source <name> [opts]           add custom log source + apply
    --type file|unix-dgram|network   source type (default: file)
    --path <path>                    file path or socket path
    --program-override <name>        tag messages with this program name
    # add-source hostapd --path /tmp/hapd.log --type file --program-override hostapd

  remove-source <name>               remove custom source + apply
    # remove-source hostapd

  add-filter <name> [opts]           add subsystem filter + apply
    --match <regex>                  regex on message text
    --program <name>                 match by program name
    --facility <fac>                 match by syslog facility (repeatable)
    --level <level>                  match by severity
    --logfile <path>                 override log file path
    --maxsize <size>                 override logrotate maxsize for this file
    --rotate <n>                     override rotate count for this file
    # add-filter ath12k --match 'ath12k' --logfile /var/log/ath12k.log --maxsize 1M --rotate 3
    # add-filter kern_err --facility kern --level err
    # add-filter hostapd --program hostapd

  remove-filter <name>               remove filter + apply
    # remove-filter ath12k

  list                               show active sources, filters, remote config

  set-remote <host> [opts]           enable/configure remote forwarding + apply
    --type udp|tcp                   transport (default: udp)
    --port <port>                    remote port (default: 514)
    # set-remote 10.0.0.5 --type udp --port 514
    # set-remote 10.0.0.5 --type tcp --port 1514

  disable-remote                     disable remote forwarding + apply

  set-logrotate [opts]               change global logrotate settings + apply
    --maxsize <size>                 e.g. 300K, 1M
    --rotate <n>                     rotation count
    --schedule <val>                 minutely|hourly|daily|weekly|monthly|<cron>
    --rotate-when <val>              daily|weekly|monthly (time-based rotation)
    # set-logrotate --maxsize 1M --rotate 5 --schedule daily --rotate-when daily
EOF
	exit 1
}

main() {
	local cmd="$1"
	[ -n "$cmd" ] || usage
	shift

	case "$cmd" in
		apply)           cmd_apply "$@" ;;
		generate)        cmd_generate "$@" ;;
		add-source)      cmd_add_source "$@" ;;
		remove-source)   cmd_remove_source "$@" ;;
		add-filter)      cmd_add_filter "$@" ;;
		remove-filter)   cmd_remove_filter "$@" ;;
		list)            cmd_list "$@" ;;
		set-remote)      cmd_set_remote "$@" ;;
		disable-remote)  cmd_disable_remote "$@" ;;
		set-logrotate)   cmd_set_logrotate "$@" ;;
		*) usage ;;
	esac
}

main "$@"