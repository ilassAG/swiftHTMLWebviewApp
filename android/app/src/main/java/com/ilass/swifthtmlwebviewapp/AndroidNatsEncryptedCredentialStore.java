package com.ilass.swifthtmlwebviewapp;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import java.nio.charset.StandardCharsets;
import java.security.KeyStore;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

final class AndroidNatsEncryptedCredentialStore implements AndroidNatsBridge.CredentialStore {
    private static final String PREFS = "swift_html_webview_app_nats_credentials";
    private static final String KEY_ALIAS = "swift_html_webview_app_nats";
    private static final String CIPHERTEXT_KEY = "credential_ciphertext";
    private static final String IV_KEY = "credential_iv";
    private static final String METHOD_KEY = "credential_method";

    private final SharedPreferences preferences;

    AndroidNatsEncryptedCredentialStore(Context context) {
        this.preferences = context.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    @Override
    public void store(String credential, String method) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, secretKey());
        byte[] encrypted = cipher.doFinal((credential != null ? credential : "").getBytes(StandardCharsets.UTF_8));
        preferences.edit()
                .putString(CIPHERTEXT_KEY, Base64.encodeToString(encrypted, Base64.NO_WRAP))
                .putString(IV_KEY, Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP))
                .putString(METHOD_KEY, method != null ? method : "")
                .apply();
    }

    @Override
    public boolean hasCredential() {
        return preferences.contains(CIPHERTEXT_KEY) && preferences.contains(IV_KEY);
    }

    @Override
    public String loadCredential() {
        try {
            String encrypted = preferences.getString(CIPHERTEXT_KEY, "");
            String iv = preferences.getString(IV_KEY, "");
            if (encrypted == null || encrypted.isEmpty() || iv == null || iv.isEmpty()) {
                return "";
            }
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(
                    Cipher.DECRYPT_MODE,
                    secretKey(),
                    new GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP))
            );
            byte[] decoded = cipher.doFinal(Base64.decode(encrypted, Base64.NO_WRAP));
            return new String(decoded, StandardCharsets.UTF_8);
        } catch (Exception ignored) {
            return "";
        }
    }

    @Override
    public void clear() {
        preferences.edit().remove(CIPHERTEXT_KEY).remove(IV_KEY).remove(METHOD_KEY).apply();
    }

    private SecretKey secretKey() throws Exception {
        KeyStore keyStore = KeyStore.getInstance("AndroidKeyStore");
        keyStore.load(null);
        KeyStore.Entry entry = keyStore.getEntry(KEY_ALIAS, null);
        if (entry instanceof KeyStore.SecretKeyEntry) {
            return ((KeyStore.SecretKeyEntry) entry).getSecretKey();
        }

        KeyGenerator keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        keyGenerator.init(new KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT
        )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build());
        return keyGenerator.generateKey();
    }
}
