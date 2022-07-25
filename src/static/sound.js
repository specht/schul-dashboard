class SoundPlayer {
    constructor() {
        this.sprite = new Audio('/sound-sprite.mp3');
        this.sounds = {
            scan: {start: 0.0, duration: 1.5},
            success: {start: 2.0, duration: 1.5},
            snapshot: {start: 4.0, duration: 1.5},
            error: {start: 6.0, duration: 1.5},
        };
        this.stopTime = 0.0;
        let self = this;
        this.sprite.addEventListener('timeupdate', function(data) {
            let t = self.sprite.currentTime;
            if (t >= self.stopTime) {
                self.sprite.pause();
            }
        }, false);
    }

    play(which) {
        if (!(which in this.sounds)) return;
        this.sprite.pause();
        this.stopTime = this.sounds[which].start + this.sounds[which].duration;
        this.sprite.currentTime = this.sounds[which].start;
        this.sprite.play();
    }
}
