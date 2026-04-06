import QtQuick
import QtQuick.Controls
import QtQuick.Controls.impl
import QtQuick.Layouts
import MyDesktop.Backend 1.0

Window {
    id: window
    width: 360
    // OnePlus 6 target ratio: 19:9 -> 360 x 760
    height: 760
    visible: true
    title: "Dashboard"
    color: "#121212"

    property bool historyExpanded: true
    property string screenshotToastMessage: ""
    property var remoteMemoryInfoKeys: [
        "Used", "Total", "Available", "Free",
        "Cached", "Buffers", "Swap Used", "Swap Free", "Swap Total"
    ]

    function remoteServerAt(index) {
        if (!backend || !backend.remoteServers || index < 0 || index >= backend.remoteServers.length)
            return null
        return backend.remoteServers[index]
    }

    function denseHistory(values, targetCount) {
        if (!values || values.length === 0)
            return []

        var target = Math.max(2, targetCount || 120)
        if (values.length >= target)
            return values

        var out = []
        if (values.length === 1) {
            for (var i = 0; i < target; ++i)
                out.push(values[0])
            return out
        }

        for (var j = 0; j < target; ++j) {
            var pos = j * (values.length - 1) / (target - 1)
            var left = Math.floor(pos)
            var right = Math.min(values.length - 1, left + 1)
            var t = pos - left
            out.push(values[left] * (1 - t) + values[right] * t)
        }
        return out
    }

    SystemMonitor {
        id: backend
    }

    TerminalBackend {
        id: terminalSession
    }

    // --- 1. CPU 配色 (经典性能监控色: 绿 -> 黄 -> 红) ---
    function cpuColor(v) {
        var value = Math.max(0, Math.min(1, v));
        if (value < 0.4) return "#4CAF50"; // Green
        if (value < 0.7) return "#FFC107"; // Amber
        return "#FF5252"; // Red
    }

    // --- 2. 内存 配色 (科技冷色调: 蓝 -> 紫 -> 粉红) ---
    function memColor(v) {
        var value = Math.max(0, Math.min(1, v));
        if (value < 0.5) return "#2196F3"; // Blue
        if (value < 0.8) return "#9C27B0"; // Purple
        return "#E91E63"; // Pink/Red
    }

    // --- 3. 硬盘 配色 (数据存储色: 青 -> 橙 -> 红) ---
    function diskColor(v) {
        var value = Math.max(0, Math.min(1, v));
        if (value < 0.6) return "#00E5FF"; // Cyan
        if (value < 0.85) return "#FF9800"; // Orange
        return "#FF5252"; // Red
    }

    // --- 4. 电池 配色 (充电状态优先) ---
    function batteryColor(percent, state) {
        if (state === "Charging") return "#00E676"; // Bright Green
        var p = Math.max(0, Math.min(100, percent));
        if (p >= 80) return "#4CAF50"; 
        if (p >= 30) return "#FFC107"; 
        if (p >= 15) return "#FF9800"; 
        return "#FF5252"; 
    }

    function showScreenshotToast(message) {
        screenshotToastMessage = message
        screenshotToastTimer.restart()
    }

    function captureScreenshot() {
        var path = backend.nextScreenshotPath()
        if (!path) {
            showScreenshotToast("Screenshot path unavailable")
            return
        }

        screenshotToastTimer.stop()
        screenshotToastMessage = ""

        Qt.callLater(function() {
            var accepted = window.contentItem.grabToImage(function(result) {
                if (result && result.saveToFile(path))
                    showScreenshotToast("Screenshot saved")
                else
                    showScreenshotToast("Screenshot save failed")
            })

            if (!accepted)
                showScreenshotToast("Screenshot unavailable")
        })
    }

    Connections {
        target: backend

        function onScreenshotRequested() {
            window.captureScreenshot()
        }
    }

    // ================= POPUPS =================

    Popup {
        id: cpuDetailsPopup
        parent: Overlay.overlay
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: parent.width * 0.85
        height: parent.height * 0.6
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        
        Overlay.modal: Rectangle { color: "#aa000000" }
        
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 200 }
            NumberAnimation { property: "scale"; from: 0.9; to: 1.0; duration: 200 }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 200 }
            NumberAnimation { property: "scale"; from: 1.0; to: 0.9; duration: 200 }
        }

        background: Rectangle {
            color: "#1e1e1e"
            radius: 15
            border.color: "#333333"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 20
            // 顶部留白，替代原来的 Layout.topMargin，布局更稳定
            Item { height: 10; Layout.fillWidth: true } 

            Text {
                text: "CPU Core Details"
                color: "white"
                font.pixelSize: 20
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }

            ListView {
                focus: true
                Layout.fillWidth: true
                Layout.fillHeight: true
                // 左右留白，防止滚动条贴边
                Layout.leftMargin: 20
                Layout.rightMargin: 20 
                model: backend.cpuCores
                spacing: 15
                clip: true
                
                delegate: ColumnLayout {
                    width: ListView.view.width // 强制宽度与列表一致
                    spacing: 5
                    
                    RowLayout {
                        Layout.fillWidth: true
                        Text { 
                            text: "Core " + index
                            color: "#aaaaaa"
                            font.pixelSize: 14 
                        }
                        Item { Layout.fillWidth: true } // 弹簧占位
                        Text { 
                            text: (modelData * 100).toFixed(1) + "%"
                            color: "white"
                            font.family: "Monospace"
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 12
                        color: "#333333"
                        radius: 6
                        Rectangle {
                            width: parent.width * modelData
                            height: parent.height
                            color: cpuColor(modelData)
                            radius: 6
                            Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }
                        }
                    }
                }
            }
            // 底部留白
            Item { height: 10; Layout.fillWidth: true }
        }
    }

    // 2. 硬盘详情模态框 (Fixed Overflow)
    Popup {
        id: diskPopup
        parent: Overlay.overlay
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: parent.width * 0.9 // 硬盘路径通常较长，给宽一点
        height: parent.height * 0.6
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        
        Overlay.modal: Rectangle { color: "#aa000000" }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 200 }
            NumberAnimation { property: "scale"; from: 0.9; to: 1.0; duration: 200 }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 200 }
            NumberAnimation { property: "scale"; from: 1.0; to: 0.9; duration: 200 }
        }

        background: Rectangle {
            color: "#1e1e1e"
            radius: 15
            border.color: "#333333"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 20
            Item { height: 10; Layout.fillWidth: true }

            Text { 
                text: "Storage Partitions"
                color: "white" 
                font.pixelSize: 20 
                font.bold: true 
                Layout.alignment: Qt.AlignHCenter 
            }
            
            ListView {
                focus: true
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 15
                Layout.rightMargin: 15
                model: backend.diskPartitions
                spacing: 10
                clip: true // 防止溢出绘制到圆角外部
                
                delegate: Rectangle {
                    width: ListView.view.width
                    height: 75
                    color: "#2d2d2d"
                    radius: 8
                    
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 4
                        
                        // 第一行：挂载点 (左) + 容量 (右)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            
                            Text { 
                                text: modelData.mount
                                color: "white"
                                font.bold: true
                                font.pixelSize: 16
                                // 尽量完整展示挂载点，优先留更多宽度且使用中间省略
                                Layout.fillWidth: true 
                                elide: Text.ElideMiddle
                            }
                            
                            Text { 
                                text: modelData.used + " / " + modelData.size
                                color: "#aaaaaa"
                                font.pixelSize: 12
                                // 强制不换行，保持右侧对齐
                                Layout.preferredWidth: implicitWidth 
                            }
                        }
                        
                        // 第二行：设备名 (左) + 类型 (左)
                        RowLayout {
                            Layout.fillWidth: true
                            Text { 
                                text: modelData.device
                                color: "#666666"
                                font.pixelSize: 10
                                Layout.maximumWidth: parent.width * 0.8 // 放宽一点避免过度截断
                                elide: Text.ElideMiddle // 设备名如果太长，中间省略
                            }
                            Text { 
                                text: "[" + modelData.type + "]"
                                color: "#666666"
                                font.pixelSize: 10
                            }
                        }
                        
                        // 第三行：进度条
                        Rectangle {
                            Layout.fillWidth: true
                            height: 4
                            color: "#444"
                            radius: 2
                            Rectangle { 
                                width: parent.width * modelData.percent
                                height: parent.height
                                color: diskColor(modelData.percent)
                                radius: 2
                            }
                        }
                    }
                }
            }
            Item { height: 10; Layout.fillWidth: true }
        }
    }

    Popup {
        id: memPopup
        property var detailsCtrl: backend ? backend.systemDetailsBackend : null
        property string sortMode: "cpu"

        function metricText(item) {
            if (!item)
                return "--"
            if (sortMode === "mem")
                return item.displayMemory + " (" + Number(item.memoryPercent).toFixed(1) + "%)"
            if (sortMode === "io")
                return item.displayIo
            if (sortMode === "net")
                return item.displayNet
            return item.displayCpu
        }

        parent: Overlay.overlay
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: parent.width * 0.85
        height: parent.height * 0.68
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: {
            sortMode = "cpu"
            if (detailsCtrl) {
                detailsCtrl.topProcessSort = sortMode
                detailsCtrl.active = true
            }
        }
        onClosed: {
            if (detailsCtrl)
                detailsCtrl.active = false
        }
        onSortModeChanged: {
            if (detailsCtrl)
                detailsCtrl.topProcessSort = sortMode
        }

        Overlay.modal: Rectangle { color: "#aa000000" }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 200 }
            NumberAnimation { property: "scale"; from: 0.9; to: 1.0; duration: 200 }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 200 }
            NumberAnimation { property: "scale"; from: 1.0; to: 0.9; duration: 200 }
        }

        background: Rectangle {
            color: "#1e1e1e"
            radius: 15
            border.color: "#333333"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 12
            Item { height: 10; Layout.fillWidth: true }

            Text {
                text: "Memory Details"
                color: "white"
                font.pixelSize: 20
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                text: backend.memDetail + " (" + (backend.memPercent * 100).toFixed(0) + "%)"
                color: "#9fb4cf"
                font.pixelSize: 13
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 8

                Repeater {
                    model: [
                        { key: "cpu", label: "CPU" },
                        { key: "mem", label: "MEM" },
                        { key: "io", label: "IO" },
                        { key: "net", label: "NET" }
                    ]

                    Rectangle {
                        required property var modelData
                        width: 56
                        height: 24
                        radius: 12
                        color: memPopup.sortMode === modelData.key
                               ? "#2e6ea6"
                               : (sortTap.pressed ? "#25303d" : "#1a2430")
                        border.width: 1
                        border.color: memPopup.sortMode === modelData.key ? "#78b9ff" : "#33475c"

                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData.label
                            color: "white"
                            font.pixelSize: 11
                            font.bold: true
                        }

                        TapHandler {
                            id: sortTap
                            onTapped: memPopup.sortMode = parent.modelData.key
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                text: "Top Processes by " + (memPopup.sortMode === "mem" ? "MEM"
                     : memPopup.sortMode === "io" ? "IO"
                     : memPopup.sortMode === "net" ? "NET" : "CPU")
                color: "#b7c4d4"
                font.pixelSize: 11
            }

            ListView {
                focus: true
                Layout.fillWidth: true
                Layout.preferredHeight: 138
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                clip: true
                spacing: 6
                model: memPopup.detailsCtrl ? memPopup.detailsCtrl.topProcesses.slice(0, 6) : []

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: 38
                    radius: 8
                    color: "#222831"
                    border.width: 1
                    border.color: "#323b46"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Text {
                            text: modelData.name + " [" + modelData.pid + "]"
                            color: "#e5e9ef"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            text: memPopup.metricText(modelData)
                            color: "#9dd4ff"
                            font.pixelSize: 11
                            font.bold: true
                            font.family: "Monospace"
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideLeft
                            Layout.preferredWidth: 110
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                height: 1
                color: "#323a43"
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                text: "Memory Breakdown"
                color: "#b7c4d4"
                font.pixelSize: 11
                font.bold: true
            }

            ListView {
                focus: true
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                clip: true
                spacing: 8
                model: [
                    "Used", "Total", "Available", "Free",
                    "Cached", "Buffers", "Swap Used", "Swap Free", "Swap Total"
                ]

                delegate: RowLayout {
                    required property string modelData
                    visible: backend.memInfo[modelData] !== undefined && backend.memInfo[modelData] !== ""
                    width: ListView.view.width
                    spacing: 8

                    Text {
                        text: modelData
                        color: "#888888"
                        font.pixelSize: 12
                        Layout.preferredWidth: parent.width * 0.45
                        elide: Text.ElideRight
                    }

                    Text {
                        text: backend.memInfo[modelData]
                        color: "white"
                        font.pixelSize: 12
                        font.bold: true
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideMiddle
                    }
                }
            }

            Item { height: 8; Layout.fillWidth: true }
        }
    }

    // 3. 电池详情模态框 (Fixed Overflow & Layout)
    Popup {
        id: batPopup
        parent: Overlay.overlay
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: parent.width * 0.85
        height: parent.height * 0.5
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        
        Overlay.modal: Rectangle { color: "#aa000000" }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 200 }
            NumberAnimation { property: "scale"; from: 0.9; to: 1.0; duration: 200 }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 200 }
            NumberAnimation { property: "scale"; from: 1.0; to: 0.9; duration: 200 }
        }

        background: Rectangle {
            color: "#1e1e1e"
            radius: 15
            border.color: "#333333"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 20
            Item { height: 10; Layout.fillWidth: true }

            Text { 
                text: "Battery Status"
                color: "white" 
                font.pixelSize: 20 
                font.bold: true 
                Layout.alignment: Qt.AlignHCenter 
            }
            
            // 使用 ListView 替代 GridLayout，处理长内容更灵活
            ListView {
                focus: true
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 25
                Layout.rightMargin: 25
                clip: true
                
                // 将 Map 的 Key 转换为数组模型
                model: Object.keys(backend.batDetails)
                spacing: 12
                
                delegate: RowLayout {
                    width: ListView.view.width
                    spacing: 10
                    
                    // Key (左侧，灰色)
                    Text { 
                        text: modelData
                        color: "#888888"
                        font.pixelSize: 14
                        // 限制 Key 的最大宽度，防止挤压 Value
                        Layout.preferredWidth: parent.width * 0.4 
                        elide: Text.ElideRight 
                    }
                    
                    // Value (右侧，白色，高亮)
                    Text { 
                        text: backend.batDetails[modelData]
                        color: "white"
                        font.pixelSize: 14
                        font.bold: true
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        
                        elide: Text.ElideMiddle 
                    }
                }
            }
            Item { height: 10; Layout.fillWidth: true }
        }
    }

    Popup {
        id: netPopup
        parent: Overlay.overlay
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: parent.width * 0.9
        height: parent.height * 0.7 // 网络信息可能比较长，给高一点
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        
        Overlay.modal: Rectangle { color: "#aa000000" }
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 } }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 200 } }

        background: Rectangle {
            color: "#1e1e1e"
            radius: 15
            border.color: "#333333"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 15
            Item { height: 10; Layout.fillWidth: true }

            Text { 
                text: "Network Interfaces"
                color: "white"
                font.pixelSize: 20
                font.bold: true
                Layout.alignment: Qt.AlignHCenter 
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 20; Layout.rightMargin: 20
                clip: true
                spacing: 15
                model: backend.netInterfaces

                delegate: Rectangle {
                    width: ListView.view.width
                    // 自适应高度：根据 IP 数量撑开
                    height: contentCol.implicitHeight + 30
                    color: "#252525"
                    radius: 8
                    
                    ColumnLayout {
                        id: contentCol
                        anchors.fill: parent
                        anchors.margins: 15
                        spacing: 8

                        // 1. 接口名 + 状态
                        RowLayout {
                            Layout.fillWidth: true
                            Text { 
                                text: modelData.name // wlan0
                                color: "#00E5FF" // 青色高亮
                                font.bold: true
                                font.pixelSize: 16
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                width: 40; height: 18; radius: 4
                                color: modelData.state === "UP" ? "#2E7D32" : "#C62828"
                                Text { 
                                    text: modelData.state
                                    anchors.centerIn: parent
                                    color: "white"
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }
                        }

                        // 2. MAC 地址
                        Text {
                            visible: modelData.mac !== ""
                            text: "MAC: " + modelData.mac
                            color: "#888"
                            font.family: "Monospace"
                            font.pixelSize: 12
                        }
                        
                        // 分割线
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#333" }

                        // 3. IP 地址列表
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Repeater {
                                model: modelData.ips // 这是一个 StringList
                                delegate: Text {
                                    text: modelData
                                    color: "#ddd"
                                    font.family: "Monospace"
                                    font.pixelSize: 13
                                    // 自动换行，防止 IPv6 太长
                                    wrapMode: Text.WrapAnywhere 
                                    Layout.fillWidth: true
                                }
                            }
                            // 如果没有 IP
                            Text {
                                visible: modelData.ips.length === 0
                                text: "No IP Address"
                                color: "#555"
                                font.italic: true
                                font.pixelSize: 12
                            }
                        }
                    }
                }
            }
            Item { height: 10; Layout.fillWidth: true }
        }
    }

    Popup {
        id: remoteCpuPopup
        property int serverIndex: -1
        property string serverName: ""
        property var serverData: {
            if (!backend || !backend.remoteServers)
                return null
            if (serverName !== "") {
                for (var i = 0; i < backend.remoteServers.length; ++i) {
                    var item = backend.remoteServers[i]
                    if ((item.name || "") === serverName)
                        return item
                }
            }
            return window.remoteServerAt(serverIndex)
        }

        parent: Overlay.overlay
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: parent.width * 0.9
        height: parent.height * 0.62
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        Overlay.modal: Rectangle { color: "#aa000000" }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 200 }
            NumberAnimation { property: "scale"; from: 0.9; to: 1.0; duration: 200 }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 200 }
            NumberAnimation { property: "scale"; from: 1.0; to: 0.9; duration: 200 }
        }

        background: Rectangle {
            color: "#1e1e1e"
            radius: 15
            border.color: "#333333"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 10
            Item { height: 8; Layout.fillWidth: true }

            Text {
                text: (remoteCpuPopup.serverData ? remoteCpuPopup.serverData.name : "Remote") + " CPU"
                color: "white"
                font.pixelSize: 20
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                text: "Updated: " + (remoteCpuPopup.serverData ? remoteCpuPopup.serverData.lastUpdate : "--")
                color: "#9db0c3"
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                spacing: 8

                Text {
                    text: "Usage " + (Number(remoteCpuPopup.serverData ? remoteCpuPopup.serverData.cpuTotal : 0) * 100).toFixed(0) + "%"
                    color: cpuColor(Number(remoteCpuPopup.serverData ? remoteCpuPopup.serverData.cpuTotal : 0))
                    font.pixelSize: 13
                    font.bold: true
                }

                Text {
                    text: "Cores " + (remoteCpuPopup.serverData ? remoteCpuPopup.serverData.coreCount : 0)
                    color: "#c6ccd7"
                    font.pixelSize: 12
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "Load " + (remoteCpuPopup.serverData ? remoteCpuPopup.serverData.loadAvg : "--")
                    color: "#a7b9cc"
                    font.pixelSize: 11
                    font.family: "Monospace"
                }
            }

            Row {
                id: remoteCpuPopupGroupRow
                Layout.alignment: Qt.AlignHCenter
                spacing: 4
                property var groups: (remoteCpuPopup.serverData && remoteCpuPopup.serverData.cpuGroups)
                                     ? remoteCpuPopup.serverData.cpuGroups : []

                Repeater {
                    model: 8

                    Rectangle {
                        required property int index
                        property real groupLoad: (remoteCpuPopupGroupRow.groups && index < remoteCpuPopupGroupRow.groups.length)
                                                 ? Number(remoteCpuPopupGroupRow.groups[index]) : 0

                        width: 32
                        height: 26
                        radius: 4
                        color: "#202634"
                        border.width: 1
                        border.color: "#343b48"

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 1
                            height: Math.max(0, (parent.height - 2) * parent.groupLoad)
                            radius: 3
                            color: cpuColor(parent.groupLoad)
                        }

                        Text {
                            anchors.centerIn: parent
                            text: Math.round(parent.groupLoad * 100)
                            color: "#e7ebf0"
                            font.pixelSize: 8
                            font.bold: true
                            font.family: "Monospace"
                        }
                    }
                }
            }

            LineChart {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                chartTitle: "History"
                datasets: [
                    {
                        label: "CPU",
                        values: (remoteCpuPopup.serverData && remoteCpuPopup.serverData.cpuHistory)
                                ? window.denseHistory(remoteCpuPopup.serverData.cpuHistory, 160) : [],
                        color: "#FF5252"
                    }
                ]
                fixedMax: -1
                suffix: "%"
                showLegend: false
                showLine: false
                showPoints: true
                fillArea: false
                pointRadius: 1
            }

            Item { height: 8; Layout.fillWidth: true }
        }
    }

    Popup {
        id: remoteMemPopup
        property int serverIndex: -1
        property string serverName: ""
        property var serverData: {
            if (!backend || !backend.remoteServers)
                return null
            if (serverName !== "") {
                for (var i = 0; i < backend.remoteServers.length; ++i) {
                    var item = backend.remoteServers[i]
                    if ((item.name || "") === serverName)
                        return item
                }
            }
            return window.remoteServerAt(serverIndex)
        }

        parent: Overlay.overlay
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: parent.width * 0.9
        height: parent.height * 0.68
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        Overlay.modal: Rectangle { color: "#aa000000" }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 200 }
            NumberAnimation { property: "scale"; from: 0.9; to: 1.0; duration: 200 }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 200 }
            NumberAnimation { property: "scale"; from: 1.0; to: 0.9; duration: 200 }
        }

        background: Rectangle {
            color: "#1e1e1e"
            radius: 15
            border.color: "#333333"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 10
            Item { height: 8; Layout.fillWidth: true }

            Text {
                text: (remoteMemPopup.serverData ? remoteMemPopup.serverData.name : "Remote") + " Memory"
                color: "white"
                font.pixelSize: 20
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 22
                Layout.rightMargin: 22
                text: (remoteMemPopup.serverData ? remoteMemPopup.serverData.memDetail : "--")
                      + "  (" + (Number(remoteMemPopup.serverData ? remoteMemPopup.serverData.memPercent : 0) * 100).toFixed(0) + "%)"
                color: "#9fb4cf"
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 22
                Layout.rightMargin: 22
                text: "Updated: " + (remoteMemPopup.serverData ? remoteMemPopup.serverData.lastUpdate : "--")
                color: "#8fa4bf"
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            LineChart {
                Layout.fillWidth: true
                Layout.preferredHeight: 170
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                chartTitle: "History"
                datasets: [
                    {
                        label: "MEM",
                        values: (remoteMemPopup.serverData && remoteMemPopup.serverData.memHistory)
                                ? window.denseHistory(remoteMemPopup.serverData.memHistory, 160) : [],
                        color: "#2196F3"
                    }
                ]
                fixedMax: -1
                suffix: "%"
                showLegend: false
                showLine: false
                showPoints: true
                fillArea: false
                pointRadius: 1
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                height: 1
                color: "#323a43"
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                text: "Memory Breakdown"
                color: "#b7c4d4"
                font.pixelSize: 11
                font.bold: true
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                clip: true
                spacing: 8
                model: window.remoteMemoryInfoKeys

                delegate: RowLayout {
                    required property string modelData
                    property var infoMap: (remoteMemPopup.serverData && remoteMemPopup.serverData.memInfo)
                                          ? remoteMemPopup.serverData.memInfo : ({})
                    visible: infoMap[modelData] !== undefined && infoMap[modelData] !== ""
                    width: ListView.view.width
                    spacing: 8

                    Text {
                        text: modelData
                        color: "#888888"
                        font.pixelSize: 12
                        Layout.preferredWidth: parent.width * 0.45
                        elide: Text.ElideRight
                    }

                    Text {
                        text: parent.infoMap[modelData]
                        color: "white"
                        font.pixelSize: 12
                        font.bold: true
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideMiddle
                    }
                }
            }

            Item { height: 8; Layout.fillWidth: true }
        }
    }

    Popup {
        id: remoteDiskPopup
        property int serverIndex: -1
        property string serverName: ""
        property var serverData: {
            if (!backend || !backend.remoteServers)
                return null
            if (serverName !== "") {
                for (var i = 0; i < backend.remoteServers.length; ++i) {
                    var item = backend.remoteServers[i]
                    if ((item.name || "") === serverName)
                        return item
                }
            }
            return window.remoteServerAt(serverIndex)
        }

        parent: Overlay.overlay
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: parent.width * 0.92
        height: parent.height * 0.7
        modal: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        Overlay.modal: Rectangle { color: "#aa000000" }
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 200 }
            NumberAnimation { property: "scale"; from: 0.9; to: 1.0; duration: 200 }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 200 }
            NumberAnimation { property: "scale"; from: 1.0; to: 0.9; duration: 200 }
        }

        background: Rectangle {
            color: "#1e1e1e"
            radius: 15
            border.color: "#333333"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 10
            Item { height: 8; Layout.fillWidth: true }

            Text {
                text: (remoteDiskPopup.serverData ? remoteDiskPopup.serverData.name : "Remote") + " Disk"
                color: "white"
                font.pixelSize: 20
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 22
                Layout.rightMargin: 22
                text: (remoteDiskPopup.serverData ? remoteDiskPopup.serverData.diskDetail : "--")
                      + "  (" + (Number(remoteDiskPopup.serverData ? remoteDiskPopup.serverData.diskPercent : 0) * 100).toFixed(0) + "%)"
                color: "#9fb4cf"
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 22
                Layout.rightMargin: 22
                text: "Updated: " + (remoteDiskPopup.serverData ? remoteDiskPopup.serverData.lastUpdate : "--")
                color: "#8fa4bf"
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 15
                Layout.rightMargin: 15
                spacing: 10
                clip: true
                model: (remoteDiskPopup.serverData && remoteDiskPopup.serverData.diskPartitions)
                       ? remoteDiskPopup.serverData.diskPartitions : []

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: 74
                    color: "#2d2d2d"
                    radius: 8

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: modelData.mount
                                color: "white"
                                font.bold: true
                                font.pixelSize: 14
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                            }

                            Text {
                                text: modelData.used + " / " + modelData.size
                                color: "#aaaaaa"
                                font.pixelSize: 11
                                Layout.preferredWidth: implicitWidth
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: modelData.filesystem
                                color: "#666666"
                                font.pixelSize: 10
                                Layout.maximumWidth: parent.width * 0.6
                                elide: Text.ElideMiddle
                            }

                            Text {
                                text: "[" + modelData.type + "]"
                                color: "#666666"
                                font.pixelSize: 10
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 4
                            color: "#444"
                            radius: 2

                            Rectangle {
                                width: parent.width * Number(modelData.percent || 0)
                                height: parent.height
                                color: diskColor(Number(modelData.percent || 0))
                                radius: 2
                            }
                        }
                    }
                }
            }

            Item { height: 8; Layout.fillWidth: true }
        }
    }

    // ================= 页面导航 (StackView) =================
    StackView {
        id: stackView
        anchors.fill: parent
        initialItem: homePage
        focus: true
        z: 0
        
        // 自定义页面切换动画 (推入/推出)
        pushEnter: Transition {
            PropertyAnimation { property: "x"; from: window.width; to: 0; duration: 250; easing.type: Easing.OutCubic }
        }
        pushExit: Transition {
            PropertyAnimation { property: "x"; from: 0; to: -window.width * 0.3; duration: 250; easing.type: Easing.OutCubic }
        }
        popEnter: Transition {
            PropertyAnimation { property: "x"; from: -window.width * 0.3; to: 0; duration: 250; easing.type: Easing.OutCubic }
        }
        popExit: Transition {
            PropertyAnimation { property: "x"; from: 0; to: window.width; duration: 250; easing.type: Easing.OutCubic }
        }
    }

    Drawer {
        id: drawer
        width: window.width * 0.65 // 稍微加宽一点，让大图标看起来更舒服
        height: window.height
        z: position > 0 ? 999 : 1      
        edge: Qt.LeftEdge 
        interactive: stackView.depth === 1 
        dragMargin: window.width * 0.2

        background: Rectangle {
            color: "#121212" // 整体背景加深
            layer.enabled: true
            // 右侧分割线/阴影
            Rectangle {
                anchors.right: parent.right
                width: 1; height: parent.height
                color: "#333"
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ==========================================
            // 1. 顶部 Logo 区域 (占据 45% 高度)
            // ==========================================
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: parent.height * 0.45
                
                // 渐变背景，提升质感
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#252525" }
                    GradientStop { position: 1.0; color: "#1a1a1a" }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 20

                    // 大 Logo
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 96; height: 96
                        color: "transparent"
                        
                        // 外部光晕效果 (可选)
                        Rectangle {
                            anchors.centerIn: parent
                            width: 80; height: 80
                            radius: 40
                            color: "#ffffff"
                            opacity: 0.05
                        }

                        IconImage {
                            anchors.centerIn: parent
                            source: "qrc:/MyDesktop/Backend/assets/logo.svg"
                            sourceSize: Qt.size(80, 80) // 放大图标
                            color: "white"
                        }
                    }

                    // 文字信息
                    ColumnLayout {
                        spacing: 5
                        Text {
                            text: "Orbital"
                            color: "white"
                            font.bold: true
                            font.pixelSize: 22
                            font.letterSpacing: 2
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }

            // 分割线
            Rectangle { Layout.fillWidth: true; height: 1; color: "#333" }

            // ==========================================
            // 2. 底部功能按键区域 (剩余空间)
            // ==========================================
            ListView {
                id: menuList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                interactive: false // 禁止滚动，固定布局
                
                // 顶部留白
                header: Item { height: 20 }

                model: ListModel {
                    // Settings
                    ListElement { 
                        name: "Settings"; 
                        icon: "settings.svg"; 
                        action: "settings"; 
                        itemColor: "white" 
                    }
                    ListElement {
                        name: "Terminal";
                        icon: "terminal.svg";
                        action: "terminal";
                        itemColor: "#81A1C1"
                    }
                    // Reset Desktop (Exit 42)
                    ListElement { 
                        name: "Reset Desktop"; 
                        icon: "refresh.svg";
                        action: "reset"; 
                        itemColor: "#12E7FF"
                    }
                    // Reboot
                    ListElement { 
                        name: "Reboot"; 
                        icon: "restart.svg";
                        action: "reboot"; 
                        itemColor: "#FF9800"
                    }
                    // Power Off
                    ListElement { 
                        name: "Shut Down"; 
                        icon: "power.svg";
                        action: "shutdown"; 
                        itemColor: "#FF5252"
                    }
                }

                delegate: ItemDelegate {
                    width: parent.width
                    height: 65
                    
                    background: Rectangle {
                        color: parent.down ? "#2a2a2a" : "transparent"
                        Rectangle {
                            width: 4; height: parent.height
                            color: model.itemColor
                            visible: parent.parent.down
                        }
                    }

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 30
                        anchors.rightMargin: 30
                        spacing: 20

                        // 图标
                        IconImage {
                            source: "qrc:/MyDesktop/Backend/assets/" + model.icon
                            sourceSize: Qt.size(24, 24)
                            color: model.itemColor // 图标颜色跟随定义
                            Layout.alignment: Qt.AlignVCenter
                        }

                        // 文字
                        Text {
                            text: model.name
                            color: model.itemColor
                            font.pixelSize: 16
                            font.bold: true
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }

                    }

                    onClicked: {
                        // 稍微延迟关闭，让用户看到点击动画
                        drawer.close()
                        
                        if (model.action === "settings") {
                            stackView.push(settingsPage)
                        }
                        else if (model.action === "terminal") {
                            stackView.push("qrc:/MyDesktop/Backend/qml/TerminalPage.qml", {
                                "terminalBackend": terminalSession
                            })
                        }
                        else if (model.action === "reset") {
                            // 触发 Exit 42，配合 run.sh 重启
                            Qt.exit(42)
                        }
                        else if (model.action === "reboot") {
                            backend.systemCmd("reboot")
                        }
                        else if (model.action === "shutdown") {
                            backend.systemCmd("poweroff")
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: screenshotToast
        z: 2000
        width: Math.min(window.width - 40, screenshotToastText.implicitWidth + 36)
        height: screenshotToastText.implicitHeight + 18
        radius: 10
        color: "#202020"
        border.color: "#3a3a3a"
        border.width: 1
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 32
        opacity: screenshotToastMessage !== "" ? 0.96 : 0
        visible: opacity > 0

        Text {
            id: screenshotToastText
            anchors.centerIn: parent
            width: screenshotToast.width - 28
            text: screenshotToastMessage
            color: "white"
            font.pixelSize: 12
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }
    }

    Timer {
        id: screenshotToastTimer
        interval: 1800
        onTriggered: screenshotToastMessage = ""
    }

    // ================= MAIN UI =================
    Component {
        id: homePage
        Item {
            id: homeRoot
            property int horizontalPadding: 10
            property int topPadding: 0
            property int bottomPadding: 10
            property int metricsHeight: Math.round(window.height * 0.25)
            property int metricsBottomRowHeight: 52
            property int metricsTopRowHeight: Math.max(84, metricsHeight - metricsBottomRowHeight - 8)

            Rectangle {
                anchors.fill: parent
                color: "#121212"
                z: -1
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: homeRoot.horizontalPadding
                anchors.rightMargin: homeRoot.horizontalPadding
                anchors.topMargin: homeRoot.topPadding
                anchors.bottomMargin: homeRoot.bottomPadding
                spacing: 10

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 2
                        anchors.rightMargin: 14
                        spacing: 8

                        Text {
                            text: "Dashboard"
                            color: "white"
                            font.bold: true
                            font.pixelSize: 24
                            Layout.alignment: Qt.AlignBottom
                        }

                        Item { Layout.fillWidth: true }

                        Row {
                            spacing: 8
                            Layout.alignment: Qt.AlignBottom

                            IconImage {
                                source: "qrc:/MyDesktop/Backend/assets/logo.svg"
                                sourceSize: Qt.size(28, 28)
                                color: "white"
                            }

                            Text {
                                text: appName
                                color: "#efefef"
                                font.pixelSize: 20
                                font.bold: true
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: homeRoot.metricsHeight

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: homeRoot.metricsTopRowHeight
                            spacing: 10

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                color: cpuTap.pressed ? "#2a303a" : "#1a1d23"
                                radius: 12
                                border.color: "#2c3038"
                                border.width: 1

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 6

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Text {
                                            text: "CPU"
                                            color: "white"
                                            font.pixelSize: 15
                                            font.bold: true
                                        }

                                        Item { Layout.fillWidth: true }

                                        Column {
                                            spacing: 1
                                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

                                            Text {
                                                text: (backend.cpuTotal * 100).toFixed(0) + "%"
                                                color: cpuColor(backend.cpuTotal)
                                                font.pixelSize: 16
                                                font.bold: true
                                                horizontalAlignment: Text.AlignRight
                                            }

                                            Text {
                                                text: backend.cpuTemp
                                                color: "#FFB74D"
                                                font.pixelSize: 10
                                                font.bold: true
                                                horizontalAlignment: Text.AlignRight
                                            }
                                        }
                                    }

                                    Row {
                                        spacing: 2

                                        Repeater {
                                            model: 8

                                            Rectangle {
                                                required property int index
                                                property real coreLoad: backend.cpuCores[index] || 0

                                                width: 22
                                                height: 20
                                                radius: 4
                                                color: "#202634"
                                                border.width: 1
                                                border.color: "#343b48"

                                                Rectangle {
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.bottom: parent.bottom
                                                    anchors.margins: 1
                                                    height: Math.max(0, (parent.height - 2) * parent.coreLoad)
                                                    radius: 3
                                                    color: cpuColor(parent.coreLoad)
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: Math.round(parent.coreLoad * 100)
                                                    color: "#e7ebf0"
                                                    font.pixelSize: 8
                                                    font.bold: true
                                                    font.family: "Monospace"
                                                }
                                            }
                                        }
                                    }

                                    LineChart {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        chartTitle: "History"
                                        datasets: [
                                            { label: "Total", values: backend.cpuHistory, color: "#FF5252" }
                                        ]
                                        fixedMax: 100
                                        suffix: "%"
                                        showLegend: false
                                    }
                                }

                                TapHandler {
                                    id: cpuTap
                                    enabled: !cpuDetailsPopup.visible
                                    onTapped: cpuDetailsPopup.open()
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                color: memTap.pressed ? "#2a303a" : "#1a1d23"
                                radius: 12
                                border.color: "#2c3038"
                                border.width: 1

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 6

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Text {
                                            text: "Memory"
                                            color: "white"
                                            font.pixelSize: 15
                                            font.bold: true
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: (backend.memPercent * 100).toFixed(0) + "%"
                                            color: memColor(backend.memPercent)
                                            font.pixelSize: 16
                                            font.bold: true
                                        }
                                    }

                                    Text {
                                        text: backend.memDetail
                                        color: "#d0d5de"
                                        font.pixelSize: 12
                                    }

                                    LineChart {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        chartTitle: "History"
                                        datasets: [
                                            { label: "RAM", values: backend.memHistory, color: "#2196F3" }
                                        ]
                                        fixedMax: 100
                                        suffix: "%"
                                        showLegend: false
                                    }
                                }

                                TapHandler {
                                    id: memTap
                                    enabled: !memPopup.visible
                                    onTapped: memPopup.open()
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: homeRoot.metricsBottomRowHeight
                            spacing: 10

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 10
                                color: diskTap.pressed ? "#2a303a" : "#202736"
                                border.color: "#2f3744"
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    Text {
                                        text: "Disk " + (backend.diskPercent * 100).toFixed(0) + "%"
                                        color: diskColor(backend.diskPercent)
                                        font.pixelSize: 14
                                        font.bold: true
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: backend.diskRootUsage
                                        color: "#c6ccd7"
                                        font.pixelSize: 12
                                        elide: Text.ElideMiddle
                                        Layout.maximumWidth: 120
                                    }
                                }

                                TapHandler {
                                    id: diskTap
                                    enabled: !diskPopup.visible
                                    onTapped: diskPopup.open()
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 132
                                Layout.fillHeight: true
                                radius: 10
                                color: batTap.pressed ? "#2a303a" : "#202736"
                                border.color: "#2f3744"
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6

                                    Item {
                                        Layout.preferredWidth: 20
                                        Layout.preferredHeight: 12

                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 17
                                            height: 10
                                            radius: 2
                                            color: "#1b202a"
                                            border.width: 1
                                            border.color: "#9aa3b3"

                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.bottom: parent.bottom
                                                anchors.margins: 1
                                                width: Math.max(1, (parent.width - 2) * backend.batPercent / 100)
                                                height: parent.height - 2
                                                radius: 1
                                                color: batteryColor(backend.batPercent, backend.batState)
                                            }
                                        }

                                        Rectangle {
                                            x: 17
                                            y: 3
                                            width: 2
                                            height: 4
                                            radius: 1
                                            color: "#9aa3b3"
                                        }
                                    }

                                    Text {
                                        text: backend.batPercent + "%"
                                        color: batteryColor(backend.batPercent, backend.batState)
                                        font.pixelSize: 14
                                        font.bold: true
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: backend.batState
                                        color: "#c6ccd7"
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: 52
                                    }
                                }

                                TapHandler {
                                    id: batTap
                                    enabled: !batPopup.visible
                                    onTapped: batPopup.open()
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 106
                    radius: 12
                    color: netTap.pressed ? "#2a2f39" : "#1a1f29"
                    border.color: "#2c3038"
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "Network"
                                color: "white"
                                font.pixelSize: 14
                                font.bold: true
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: "⬇ " + backend.netRxSpeed
                                color: "#00E676"
                                font.pixelSize: 12
                                font.family: "Monospace"
                                font.bold: true
                            }

                            Rectangle { width: 1; height: 18; color: "#384050" }

                            Text {
                                text: "⬆ " + backend.netTxSpeed
                                color: "#FF9800"
                                font.pixelSize: 12
                                font.family: "Monospace"
                                font.bold: true
                            }
                        }

                        LineChart {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            chartTitle: "History"
                            datasets: [
                                { label: "Down", values: backend.netRxHistory, color: "#00E676" },
                                { label: "Up", values: backend.netTxHistory, color: "#FF9800" }
                            ]
                            fixedMax: -1
                            suffix: " KB/s"
                            showLegend: false
                        }
                    }

                    TapHandler {
                        id: netTap
                        enabled: !netPopup.visible
                        onTapped: netPopup.open()
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: backend.remoteServers

                        Rectangle {
                            id: remoteServerCard
                            required property var modelData
                            property var serverData: modelData
                            property int serverIndex: index

                            Layout.fillWidth: true
                            Layout.preferredHeight: 212
                            radius: 12
                            color: "#1a1f29"
                            border.width: 1
                            border.color: "#2c3038"

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        text: serverData.name || "Remote"
                                        color: "white"
                                        font.pixelSize: 13
                                        font.bold: true
                                    }

                                    Rectangle {
                                        radius: 6
                                        width: 56
                                        height: 16
                                        color: serverData.status === "Online"
                                               ? "#1f6f4f"
                                               : (serverData.status === "Updating" ? "#6d571f" : "#6f1f2f")

                                        Text {
                                            anchors.centerIn: parent
                                            text: serverData.status || "--"
                                            color: "#f2f4f8"
                                            font.pixelSize: 9
                                            font.bold: true
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: serverData.lastUpdate || "--"
                                        color: "#9db0c3"
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: 90
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 104
                                    spacing: 8

                                    Rectangle {
                                        id: remoteCpuCard
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: 10
                                        color: remoteCpuClick.pressed ? "#2a303a" : "#1a1d23"
                                        border.color: "#2f3744"
                                        border.width: 1

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 4

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6

                                                Text {
                                                    text: "CPU"
                                                    color: "white"
                                                    font.pixelSize: 13
                                                    font.bold: true
                                                }

                                                Item { Layout.fillWidth: true }

                                                Text {
                                                    text: (Number(serverData.cpuTotal || 0) * 100).toFixed(0) + "% · " + (serverData.coreCount || 0) + "C"
                                                    color: cpuColor(Number(serverData.cpuTotal || 0))
                                                    font.pixelSize: 11
                                                    font.bold: true
                                                }
                                            }

                                            Row {
                                                id: remoteCpuGroupRow
                                                property var groups: serverData.cpuGroups || []
                                                spacing: 2

                                                Repeater {
                                                    model: 8

                                                    Rectangle {
                                                        required property int index
                                                        property real groupLoad: (remoteCpuGroupRow.groups && index < remoteCpuGroupRow.groups.length)
                                                                                 ? Number(remoteCpuGroupRow.groups[index]) : 0

                                                        width: Math.max(12, Math.floor((remoteCpuCard.width - 24) / 8))
                                                        height: 18
                                                        radius: 3
                                                        color: "#202634"
                                                        border.width: 1
                                                        border.color: "#343b48"

                                                        Rectangle {
                                                            anchors.left: parent.left
                                                            anchors.right: parent.right
                                                            anchors.bottom: parent.bottom
                                                            anchors.margins: 1
                                                            height: Math.max(0, (parent.height - 2) * parent.groupLoad)
                                                            radius: 2
                                                            color: cpuColor(parent.groupLoad)
                                                        }

                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: Math.round(parent.groupLoad * 100)
                                                            color: "#e7ebf0"
                                                            font.pixelSize: 7
                                                            font.bold: true
                                                            font.family: "Monospace"
                                                        }
                                                    }
                                                }
                                            }

                                            LineChart {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                chartTitle: "History"
                                                datasets: [
                                                    { label: "CPU", values: window.denseHistory(serverData.cpuHistory || [], 96), color: "#FF5252" }
                                                ]
                                                fixedMax: -1
                                                suffix: "%"
                                                showLegend: false
                                                showLine: false
                                                showPoints: true
                                                fillArea: false
                                                pointRadius: 1
                                                compact: true
                                                showScaleLabels: false
                                            }
                                        }

                                        MouseArea {
                                            id: remoteCpuClick
                                            anchors.fill: parent
                                            z: 5
                                            onClicked: {
                                                remoteCpuPopup.serverIndex = remoteServerCard.serverIndex
                                                remoteCpuPopup.serverName = remoteServerCard.serverData.name || ""
                                                backend.refreshRemoteServers()
                                                remoteCpuPopup.open()
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: 10
                                        color: remoteMemClick.pressed ? "#2a303a" : "#1a1d23"
                                        border.color: "#2f3744"
                                        border.width: 1

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 4

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6

                                                Text {
                                                    text: "Memory"
                                                    color: "white"
                                                    font.pixelSize: 13
                                                    font.bold: true
                                                }

                                                Item { Layout.fillWidth: true }

                                                Text {
                                                    text: (Number(serverData.memPercent || 0) * 100).toFixed(0) + "%"
                                                    color: memColor(Number(serverData.memPercent || 0))
                                                    font.pixelSize: 12
                                                    font.bold: true
                                                }
                                            }

                                            Text {
                                                text: serverData.memDetail || "--"
                                                color: "#d0d5de"
                                                font.pixelSize: 10
                                                elide: Text.ElideRight
                                            }

                                            LineChart {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                chartTitle: "History"
                                                datasets: [
                                                    { label: "MEM", values: window.denseHistory(serverData.memHistory || [], 96), color: "#2196F3" }
                                                ]
                                                fixedMax: -1
                                                suffix: "%"
                                                showLegend: false
                                                showLine: false
                                                showPoints: true
                                                fillArea: false
                                                pointRadius: 1
                                                compact: true
                                                showScaleLabels: false
                                            }
                                        }

                                        MouseArea {
                                            id: remoteMemClick
                                            anchors.fill: parent
                                            z: 5
                                            onClicked: {
                                                remoteMemPopup.serverIndex = remoteServerCard.serverIndex
                                                remoteMemPopup.serverName = remoteServerCard.serverData.name || ""
                                                backend.refreshRemoteServers()
                                                remoteMemPopup.open()
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 48
                                    radius: 10
                                    color: remoteDiskClick.pressed ? "#2a303a" : "#202736"
                                    border.color: "#2f3744"
                                    border.width: 1

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        anchors.topMargin: 6
                                        anchors.bottomMargin: 6
                                        spacing: 2

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Text {
                                                text: "Disk " + (Number(serverData.diskPercent || 0) * 100).toFixed(0) + "%"
                                                color: diskColor(Number(serverData.diskPercent || 0))
                                                font.pixelSize: 12
                                                font.bold: true
                                            }

                                            Item { Layout.fillWidth: true }

                                            Text {
                                                text: serverData.diskDetail || "--"
                                                color: "#c6ccd7"
                                                font.pixelSize: 10
                                                elide: Text.ElideMiddle
                                                Layout.maximumWidth: 138
                                            }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 4
                                            radius: 2
                                            color: "#394252"

                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.top: parent.top
                                                anchors.bottom: parent.bottom
                                                width: parent.width * Number(serverData.diskPercent || 0)
                                                radius: 2
                                                color: diskColor(Number(serverData.diskPercent || 0))
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: remoteDiskClick
                                        anchors.fill: parent
                                        z: 5
                                        onClicked: {
                                            remoteDiskPopup.serverIndex = remoteServerCard.serverIndex
                                            remoteDiskPopup.serverName = remoteServerCard.serverData.name || ""
                                            backend.refreshRemoteServers()
                                            remoteDiskPopup.open()
                                        }
                                    }
                                }

                                Text {
                                    visible: (serverData.error || "") !== ""
                                    Layout.fillWidth: true
                                    text: serverData.error
                                    color: "#c88f8f"
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }
            }
        }
    }

    Component {
        id: settingsPage
        
        // 引用外部文件
        SettingsPage {
            // 1. 传入后端实例 (Window里定义的 backend id)
            sysMon: backend
            
            // 2. 响应返回信号
            onRequestBack: {
                stackView.pop()
            }
        }
    }
}
