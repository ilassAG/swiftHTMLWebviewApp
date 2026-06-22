package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import java.util.ArrayList;
import java.util.Arrays;

import org.junit.Test;

public class StartupUrlResolverTest {
    private static final String LOCAL_URL = "file:///android_asset/index.html";

    @Test
    public void resolvesLocalAliasesToBundledAssetUrl() {
        assertEquals(LOCAL_URL, StartupUrlResolver.resolveStartUrl(" local ", "https://example.invalid/mobile/", LOCAL_URL));
        assertEquals(LOCAL_URL, StartupUrlResolver.resolveStartUrl("", "local", LOCAL_URL));
        assertEquals(LOCAL_URL, StartupUrlResolver.resolveStartUrl("file:///android_asset/custom.html", "https://example.invalid/mobile/", LOCAL_URL));
    }

    @Test
    public void returnsRemoteUrlWhenConfigured() {
        assertEquals(
                "https://example.invalid/mobile/",
                StartupUrlResolver.resolveStartUrl(" https://example.invalid/mobile/ ", "local", LOCAL_URL)
        );
    }

    @Test
    public void candidatesDeduplicateRemoteAndLocalUrls() {
        ArrayList<String> candidates = StartupUrlResolver.candidates(
                "https://example.invalid/mobile/",
                true,
                "https://example.invalid/mobile",
                " local ",
                "about:local",
                LOCAL_URL
        );

        assertEquals(Arrays.asList("https://example.invalid/mobile/", LOCAL_URL, "about:local"), candidates);
    }

    @Test
    public void candidatesIgnoreHighAvailabilityUrlsWhenDisabled() {
        ArrayList<String> candidates = StartupUrlResolver.candidates(
                "https://primary.invalid/mobile/",
                false,
                "https://backup.invalid/mobile/",
                LOCAL_URL,
                "",
                LOCAL_URL
        );

        assertEquals(Arrays.asList("https://primary.invalid/mobile/"), candidates);
    }

    @Test
    public void candidatesFallBackToLocalWhenNoValuesExist() {
        ArrayList<String> candidates = StartupUrlResolver.candidates("", true, "", " ", null, LOCAL_URL);

        assertEquals(1, candidates.size());
        assertTrue(candidates.contains(LOCAL_URL));
    }
}
