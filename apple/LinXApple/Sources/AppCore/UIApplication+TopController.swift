import UIKit

extension UIApplication {
    @MainActor
    static func linxTopViewController(
        base: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    ) -> UIViewController? {
        if let navigationController = base as? UINavigationController {
            return linxTopViewController(base: navigationController.visibleViewController)
        }

        if let tabBarController = base as? UITabBarController {
            return linxTopViewController(base: tabBarController.selectedViewController)
        }

        if let presentedViewController = base?.presentedViewController {
            return linxTopViewController(base: presentedViewController)
        }

        return base
    }
}
