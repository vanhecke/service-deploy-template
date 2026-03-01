#!/usr/bin/env bash
# @description Application hooks — override these functions in your project.
#
# This file is sourced by both deploy.sh and ctl.sh. Replace the stub
# implementations below with your actual application logic.
#
# Available context when hooks run:
#   APP_NAME, APP_USER, APP_PORT, APP_DATA_DIR — from .env config
#   All lib/core/* and lib/modules/* functions are loaded

# @description Install the application (download, extract, build).
# Called during initial deployment and re-deployment.
app_install() {
    logging::info "No app_install hook defined"
}

# @description Generate or update application configuration files.
app_configure() {
    logging::info "No app_configure hook defined"
}

# @description Run after systemd services are enabled and started.
app_post_install() {
    :
}

# @description Update the application to the latest version.
# Called by: ctl upgrade
app_update() {
    logging::info "No app_update hook defined"
}

# @description Application-specific health checks beyond service/port status.
# Return non-zero to indicate unhealthy.
# Called by: ctl health
app_health() {
    return 0
}

# @description Return the currently installed application version string.
# Called by: ctl version
app_version() {
    echo "unknown"
}

# @description Back up application-specific data.
# Called by: ctl backup
app_backup() {
    logging::info "No app_backup hook defined"
}

# @description Restore application data from backup.
# Called by: ctl restore
app_restore() {
    logging::info "No app_restore hook defined"
}

# @description Clean up application files during uninstall.
# Called by: ctl uninstall
app_uninstall() {
    logging::info "No app_uninstall hook defined"
}
