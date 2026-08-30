import Toybox.Lang;

//! Vibration feedback, guarded twice: the Attention module is optional on
//! some products, and vibrate() is optional within it.
module Haptics {

    function pulse(strength as Number, durationMs as Number) as Void {
        var state = TimberlineApp.game();
        if (state == null || !state.haptics) {
            return;
        }
        if (!(Toybox has :Attention)) {
            return;
        }
        if (!(Toybox.Attention has :vibrate)) {
            return;
        }
        Toybox.Attention.vibrate([
            new Toybox.Attention.VibeProfile(strength, durationMs)
        ] as Array<Toybox.Attention.VibeProfile>);
    }

    //! Acknowledging a tap on the board.
    function tap() as Void {
        pulse(20, 30);
    }

    //! A sale or a purchase landing.
    function confirm() as Void {
        pulse(45, 60);
    }

    //! Something refused - usually not enough cash.
    function deny() as Void {
        pulse(15, 120);
    }
}
