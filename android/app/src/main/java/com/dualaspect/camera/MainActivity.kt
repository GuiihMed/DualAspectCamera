package com.dualaspect.camera

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.util.Base64
import android.view.View
import android.view.WindowManager
import android.webkit.JavascriptInterface
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream

class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView
    private var pendingPermissionRequest: PermissionRequest? = null

    companion object {
        private const val PERMISSIONS_REQUEST_CODE = 101
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        supportActionBar?.hide()
        setupImmersiveMode()

        webView = WebView(this)
        setContentView(webView)

        setupWebView()

        if (hasRequiredPermissions()) {
            loadApp()
        } else {
            requestPermissions()
        }
    }

    override fun onResume() {
        super.onResume()
        setupImmersiveMode()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            setupImmersiveMode()
        }
    }

    private fun setupImmersiveMode() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        controller.hide(WindowInsetsCompat.Type.systemBars())
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }

    private fun setupWebView() {
        webView.apply {
            overScrollMode = View.OVER_SCROLL_NEVER
            isVerticalScrollBarEnabled = false
            isHorizontalScrollBarEnabled = false

            settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                mediaPlaybackRequiresUserGesture = false
                allowFileAccess = true
                databaseEnabled = true
                mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                cacheMode = WebSettings.LOAD_DEFAULT
                useWideViewPort = true
                loadWithOverviewMode = true
                setSupportZoom(false)
            }

            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean {
                    return false
                }
            }

            webChromeClient = object : WebChromeClient() {
                override fun onPermissionRequest(request: PermissionRequest?) {
                    runOnUiThread {
                        if (hasRequiredPermissions()) {
                            request?.grant(request.resources)
                        } else {
                            pendingPermissionRequest = request
                            requestPermissions()
                        }
                    }
                }

                override fun onPermissionRequestCanceled(request: PermissionRequest?) {
                    super.onPermissionRequestCanceled(request)
                    if (pendingPermissionRequest == request) {
                        pendingPermissionRequest = null
                    }
                }
            }

            addJavascriptInterface(AndroidBridge(this@MainActivity), "AndroidBridge")
        }
    }

    private fun loadApp() {
        webView.loadUrl("https://guiihmed.github.io/DualAspectCamera/")
    }

    private fun hasRequiredPermissions(): Boolean {
        val permissions = arrayOf(
            Manifest.permission.CAMERA,
            Manifest.permission.RECORD_AUDIO
        )
        return permissions.all {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestPermissions() {
        val permissions = mutableListOf(
            Manifest.permission.CAMERA,
            Manifest.permission.RECORD_AUDIO
        )
        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P) {
            permissions.add(Manifest.permission.WRITE_EXTERNAL_STORAGE)
        }
        ActivityCompat.requestPermissions(this, permissions.toTypedArray(), PERMISSIONS_REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSIONS_REQUEST_CODE) {
            val allGranted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            if (allGranted) {
                pendingPermissionRequest?.let { req ->
                    req.grant(req.resources)
                    pendingPermissionRequest = null
                }
                loadApp()
            } else {
                Toast.makeText(this, "Permissão de câmera e microfone necessária.", Toast.LENGTH_LONG).show()
                loadApp()
            }
        }
    }

    fun saveMediaToGallery(base64Data: String, fileName: String, isVideo: Boolean) {
        try {
            val cleanData = if (base64Data.contains(",")) {
                base64Data.substringAfter(",")
            } else {
                base64Data
            }
            val bytes = Base64.decode(cleanData, Base64.DEFAULT)

            val mimeType = if (isVideo) {
                if (fileName.endsWith(".mp4")) "video/mp4" else "video/webm"
            } else {
                "image/jpeg"
            }

            var outputStream: OutputStream? = null

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val contentValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                    put(
                        MediaStore.MediaColumns.RELATIVE_PATH,
                        if (isVideo) Environment.DIRECTORY_MOVIES + "/DualCam" else Environment.DIRECTORY_DCIM + "/DualCam"
                    )
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }

                val collection = if (isVideo) {
                    MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                } else {
                    MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                }

                val itemUri = contentResolver.insert(collection, contentValues)
                if (itemUri != null) {
                    outputStream = contentResolver.openOutputStream(itemUri)
                    outputStream?.write(bytes)
                    outputStream?.flush()

                    contentValues.clear()
                    contentValues.put(MediaStore.MediaColumns.IS_PENDING, 0)
                    contentResolver.update(itemUri, contentValues, null, null)
                }
            } else {
                val dir = File(
                    Environment.getExternalStoragePublicDirectory(
                        if (isVideo) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_DCIM
                    ),
                    "DualCam"
                )
                if (!dir.exists()) dir.mkdirs()
                val file = File(dir, fileName)
                outputStream = FileOutputStream(file)
                outputStream.write(bytes)
                outputStream.flush()

                sendBroadcast(Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE, Uri.fromFile(file)))
            }

            outputStream?.close()

            runOnUiThread {
                Toast.makeText(
                    this,
                    if (isVideo) "Vídeo salvo na Galeria!" else "Foto salva na Galeria!",
                    Toast.LENGTH_SHORT
                ).show()
            }
        } catch (e: Exception) {
            e.printStackTrace()
            runOnUiThread {
                Toast.makeText(this, "Erro ao salvar mídia: ${e.localizedMessage}", Toast.LENGTH_SHORT).show()
            }
        }
    }

    fun openNativeGallery() {
        try {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, "image/*")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
        } catch (e: Exception) {
            try {
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    type = "image/*"
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(intent)
            } catch (ex: Exception) {
                runOnUiThread {
                    Toast.makeText(this, "Não foi possível abrir a galeria.", Toast.LENGTH_SHORT).show()
                }
            }
        }
    }

    class AndroidBridge(private val activity: MainActivity) {
        @JavascriptInterface
        fun saveImage(base64Data: String, fileName: String) {
            activity.saveMediaToGallery(base64Data, fileName, isVideo = false)
        }

        @JavascriptInterface
        fun saveVideo(base64Data: String, fileName: String) {
            activity.saveMediaToGallery(base64Data, fileName, isVideo = true)
        }

        @JavascriptInterface
        fun openGallery() {
            activity.openNativeGallery()
        }

        @JavascriptInterface
        fun isAndroid(): Boolean = true
    }
}
