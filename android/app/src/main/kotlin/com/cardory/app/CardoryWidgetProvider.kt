package com.cardory.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Color
import android.os.Bundle
import android.text.TextUtils
import android.widget.RemoteViews
import java.util.Calendar
import org.json.JSONArray
import org.json.JSONObject

class CardoryWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val PREFS_NAME = "FlutterHomeWidget"
        private const val DATA_KEY = "cardory_todos"
        private const val MAX_ITEMS = 5

        fun updateAllWidgets(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, CardoryWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
            for (appWidgetId in appWidgetIds) {
                updateAppWidget(context, appWidgetManager, appWidgetId)
            }
        }

        private fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.cardory_widget)

            // 根据系统暗色模式切换背景
            val nightMode = context.resources.configuration.uiMode and
                    Configuration.UI_MODE_NIGHT_MASK
            val bgRes = if (nightMode == Configuration.UI_MODE_NIGHT_YES) {
                R.drawable.widget_background_dark
            } else {
                R.drawable.widget_background
            }
            views.setInt(R.id.widget_root, "setBackgroundResource", bgRes)

            val prefs: SharedPreferences =
                context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val payload = prefs.getString(DATA_KEY, null)

            if (payload != null) {
                try {
                    val root = JSONObject(payload)
                    val todos = root.optJSONArray("todos")
                    val pendingCount = root.optInt("pendingCount", 0)

                    // 标题栏：显示待办数量
                    views.setTextViewText(
                        R.id.widget_title,
                        "待办 ($pendingCount)"
                    )

                    // 填充条目
                    val container = R.id.widget_container // LinearLayout id
                    views.removeAllViews(container)

                    if (todos == null || todos.length() == 0) {
                        views.setTextViewText(R.id.widget_empty, "暂无待办事项")
                        views.setViewVisibility(R.id.widget_empty, android.view.View.VISIBLE)
                    } else {
                        views.setViewVisibility(R.id.widget_empty, android.view.View.GONE)
                        for (i in 0 until minOf(todos.length(), MAX_ITEMS)) {
                            val todo = todos.getJSONObject(i)
                            addTodoRow(context, views, container, todo)
                        }
                    }
                } catch (_: Exception) {
                    views.removeAllViews(R.id.widget_container)
                    views.setTextViewText(R.id.widget_title, "Cardory")
                    views.setTextViewText(R.id.widget_empty, "数据加载失败")
                    views.setViewVisibility(R.id.widget_empty, android.view.View.VISIBLE)
                }
            } else {
                views.setTextViewText(R.id.widget_title, "Cardory")
                views.setTextViewText(R.id.widget_empty, "打开应用以同步待办")
                views.setViewVisibility(R.id.widget_empty, android.view.View.VISIBLE)
            }

            // 点击整个小组件打开应用
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                launchIntent.putExtra("widget_action", "open_todos")
                val pendingIntent = PendingIntent.getActivity(
                    context, appWidgetId, launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun addTodoRow(
            context: Context,
            views: RemoteViews,
            container: Int,
            todo: JSONObject
        ) {
            val title = todo.optString("title", "未命名")
            val priority = todo.optString("priority", "p2")
            val projectTitle = todo.optString("projectTitle", "")
            val dueState = dueState(todo.optString("endDate", ""))

            val itemView = RemoteViews(context.packageName, R.layout.cardory_widget_item)

            // 设置标题
            itemView.setTextViewText(R.id.item_title, title)

            // 设置副标题（项目名）
            if (projectTitle.isNotEmpty()) {
                itemView.setViewVisibility(R.id.item_project, android.view.View.VISIBLE)
                itemView.setTextViewText(R.id.item_project, projectTitle)
            } else {
                itemView.setViewVisibility(R.id.item_project, android.view.View.GONE)
            }

            // 设置优先级指示器颜色
            val priorityColor = getPriorityColor(priority)
            itemView.setInt(R.id.item_priority_dot, "setBackgroundColor", priorityColor)

            // 设置到期状态
            when {
                dueState == DueState.overdue -> {
                    itemView.setViewVisibility(R.id.item_status, android.view.View.VISIBLE)
                    itemView.setTextViewText(R.id.item_status, "已过期")
                    itemView.setTextColor(R.id.item_status, Color.parseColor("#E53935"))
                }
                dueState == DueState.soon -> {
                    itemView.setViewVisibility(R.id.item_status, android.view.View.VISIBLE)
                    itemView.setTextViewText(R.id.item_status, "即将到期")
                    itemView.setTextColor(R.id.item_status, Color.parseColor("#FB8C00"))
                }
                else -> {
                    itemView.setViewVisibility(R.id.item_status, android.view.View.GONE)
                }
            }

            views.addView(container, itemView)
        }

        private enum class DueState { none, soon, overdue }

        private fun dueState(endDate: String): DueState {
            val parts = endDate.split("-")
            if (parts.size != 3) return DueState.none
            val year = parts[0].toIntOrNull() ?: return DueState.none
            val month = parts[1].toIntOrNull() ?: return DueState.none
            val day = parts[2].toIntOrNull() ?: return DueState.none
            val today = Calendar.getInstance()
            today.set(Calendar.HOUR_OF_DAY, 0)
            today.set(Calendar.MINUTE, 0)
            today.set(Calendar.SECOND, 0)
            today.set(Calendar.MILLISECOND, 0)
            val due = Calendar.getInstance()
            due.clear()
            due.set(year, month - 1, day)
            if (due.before(today)) return DueState.overdue
            val tomorrow = today.clone() as Calendar
            tomorrow.add(Calendar.DAY_OF_YEAR, 1)
            return if (due.before(tomorrow)) DueState.soon else DueState.none
        }

        private fun getPriorityColor(priority: String): Int = when (priority) {
            "p0" -> Color.parseColor("#E53935") // 红 - 高
            "p1" -> Color.parseColor("#FB8C00") // 橙 - 中
            "p2" -> Color.parseColor("#43A047") // 绿 - 普通
            "p3" -> Color.parseColor("#9E9E9E") // 灰 - 低
            else -> Color.parseColor("#43A047")
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == "com.cardory.app.UPDATE_WIDGET") {
            updateAllWidgets(context)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        updateAppWidget(context, appWidgetManager, appWidgetId)
    }
}
