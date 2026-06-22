package com.ilass.swifthtmlwebviewapp;

final class AndroidBridgeShimBuilder {
    private AndroidBridgeShimBuilder() {
    }

    static String bridgeShimScript() {
        return "(function(){"
                + "window.webkit=window.webkit||{};"
                + "window.webkit.messageHandlers=window.webkit.messageHandlers||{};"
                + "window.webkit.messageHandlers.swiftBridge={postMessage:function(message){"
                + "window.AndroidNativeBridge.postMessage(JSON.stringify(message||{}));"
                + "}};"
                + "})();";
    }

    static String idleActivityShimScript() {
        return "(function(){"
                + "if(window.__swiftHTMLIdleShimInstalled){return;}"
                + "window.__swiftHTMLIdleShimInstalled=true;"
                + "function notify(){try{window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.swiftBridge.postMessage({action:'idleActivity',source:'web'});}catch(e){}}"
                + "['pointerdown','touchstart','mousedown','keydown','scroll'].forEach(function(name){document.addEventListener(name,notify,{capture:true,passive:true});});"
                + "})();";
    }
}
