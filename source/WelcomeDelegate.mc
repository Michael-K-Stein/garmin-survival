import Toybox.Lang;
import Toybox.WatchUi;

//! The welcome card takes one input and one only: claim it and play. Any tap
//! or key counts, because a card with a single outcome should never make the
//! player aim.
class WelcomeDelegate extends WatchUi.BehaviorDelegate {

    private var mView as WelcomeView;

    function initialize(view as WelcomeView) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onTap(event as WatchUi.ClickEvent) as Boolean {
        proceed();
        return true;
    }

    function onSelect() as Boolean {
        proceed();
        return true;
    }

    function onBack() as Boolean {
        proceed();
        return true;
    }

    private function proceed() as Void {
        mView.claim();
        var board = new GameView();
        WatchUi.switchToView(board, new GameDelegate(board), WatchUi.SLIDE_UP);
    }
}
