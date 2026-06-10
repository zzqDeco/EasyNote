import UIKit

extension UIView {
    /// 递归查找视图层次结构中的第一个UITextView
    func findUITextView() -> UITextView? {
        // 检查当前视图是否是UITextView
        if let textView = self as? UITextView {
            return textView
        }
        
        // 递归搜索子视图
        for subview in subviews {
            if let textView = subview.findUITextView() {
                return textView
            }
        }
        
        return nil
    }
} 