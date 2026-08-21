import WidgetKit
import SwiftUI

// MARK: - 数据模型

struct WidgetTodo: Identifiable, Decodable {
    let id: String
    let title: String
    let priority: String
    let priorityLabel: String
    let projectTitle: String
    let endDate: String?
    let subTodoCount: Int
    let subTodoDoneCount: Int
    let isOverdue: Bool
    let isDueSoon: Bool
}

struct WidgetEntry: TimelineEntry {
    let date: Date
    let todos: [WidgetTodo]
    let pendingCount: Int
    let totalCount: Int
}

// MARK: - 数据读取

func loadWidgetData() -> WidgetEntry {
    guard let shared = UserDefaults(suiteName: "group.com.cardoryapp.widget") else {
        return WidgetEntry(date: Date(), todos: [], pendingCount: 0, totalCount: 0)
    }
    guard let payload = shared.string(forKey: "cardory_todos"),
          let data = payload.data(using: .utf8) else {
        return WidgetEntry(date: Date(), todos: [], pendingCount: 0, totalCount: 0)
    }
    do {
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let pendingCount = json["pendingCount"] as? Int ?? 0
            let totalCount = json["totalCount"] as? Int ?? 0
            var todos: [WidgetTodo] = []
            if let arr = json["todos"] as? [[String: Any]] {
                for item in arr.prefix(5) {
                    if let id = item["id"] as? String,
                       let title = item["title"] as? String {
                        todos.append(WidgetTodo(
                            id: id,
                            title: title,
                            priority: item["priority"] as? String ?? "p2",
                            priorityLabel: item["priorityLabel"] as? String ?? "普通",
                            projectTitle: item["projectTitle"] as? String ?? "",
                            endDate: item["endDate"] as? String,
                            subTodoCount: item["subTodoCount"] as? Int ?? 0,
                            subTodoDoneCount: item["subTodoDoneCount"] as? Int ?? 0,
                            isOverdue: item["isOverdue"] as? Bool ?? false,
                            isDueSoon: item["isDueSoon"] as? Bool ?? false
                        ))
                    }
                }
            }
            return WidgetEntry(
                date: Date(),
                todos: todos,
                pendingCount: pendingCount,
                totalCount: totalCount
            )
        }
    } catch {}
    return WidgetEntry(date: Date(), todos: [], pendingCount: 0, totalCount: 0)
}

// MARK: - TimelineProvider

struct CardoryProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(
            date: Date(),
            todos: [
                WidgetTodo(id: "1", title: "完成项目报告", priority: "p0", priorityLabel: "高", projectTitle: "工作", endDate: nil, subTodoCount: 2, subTodoDoneCount: 1, isOverdue: false, isDueSoon: true),
                WidgetTodo(id: "2", title: "购买食材", priority: "p1", priorityLabel: "中", projectTitle: "生活", endDate: nil, subTodoCount: 0, subTodoDoneCount: 0, isOverdue: false, isDueSoon: false)
            ],
            pendingCount: 2,
            totalCount: 2
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(loadWidgetData())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let entry = loadWidgetData()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }
}

// MARK: - 优先级颜色

func priorityColor(_ name: String) -> Color {
    switch name {
    case "p0": return Color(red: 0.898, green: 0.224, blue: 0.208)  // 红
    case "p1": return Color(red: 0.984, green: 0.549, blue: 0.0)     // 橙
    case "p2": return Color(red: 0.263, green: 0.627, blue: 0.278)   // 绿
    case "p3": return Color(red: 0.620, green: 0.620, blue: 0.620)   // 灰
    default:   return Color(red: 0.263, green: 0.627, blue: 0.278)
    }
}

// MARK: - SwiftUI 视图

struct CardoryWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Text("待办")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.420, green: 0.384, blue: 0.875))
                Spacer()
                Text("\(entry.pendingCount)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if entry.todos.isEmpty {
                Spacer()
                Text("暂无待办事项")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                // 待办列表
                let displayCount = min(entry.todos.count,
                    family == .systemSmall ? 2 : (family == .systemMedium ? 4 : 6))

                ForEach(entry.todos.prefix(displayCount).indices, id: \.self) { index in
                    let todo = entry.todos[index]
                    TodoRow(todo: todo)
                    if index < displayCount - 1 {
                        Divider().padding(.leading, 24)
                    }
                }

                if displayCount < entry.todos.count && family == .systemLarge {
                    Text("还有 \(entry.todos.count - displayCount) 条待办...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.leading, 24)
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetBackground(Color(uiColor: .systemBackground))
    }
}

struct TodoRow: View {
    let todo: WidgetTodo

    var body: some View {
        HStack(spacing: 8) {
            // 优先级圆点
            Circle()
                .fill(priorityColor(todo.priority))
                .frame(width: 8, height: 8)

            // 内容
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(todo.title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Spacer()
                    if todo.isOverdue {
                        Text("已过期")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    } else if todo.isDueSoon {
                        Text("即将到期")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }
                if !todo.projectTitle.isEmpty {
                    Text(todo.projectTitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

// MARK: - Widget 主入口

struct CardoryWidget: Widget {
    let kind = "CardoryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CardoryProvider()) { entry in
            CardoryWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("待办列表")
        .description("在主屏幕查看你的待办事项")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Widget Background 扩展（iOS 17+ 兼容）

extension View {
    func widgetBackground(_ backgroundView: some View) -> some View {
        if #available(iOS 17.0, *) {
            return containerBackground(for: .widget) { backgroundView }
        } else {
            return background(backgroundView)
        }
    }
}
