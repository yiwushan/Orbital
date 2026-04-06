import QtQuick
import QtQuick.Layouts

Item {
    id: root
    
    property string chartTitle: "" 
    property var datasets: []      
    property double fixedMax: -1   
    property string suffix: ""     
    property bool showLegend: true 
    property bool showLine: true
    property bool showPoints: false
    property bool fillArea: true
    property int pointRadius: 2
    property bool compact: false
    property bool showScaleLabels: true

    property double _currentMaxY: 100 

    Behavior on _currentMaxY {
        NumberAnimation { 
            duration: 300 
            easing.type: Easing.OutCubic 
        }
    }

    onDatasetsChanged: {
        calculateMax();
        canvas.requestPaint(); 
    }

    on_CurrentMaxYChanged: canvas.requestPaint()

    function calculateMax() {
        if (!root.datasets || root.datasets.length === 0) return;

        var globalMax = 0;
        if (root.fixedMax > 0) {
            globalMax = root.fixedMax;
        } else {
            for (var d = 0; d < root.datasets.length; d++) {
                var vals = root.datasets[d].values;
                if (!vals) continue;
                for (var i = 0; i < vals.length; i++) {
                    if (vals[i] > globalMax) globalMax = vals[i];
                }
            }
            if (globalMax === 0) globalMax = 10;
            globalMax = globalMax * 1.1; 
        }
        
        // 更新目标值，如果值变了，Behavior 会自动开启动画
        root._currentMaxY = globalMax;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            
            Canvas {
                id: canvas
                anchors.fill: parent
                anchors.topMargin: root.compact ? 20 : 38
                anchors.bottomMargin: root.compact ? 6 : 14
                
                renderTarget: Canvas.Image
                renderStrategy: Canvas.Threaded

                onPaint: {
                    var ctx = getContext("2d");
                    var w = width;
                    var h = height;
                    
                    ctx.clearRect(0, 0, w, h);

                    if (!root.datasets || root.datasets.length === 0) return;

                    // 使用 _currentMaxY 进行绘图
                    var drawMax = root._currentMaxY;

                    // --- 绘制网格 ---
                    ctx.strokeStyle = "#333333";
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    
                    ctx.moveTo(0, 0); ctx.lineTo(w, 0);
                    ctx.moveTo(0, h * 0.33); ctx.lineTo(w, h * 0.33);
                    ctx.moveTo(0, h * 0.66); ctx.lineTo(w, h * 0.66);
                    ctx.moveTo(0, h); ctx.lineTo(w, h);
                    ctx.stroke();

                    // --- 绘制曲线 ---
                    function getY(val) { return h - (val / drawMax * h); }

                    for (var k = 0; k < root.datasets.length; k++) {
                        var series = root.datasets[k];
                        var data = series.values;
                        var color = series.color;

                        if (!data || data.length < 1) continue;

                        var stepX = data.length > 1 ? w / (data.length - 1) : 0;
                        function xOf(i) { return data.length > 1 ? i * stepX : w * 0.5; }

                        if (root.showLine && root.fillArea && data.length >= 2) {
                            // 填充
                            ctx.save();
                            ctx.beginPath();
                            ctx.moveTo(xOf(0), getY(data[0]));
                            for (var i = 1; i < data.length; i++) {
                                ctx.lineTo(xOf(i), getY(data[i]));
                            }
                            ctx.lineTo(xOf(data.length - 1), h);
                            ctx.lineTo(xOf(0), h);
                            ctx.closePath();
                            ctx.globalAlpha = 0.2;
                            ctx.fillStyle = color;
                            ctx.fill();
                            ctx.restore();
                        }

                        if (root.showLine && data.length >= 2) {
                            // 描边
                            ctx.beginPath();
                            ctx.moveTo(xOf(0), getY(data[0]));
                            for (var i = 1; i < data.length; i++) {
                                ctx.lineTo(xOf(i), getY(data[i]));
                            }
                            ctx.lineJoin = "round";
                            ctx.lineCap = "round";
                            ctx.strokeStyle = color;
                            ctx.lineWidth = 2;
                            ctx.stroke();
                        }

                        if (root.showPoints) {
                            ctx.save();
                            ctx.fillStyle = color;
                            for (var i = 0; i < data.length; i++) {
                                ctx.beginPath();
                                ctx.arc(xOf(i), getY(data[i]), Math.max(1, root.pointRadius), 0, Math.PI * 2, false);
                                ctx.fill();
                            }
                            ctx.restore();
                        }
                    }
                }
            }

            // --- 覆盖层信息 ---
            Text {
                id: titleText
                anchors.left: parent.left
                anchors.top: parent.top
                text: root.chartTitle
                color: "#dddddd"
                font.pixelSize: root.compact ? 10 : 12
                font.bold: true
            }

            Text {
                anchors.left: parent.left
                anchors.bottom: canvas.top 
                anchors.bottomMargin: 2 
                text: "Max: " + (root.fixedMax > 0 ? root.fixedMax : root._currentMaxY.toFixed(1)) + root.suffix
                color: "#666666"
                font.pixelSize: 10
                visible: root.showScaleLabels
            }
            
            Text {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                text: "0"
                color: "#666666"
                font.pixelSize: 10
                visible: root.showScaleLabels
            }
        }

        Row {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 5
            Layout.topMargin: 0
            spacing: 20
            visible: root.showLegend && root.datasets.length > 1
            Repeater {
                model: root.datasets
                Row {
                    spacing: 6
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle { width: 10; height: 10; radius: 2; color: modelData.color; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: modelData.label; color: "#aaaaaa"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                }
            }
        }
    }
}
