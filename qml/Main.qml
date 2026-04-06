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
            property int topPadding: 20
            property int bottomPadding: 12

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

                Rectangle {
                    id: metricsPanel
                    Layout.fillWidth: true
                    Layout.preferredHeight: metricsPanelContent.implicitHeight + 24
                    color: "#1a1d23"
                    radius: 14
                    border.color: "#2c3038"
                    border.width: 1

                    ColumnLayout {
                        id: metricsPanelContent
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 44

                            Text {
                                id: dashboardTitle
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                text: "Dashboard"
                                color: "white"
                                font.bold: true
                                font.pixelSize: 24
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                spacing: 8

                                IconImage {
                                    source: "qrc:/MyDesktop/Backend/assets/logo.svg"
                                    sourceSize: Qt.size(30, 30)
                                    color: "white"
                                }

                                Text {
                                    text: appName
                                    color: "#efefef"
                                    font.pixelSize: 23
                                    font.bold: true
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: "#2f3440"
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            radius: 8
                            color: cpuTap.pressed ? "#2a303a" : "#141922"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                Text {
                                    text: "CPU " + (backend.cpuTotal * 100).toFixed(0) + "%"
                                    color: cpuColor(backend.cpuTotal)
                                    font.pixelSize: 14
                                    font.bold: true
                                    Layout.preferredWidth: 72
                                }

                                Item { Layout.fillWidth: true }

                                Row {
                                    spacing: 2

                                    Repeater {
                                        model: 8

                                        Rectangle {
                                            required property int index
                                            property real coreLoad: backend.cpuCores[index] || 0

                                            width: 22
                                            height: 18
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
                            }

                            TapHandler {
                                id: cpuTap
                                enabled: !cpuDetailsPopup.visible
                                onTapped: cpuDetailsPopup.open()
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            radius: 8
                            color: "#141922"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                Text {
                                    text: "Memory " + (backend.memPercent * 100).toFixed(0) + "%"
                                    color: memColor(backend.memPercent)
                                    font.pixelSize: 14
                                    font.bold: true
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: backend.memDetail
                                    color: "#d0d5de"
                                    font.pixelSize: 13
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            radius: 8
                            color: "#141922"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                spacing: 6

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 26
                                    radius: 6
                                    color: diskTap.pressed ? "#2a303a" : "#202736"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 6

                                        Text {
                                            text: "Disk " + (backend.diskPercent * 100).toFixed(0) + "%"
                                            color: diskColor(backend.diskPercent)
                                            font.pixelSize: 13
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
                                    Layout.preferredWidth: 130
                                    Layout.preferredHeight: 26
                                    radius: 6
                                    color: batTap.pressed ? "#2a303a" : "#202736"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 6

                                        Text {
                                            text: "BAT " + backend.batPercent + "%"
                                            color: batteryColor(backend.batPercent, backend.batState)
                                            font.pixelSize: 13
                                            font.bold: true
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: backend.batState
                                            color: "#c6ccd7"
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                            Layout.maximumWidth: 62
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
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 58
                    radius: 12
                    color: netTap.pressed ? "#2a2f39" : "#1a1f29"
                    border.color: "#2c3038"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 8

                        Text {
                            text: "Network"
                            color: "white"
                            font.pixelSize: 15
                            font.bold: true
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: "⬇ " + backend.netRxSpeed
                            color: "#00E676"
                            font.pixelSize: 14
                            font.family: "Monospace"
                            font.bold: true
                        }

                        Rectangle { width: 1; height: 24; color: "#384050" }

                        Text {
                            text: "⬆ " + backend.netTxSpeed
                            color: "#FF9800"
                            font.pixelSize: 14
                            font.family: "Monospace"
                            font.bold: true
                        }
                    }

                    TapHandler {
                        id: netTap
                        enabled: !netPopup.visible
                        onTapped: netPopup.open()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "#1a1d23"
                    radius: 14
                    border.color: "#2c3038"
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        Text {
                            text: "History"
                            color: "white"
                            font.pixelSize: 16
                            font.bold: true
                        }

                        LineChart {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            chartTitle: "CPU Usage"
                            datasets: [
                                { label: "Total", values: backend.cpuHistory, color: "#FF5252" }
                            ]
                            fixedMax: 100
                            suffix: "%"
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: "#323844"
                        }

                        LineChart {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            chartTitle: "Memory Usage"
                            datasets: [
                                { label: "RAM", values: backend.memHistory, color: "#2196F3" }
                            ]
                            fixedMax: 100
                            suffix: "%"
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: "#323844"
                        }

                        LineChart {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            chartTitle: "Network I/O"
                            datasets: [
                                { label: "Down", values: backend.netRxHistory, color: "#00E676" },
                                { label: "Up", values: backend.netTxHistory, color: "#FF9800" }
                            ]
                            fixedMax: -1
                            suffix: " KB/s"
                        }
                    }
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
