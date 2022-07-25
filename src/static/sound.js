class SoundPlayer {
    constructor() {
        this.howl = new Howl({
            src: ['/sound-sprite.mp3'],
            sprite: {
                scan: [0, 1500],
                success: [2000, 1500],
                snapshot: [4000, 1500],
                error: [6000, 1500]
            }
        });
    }

    play(which) {
        this.howl.play(which);
    }
}
