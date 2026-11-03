package blog.parshwa.rysteria

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.browser.customtabs.CustomTabsIntent

/**
 * The game in a WebView, nothing else. The page is the site itself, so it is always
 * the version the servers speak.
 *
 * Signing in with Google, Apple or Discord can't happen inside a WebView (Google
 * refuses it), so those pages open in a Custom Tab. The master (api-game...) is told
 * `?app=1` and, when the sign in is done, sends the browser to
 * rysteria://oauth#oauth_code=...; the manifest sends that back here and the code
 * is handed to the page, which exchanges it exactly like on the website.
 */
class MainActivity : AppCompatActivity() {
    private lateinit var web: WebView

    private val signInHosts = setOf(
        "accounts.google.com", "appleid.apple.com", "discord.com", "www.discord.com"
    )

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        web = WebView(this)
        setContentView(web)
        hideSystemBars()

        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true          // the login lives in localStorage
            mediaPlaybackRequiresUserGesture = false
            cacheMode = WebSettings.LOAD_DEFAULT
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            userAgentString = userAgentString + " RysteriaApp"
        }
        CookieManager.getInstance().setAcceptCookie(true)
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                return route(request.url)
            }
        }
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (web.canGoBack()) web.goBack() else finish()
            }
        })

        if (savedInstanceState != null) web.restoreState(savedInstanceState)
        else if (!handleSignInReturn(intent)) web.loadUrl(BuildConfig.GAME_URL)
    }

    /** true when the app handled the address itself (a page is not loaded for it) */
    private fun route(uri: Uri): Boolean {
        val host = uri.host ?: return true
        val game = Uri.parse(BuildConfig.GAME_URL).host
        if (host == BuildConfig.API_HOST && uri.path?.endsWith("/start") == true &&
            uri.path?.startsWith("/oauth/") == true
        ) {
            // the page asked to sign in with a provider: do it in the browser
            openInBrowser(uri.buildUpon().appendQueryParameter("app", "1").build())
            return true
        }
        if (host in signInHosts) {
            openInBrowser(uri)
            return true
        }
        if (host == game || host == BuildConfig.API_HOST || host.endsWith("." + game)) return false
        // any other site opens outside the game
        startActivity(Intent(Intent.ACTION_VIEW, uri))
        return true
    }

    private fun openInBrowser(uri: Uri) {
        CustomTabsIntent.Builder().build().launchUrl(this, uri)
    }

    /** rysteria://oauth#oauth_code=... or #oauth_error=...: load the game with it */
    private fun handleSignInReturn(intent: Intent?): Boolean {
        val data = intent?.data ?: return false
        if (data.scheme != "rysteria" || data.host != "oauth") return false
        val fragment = data.encodedFragment ?: ""
        web.loadUrl(BuildConfig.GAME_URL + (if (fragment.isNotEmpty()) "#$fragment" else ""))
        return true
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleSignInReturn(intent)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        web.saveState(outState)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemBars()
    }

    @Suppress("DEPRECATION")
    private fun hideSystemBars() {
        window.decorView.systemUiVisibility = (View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                or View.SYSTEM_UI_FLAG_FULLSCREEN
                or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION)
    }

    override fun onResume() { super.onResume(); web.onResume() }
    override fun onPause() { web.onPause(); super.onPause() }
    override fun onDestroy() { web.destroy(); super.onDestroy() }
}
