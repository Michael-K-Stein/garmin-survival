import Toybox.Lang;
import Toybox.WatchUi;

//! Confirms moving camp. Everything the player built goes; the mastery they
//! earned and the legacy cut they just bought come with them, so the board
//! they land back on is the forest again but worth more per swing than it has
//! ever been. Worth one second question - it is the only destructive thing in
//! the game, and unlike wiping a save it is progress rather than the loss of
//! it.
class PrestigeDelegate extends WatchUi.ConfirmationDelegate {

    function initialize() {
        ConfirmationDelegate.initialize();
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response != WatchUi.CONFIRM_YES) {
            return true;
        }
        var game = TimberlineApp.game();
        if (game != null && game.prestige()) {
            Haptics.confirm();
            var board = new GameView();
            WatchUi.switchToView(board, new GameDelegate(board), WatchUi.SLIDE_DOWN);
        } else {
            Haptics.deny();
        }
        return true;
    }
}
