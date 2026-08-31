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

    //! onKey, not onSelect: a real screen tap also fires the select behaviour
    //! with no coordinates, so relying on onSelect would run proceed() twice
    //! per tap. Harmless here since both paths do the same thing, but
    //! onKey(KEY_ENTER) keeps every delegate off onSelect, which is the rule
    //! tools/check_input.py enforces.
    function onKey(event as WatchUi.KeyEvent) as Boolean {
        if (event.getKey() != WatchUi.KEY_ENTER) {
            return false;
        }
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
