import QtCore
import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    readonly property string snapshotPath: StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/dayman/dayman-state-v1.json"
    property var snapshot: null
    property var platformState: null
    property string currentDateKey: ""
    property int currentMinute: 0

    preferredRepresentation: compactRepresentation
    compactRepresentation: faceComponent
    fullRepresentation: faceComponent

    function updateMinute() {
        if (currentDateKey.length > 0)
            return

        const now = new Date()
        if (snapshot && Number.isFinite(snapshot.referenceMinute)) {
            const calculatedAt = Date.parse(snapshot.calculatedAt)
            const elapsedMinutes = Number.isFinite(calculatedAt)
                                 ? Math.floor((now.getTime() - calculatedAt) / 60000)
                                 : 0
            currentMinute = (Math.round(snapshot.referenceMinute) + elapsedMinutes + 144000) % 1440
        } else {
            currentMinute = now.getHours() * 60 + now.getMinutes()
        }
    }

    function selectCurrentSnapshot(state) {
        const fallback = state && state.snapshot
        if (!fallback || fallback.schemaVersion !== 1)
            return null

        const queue = Array.isArray(state.snapshots) ? state.snapshots : []
        if (queue.length > 0) {
            if (currentDateKey.length === 0)
                return null
            for (const candidate of queue) {
                if (candidate && candidate.schemaVersion === 1 &&
                    candidate.timezone === fallback.timezone &&
                    candidate.dateKey === currentDateKey)
                    return candidate
            }
            return null
        }

        return currentDateKey.length > 0 &&
               fallback.dateKey === currentDateKey ? fallback : null
    }

    function applyZonedTime(dateKey, minute) {
        currentDateKey = dateKey
        currentMinute = minute
        const candidate = selectCurrentSnapshot(platformState)
        snapshot = candidate && Array.isArray(candidate.arcs) ? candidate : null
    }

    function loadSnapshot() {
        const request = new XMLHttpRequest()
        request.onreadystatechange = function () {
            if (request.readyState !== XMLHttpRequest.DONE)
                return

            if (request.status === 0 || request.status === 200) {
                try {
                    const state = JSON.parse(request.responseText)
                    platformState = state
                    const candidate = selectCurrentSnapshot(state)
                    const fallback = state.snapshot
                    if (state.schemaVersion === 1 && fallback &&
                        fallback.schemaVersion === 1)
                        executable.updateZonedTime(fallback.timezone)
                    snapshot = candidate && candidate.schemaVersion === 1 &&
                               Array.isArray(candidate.arcs) ? candidate : null
                } catch (error) {
                    platformState = null
                    snapshot = null
                    console.warn("DayMan: invalid ClockSnapshot:", error)
                }
            } else {
                platformState = null
                snapshot = null
            }
            updateMinute()
        }
        request.open("GET", "file://" + snapshotPath)
        request.send()
    }

    Component.onCompleted: loadSnapshot()

    Timer {
        id: alignmentTimer
        interval: {
            const now = new Date()
            return Math.max(250, (60 - now.getSeconds()) * 1000 - now.getMilliseconds())
        }
        repeat: false
        running: true
        onTriggered: {
            root.loadSnapshot()
            minuteTimer.start()
        }
    }

    Timer {
        id: minuteTimer
        interval: 60000
        repeat: true
        running: false
        onTriggered: {
            root.loadSnapshot()
        }
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        property string timeCommand: ""

        function updateZonedTime(timezone) {
            // IANA zone identifiers contain only these characters. Rejecting
            // anything else keeps the executable data source free of shell
            // interpolation even if the state file was externally modified.
            if (!/^[A-Za-z0-9_+\-]+(\/[A-Za-z0-9_+\-]+)*$/.test(timezone))
                return
            timeCommand = "env TZ=" + timezone + " date '+%Y-%m-%d %H:%M'"
            connectSource(timeCommand)
        }

        function launchDayMan() {
            const command = "sh -c 'gtk-launch com.dayman.DayMan >/dev/null 2>&1 || gtk-launch DayMan >/dev/null 2>&1 || exec dayman'"
            connectSource(command)
        }

        onNewData: function (sourceName, data) {
            if (sourceName === timeCommand) {
                const output = String(data["stdout"] || "").trim()
                const match = /^(\d{4}-\d{2}-\d{2}) (\d{2}):(\d{2})$/.exec(output)
                if (match) {
                    const minute = Number(match[2]) * 60 + Number(match[3])
                    root.applyZonedTime(match[1], minute)
                }
                timeCommand = ""
            }
            disconnectSource(sourceName)
        }
    }

    Component {
        id: faceComponent

        Item {
            id: face
            implicitWidth: 160
            implicitHeight: 160
            Accessible.name: root.snapshot ? root.snapshot.accessibilityText :
                             (root.platformState ? "DayMan clock data is stale. Open DayMan to refresh it." :
                                                   "DayMan clock. Open DayMan to choose a location.")
            Accessible.role: Accessible.Button

            Canvas {
                id: canvas
                anchors.fill: parent
                antialiasing: true

                function angle(minute) {
                    return minute / 1440 * Math.PI * 2 - Math.PI / 2
                }

                function drawRange(context, arc, range, centerX, centerY, radius, width) {
                    let end = Number(range.endMinute)
                    const start = Number(range.startMinute)
                    if (end <= start)
                        end += 1440
                    context.beginPath()
                    context.arc(centerX, centerY, radius, angle(start), angle(end), false)
                    context.lineWidth = width
                    context.lineCap = "round"
                    context.strokeStyle = arc.color || "#ffbd63"
                    context.stroke()
                }

                onPaint: {
                    const context = getContext("2d")
                    context.reset()
                    const size = Math.min(width, height)
                    const centerX = width / 2
                    const centerY = height / 2
                    const outerRadius = size * 0.39
                    const moonRadius = size * 0.29

                    context.fillStyle = root.snapshot && root.snapshot.palette
                                      ? root.snapshot.palette.face : "#101a2d"
                    context.beginPath()
                    context.arc(centerX, centerY, size * 0.48, 0, Math.PI * 2)
                    context.fill()

                    context.strokeStyle = root.snapshot && root.snapshot.palette
                                        ? root.snapshot.palette.track : "#334b68"
                    context.lineWidth = Math.max(2, size * 0.035)
                    context.beginPath()
                    context.arc(centerX, centerY, outerRadius, 0, Math.PI * 2)
                    context.stroke()

                    if (root.snapshot) {
                        for (const arc of root.snapshot.arcs) {
                            const isMoon = arc.kind === "moon"
                            for (const range of arc.ranges || []) {
                                drawRange(context, arc, range, centerX, centerY,
                                          isMoon ? moonRadius : outerRadius,
                                          Math.max(3, size * (isMoon ? 0.045 : 0.055)))
                            }
                        }
                        for (const event of root.snapshot.events || []) {
                            if (!event.visibleOnDial)
                                continue
                            const eventAngle = angle(event.minute)
                            const eventRadius = event.body === "moon" ? moonRadius : outerRadius
                            context.beginPath()
                            context.arc(centerX + Math.cos(eventAngle) * eventRadius,
                                        centerY + Math.sin(eventAngle) * eventRadius,
                                        Math.max(2, size * 0.018), 0, Math.PI * 2)
                            context.fillStyle = event.body === "moon" ? "#d9e5ea" : "#ffb552"
                            context.fill()
                        }
                    }

                    for (let hour = 0; hour < 24; hour += 3) {
                        const tickAngle = angle(hour * 60)
                        const inner = size * 0.425
                        const outer = size * 0.455
                        context.beginPath()
                        context.moveTo(centerX + Math.cos(tickAngle) * inner,
                                       centerY + Math.sin(tickAngle) * inner)
                        context.lineTo(centerX + Math.cos(tickAngle) * outer,
                                       centerY + Math.sin(tickAngle) * outer)
                        context.lineWidth = Math.max(1, size * 0.008)
                        context.strokeStyle = "#9eb2c5"
                        context.stroke()
                    }

                    if (size >= 120) {
                        context.font = Math.max(8, size * 0.065) + "px sans-serif"
                        context.textAlign = "center"
                        context.textBaseline = "middle"
                        context.fillStyle = root.snapshot && root.snapshot.palette
                                          ? root.snapshot.palette.mutedText : "#9eb2c5"
                        for (let hour = 0; hour < 24; hour += 3) {
                            const labelAngle = angle(hour * 60)
                            const labelRadius = size * 0.34
                            const label = hour < 10 ? "0" + hour : String(hour)
                            context.fillText(label,
                                             centerX + Math.cos(labelAngle) * labelRadius,
                                             centerY + Math.sin(labelAngle) * labelRadius)
                        }
                    }

                    const handAngle = angle(root.currentMinute)
                    context.setLineDash([Math.max(2, size * 0.018), Math.max(2, size * 0.018)])
                    context.beginPath()
                    context.moveTo(centerX, centerY)
                    context.lineTo(centerX + Math.cos(handAngle) * size * 0.44,
                                   centerY + Math.sin(handAngle) * size * 0.44)
                    context.lineWidth = Math.max(2, size * 0.018)
                    context.strokeStyle = root.snapshot && root.snapshot.palette
                                        ? root.snapshot.palette.currentHand : "#f8fafc"
                    context.stroke()
                    context.setLineDash([])

                    context.beginPath()
                    context.arc(centerX, centerY, Math.max(2, size * 0.018), 0, Math.PI * 2)
                    context.fillStyle = root.snapshot && root.snapshot.palette
                                      ? root.snapshot.palette.currentHand : "#f8fafc"
                    context.fill()
                }

                Connections {
                    target: root
                    function onSnapshotChanged() {
                        canvas.requestPaint()
                    }
                    function onCurrentMinuteChanged() {
                        canvas.requestPaint()
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton
                onClicked: executable.launchDayMan()
            }
        }
    }
}
