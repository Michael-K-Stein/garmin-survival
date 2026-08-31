import Toybox.Lang;

//! State changes announce themselves here instead of reaching into whichever
//! view happens to be on screen. Exactly one listener is supported, because
//! exactly one view is ever in front of the player: it subscribes on show and
//! unsubscribes on hide.
module Events {

    enum {
        RESOURCE_COLLECTED,
        INVENTORY_CHANGED,
        ITEM_SOLD,
        CASH_CHANGED,
        WORKER_HIRED,
        MACHINE_COMPLETED,
        UPGRADE_PURCHASED,
        AREA_UNLOCKED,
        CONTRACT_DONE,
        MASTERY_GAINED,
        RICH_VEIN
    }

    var listener as Method(name as Number, value as Double) or Null = null;

    function subscribe(method as Method(name as Number, value as Double)) as Void {
        listener = method;
    }

    function unsubscribe() as Void {
        listener = null;
    }

    function emit(name as Number, value as Double) as Void {
        var target = listener;
        if (target != null) {
            target.invoke(name, value);
        }
    }
}
