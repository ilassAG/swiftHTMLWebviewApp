# Screenstream Viewer

Small local Go viewer for the native `screenStreamStart` bridge action.

Run:

```sh
go run . -addr :18090
```

Open:

```text
http://<mac-ip>:18090/
```

Set the wrapper demo page target to:

```text
ws://<mac-ip>:18090/screen
```

The viewer accepts WebSocket text metadata and JPEG binary frames. It shows the
latest frame, total bytes, bytes per second, average FPS, and last-frame size.
