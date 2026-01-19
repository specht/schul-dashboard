// card-scanner.js
export class CardScanner {
    constructor({
        videoEl,
        previewCanvas,
        statusEl,
        sharpnessEl,
        sharpnessThreshold = 150,
        targetAspect = 4 / 3,
        outputWidth = 1024,
        outputHeight = 640,
        scanIntervalMs = 400,
        onGoodCapture = () => {}
    }) {
        this.video = videoEl;
        this.previewCanvas = previewCanvas;
        this.previewCtx = previewCanvas.getContext("2d");
        this.statusEl = statusEl;
        this.sharpnessEl = sharpnessEl;

        this.sharpnessThreshold = sharpnessThreshold;
        this.targetAspect = targetAspect;
        this.outputWidth = outputWidth;
        this.outputHeight = outputHeight;
        this.scanIntervalMs = scanIntervalMs;
        this.onGoodCapture = onGoodCapture;

        this.frameCanvas = document.createElement("canvas");
        this.frameCtx = this.frameCanvas.getContext("2d");

        this.cvReady = false;
        this.cameraReady = false;
        this.currentStream = null;
        this.scanTimer = null;
        this.isProcessing = false;

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
                this._updateStatus();
            }
        }, 100);
    }

    _updateStatus() {
        if (this.cvReady && this.cameraReady) {
            this._setStatus("Camera ready. Hold card steady.");
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
                    width: { ideal: 4096 },
                    height: { ideal: 2160 }
                },
                audio: false
            });

            this.currentStream = stream;
            this.video.srcObject = stream;
            await this.video.play();

            // Request continuous AF if possible
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

            // Set frame canvas size from actual resolution
            if (this.video.videoWidth && this.video.videoHeight) {
                this.frameCanvas.width = this.video.videoWidth;
                this.frameCanvas.height = this.video.videoHeight;
                this.cameraReady = true;
                this._updateStatus();
            } else {
                this.video.onloadedmetadata = () => {
                    if (!this.video.videoWidth || !this.video.videoHeight) {
                        setTimeout(this.video.onloadedmetadata, 100);
                        return;
                    }
                    this.frameCanvas.width = this.video.videoWidth;
                    this.frameCanvas.height = this.video.videoHeight;
                    this.cameraReady = true;
                    this._updateStatus();
                };
            }
        } catch (err) {
            console.error("getUserMedia failed:", err);
            this._setStatus("Camera error: " + err.message);
        }
    }

    // NEW: actually turn the camera off
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
        this._setStatus("Starting scanner…");
        await this.initCamera();

        if (!this.cvReady) {
            this._setStatus("Waiting for OpenCV…");
            // wait until cvReady flips true
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

        this._setStatus("Scanning… hold card steady.");
        this.scanTimer = setInterval(() => this._scanOnce(), this.scanIntervalMs);
    }

    stop() {
        if (this.scanTimer) {
            clearInterval(this.scanTimer);
            this.scanTimer = null;
        }

        // Turn off camera when we stop scanning
        this._stopCamera();

        this._setStatus("Scanner stopped.");
    }

    async restart() {
        this.stop();
        this._setStatus("Restarting scanner…");
        await this.start();
    }

    // optional: expose tap-to-focus if caller wants to hook it up
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
                // stop scanning and notify caller
                this.stop(); // <-- now also turns off camera
                this._setStatus("Good card captured.");
                this.onGoodCapture(result);
            }
        } catch (e) {
            console.error("Scan error:", e);
        } finally {
            this.isProcessing = false;
        }
    }

    _processFrame() {
        const frameW = this.frameCanvas.width;
        const frameH = this.frameCanvas.height;

        // Draw current video frame onto canvas
        this.frameCtx.drawImage(this.video, 0, 0, frameW, frameH);

        // Full frame to Mat (RGBA)
        let srcFull = cv.imread(this.frameCanvas);

        // Crop to same central aspect as visible video
        const TARGET_ASPECT = this.targetAspect;
        const fullW = srcFull.cols;
        const fullH = srcFull.rows;
        const fullAspect = fullW / fullH;

        let roiRect;
        if (fullAspect > TARGET_ASPECT) {
            const roiH = fullH;
            const roiW = Math.round(roiH * TARGET_ASPECT);
            const x = Math.floor((fullW - roiW) / 2);
            roiRect = new cv.Rect(x, 0, roiW, roiH);
        } else {
            const roiW = fullW;
            const roiH = Math.round(roiW / TARGET_ASPECT);
            const y = Math.floor((fullH - roiH) / 2);
            roiRect = new cv.Rect(0, y, roiW, roiH);
        }

        let src = srcFull.roi(roiRect);
        srcFull.delete();

        // Preprocess
        let gray = new cv.Mat();
        cv.cvtColor(src, gray, cv.COLOR_RGBA2GRAY, 0);

        let blurred = new cv.Mat();
        cv.GaussianBlur(gray, blurred, new cv.Size(5, 5), 0, 0, cv.BORDER_DEFAULT);

        let bin = new cv.Mat();
        cv.threshold(blurred, bin, 0, 255, cv.THRESH_BINARY + cv.THRESH_OTSU);

        // Contours
        let contours = new cv.MatVector();
        let hierarchy = new cv.Mat();
        cv.findContours(bin, contours, hierarchy, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);

        let bestQuad = null;
        let bestArea = 0;
        const imgArea = src.cols * src.rows;

        for (let i = 0; i < contours.size(); i++) {
            const contour = contours.get(i);
            const peri = cv.arcLength(contour, true);
            const approx = new cv.Mat();
            cv.approxPolyDP(contour, approx, 0.02 * peri, true);

            if (approx.rows === 4) {
                const area = cv.contourArea(approx);
                if (area < imgArea * 0.05) {
                    approx.delete();
                    contour.delete();
                    continue;
                }

                const pts = [];
                for (let j = 0; j < 4; j++) {
                    pts.push({ x: approx.intAt(j, 0), y: approx.intAt(j, 1) });
                }

                if (area > bestArea) {
                    bestArea = area;
                    bestQuad = pts;
                }
            }

            approx.delete();
            contour.delete();
        }

        let rectified = null;
        let normalized = null;
        let sharpness = null;

        if (!bestQuad) {
            this._setStatus("Looking for card…");
        } else {
            const ordered = this._orderCorners(bestQuad);
            rectified = this._warpToCard(src, ordered, this.outputWidth, this.outputHeight);

            normalized = this._stretchHighlights(rectified, 0.95);

            // Preview
            const cardCanvas = document.createElement("canvas");
            cardCanvas.width = this.outputWidth;
            cardCanvas.height = this.outputHeight;
            cv.imshow(cardCanvas, normalized);
            this.previewCtx.clearRect(0, 0, this.previewCanvas.width, this.previewCanvas.height);
            this.previewCtx.drawImage(
                cardCanvas,
                0, 0, cardCanvas.width, cardCanvas.height,
                0, 0, this.previewCanvas.width, this.previewCanvas.height
            );

            sharpness = this._computeSharpness(normalized);
            if (this.sharpnessEl) this.sharpnessEl.textContent = sharpness.toFixed(1);

            const frameEl = document.querySelector(".target-frame");

            if (sharpness >= this.sharpnessThreshold) {
                this._setStatus("Card OK (sharp).");
                frameEl && frameEl.classList.add("ready");
            } else {
                this._setStatus("Card detected but blurry…");
                frameEl && frameEl.classList.remove("ready");
            }
        }

        // Cleanup
        src.delete();
        gray.delete();
        blurred.delete();
        bin.delete();
        contours.delete();
        hierarchy.delete();
        if (rectified) rectified.delete();

        const ok = !!bestQuad && sharpness >= this.sharpnessThreshold;

        if (normalized && ok) {
            const tmpCanvas = document.createElement("canvas");
            tmpCanvas.width = this.outputWidth;
            tmpCanvas.height = this.outputHeight;
            cv.imshow(tmpCanvas, normalized);
            const dataUrl = tmpCanvas.toDataURL("image/png");
            normalized.delete();
            return { ok: true, sharpness, dataUrl };
        }

        if (normalized) normalized.delete();
        return { ok: false };
    }

    _orderCorners(pts) {
        const sorted = pts.slice().sort((a, b) => a.y - b.y || a.x - b.x);
        const top = sorted.slice(0, 2).sort((a, b) => a.x - b.x);
        const bottom = sorted.slice(2, 4).sort((a, b) => a.x - b.x);
        const tl = top[0];
        const tr = top[1];
        const bl = bottom[0];
        const br = bottom[1];
        return [tl, tr, br, bl];
    }

    _warpToCard(src, corners, outW, outH) {
        const dst = new cv.Mat();
        const srcTri = cv.matFromArray(4, 1, cv.CV_32FC2, [
            corners[0].x, corners[0].y,
            corners[1].x, corners[1].y,
            corners[2].x, corners[2].y,
            corners[3].x, corners[3].y
        ]);
        const dstTri = cv.matFromArray(4, 1, cv.CV_32FC2, [
            0, 0,
            outW - 1, 0,
            outW - 1, outH - 1,
            0, outH - 1
        ]);
        const M = cv.getPerspectiveTransform(srcTri, dstTri);
        cv.warpPerspective(
            src,
            dst,
            M,
            new cv.Size(outW, outH),
            cv.INTER_LINEAR,
            cv.BORDER_CONSTANT,
            new cv.Scalar()
        );
        srcTri.delete();
        dstTri.delete();
        M.delete();
        return dst;
    }

    _computeSharpness(mat) {
        let gray = new cv.Mat();
        if (mat.channels() === 1) {
            gray = mat.clone();
        } else {
            cv.cvtColor(mat, gray, cv.COLOR_RGBA2GRAY, 0);
        }

        let lap = new cv.Mat();
        cv.Laplacian(gray, lap, cv.CV_64F);

        const mean = new cv.Mat();
        const stddev = new cv.Mat();
        cv.meanStdDev(lap, mean, stddev);
        const sigma = stddev.doubleAt(0, 0);
        const variance = sigma * sigma;

        gray.delete();
        lap.delete();
        mean.delete();
        stddev.delete();

        return variance;
    }

    // top-X% highlight stretch
    _stretchHighlights(mat, percentile = 0.95) {
        let src = mat.clone();

        let gray = new cv.Mat();
        if (src.channels() === 4) {
            cv.cvtColor(src, gray, cv.COLOR_RGBA2GRAY);
        } else {
            cv.cvtColor(src, gray, cv.COLOR_BGR2GRAY);
        }

        let srcVec = new cv.MatVector();
        srcVec.push_back(gray);
        let hist = new cv.Mat();
        let mask = new cv.Mat();
        let channels = [0];
        let histSize = [256];
        let ranges = [0, 256];

        cv.calcHist(srcVec, channels, mask, hist, histSize, ranges, false);

        const totalPixels = gray.rows * gray.cols;
        let cumulative = 0;
        let level = 255;

        for (let i = 0; i < 256; i++) {
            cumulative += hist.floatAt(i, 0);
            if (cumulative / totalPixels >= percentile) {
                level = i;
                break;
            }
        }

        let out = new cv.Mat();
        if (level > 0 && level < 255) {
            const alpha = 255.0 / level;
            const beta = 0;
            cv.convertScaleAbs(src, out, alpha, beta);
        } else {
            out = src.clone();
        }

        src.delete();
        gray.delete();
        srcVec.delete();
        hist.delete();
        mask.delete();

        return out;
    }
}
