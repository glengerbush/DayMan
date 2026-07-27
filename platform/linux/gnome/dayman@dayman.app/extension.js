import Cairo from 'cairo';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Shell from 'gi://Shell';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';

const SNAPSHOT_VERSION = 1;
const STATE_FILENAME = 'dayman-state-v1.json';

function angleForMinute(minute) {
    return minute / 1440 * Math.PI * 2 - Math.PI / 2;
}

function setColor(context, color, fallback) {
    const match = /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(color ?? '');
    const value = match ?? fallback;
    context.setSourceRGBA(
        Number.parseInt(value[1], 16) / 255,
        Number.parseInt(value[2], 16) / 255,
        Number.parseInt(value[3], 16) / 255,
        1
    );
}

class DayManIndicator extends PanelMenu.Button {
    constructor() {
        super(0.0, 'DayMan Clock', false);
        this._snapshot = null;
        this._hasState = false;
        this._alignmentTimeout = 0;
        this._minuteTimeout = 0;
        this._drawing = new St.DrawingArea({
            style_class: 'dayman-clock',
            reactive: false,
            can_focus: false,
            x_expand: false,
            y_expand: false,
        });
        this.add_child(this._drawing);
        this._drawing.connect('repaint', area => this._paint(area));
        this.connect('button-press-event', () => {
            this._launchDayMan();
            return true;
        });

        this._refresh();
        this._scheduleMinuteUpdates();
    }

    _snapshotFile() {
        return Gio.File.new_for_path(
            GLib.build_filenamev([
                GLib.get_user_config_dir(),
                'dayman',
                STATE_FILENAME,
            ])
        );
    }

    _loadSnapshot() {
        this._snapshot = null;
        this._hasState = false;
        try {
            const [ok, contents] = this._snapshotFile().load_contents(null);
            if (!ok)
                return;
            const state = JSON.parse(new TextDecoder().decode(contents));
            this._hasState = state.schemaVersion === SNAPSHOT_VERSION;
            const candidate = this._selectCurrentSnapshot(state);
            if (state.schemaVersion === SNAPSHOT_VERSION &&
                candidate?.schemaVersion === SNAPSHOT_VERSION &&
                Array.isArray(candidate.arcs))
                this._snapshot = candidate;
            else
                this._snapshot = null;
        } catch (error) {
            if (!error.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.NOT_FOUND))
                console.warn(`DayMan: could not read ClockSnapshot: ${error.message}`);
        }
    }

    _selectCurrentSnapshot(state) {
        const fallback = state?.snapshot;
        if (fallback?.schemaVersion !== SNAPSHOT_VERSION)
            return null;

        let timezone = GLib.TimeZone.new_local();
        if (fallback.timezone) {
            try {
                timezone = GLib.TimeZone.new_identifier(fallback.timezone) ??
                    timezone;
            } catch (error) {
                console.warn(`DayMan: invalid snapshot timezone: ${error.message}`);
            }
        }
        const currentDateKey = GLib.DateTime.new_now(timezone)
            .format('%Y-%m-%d');
        const queue = Array.isArray(state.snapshots) ? state.snapshots : [];
        if (queue.length > 0) {
            return queue.find(candidate =>
                candidate?.schemaVersion === SNAPSHOT_VERSION &&
                candidate.timezone === fallback.timezone &&
                candidate.dateKey === currentDateKey
            ) ?? null;
        }
        return fallback.dateKey === currentDateKey ? fallback : null;
    }

    _currentMinute() {
        const timezone = this._snapshot?.timezone
            ? GLib.TimeZone.new_identifier(this._snapshot.timezone)
            : GLib.TimeZone.new_local();
        const now = GLib.DateTime.new_now(timezone);
        return now.get_hour() * 60 + now.get_minute();
    }

    _refresh() {
        this._loadSnapshot();
        this.accessible_name = this._snapshot?.accessibilityText ??
            (this._hasState
                ? 'DayMan clock data is stale. Open DayMan to refresh it.'
                : 'DayMan clock. Open DayMan to choose a location.');
        this._drawing.queue_repaint();
    }

    _scheduleMinuteUpdates() {
        const now = GLib.DateTime.new_now_local();
        const firstDelay = Math.max(1, 60 - now.get_second());
        this._alignmentTimeout = GLib.timeout_add_seconds(
            GLib.PRIORITY_DEFAULT,
            firstDelay,
            () => {
                this._alignmentTimeout = 0;
                this._refresh();
                this._minuteTimeout = GLib.timeout_add_seconds(
                    GLib.PRIORITY_DEFAULT,
                    60,
                    () => {
                        this._refresh();
                        return GLib.SOURCE_CONTINUE;
                    }
                );
                return GLib.SOURCE_REMOVE;
            }
        );
    }

    _paint(area) {
        const context = area.get_context();
        const [width, height] = area.get_surface_size();
        const size = Math.min(width, height);
        const centerX = width / 2;
        const centerY = height / 2;
        const outerRadius = size * 0.40;
        const moonRadius = size * 0.29;

        setColor(context, this._snapshot?.palette?.face,
            ['#101a2d', '10', '1a', '2d']);
        context.arc(centerX, centerY, size * 0.48, 0, Math.PI * 2);
        context.fill();

        setColor(context, this._snapshot?.palette?.track,
            ['#334b68', '33', '4b', '68']);
        context.setLineWidth(Math.max(1.5, size * 0.065));
        context.arc(centerX, centerY, outerRadius, 0, Math.PI * 2);
        context.stroke();

        for (const arc of this._snapshot?.arcs ?? []) {
            for (const range of arc.ranges ?? []) {
                const start = Number(range.startMinute);
                let end = Number(range.endMinute);
                if (!Number.isFinite(start) || !Number.isFinite(end))
                    continue;
                if (end <= start)
                    end += 1440;

                const isMoon = arc.kind === 'moon';
                setColor(context, arc.color, ['#ffbd63', 'ff', 'bd', '63']);
                context.setLineCap(Cairo.LineCap.ROUND);
                context.setLineWidth(Math.max(1.5, size * (isMoon ? 0.05 : 0.07)));
                context.arc(
                    centerX,
                    centerY,
                    isMoon ? moonRadius : outerRadius,
                    angleForMinute(start),
                    angleForMinute(end)
                );
                context.stroke();
            }
        }

        for (const event of this._snapshot?.events ?? []) {
            if (!event.visibleOnDial)
                continue;
            const eventAngle = angleForMinute(event.minute);
            const radius = event.body === 'moon' ? moonRadius : outerRadius;
            setColor(context,
                event.body === 'moon' ? '#d9e5ea' : '#ffb552',
                ['#d9e5ea', 'd9', 'e5', 'ea']);
            context.arc(
                centerX + Math.cos(eventAngle) * radius,
                centerY + Math.sin(eventAngle) * radius,
                Math.max(1, size * 0.035),
                0,
                Math.PI * 2
            );
            context.fill();
        }

        const handAngle = angleForMinute(this._currentMinute());
        context.setDash([Math.max(1, size * 0.035), Math.max(1, size * 0.025)], 0);
        setColor(context, this._snapshot?.palette?.currentHand,
            ['#f8fafc', 'f8', 'fa', 'fc']);
        context.setLineWidth(Math.max(1.25, size * 0.035));
        context.moveTo(centerX, centerY);
        context.lineTo(
            centerX + Math.cos(handAngle) * size * 0.43,
            centerY + Math.sin(handAngle) * size * 0.43
        );
        context.stroke();
        context.setDash([], 0);
        context.$dispose();
    }

    _launchDayMan() {
        const appSystem = Shell.AppSystem.get_default();
        const app = appSystem.lookup_app('com.dayman.DayMan.desktop') ??
            appSystem.lookup_app('DayMan.desktop');
        if (app) {
            app.activate();
            return;
        }

        try {
            Gio.Subprocess.new(['dayman'], Gio.SubprocessFlags.NONE);
        } catch (error) {
            console.error(`DayMan: could not launch the app: ${error.message}`);
        }
    }

    destroy() {
        if (this._alignmentTimeout)
            GLib.source_remove(this._alignmentTimeout);
        if (this._minuteTimeout)
            GLib.source_remove(this._minuteTimeout);
        this._alignmentTimeout = 0;
        this._minuteTimeout = 0;
        super.destroy();
    }
}

export default class DayManExtension extends Extension {
    enable() {
        this._indicator = new DayManIndicator();
        Main.panel.addToStatusArea(this.uuid, this._indicator);
    }

    disable() {
        this._indicator?.destroy();
        this._indicator = null;
    }
}
