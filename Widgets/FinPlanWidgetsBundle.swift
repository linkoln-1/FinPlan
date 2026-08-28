import SwiftUI
import WidgetKit

@main
struct FinPlanWidgetsBundle: WidgetBundle {
    var body: some Widget {
        GoalWidget()
        SafeToSpendWidget()
        MonthWidget()
    }
}
