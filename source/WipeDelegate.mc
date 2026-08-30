import Toybox.Lang;
import Toybox.WatchUi;

//! Confirms erasing the save. The board is rebuilt from scratch underneath,
//! so the player lands back in the forest with nothing, which is exactly what
//! they asked for.
class WipeDelegate extends WatchUi.ConfirmationDelegate {

    function initialize() {
        ConfirmationDelegate.initialize();
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            var game = TimberlineApp.game();
            if (game != null) {
                game.wipe();
            }
            Haptics.confirm();
            var board = new GameView();
            WatchUi.switchToView(board, new GameDelegate(board), WatchUi.SLIDE_DOWN);
        }
        return true;
    }
}
