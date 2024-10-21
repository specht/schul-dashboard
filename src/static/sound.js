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
        if (is_safari) {
            if (!window.sound_initialized_by_user_interaction) {
                $('body').append(`<span class='safari_volume_indicator bg-grass-600'><i class='bi bi-volume-up text-white'></i></span>`);
                $('.safari_volume_indicator').click(function() {
                    window.sound_initialized_by_user_interaction = true;
                    window.sound = new SoundPlayer();
                    $('.safari_volume_indicator').fadeOut();
                });
            }
        }
    }
}
