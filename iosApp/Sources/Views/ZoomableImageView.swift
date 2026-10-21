import SwiftUI
import UIKit

/// A page image that zooms with a pinch or a double tap (up to 4×), backed by UIScrollView.
///
/// At 1× the scroll view has nothing to scroll, so horizontal swipes still reach the paging
/// TabView around it. Single taps report where they landed (0 = left edge, 1 = right edge) so
/// the reader can turn pages from the screen edges.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    var onTap: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    func makeUIView(context: Context) -> ZoomingScrollView {
        let scrollView = ZoomingScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.imageView.image = image

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:))
        )
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateUIView(_ scrollView: ZoomingScrollView, context: Context) {
        context.coordinator.onTap = onTap
        if scrollView.imageView.image !== image {
            scrollView.imageView.image = image
            scrollView.setZoomScale(1, animated: false)
            scrollView.setNeedsLayout()
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var onTap: (CGFloat) -> Void
        weak var scrollView: ZoomingScrollView?

        init(onTap: @escaping (CGFloat) -> Void) {
            self.onTap = onTap
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ZoomingScrollView)?.imageView
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > 1.01 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = recognizer.location(in: scrollView.imageView)
                let scale: CGFloat = 2.5
                let size = CGSize(
                    width: scrollView.bounds.width / scale,
                    height: scrollView.bounds.height / scale
                )
                let rect = CGRect(
                    x: point.x - size.width / 2,
                    y: point.y - size.height / 2,
                    width: size.width,
                    height: size.height
                )
                scrollView.zoom(to: rect, animated: true)
            }
        }

        @objc func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView, scrollView.bounds.width > 0 else { return }
            let x = recognizer.location(in: scrollView).x - scrollView.contentOffset.x
            onTap(min(max(x / scrollView.bounds.width, 0), 1))
        }
    }
}

final class ZoomingScrollView: UIScrollView {
    let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addSubview(imageView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // At rest the image fills the page; while zoomed, UIScrollView owns its frame.
        if zoomScale <= minimumZoomScale + 0.001 {
            imageView.frame = bounds
            contentSize = bounds.size
        }
    }
}
