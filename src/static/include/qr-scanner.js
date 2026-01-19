// qr-scanner.js
export class QrScanner {
    constructor({
        videoEl,
        previewCanvas,
        statusEl,
        scanIntervalMs = 200,
        onResult = () => {}
    }) {
        this.video = videoEl;
        this.previewCanvas = previewCanvas;
        this.previewCtx = previewCanvas ? previewCanvas.getContext("2d") : null;
        this.statusEl = statusEl;

        this.scanIntervalMs = scanIntervalMs;
        this.onResult = onResult;

        this.frameCanvas = document.createElement("canvas");
        this.frameCtx = this.frameCanvas.getContext("2d");

        this.cvReady = false;
        this.cameraReady = false;
        this.currentStream = null;
        this.scanTimer = null;
        this.isProcessing = false;

        this.qrDetector = null;

        this._initOpenCvWatcher();
    }

    _setStatus(text) {
        if (this.statusEl) this.statusEl.textContent = text;
    }

    _initOpenCvWatcher() {
        const interval = setInterval(() => {
            if (window.cv && typeof cv.Mat === "function") {
                clearInterval(interval);
                this.cvReady = true;
                try {
                    this.qrDetector = new cv.QRCodeDetector();
                } catch (e) {
                    console.warn("QRCodeDetector not available in this OpenCV build:", e);
                }
                this._updateStatus();
            }
        }, 100);
    }

    _updateStatus() {
        if (this.cvReady && this.cameraReady) {
            this._setStatus("Camera ready. Point at QR code.");
        } else if (!this.cvReady && !this.cameraReady) {
            this._setStatus("Initializing camera and OpenCV…");
        } else if (!this.cvReady && this.cameraReady) {
            this._setStatus("Camera ready. Waiting for OpenCV…");
        } else if (this.cvReady && !this.cameraReady) {
            this._setStatus("OpenCV ready. Waiting for camera…");
        }
    }

    async initCamera() {
        if (this.cameraReady && this.currentStream) return;

        try {
            const stream = await navigator.mediaDevices.getUserMedia({
                video: {
                    facingMode: { ideal: "environment" },
                    width: { ideal: 1920 },
                    height: { ideal: 1080 }
                },
                audio: false
            });

            this.currentStream = stream;
            this.video.srcObject = stream;
            await this.video.play();

            // Try to use continuous autofocus if available
            try {
                const track = stream.getVideoTracks()[0];
                if (track && track.getCapabilities) {
                    const caps = track.getCapabilities();
                    if (caps.focusMode && caps.focusMode.includes("continuous")) {
                        await track.applyConstraints({ advanced: [{ focusMode: "continuous" }] });
                    }
                }
            } catch (e) {
                console.warn("Continuous AF not supported:", e);
            }

            // Use actual camera resolution for frame canvas
            const setDimensions = () => {
                if (!this.video.videoWidth || !this.video.videoHeight) {
                    setTimeout(setDimensions, 100);
                    return;
                }
                this.frameCanvas.width = this.video.videoWidth;
                this.frameCanvas.height = this.video.videoHeight;
                this.cameraReady = true;
                this._updateStatus();
            };

            if (this.video.videoWidth && this.video.videoHeight) {
                setDimensions();
            } else {
                this.video.onloadedmetadata = setDimensions;
            }
        } catch (err) {
            console.error("getUserMedia failed:", err);
            this._setStatus("Camera error: " + err.message);
        }
    }

    // Turn camera off
    _stopCamera() {
        if (this.currentStream) {
            this.currentStream.getTracks().forEach(track => track.stop());
            this.currentStream = null;
        }
        if (this.video) {
            this.video.srcObject = null;
        }
        this.cameraReady = false;
        this._updateStatus();
    }

    // public API
    async start() {
        this._setStatus("Starting QR scanner…");
        await this.initCamera();

        if (!this.cvReady) {
            this._setStatus("Waiting for OpenCV…");
            const waitCv = () =>
                new Promise(resolve => {
                    const intv = setInterval(() => {
                        if (this.cvReady) {
                            clearInterval(intv);
                            resolve();
                        }
                    }, 100);
                });
            await waitCv();
        }

        if (!this.cameraReady) {
            this._setStatus("Camera not ready.");
            return;
        }

        if (!this.qrDetector) {
            this._setStatus("QR code detector not available.");
            return;
        }

        this._setStatus("Scanning for QR code…");
        this.scanTimer = setInterval(() => this._scanOnce(), this.scanIntervalMs);
    }

    stop() {
        if (this.scanTimer) {
            clearInterval(this.scanTimer);
            this.scanTimer = null;
        }
        this._stopCamera();
        this._setStatus("QR scanner stopped.");
    }

    async restart() {
        this.stop();
        this._setStatus("Restarting QR scanner…");
        await this.start();
    }

    // optional: tap-to-focus
    attachTapToFocus() {
        this.video.addEventListener("click", async (event) => {
            if (!this.currentStream) return;

            const track = this.currentStream.getVideoTracks()[0];
            if (!track || !track.getCapabilities || !track.applyConstraints) {
                console.log("Tap-to-focus not supported on this device");
                return;
            }

            const caps = track.getCapabilities();
            const constraints = { advanced: [] };

            if (caps.pointsOfInterest) {
                const rect = this.video.getBoundingClientRect();
                const x = (event.clientX - rect.left) / rect.width;
                const y = (event.clientY - rect.top) / rect.height;
                constraints.advanced.push({ pointsOfInterest: [{ x, y }] });
            }

            if (caps.focusMode && caps.focusMode.includes("single-shot")) {
                constraints.advanced.push({ focusMode: "single-shot" });
            }

            if (!constraints.advanced.length) return;

            try {
                await track.applyConstraints(constraints);
                console.log("Tap-to-focus constraints applied:", constraints);
            } catch (err) {
                console.warn("Failed to apply tap-to-focus constraints:", err);
            }
        });
    }

    _scanOnce() {
        if (this.isProcessing) return;
        if (!this.cvReady || !this.cameraReady) return;

        this.isProcessing = true;
        try {
            const result = this._processFrame();
            if (result && result.ok) {
                // Found a QR code: stop scanning and camera, notify caller
                this._setStatus("QR code detected.");
                this.stop();
                this.onResult(result);
            }
        } catch (e) {
            console.error("QR scan error:", e);
        } finally {
            this.isProcessing = false;
        }
    }

    _processFrame() {
        const frameW = this.frameCanvas.width;
        const frameH = this.frameCanvas.height;

        // Draw current video frame onto canvas
        this.frameCtx.drawImage(this.video, 0, 0, frameW, frameH);

        // Read into OpenCV
        let src = cv.imread(this.frameCanvas);

        let points = new cv.Mat();
        let straightQr = new cv.Mat();
        let decodedText = "";

        try {
            // detectAndDecode returns "" on failure
            decodedText = this.qrDetector.detectAndDecode(src, points, straightQr);
        } catch (e) {
            console.warn("detectAndDecode failed:", e);
        }

        let ok = false;
        let polygon = null;
        let dataUrl = null;

        if (decodedText && typeof decodedText === "string" && decodedText.length > 0) {
            ok = true;

            // Extract polygon points if available (4 points, 8 values)
            if (!points.empty()) {
                polygon = [];
                // points is 1x4xCV_64FC2 or similar; OpenCV.js flattens differently,
                // but this loop works for typical builds.
                for (let i = 0; i < points.data64F.length; i += 2) {
                    polygon.push({
                        x: points.data64F[i],
                        y: points.data64F[i + 1]
                    });
                }
            }

            // Preview straightened QR or full frame if you like
            if (this.previewCtx) {
                const canvas = document.createElement("canvas");
                if (!straightQr.empty()) {
                    canvas.width = straightQr.cols;
                    canvas.height = straightQr.rows;
                    cv.imshow(canvas, straightQr);
                } else {
                    canvas.width = src.cols;
                    canvas.height = src.rows;
                    cv.imshow(canvas, src);
                }

                this.previewCtx.clearRect(0, 0, this.previewCanvas.width, this.previewCanvas.height);
                this.previewCtx.drawImage(
                    canvas,
                    0, 0, canvas.width, canvas.height,
                    0, 0, this.previewCanvas.width, this.previewCanvas.height
                );

                // Optional: return image data URL in result
                dataUrl = canvas.toDataURL("image/png");
            }
        } else {
            this._setStatus("Looking for QR code…");
        }

        src.delete();
        points.delete();
        straightQr.delete();

        if (ok) {
            return {
                ok: true,
                text: decodedText,
                polygon,
                imageDataUrl: dataUrl
            };
        }

        return { ok: false };
    }
}
