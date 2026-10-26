package de.redstream.app.data

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit

/** Everything the app remembers between launches. */
class Prefs(context: Context) {
    private val sp: SharedPreferences = context.getSharedPreferences("redstream", Context.MODE_PRIVATE)

    var baseUrl: String?
        get() = sp.getString("base_url", null)
        set(v) = sp.edit { putString("base_url", v) }

    var token: String?
        get() = sp.getString("token", null)
        set(v) = sp.edit { putString("token", v) }

    /** Device-approval request still waiting for the terminal. */
    var pendingDeviceId: String?
        get() = sp.getString("pending_device_id", null)
        set(v) = sp.edit { putString("pending_device_id", v) }

    var pendingCode: String?
        get() = sp.getString("pending_code", null)
        set(v) = sp.edit { putString("pending_code", v) }

    var profileId: Int?
        get() = sp.getInt("profile_id", -1).takeIf { it >= 0 }
        set(v) = sp.edit { if (v == null) remove("profile_id") else putInt("profile_id", v) }

    var profileName: String?
        get() = sp.getString("profile_name", null)
        set(v) = sp.edit { putString("profile_name", v) }

    /** Screen (TV) chosen as playback target; null = play on this phone. */
    var castScreenId: String?
        get() = sp.getString("cast_screen_id", null)
        set(v) = sp.edit { putString("cast_screen_id", v) }

    var castScreenName: String?
        get() = sp.getString("cast_screen_name", null)
        set(v) = sp.edit { putString("cast_screen_name", v) }

    fun clearSession() = sp.edit {
        remove("token"); remove("profile_id"); remove("profile_name")
        remove("pending_device_id"); remove("pending_code")
        remove("cast_screen_id"); remove("cast_screen_name")
    }
}
