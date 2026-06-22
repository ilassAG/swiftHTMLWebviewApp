package com.ilass.swifthtmlwebviewapp;

import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteException;
import android.util.Base64;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;

final class AndroidNativeSQLiteBridge {
    private final Context context;

    AndroidNativeSQLiteBridge(Context context) {
        this.context = context.getApplicationContext();
    }

    JSONObject execute(JSONObject request) throws JSONException {
        File dbFile;
        try {
            dbFile = databaseFile(request);
        } catch (SQLiteException error) {
            return BridgeResponse.error(request, "sqliteExecute", error.getMessage());
        }
        String sql = request.optString("sql", "").trim();
        if (sql.isEmpty()) {
            return BridgeResponse.error(request, "sqliteExecute", "SQL must not be empty.");
        }
        try {
            SQLiteDatabase database = SQLiteDatabase.openOrCreateDatabase(dbFile, null);
            try {
                JSONArray rows = new JSONArray();
                int changes = 0;
                long lastInsertRowId = 0L;
                if (isQuery(sql)) {
                    try (Cursor cursor = database.rawQuery(sql, bindArgs(request.optJSONArray("args")))) {
                        while (cursor.moveToNext()) {
                            rows.put(row(cursor));
                        }
                    }
                } else {
                    database.execSQL(sql, bindObjects(request.optJSONArray("args")));
                    changes = changedRows(database);
                    lastInsertRowId = lastInsertRowId(database);
                }
                JSONObject response = BridgeResponse.base(request, "sqliteExecute");
                response.put("success", true);
                response.put("database", dbFile.getName());
                response.put("rows", rows);
                response.put("changes", changes);
                response.put("lastInsertRowId", lastInsertRowId);
                return response;
            } finally {
                database.close();
            }
        } catch (SQLiteException error) {
            return BridgeResponse.error(request, "sqliteExecute", error.getMessage());
        }
    }

    JSONObject deleteDatabase(JSONObject request) throws JSONException {
        try {
            File dbFile = databaseFile(request);
            if (dbFile.exists() && !dbFile.delete()) {
                return BridgeResponse.error(request, "sqliteDeleteDatabase", "Unable to delete database.");
            }
            JSONObject response = BridgeResponse.base(request, "sqliteDeleteDatabase");
            response.put("success", true);
            response.put("database", dbFile.getName());
            return response;
        } catch (SQLiteException error) {
            return BridgeResponse.error(request, "sqliteDeleteDatabase", error.getMessage());
        }
    }

    private File databaseFile(JSONObject request) {
        String raw = request.optString("database", request.optString("name", "default")).trim();
        String name = raw.isEmpty() ? "default.sqlite" : raw;
        if (name.contains("/") || name.contains("\\") || name.indexOf('\0') >= 0) {
            throw new SQLiteException("Database name is invalid.");
        }
        if (!name.endsWith(".sqlite") && !name.endsWith(".db")) {
            name += ".sqlite";
        }
        File base = new File(context.getFilesDir(), "NativeBridgeSQLite");
        if (!base.exists() && !base.mkdirs()) {
            throw new SQLiteException("Unable to create SQLite directory.");
        }
        return new File(base, name);
    }

    private boolean isQuery(String sql) {
        String normalized = sql.trim().toLowerCase();
        return normalized.startsWith("select") || normalized.startsWith("pragma") || normalized.startsWith("with");
    }

    private String[] bindArgs(JSONArray args) {
        if (args == null || args.length() == 0) {
            return new String[0];
        }
        String[] result = new String[args.length()];
        for (int i = 0; i < args.length(); i++) {
            Object value = args.opt(i);
            result[i] = value == null || value == JSONObject.NULL ? null : String.valueOf(value);
        }
        return result;
    }

    private Object[] bindObjects(JSONArray args) {
        if (args == null || args.length() == 0) {
            return new Object[0];
        }
        Object[] result = new Object[args.length()];
        for (int i = 0; i < args.length(); i++) {
            Object value = args.opt(i);
            result[i] = value == JSONObject.NULL ? null : value;
        }
        return result;
    }

    private JSONObject row(Cursor cursor) throws JSONException {
        JSONObject row = new JSONObject();
        for (int index = 0; index < cursor.getColumnCount(); index++) {
            String name = cursor.getColumnName(index);
            switch (cursor.getType(index)) {
                case Cursor.FIELD_TYPE_INTEGER:
                    row.put(name, cursor.getLong(index));
                    break;
                case Cursor.FIELD_TYPE_FLOAT:
                    row.put(name, cursor.getDouble(index));
                    break;
                case Cursor.FIELD_TYPE_STRING:
                    row.put(name, cursor.getString(index));
                    break;
                case Cursor.FIELD_TYPE_BLOB:
                    row.put(name, Base64.encodeToString(cursor.getBlob(index), Base64.NO_WRAP));
                    break;
                default:
                    row.put(name, JSONObject.NULL);
                    break;
            }
        }
        return row;
    }

    private int changedRows(SQLiteDatabase database) {
        try (Cursor cursor = database.rawQuery("SELECT changes()", null)) {
            return cursor.moveToFirst() ? cursor.getInt(0) : 0;
        }
    }

    private long lastInsertRowId(SQLiteDatabase database) {
        try (Cursor cursor = database.rawQuery("SELECT last_insert_rowid()", null)) {
            return cursor.moveToFirst() ? cursor.getLong(0) : 0L;
        }
    }
}
