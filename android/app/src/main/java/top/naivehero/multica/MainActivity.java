package top.naivehero.multica;

import android.app.DownloadManager;
import android.content.Context;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.webkit.CookieManager;
import android.webkit.URLUtil;
import android.widget.Toast;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Capacitor's WebView has no download handling out of the box: any
        // attachment-download navigation (<a download>, Content-Disposition:
        // attachment — this is exactly how issue/comment attachments trigger
        // a save) is silently dropped without a DownloadListener. Hand it off
        // to Android's system DownloadManager instead.
        //
        // Cookie is attached because the web client sends session cookies
        // (credentials: "include") alongside its Authorization header; a
        // DownloadManager-issued request can't carry that header, but the
        // cookie alone is enough when the server accepts cookie auth (and is
        // harmless if the download URL is already a self-authenticating
        // signed link).
        bridge.getWebView().setDownloadListener((url, userAgent, contentDisposition, mimeType, contentLength) -> {
            try {
                DownloadManager.Request request = new DownloadManager.Request(Uri.parse(url));
                String cookie = CookieManager.getInstance().getCookie(url);
                if (cookie != null) {
                    request.addRequestHeader("Cookie", cookie);
                }
                request.addRequestHeader("User-Agent", userAgent);
                request.setMimeType(mimeType);
                request.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
                request.setDestinationInExternalPublicDir(
                    Environment.DIRECTORY_DOWNLOADS,
                    URLUtil.guessFileName(url, contentDisposition, mimeType)
                );

                DownloadManager downloadManager = (DownloadManager) getSystemService(Context.DOWNLOAD_SERVICE);
                if (downloadManager != null) {
                    downloadManager.enqueue(request);
                    Toast.makeText(getApplicationContext(), "正在下载附件...", Toast.LENGTH_SHORT).show();
                }
            } catch (Exception e) {
                Toast.makeText(getApplicationContext(), "下载失败: " + e.getMessage(), Toast.LENGTH_LONG).show();
            }
        });
    }
}
