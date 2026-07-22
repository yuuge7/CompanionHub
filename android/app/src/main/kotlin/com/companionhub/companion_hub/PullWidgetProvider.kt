package com.companionhub.companion_hub

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

/**
 * "Currency-to-Pulls" home screen widget.
 *
 * The Flutter side (WidgetService) writes per-game values into the
 * home_widget SharedPreferences store using the keys:
 *   vis_<game>        "1" = row shown, "0" = game hidden in app settings
 *   cur_<game>        raw premium currency, e.g. "24800"
 *   pulls_<game>      computed total pulls (currency / cost + owned tickets)
 *   eanchor_<game>    energy anchor value
 *   eanchorms_<game>  anchor timestamp (epoch ms)
 *   ecap_<game>       normal energy cap
 *   erate_<game>      minutes per 1 energy up to the normal cap
 *   eocap_<game>      overflow cap, "0" when the game has none
 *   eorate_<game>     minutes per 1 overflow energy, "0" when none
 *
 * Energy is projected forward from the anchor at render time (mirrors
 * lib/core/energy_math.dart), so the 30-minute periodic update keeps the
 * numbers fresh without ever starting the Flutter engine.
 */
class PullWidgetProvider : HomeWidgetProvider() {

    private data class Row(
        val game: String,
        val rowId: Int,
        val pullsId: Int,
        val energyTextId: Int,
        val progressId: Int,
        val etaId: Int,
    )

    private val rows = listOf(
        Row("hsr", R.id.row_hsr, R.id.txt_pulls_hsr, R.id.txt_energy_hsr, R.id.progress_hsr, R.id.txt_eta_hsr),
        Row("wuwa", R.id.row_wuwa, R.id.txt_pulls_wuwa, R.id.txt_energy_wuwa, R.id.progress_wuwa, R.id.txt_eta_wuwa),
        Row("re1999", R.id.row_re1999, R.id.txt_pulls_re1999, R.id.txt_energy_re1999, R.id.progress_re1999, R.id.txt_eta_re1999),
        Row("nte", R.id.row_nte, R.id.txt_pulls_nte, R.id.txt_energy_nte, R.id.progress_nte, R.id.txt_eta_nte),
    )

    private fun SharedPreferences.int(key: String, def: Int): Int =
        (getString(key, null) ?: "").toIntOrNull() ?: def

    private fun SharedPreferences.long(key: String, def: Long): Long =
        (getString(key, null) ?: "").toLongOrNull() ?: def

    /**
     * Piecewise projection: normal rate up to cap, then overflow rate.
     * Returns the fractional energy so fill ETAs can be computed exactly.
     */
    private fun projectEnergy(
        anchor: Int,
        anchorMs: Long,
        nowMs: Long,
        cap: Int,
        rateMin: Int,
        oCap: Int,
        oRateMin: Int,
    ): Double {
        val absCap = if (oCap > 0) oCap else cap
        var e = anchor.coerceIn(0, absCap).toDouble()
        var minutesLeft = max(0L, nowMs - anchorMs) / 60000.0

        if (e < cap) {
            val minutesToCap = (cap - e) * rateMin
            if (minutesLeft >= minutesToCap) {
                minutesLeft -= minutesToCap
                e = cap.toDouble()
            } else {
                e += minutesLeft / rateMin
                minutesLeft = 0.0
            }
        }
        if (oCap > 0 && minutesLeft > 0 && e < oCap && oRateMin > 0) {
            e = min(oCap.toDouble(), e + minutesLeft / oRateMin)
        }
        return min(e, absCap.toDouble())
    }

    /** "1d 4h" / "5h 48m" / "48m" — durations are shown coarsely. */
    private fun fmtDuration(ms: Long): String {
        val totalMin = ms / 60000
        if (totalMin < 1) return "<1m"
        val d = totalMin / (60 * 24)
        val h = (totalMin / 60) % 24
        val m = totalMin % 60
        return when {
            d > 0 -> "${d}d ${h}h"
            h > 0 -> "${h}h ${m}m"
            else -> "${m}m"
        }
    }

    /** "14:35" today, "Tue 09:15" on another day (mirrors the in-app ETA). */
    private fun fmtClock(atMs: Long, nowMs: Long): String {
        val at = Calendar.getInstance().apply { timeInMillis = atMs }
        val ref = Calendar.getInstance().apply { timeInMillis = nowMs }
        val sameDay = at.get(Calendar.YEAR) == ref.get(Calendar.YEAR) &&
            at.get(Calendar.DAY_OF_YEAR) == ref.get(Calendar.DAY_OF_YEAR)
        val pattern = if (sameDay) "HH:mm" else "EEE HH:mm"
        return SimpleDateFormat(pattern, Locale.getDefault()).format(Date(atMs))
    }

    /** Countdown + wall-clock line: when the normal cap (then reserve) fills. */
    private fun etaText(
        e: Double,
        nowMs: Long,
        cap: Int,
        rateMin: Int,
        oCap: Int,
        oRateMin: Int,
    ): String = when {
        e < cap && rateMin > 0 -> {
            val fullAt = nowMs + ((cap - e) * rateMin * 60000.0).toLong()
            "full in ${fmtDuration(fullAt - nowMs)} (${fmtClock(fullAt, nowMs)})"
        }
        oCap > 0 && e < oCap && oRateMin > 0 -> {
            val fullAt = nowMs + ((oCap - e) * oRateMin * 60000.0).toLong()
            "reserve full in ${fmtDuration(fullAt - nowMs)} (${fmtClock(fullAt, nowMs)})"
        }
        oCap > 0 -> "fully capped"
        else -> "capped"
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val now = System.currentTimeMillis()
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.pull_widget)

            for (row in rows) {
                // Games hidden in the app's settings are dropped from the
                // widget; the remaining rows share the freed vertical space.
                val visible = widgetData.getString("vis_${row.game}", "1") != "0"
                views.setViewVisibility(row.rowId, if (visible) View.VISIBLE else View.GONE)
                if (!visible) continue

                val currency = widgetData.getString("cur_${row.game}", "0") ?: "0"
                val pulls = widgetData.getString("pulls_${row.game}", "0") ?: "0"
                val cap = widgetData.int("ecap_${row.game}", 240)
                val rateMin = widgetData.int("erate_${row.game}", 6)
                val oCap = widgetData.int("eocap_${row.game}", 0)
                val oRateMin = widgetData.int("eorate_${row.game}", 0)
                val exact = projectEnergy(
                    anchor = widgetData.int("eanchor_${row.game}", 0),
                    anchorMs = widgetData.long("eanchorms_${row.game}", now),
                    nowMs = now,
                    cap = cap,
                    rateMin = rateMin,
                    oCap = oCap,
                    oRateMin = oRateMin,
                )
                val energy = exact.toInt()
                val normal = min(energy, cap)
                val overflow = max(0, energy - cap)
                val suffix = if (overflow > 0) " +$overflow" else ""

                views.setTextViewText(row.pullsId, "$pulls pulls")
                views.setTextViewText(row.energyTextId, "$currency • ⚡ $normal/$cap$suffix")
                views.setProgressBar(row.progressId, cap, normal, false)
                views.setTextViewText(
                    row.etaId,
                    etaText(exact, now, cap, rateMin, oCap, oRateMin),
                )
            }

            // Tapping the widget just opens the app.
            val launchIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
            )
            views.setOnClickPendingIntent(R.id.widget_root, launchIntent)

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
