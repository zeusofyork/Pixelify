#!/system/bin/sh
# Do NOT assume where your module will be located.
# ALWAYS use $MODDIR if you need to know where this script
# and module is placed.
# This will make sure your module will still work
# if Magisk change its mount point in the future
MODDIR=${0%/*}

. $MODDIR/vars.sh
. $MODDIR/utils.sh

MAINDIR=/data/adb/modules/Pixelify
# This script will be executed in late_start service mode

sqlite=/data/adb/modules/PixelifyUninstaller/addon/sqlite3
chmod 0755 $sqlite

gms=/data/data/com.google.android.gms/databases/phenotype.db
gser=/data/data/com.google.android.gsf/databases/gservices.db

disable="com.google.android.gms/com.google.android.gms.update.phone.PopupDialog"

update="com.android.vending/com.google.android.finsky.systemupdate.SystemUpdateSettingsContentProvider
com.android.vending/com.google.android.finsky.systemupdateactivity.SettingsSecurityEntryPoint
com.android.vending/com.google.android.finsky.systemupdateactivity.SystemUpdateActivity
com.google.android.gms/com.google.android.gms.update.phone.PopupDialog
com.google.android.gms/com.google.android.gms.update.OtaSuggestionSummaryProvider
com.google.android.gms/com.google.android.gms.update.SystemUpdateActivity
com.google.android.gms/com.google.android.gms.update.SystemUpdateGcmTaskService
com.google.android.gms/com.google.android.gms.update.SystemUpdateService
com.google.android.apps.wellbeing/com.google.android.apps.wellbeing.sleepinsights.ui.SleepInsightsActivity
com.google.android.apps.wellbeing/com.google.android.apps.wellbeing.sleepinsights.ui.dailyinsights.SleepInsightsDailyCardsActivity
com.google.android.apps.wellbeing/com.google.android.apps.wellbeing.coughandsnore.consent.ui.CoughAndSnoreConsentActivity"

set_device_config() {
    while read p; do
        if [ ! -z "$(echo $p)" ]; then
            if [ "$(echo $p | head -c 1)" != "#" ]; then
                name="$(echo $p | cut -d= -f1)"
                namespace="$(echo $name | cut -d/ -f1)"
                key="$(echo $name | cut -d/ -f2)"
                value="$(echo $p | cut -d= -f2)"
                device_config put $namespace $key $value
                # setprop persist.device_config.$namespace.$key $value
            fi
        fi
    done <$MODDIR/deviceconfig.txt
}

log() {
    date=$(date +%y/%m/%d)
    tim=$(date +%H:%M:%S)
    echo "$@"
    temp="$temp
$date $tim: $@"
}

set_prop() {
    setprop "$1" "$2"
    log "Setting prop $1 to $2"
}

bool_patch() {
    file=$2
    if [ -f $file ]; then
        line=$(grep $1 $2 | grep false | cut -c 16- | cut -d' ' -f1)
        for i in $line; do
            val_false='value="false"'
            val_true='value="true"'
            write="${i} $val_true"
            find="${i} $val_false"
            log "Setting bool $(echo $i | cut -d'"' -f2) to True"
            sed -i -e "s/${find}/${write}/g" $file
        done
    fi
}

bool_patch_false() {
    file=$2
    if [ -f $file ]; then
        line=$(grep $1 $2 | grep false | cut -c 14- | cut -d' ' -f1)
        for i in $line; do
            val_false='value="true"'
            val_true='value="false"'
            write="${i} $val_true"
            find="${i} $val_false"
            log "Setting bool $i to False"
            sed -i -e "s/${find}/${write}/g" $file
        done
    fi
}

string_patch() {
    file=$3
    if [ -f $file ]; then
        str1=$(grep $1 $3 | grep string | cut -c 14- | cut -d'>' -f1)
        for i in $str1; do
            str2=$(grep $i $3 | grep string | cut -c 14- | cut -d'<' -f1)
            add="$i>$2"
            if [ ! "$add" == "$str2" ]; then
                log "Setting string $i to $2"
                sed -i -e "s/${str2}/${add}/g" $file
            fi
        done
    fi
}

long_patch() {
    file=$3
    if [ -f $file ]; then
        lon=$(grep $1 $3 | grep long | cut -c 17- | cut -d'"' -f1)
        for i in $lon; do
            str=$(grep $i $3 | grep long | cut -c 17- | cut -d'"' -f1-2)
            str1=$(grep $i $3 | grep long | cut -c 17- | cut -d'"' -f1-3)
            add="$str\"$2"
            if [ ! "$add" == "$str1" ]; then
                log "Setting string $i to $2"
                sed -i -e "s/${str1}/${add}/g" $file
            fi
        done
    fi
}

TARGET_LOGGING=1
temp=""

pm_enable() {
    pm enable $1 >/dev/null 2>&1
    log "Enabling $1"
}

loop_count=0

# Wait for the boot
while true; do
    boot=$(getprop sys.boot_completed)
    if [ "$boot" -eq 1 ] && [ -d /data/data ]; then
        sleep 5
        log " Boot completed"
        break
    fi
    if [ $loop_count -gt 30 ]; then
        log " ! Boot time exceeded"
        break
    fi
    sleep 5
    loop_count=$((loop_count + 1))
done

# Uninstall if Pixelify is not detected.
if [ ! -d /data/adb/modules/Pixelify ]; then
    #Remove XML patches and let app to regenrate without them.
    rm -rf /data/data/com.google.android.dialer/shared_prefs/dialer_phenotype_flags.xml
    rm -rf /data/data/com.google.android.inputmethod.latin/shared_prefs/flag_value.xml
    rm -rf /data/data/com.google.android.inputmethod.latin/shared_prefs/flag_override.xml
    rm -rf /data/data/com.google.android.apps.fitness/shared_prefs/growthkit_phenotype_prefs.xml
    rm -rf /data/data/com.google.android.googlequicksearchbox/shared_prefs/GEL.GSAPrefs.xml
    rm -rf /data/data/com.google.android.apps.turbo/shared_prefs/phenotypeFlags.xml

    #Remove Pixelify version store data
    rm -rf /data/pixelify

    #Remove callscreening patch
    chmod 0755 /data/data/com.google.android.dialer/files/phenotype
    rm -rf chmod 0755 /data/data/com.google.android.dialer/files/phenotype/*

    #Remove GMS patches
    $sqlite $gms "DELETE FROM FlagOverrides"
    $sqlite $gser "DELETE FROM overrides"

    # Fixes Nexus Launcher gone
    rm -rf /data/system/package_cache/*

    # Uninstall packages of they are not system app.
    [ -z $(pm list packages -s | grep com.google.android.as) ] && pm uninstall com.google.android.as
    [ -z $(pm list packages -s | grep com.google.pixel.livewallpaper) ] && pm uninstall com.google.pixel.livewallpaper

    # Disable Pickachu Wallpaper if device on Pixel 4 or XL
    [[ "$(getprop ro.product.vendor.model)" != "Pixel 4" || "$(getprop ro.product.vendor.model)" != "Pixel 4 XL" ]] && pm disable -n com.google.pixel.livewallpaper/com.google.pixel.livewallpaper.pokemon.wallpapers.PokemonWallpaper -a android.intent.action.MAIN

    log "- Uninstalled Completed"

    # Remove Unistaller itself
    rm -rf /data/adb/modules/PixelifyUninstaller
else
    mkdir -p /sdcard/Pixelify

    log "Service Started"

    # Call Screening
    cp -Tf $MAINDIR/com.google.android.dialer /data/data/com.google.android.dialer/files/phenotype/com.google.android.dialer
    # copy bootlogs to Pixelify folder if bootloop happened.
    [ -f /data/adb/modules/Pixelify/boot_logs.txt ] && rm -rf /sdcard/Pixelify/boot_logs.txt && mv /data/adb/modules/Pixelify/boot_logs.txt /sdcard/Pixelify/boot_logs.txt

    for i in $disable; do
        pm disable $i
    done

    for i in $update; do
        pm enable $i
    done

    if [ $(grep CallScreen $MAINDIR/var.prop | cut -d'=' -f2) -eq 1 ]; then
        mkdir -p /data/data/com.google.android.dialer/files/phenotype
        cp -Tf $MAINDIR/com.google.android.dialer /data/data/com.google.android.dialer/files/phenotype/com.google.android.dialer
        chmod 500 /data/data/com.google.android.dialer/files/phenotype
        am force-stop com.google.android.dialer
    fi

    if [ $(grep Live $MAINDIR/var.prop | cut -d'=' -f2) -eq 1 ]; then
        pm enable -n com.google.pixel.livewallpaper/com.google.pixel.livewallpaper.pokemon.wallpapers.PokemonWallpaper -a android.intent.action.MAIN
    fi

    pm enable -n com.google.android.settings.intelligence/com.google.android.settings.intelligence.modules.battery.impl.usage.BootBroadcastReceiver -a android.intent.action.MAIN
    pm enable -n com.google.android.settings.intelligence/com.google.android.settings.intelligence.modules.battery.impl.usage.DataInjectorReceiver -a android.intent.action.MAIN
    pm enable -n com.google.android.settings.intelligence/com.google.android.settings.intelligence.modules.batterywidget.impl.BatteryWidgetBootBroadcastReceiver -a android.intent.action.MAIN
    pm enable -n com.google.android.settings.intelligence/com.google.android.settings.intelligence.modules.batterywidget.impl.BatteryWidgetUpdateReceiver -a android.intent.action.MAIN
    pm enable -n com.google.android.settings.intelligence/com.google.android.settings.intelligence.modules.battery.impl.usage.PeriodicJobReceiver -a android.intent.action.MAIN
    sleep .5
    pm enable -n com.google.android.settings.intelligence/com.google.android.settings.intelligence.modules.batterywidget.impl.BatteryAppWidgetProvider -a android.intent.action.MAIN

    am force-stop com.google.android.settings.intelligence

    settings put global settings_enable_clear_calling true
    settings put secure show_qr_code_scanner_setting true
    set_device_config

    patch_gboard
    am force-stop com.google.android.dialer com.google.android.inputmethod.latin

    pref_patch 45353596 true boolean $PHOTOS_PREF
    pref_patch 45363145 true boolean $PHOTOS_PREF
    pref_patch 45357512 true boolean $PHOTOS_PREF
    pref_patch 45361445 true boolean $PHOTOS_PREF
    pref_patch 45357511 true boolean $PHOTOS_PREF
    pref_patch photos.backup.throttled_state false boolean $PHOTOS_PREF

    if [ -f $MODDIR/first ]; then
        if [ -d /data/data/com.google.android.apps.nexuslauncher ]; then
            pm install $MODDIR/system/**/priv-app/WallpaperPickerGoogleRelease/WallpaperPickerGoogleRelease.apk
            if [ ! -f $PL_PREF ]; then
                echo "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>" >>$PL_PREF
                echo '<map>
    <int name="launcher.home_bounce_count" value="3" />
    <boolean name="launcher.apps_view_shown" value="true" />
    <boolean name="pref_allowChromeTabResult" value="false" />
    <boolean name="pref_allowWebResultAga" value="true" />
    <int name="ALL_APPS_SEARCH_CORPUS_PREFERENCE" value="206719" />
    <boolean name="pref_allowWidgetsResult" value="false" />
    <int name="migration_src_device_type" value="0" />
    <boolean name="pref_search_show_keyboard" value="false" />
    <boolean name="pref_allowPeopleResult" value="true" />
    <boolean name="pref_enable_minus_one" value="true" />
    <string name="migration_src_workspace_size">5,5</string>
    <boolean name="pref_search_show_hidden_targets" value="false" />
    <boolean name="pref_allowWebSuggestChrome" value="false" />
    <boolean name="pref_allowPixelTipsResult" value="true" />
    <string name="idp_grid_name">normal</string>
    <boolean name="pref_allowScreenshotResult" value="true" />
    <boolean name="pref_allowMemoryResult" value="true" />
    <boolean name="pref_allowShortcutResult" value="true" />
    <boolean name="pref_allowRotation" value="false" />
    <boolean name="launcher.select_tip_seen" value="true" />
    <boolean name="pref_allowWebResult" value="true" />
    <boolean name="pref_allowSettingsResult" value="true" />
    <int name="migration_src_hotseat_count" value="5" />
    <int name="launcher.hotseat_discovery_tip_count" value="5" />
    <boolean name="pref_add_icon_to_home" value="true" />
    <string name="migration_src_db_file">launcher.db</string>
    <boolean name="pref_overview_action_suggestions" value="false" />
    <boolean name="pref_allowPlayResult" value="true" />
    <int name="launcher.all_apps_visited_count" value="10" />
</map>' >>$PL_PREF
            else
                pref_patch pref_overview_action_suggestions false boolean $PL_PREF
            fi
            am force-stop com.google.android.apps.nexuslauncher
        fi
        rm -rf $MODDIR/first
    fi
fi

# loop=0
# while true; do
#     set_device_config
#     # Run loop for 10mins
#     if [ $loop -ge 600 ]; then
#         break
#     fi
#     sleep 1
#     loop=$((loop + 1))
# done
# sleep 30
# [ $(device_config get privacy location_accuracy_enabled) != "true" ] && sleep 1 && set_device_config

log "Service Finished"
echo "$temp" >>/sdcard/Pixelify/logs.txt