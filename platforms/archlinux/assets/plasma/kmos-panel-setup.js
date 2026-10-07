// Runs only when Plasma creates a new panel from the KMOS layout template.
// The widget order is set by layout.js; never run this as a Plasma update hook.
function configureKmosClock(widget, timezone, showDate) {
    if (!widget) {
        return;
    }
    widget.currentConfigGroup = ["Appearance"];
    widget.writeConfig("selectedTimeZones", [timezone]);
    widget.writeConfig("lastSelectedTimezone", timezone);
    widget.writeConfig("showDate", showDate);
    widget.writeConfig("dateFormat", "isoDate");
    widget.writeConfig("displayTimezoneFormat", "FullText");
    widget.writeConfig("showLocalTimezone", true);
    widget.reloadConfig();
}

var kmosClocks = panel.widgets("org.kde.plasma.digitalclock");
if (kmosClocks.length === 3) {
    configureKmosClock(kmosClocks[0], "America/Bogota", false);
    configureKmosClock(kmosClocks[1], "Local", true);
    configureKmosClock(kmosClocks[2], "Asia/Shanghai", false);
}

var kmosTaskManagers = panel.widgets("org.kde.plasma.icontasks");
for (var i = 0; i < kmosTaskManagers.length; i++) {
    kmosTaskManagers[i].currentConfigGroup = ["General"];
    kmosTaskManagers[i].writeConfig("launchers", "");
}

var kmosDashboards = panel.widgets("org.kde.plasma.kickerdash");
if (kmosDashboards.length === 1) {
    kmosDashboards[0].currentConfigGroup = ["General"];
    kmosDashboards[0].writeConfig("icon", "start-here-kde");
    kmosDashboards[0].writeConfig("Icon", "start-here-kde");
}
