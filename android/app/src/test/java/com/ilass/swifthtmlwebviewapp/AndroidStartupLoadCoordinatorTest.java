package com.ilass.swifthtmlwebviewapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.util.ArrayList;
import java.util.Arrays;

import org.junit.Test;

public class AndroidStartupLoadCoordinatorTest {
    @Test
    public void startLoadsFirstConfiguredCandidateAndSchedulesTimeoutForRemote() {
        AndroidStartupLoadCoordinator coordinator = coordinator();

        AndroidStartupLoadCoordinator.Command command = coordinator.start(
                candidates("https://primary.invalid/app/", "https://backup.invalid/app/"),
                true
        );

        assertEquals(AndroidStartupLoadCoordinator.Command.Kind.LOAD_URL, command.kind);
        assertEquals("https://primary.invalid/app/", command.url);
        assertTrue(command.scheduleTimeout);
    }

    @Test
    public void localCandidateDoesNotScheduleTimeout() {
        AndroidStartupLoadCoordinator.Command command = coordinator().start(
                candidates("file:///android_asset/index.html"),
                true
        );

        assertEquals(AndroidStartupLoadCoordinator.Command.Kind.LOAD_URL, command.kind);
        assertEquals("file:///android_asset/index.html", command.url);
        assertFalse(command.scheduleTimeout);
    }

    @Test
    public void mainFrameFailureAdvancesToNextHighAvailabilityCandidate() {
        AndroidStartupLoadCoordinator coordinator = coordinator();
        coordinator.start(candidates("https://primary.invalid/app/", "https://backup.invalid/app/"), true);

        AndroidStartupLoadCoordinator.Command command = coordinator.mainFrameFailed("network failed");

        assertEquals(AndroidStartupLoadCoordinator.Command.Kind.LOAD_URL, command.kind);
        assertEquals("https://backup.invalid/app/", command.url);
        assertTrue(command.scheduleTimeout);
    }

    @Test
    public void timeoutAdvancesToNextHighAvailabilityCandidate() {
        AndroidStartupLoadCoordinator coordinator = coordinator();
        coordinator.start(candidates("https://primary.invalid/app/", "file:///android_asset/index.html"), true);

        AndroidStartupLoadCoordinator.Command command = coordinator.timeout();

        assertEquals(AndroidStartupLoadCoordinator.Command.Kind.LOAD_URL, command.kind);
        assertEquals("file:///android_asset/index.html", command.url);
        assertFalse(command.scheduleTimeout);
    }

    @Test
    public void lastFailureShowsRecoveryWithOriginalCandidateList() {
        AndroidStartupLoadCoordinator coordinator = coordinator();
        coordinator.start(candidates("https://primary.invalid/app/", "https://backup.invalid/app/"), true);
        coordinator.mainFrameFailed("first failed");

        AndroidStartupLoadCoordinator.Command command = coordinator.mainFrameFailed("backup failed");

        assertEquals(AndroidStartupLoadCoordinator.Command.Kind.SHOW_RECOVERY, command.kind);
        assertEquals("backup failed", command.reason);
        assertEquals(
                Arrays.asList("https://primary.invalid/app/", "https://backup.invalid/app/"),
                command.candidates
        );

        assertEquals(AndroidStartupLoadCoordinator.Command.Kind.NONE, coordinator.timeout().kind);
    }

    @Test
    public void highAvailabilityDisabledShowsRecoveryAfterFirstFailure() {
        AndroidStartupLoadCoordinator coordinator = coordinator();
        coordinator.start(candidates("https://primary.invalid/app/", "https://backup.invalid/app/"), false);

        AndroidStartupLoadCoordinator.Command command = coordinator.mainFrameFailed("primary failed");

        assertEquals(AndroidStartupLoadCoordinator.Command.Kind.SHOW_RECOVERY, command.kind);
        assertEquals("primary failed", command.reason);
        assertEquals(
                Arrays.asList("https://primary.invalid/app/", "https://backup.invalid/app/"),
                command.candidates
        );
    }

    @Test
    public void reloadResetsCandidateIndexAndRecoveryState() {
        AndroidStartupLoadCoordinator coordinator = coordinator();
        coordinator.start(candidates("https://primary.invalid/app/", "https://backup.invalid/app/"), true);
        coordinator.mainFrameFailed("first failed");
        coordinator.mainFrameFailed("backup failed");

        AndroidStartupLoadCoordinator.Command command = coordinator.start(
                candidates("https://new-primary.invalid/app/", "https://new-backup.invalid/app/"),
                true
        );

        assertEquals(AndroidStartupLoadCoordinator.Command.Kind.LOAD_URL, command.kind);
        assertEquals("https://new-primary.invalid/app/", command.url);
        assertEquals(
                AndroidStartupLoadCoordinator.Command.Kind.LOAD_URL,
                coordinator.mainFrameFailed("new primary failed").kind
        );
    }

    @Test
    public void emptyCandidatesShowsRecovery() {
        AndroidStartupLoadCoordinator.Command command = coordinator().start(new ArrayList<>(), true);

        assertEquals(AndroidStartupLoadCoordinator.Command.Kind.SHOW_RECOVERY, command.kind);
        assertEquals("Keine konfigurierte Server-URL verfuegbar.", command.reason);
        assertTrue(command.candidates.isEmpty());
    }

    private AndroidStartupLoadCoordinator coordinator() {
        return new AndroidStartupLoadCoordinator(url -> url != null && url.startsWith("file:///"));
    }

    private ArrayList<String> candidates(String... urls) {
        return new ArrayList<>(Arrays.asList(urls));
    }
}
