package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class AndroidBridgeShimBuilderTest {
    @Test
    public void bridgeShimInstallsIosCompatiblePostMessageFacade() {
        String script = AndroidBridgeShimBuilder.bridgeShimScript();

        assertTrue(script.contains("window.webkit=window.webkit||{}"));
        assertTrue(script.contains("window.webkit.messageHandlers=window.webkit.messageHandlers||{}"));
        assertTrue(script.contains("window.webkit.messageHandlers.swiftBridge={postMessage:function(message){"));
        assertTrue(script.contains("window.AndroidNativeBridge.postMessage(JSON.stringify(message||{}));"));
    }

    @Test
    public void idleActivityShimInstallsOnceAndPostsIdleActivity() {
        String script = AndroidBridgeShimBuilder.idleActivityShimScript();

        assertTrue(script.contains("if(window.__swiftHTMLIdleShimInstalled){return;}"));
        assertTrue(script.contains("window.__swiftHTMLIdleShimInstalled=true;"));
        assertTrue(script.contains("postMessage({action:'idleActivity',source:'web'})"));
        assertTrue(script.contains("document.addEventListener(name,notify,{capture:true,passive:true})"));
    }
}
