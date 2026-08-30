import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! Timberline - an idle automation game for the Venu 2 family.
//!
//! Chop a tree yourself, sell the wood, then spend the money on people and
//! machinery until the forest runs without you. Every purchase is meant to
//! delete a task the player was doing by hand a minute earlier.
class TimberlineApp extends Application.AppBase {

    private var mState as GameState or Null = null;

    //! Convenience accessor so views do not have to cast the app every time.
    static function game() as GameState or Null {
        return (Application.getApp() as TimberlineApp).state();
    }

    function initialize() {
        AppBase.initialize();
    }

    function state() as GameState or Null {
        return mState;
    }

    function onStart(startState as Dictionary?) as Void {
        mState = new GameState();
        (mState as GameState).load();
    }

    function onStop(stopState as Dictionary?) as Void {
        if (mState != null) {
            (mState as GameState).save();
        }
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var state = mState as GameState;
        if (state.hasOffline()) {
            var welcome = new WelcomeView();
            return [welcome, new WelcomeDelegate(welcome)];
        }
        var view = new GameView();
        return [view, new GameDelegate(view)];
    }
}
