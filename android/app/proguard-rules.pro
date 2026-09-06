# home_widget 传递引入的 WorkManager 2.7.1 使用旧版 Room 2.2.5。
# WorkDatabase 的实现类 WorkDatabase_Impl 由 Room 注解处理器生成，
# 仅在运行期通过反射实例化；R8 全模式会将其整体移除，导致 release 包
# 在 androidx.startup.InitializationProvider 初始化 WorkManager 时抛出
# "Failed to create an instance of androidx.work.impl.WorkDatabase" 而闪退。
-keep class * extends androidx.room.RoomDatabase {
    <init>();
}
