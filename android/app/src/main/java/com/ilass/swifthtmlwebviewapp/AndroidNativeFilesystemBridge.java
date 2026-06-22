package com.ilass.swifthtmlwebviewapp;

import android.content.Context;
import android.util.Base64;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;

final class AndroidNativeFilesystemBridge {
    private final Context context;

    AndroidNativeFilesystemBridge(Context context) {
        this.context = context.getApplicationContext();
    }

    JSONObject write(JSONObject request) throws JSONException {
        try {
            File target = resolve(request, false);
            File parent = target.getParentFile();
            if (parent != null && !parent.exists() && !parent.mkdirs()) {
                throw new IOException("Unable to create parent directory.");
            }
            byte[] data = data(request);
            try (FileOutputStream output = new FileOutputStream(target, false)) {
                output.write(data);
            }
            JSONObject response = success(request, "filesystemWrite", target);
            response.put("bytes", data.length);
            return response;
        } catch (IOException error) {
            return BridgeResponse.error(request, "filesystemWrite", error.getMessage());
        }
    }

    JSONObject read(JSONObject request) throws JSONException {
        try {
            File target = resolve(request, false);
            byte[] data = readAll(target);
            JSONObject response = success(request, "filesystemRead", target);
            response.put("bytes", data.length);
            if ("base64".equals(encoding(request))) {
                response.put("data", Base64.encodeToString(data, Base64.NO_WRAP));
                response.put("encoding", "base64");
            } else {
                response.put("data", new String(data, StandardCharsets.UTF_8));
                response.put("encoding", "utf8");
            }
            return response;
        } catch (IOException error) {
            return BridgeResponse.error(request, "filesystemRead", error.getMessage());
        }
    }

    JSONObject list(JSONObject request) throws JSONException {
        try {
            File target = resolve(request, true);
            File[] files = target.listFiles();
            JSONArray entries = new JSONArray();
            if (files != null) {
                for (File file : files) {
                    JSONObject item = new JSONObject();
                    item.put("name", file.getName());
                    item.put("path", relativePath(request, file));
                    item.put("isDirectory", file.isDirectory());
                    item.put("size", file.isFile() ? file.length() : 0);
                    entries.put(item);
                }
            }
            JSONObject response = success(request, "filesystemList", target);
            response.put("entries", entries);
            return response;
        } catch (IOException error) {
            return BridgeResponse.error(request, "filesystemList", error.getMessage());
        }
    }

    JSONObject delete(JSONObject request) throws JSONException {
        try {
            File target = resolve(request, false);
            if (target.exists()) {
                deleteRecursively(target);
            }
            return success(request, "filesystemDelete", target);
        } catch (IOException error) {
            return BridgeResponse.error(request, "filesystemDelete", error.getMessage());
        }
    }

    private byte[] data(JSONObject request) throws JSONException {
        String raw = request.optString("data", "");
        if ("base64".equals(encoding(request))) {
            return Base64.decode(raw, Base64.DEFAULT);
        }
        return raw.getBytes(StandardCharsets.UTF_8);
    }

    private byte[] readAll(File target) throws IOException {
        try (FileInputStream input = new FileInputStream(target)) {
            byte[] data = new byte[(int) target.length()];
            int offset = 0;
            while (offset < data.length) {
                int read = input.read(data, offset, data.length - offset);
                if (read < 0) {
                    break;
                }
                offset += read;
            }
            return data;
        }
    }

    private File resolve(JSONObject request, boolean allowEmptyPath) throws IOException {
        File base = baseDirectory(directory(request));
        String path = request.optString("path", "").trim();
        if (path.isEmpty() && allowEmptyPath) {
            path = ".";
        }
        if (path.isEmpty() || path.indexOf('\0') >= 0) {
            throw new IOException("The path is invalid.");
        }
        File target = new File(base, path).getCanonicalFile();
        String basePath = base.getCanonicalPath();
        String targetPath = target.getCanonicalPath();
        if (!targetPath.equals(basePath) && !targetPath.startsWith(basePath + File.separator)) {
            throw new IOException("The path escapes the app-private storage directory.");
        }
        return target;
    }

    private File baseDirectory(String directory) throws IOException {
        File base;
        if ("cache".equals(directory)) {
            base = new File(context.getCacheDir(), "NativeBridgeFiles");
        } else if ("temporary".equals(directory)) {
            base = new File(context.getCacheDir(), "NativeBridgeTemporary");
        } else {
            base = new File(context.getFilesDir(), "NativeBridgeFiles");
        }
        if (!base.exists() && !base.mkdirs()) {
            throw new IOException("Unable to create storage directory.");
        }
        return base.getCanonicalFile();
    }

    private void deleteRecursively(File file) throws IOException {
        if (file.isDirectory()) {
            File[] children = file.listFiles();
            if (children != null) {
                for (File child : children) {
                    deleteRecursively(child);
                }
            }
        }
        if (!file.delete() && file.exists()) {
            throw new IOException("Unable to delete file.");
        }
    }

    private JSONObject success(JSONObject request, String action, File target) throws JSONException, IOException {
        JSONObject response = BridgeResponse.base(request, action);
        response.put("success", true);
        response.put("directory", directory(request));
        response.put("path", relativePath(request, target));
        return response;
    }

    private String relativePath(JSONObject request, File target) throws IOException {
        String basePath = baseDirectory(directory(request)).getCanonicalPath();
        String targetPath = target.getCanonicalPath();
        if (targetPath.equals(basePath)) {
            return "";
        }
        return targetPath.substring(basePath.length() + 1);
    }

    private String directory(JSONObject request) {
        String value = request.optString("directory", "data").trim().toLowerCase();
        if ("cache".equals(value) || "temporary".equals(value)) {
            return value;
        }
        return "data";
    }

    private String encoding(JSONObject request) {
        return "base64".equalsIgnoreCase(request.optString("encoding", "utf8")) ? "base64" : "utf8";
    }
}
