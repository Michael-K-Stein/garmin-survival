import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! What the operation got through while the watch was in a pocket. One tap
//! on CLAIM banks the lot and drops the player back on the board.
class WelcomeView extends WatchUi.View {

    private var mGame as GameState or Null = null;

    private var mBtnX as Number = 0;
    private var mBtnY as Number = 0;
    private var mBtnW as Number = 0;
    private var mBtnH as Number = 0;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
        Layout.measure(dc);
        mBtnH = Layout.s(62);
        mBtnY = Layout.s(288);
        var row = Layout.fitRow(mBtnY, mBtnH, Layout.s(16));
        mBtnX = row[0];
        mBtnW = row[1];
    }

    function onShow() as Void {
        mGame = TimberlineApp.game();
    }

    function claim() as Void {
        var game = mGame;
        if (game != null) {
            game.claimOffline();
            game.save();
        }
        Haptics.confirm();
    }

    function onUpdate(dc as Dc) as Void {
        Layout.measure(dc);
        dc.setColor(Theme.TEXT, Theme.BG);
        dc.clear();

        var game = mGame;
        if (game == null) {
            return;
        }

        dc.setColor(Theme.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, Layout.s(58), Graphics.FONT_XTINY, "WELCOME BACK",
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(Layout.cx, Layout.s(84), Graphics.FONT_XTINY,
            Fmt.duration(game.offlineSecs) + " away", Graphics.TEXT_JUSTIFY_CENTER);

        Theme.bigCash(dc, Layout.cx, Layout.s(122), game.offlineCash, Theme.CASH,
            Graphics.FONT_NUMBER_MEDIUM);

        dc.setColor(Theme.WOOD, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, Layout.s(198), Graphics.FONT_SMALL,
            "+" + game.offlineUnits.toNumber().toString() + " in the yards",
            Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Theme.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, Layout.s(232), Graphics.FONT_XTINY,
            "crew works at 60% while away", Graphics.TEXT_JUSTIFY_CENTER);

        Theme.button(dc, mBtnX, mBtnY, mBtnW, mBtnH, "CLAIM", Theme.CASH_DIM,
            Theme.TEXT);
    }
}
