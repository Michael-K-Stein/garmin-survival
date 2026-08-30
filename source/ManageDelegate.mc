import Toybox.Lang;
import Toybox.WatchUi;

//! Input for the management pages: tap a slab to buy it, swipe sideways to
//! change category, swipe down or press back to return to the board.
class ManageDelegate extends WatchUi.BehaviorDelegate {

    private var mView as ManageView;

    function initialize(view as ManageView) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onTap(event as WatchUi.ClickEvent) as Boolean {
        var coords = event.getCoordinates();
        mView.onTapAt(coords[0], coords[1]);
        return true;
    }

    function onSwipe(event as WatchUi.SwipeEvent) as Boolean {
        var direction = event.getDirection();
        if (direction == WatchUi.SWIPE_LEFT) {
            mView.turnPage(1);
            return true;
        }
        if (direction == WatchUi.SWIPE_RIGHT) {
            mView.turnPage(-1);
            return true;
        }
        if (direction == WatchUi.SWIPE_DOWN) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return true;
        }
        return false;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
