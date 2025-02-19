//
//  ChatAccessoryModel.swift
//  Telegram
//
//  Created by keepcoder on 01/02/2017.
//  Copyright © 2017 Telegram. All rights reserved.
//

import Cocoa
import TGUIKit
import SwiftSignalKit

class ChatAccessoryView : Button {
    var imageView: TransformImageView?
    let headerView = TextView()
    var textView: TextView?
    
    private var shimmerEffect: ShimmerView?
    private var shimmerMask: SimpleLayer?

    
    private var inlineStickerItemViews: [InlineStickerItemLayer.Key: InlineStickerItemLayer] = [:]

    
    private weak var model: ChatAccessoryModel?
    
    private let borderLayer = SimpleShapeLayer()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        initialize()
    }
    
    private func initialize() {
        headerView.userInteractionEnabled = false
        headerView.isSelectable = false
        addSubview(headerView)
                
       
        self.layer?.addSublayer(borderLayer)
    }
    
    override init() {
        super.init(frame: .zero)
        initialize()
    }
    
    override func layout() {
        super.layout()
        if let model = model {
            updateModel(model, animated: false)
        }
    }
    
    
    func updateLayout(_ size: NSSize, transition: ContainedViewLayoutTransition) {
        
        guard let model = model else {
            return
        }
        
        
        
        let x: CGFloat = model.leftInset + (model.isSideAccessory ? 10 : 0)

        let headerRect = CGRect(origin: NSMakePoint(x, (model.isSideAccessory ? 5 : 0) + model.topOffset), size: headerView.frame.size)
        transition.updateFrame(view: headerView, frame: headerRect)
        
        if let textView = textView {
            let textRect = CGRect(origin: NSMakePoint(x, headerRect.height + model.yInset + (model.isSideAccessory ? 5 : 0) + model.topOffset), size: textView.frame.size)
            transition.updateFrame(view: textView, frame: textRect)
            if let view = shimmerEffect {
                let rect = CGRect(origin: textRect.origin, size: view.frame.size)
                transition.updateFrame(view: view, frame: rect.offsetBy(dx: -5, dy: -1))
            }
        }
                
    }
    
    func updateModel(_ model: ChatAccessoryModel, animated: Bool) {
        self.model = model
        self.backgroundColor = model.presentation.background
 
        
        borderLayer.opacity = model.drawLine ? 1 : 0
        borderLayer.backgroundColor = model.presentation.border.cgColor
        if model.drawLine {
            let borderRect = NSMakeRect((model.isSideAccessory ? 10 : 0), (model.isSideAccessory ? 5 : 0) + model.topOffset, 2, model.size.height - model.topOffset - (model.isSideAccessory ? 10 : 0))
            borderLayer.frame = borderRect
            borderLayer.cornerRadius = borderRect.width / 2
        }
                
        headerView.update(model.header)
        
        if let view = self.textView {
            view.update(model.message)
        } else {
            if let view = self.textView {
                performSubviewRemoval(view, animated: animated)
            }
            let previous = self.textView != nil
            let current: TextView = TextView()
            current.update(model.message)
            current.userInteractionEnabled = false
            current.isSelectable = false
            addSubview(current)
            self.textView = current
            self.updateLayout(self.frame.size, transition: .immediate)
            if animated, previous {
                current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            }
        }
     
        if let message = model.message, let view = self.textView {
            updateInlineStickers(context: model.context, view: view, textLayout: message)
        }
        
        if let blockImage = model.shimm.1 {
            let size = blockImage.size
            let current: ShimmerView
            if let view = self.shimmerEffect {
                current = view
            } else {
                current = ShimmerView()
                self.shimmerEffect = current
                self.addSubview(current, positioned: .above, relativeTo: textView)
                
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
            current.update(backgroundColor: .blackTransparent, data: nil, size: size, imageSize: size)
            current.updateAbsoluteRect(size.bounds, within: size)
            
            current.frame = blockImage.backingSize.bounds
            
            if shimmerMask == nil {
                shimmerMask = SimpleLayer()
            }
            var fr = CATransform3DIdentity
            fr = CATransform3DTranslate(fr, blockImage.backingSize.width / 2, 0, 0)
            fr = CATransform3DScale(fr, 1, -1, 1)
            fr = CATransform3DTranslate(fr, -(blockImage.backingSize.width / 2), 0, 0)
            
            shimmerMask?.transform = fr
            shimmerMask?.contentsScale = 2.0
            shimmerMask?.contents = blockImage
            shimmerMask?.frame = CGRect(origin: .zero, size: blockImage.backingSize)
            current.layer?.mask = shimmerMask
        } else {
            if let view = self.shimmerEffect {
                let shimmerMask = self.shimmerMask
                performSubviewRemoval(view, animated: animated, completed: { [weak shimmerMask] _ in
                    shimmerMask?.removeFromSuperlayer()
                })
                self.shimmerEffect = nil
                self.shimmerMask = nil
            }
        }
        
        
        let transition: ContainedViewLayoutTransition
        if animated {
            transition = .animated(duration: 0.2, curve: .easeOut)
        } else {
            transition = .immediate
        }
        
        updateLayout(frame.size, transition: transition)
        
        self.updateListeners()
        
        self.updateTheme()
    }
    
    func updateTheme() {
        if let model = model {
            self.backgroundColor = model.presentation.background
        }
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.updateListeners()
        self.updateAnimatableContent()
    }
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        self.updateListeners()
        self.updateAnimatableContent()
    }
    
    
    
    @objc func updateAnimatableContent() -> Void {
        for (_, value) in inlineStickerItemViews {
            if let superview = value.superview {
                value.isPlayable = NSIntersectsRect(value.frame, superview.visibleRect) && window != nil && window!.isKeyWindow && !isLite
            }
        }
    }
    
    private var isLite: Bool = false
    
    func updateInlineStickers(context: AccountContext, view textView: TextView, textLayout: TextViewLayout) {
        var validIds: [InlineStickerItemLayer.Key] = []
        var index: Int = textView.hashValue
        self.isLite = context.isLite(.emoji)
        
        let textColor: NSColor
        if textLayout.attributedString.length > 0 {
            var range:NSRange = NSMakeRange(NSNotFound, 0)
            let attrs = textLayout.attributedString.attributes(at: 0, effectiveRange: &range)
            textColor = attrs[.foregroundColor] as? NSColor ?? theme.colors.text
        } else {
            textColor = theme.colors.text
        }

        for item in textLayout.embeddedItems {
            if let stickerItem = item.value as? InlineStickerItem, case let .attribute(emoji) = stickerItem.source {
                
                let id = InlineStickerItemLayer.Key(id: emoji.fileId, index: index)
                validIds.append(id)
                
                let rect = item.rect.insetBy(dx: -2, dy: -2)
                
                let view: InlineStickerItemLayer
                if let current = self.inlineStickerItemViews[id], current.frame.size == rect.size {
                    view = current
                } else {
                    self.inlineStickerItemViews[id]?.removeFromSuperlayer()
                    view = InlineStickerItemLayer(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: emoji, size: rect.size, textColor: textColor)
                    self.inlineStickerItemViews[id] = view
                    view.superview = textView
                    textView.addEmbeddedLayer(view)
                }
                index += 1
                
                view.frame = rect
            }
        }
        
        var removeKeys: [InlineStickerItemLayer.Key] = []
        for (key, itemLayer) in self.inlineStickerItemViews {
            if !validIds.contains(key) {
                removeKeys.append(key)
                itemLayer.removeFromSuperlayer()
            }
        }
        for key in removeKeys {
            self.inlineStickerItemViews.removeValue(forKey: key)
        }
        updateAnimatableContent()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func updateListeners() {
        let center = NotificationCenter.default
        if let window = window {
            center.removeObserver(self)
            center.addObserver(self, selector: #selector(updateAnimatableContent), name: NSWindow.didBecomeKeyNotification, object: window)
            center.addObserver(self, selector: #selector(updateAnimatableContent), name: NSWindow.didResignKeyNotification, object: window)
            center.addObserver(self, selector: #selector(updateAnimatableContent), name: NSView.boundsDidChangeNotification, object: self.enclosingScrollView?.contentView)
            center.addObserver(self, selector: #selector(updateAnimatableContent), name: NSView.frameDidChangeNotification, object: self.enclosingScrollView?.documentView)
            center.addObserver(self, selector: #selector(updateAnimatableContent), name: NSView.frameDidChangeNotification, object: self)
        } else {
            center.removeObserver(self)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct ChatAccessoryPresentation {
    let background: NSColor
    let title: NSColor
    let enabledText: NSColor
    let disabledText: NSColor
    let border: NSColor
    
    func withUpdatedBackground(_ backgroundColor: NSColor) -> ChatAccessoryPresentation {
        return ChatAccessoryPresentation(background: backgroundColor, title: title, enabledText: enabledText, disabledText: disabledText, border: border)
    }
}

class ChatAccessoryModel: NSObject {
    
    
    public let nodeReady = Promise<Bool>()
    
    public var shimm: (NSPoint, CGImage?) {
        return (.zero, nil)
    }
    
    var updateImageSignal: Signal<ImageDataTransformation, NoError>?

    
    open var backgroundColor:NSColor {
        didSet {
            self.presentation = presentation.withUpdatedBackground(backgroundColor)
        }
    }
    
    var isSideAccessory: Bool = false
    
    private var _presentation: ChatAccessoryPresentation? = nil
    var presentation: ChatAccessoryPresentation {
        set {
            _presentation = newValue
            self.view?.updateTheme()
        }
        get {
            return _presentation ?? ChatAccessoryPresentation(background: theme.colors.background, title: theme.colors.accent, enabledText: theme.colors.text, disabledText: theme.colors.grayText, border: theme.colors.accent)
        }
    }
    
    private let _strongView:ChatAccessoryView?
    open weak var view:ChatAccessoryView? {
        didSet {
            if let view = view {
                view.imageView?.removeFromSuperview()
                view.imageView = nil
                view.updateModel(self, animated: self.animates)
            }
        }
    }
    
    var animates: Bool = false
    
    open var size:NSSize = NSZeroSize
    let drawLine: Bool
    var width: CGFloat = 0
    var sizeToFit: Bool = false
    open var frame:NSRect {
        get {
            return self.view?.frame ?? NSZeroRect
        }
        set {
            self.view?.frame = newValue
        }
    }
    
    deinit {
        if _strongView != nil {
            assertOnMainThread()
        }
    }
    
    let context: AccountContext
    
    public init(context: AccountContext, view:ChatAccessoryView? = nil, presentation: ChatAccessoryPresentation? = nil, drawLine: Bool = true) {
        _strongView = view
        self.context = context
        self.drawLine = drawLine
        _presentation = presentation
        if view != nil {
            assertOnMainThread()
        }
        backgroundColor = theme.colors.background
        super.init()
        self.view = view
        
    }
    
    
    open func setNeedDisplay() -> Void {
        if let view = view {
            view.updateModel(self, animated: false)
        }
    }
    
    public func removeFromSuperview() -> Void {
        self.view?.removeFromSuperview()
    }
    
    
    open var viewClass:AnyClass {
        return View.self
    }
    
    
    let yInset:CGFloat = 2
    var leftInset:CGFloat {
        return drawLine ? 8 : 8
    }
    
    var header:TextViewLayout?
    var message:TextViewLayout?
    
    var topOffset: CGFloat = 0
    
    
    func measureSize(_ width:CGFloat = 0, sizeToFit: Bool = false) -> Void {
        self.sizeToFit = sizeToFit
        
        header?.measure(width: width - leftInset)
        message?.measure(width: width - leftInset)
        
        
        
        if let header = header, let message = message {            
            self.size = NSMakeSize(sizeToFit ? max(header.layoutSize.width, message.layoutSize.width) + leftInset + (isSideAccessory ? 20 : 0) : width, max(34, header.layoutSize.height + message.layoutSize.height + yInset + (isSideAccessory ? 10 : 0)))
            self.size.height += topOffset
        } else {
            self.size = NSMakeSize(width, 34)
        }
        self.width = width
    }
    
    
    
//
//    func draw(_ layer: CALayer, in ctx: CGContext) {
//        if let view = view {
//            ctx.setFillColor(presentation.background.cgColor)
//            ctx.fill(layer.bounds)
//
//            ctx.setFillColor(presentation.border.cgColor)
//
//            if drawLine {
//                let radius:CGFloat = 1.0
//                ctx.fill(NSMakeRect((isSideAccessory ? 10 : 0), radius + (isSideAccessory ? 5 : 0) + topOffset, 2, size.height - topOffset - radius * 2 - (isSideAccessory ? 10 : 0)))
//                ctx.fillEllipse(in: CGRect(origin: CGPoint(x: (isSideAccessory ? 10 : 0), y: (isSideAccessory ? 5 : 0) + topOffset), size: CGSize(width: radius + radius, height: radius + radius)))
//                ctx.fillEllipse(in: CGRect(origin: CGPoint(x: (isSideAccessory ? 10 : 0), y: size.height - radius * 2 -  (isSideAccessory ? 5 : 0)), size: CGSize(width: radius + radius, height: radius + radius)))
//            }
//
//            if  let header = header, let message = message {
//                header.1.draw(NSMakeRect(leftInset + (isSideAccessory ? 10 : 0), (isSideAccessory ? 5 : 0) + topOffset, header.0.size.width, header.0.size.height), in: ctx, backingScaleFactor: view.backingScaleFactor, backgroundColor: presentation.background)
//                if headerAttr == nil {
//                    message.1.draw(NSMakeRect(leftInset + (isSideAccessory ? 10 : 0), floorToScreenPixels(view.backingScaleFactor, topOffset + (size.height - topOffset - message.0.size.height)/2), message.0.size.width, message.0.size.height), in: ctx, backingScaleFactor: view.backingScaleFactor, backgroundColor: presentation.background)
//                } else {
//                    message.1.draw(NSMakeRect(leftInset + (isSideAccessory ? 10 : 0), header.0.size.height + yInset + (isSideAccessory ? 5 : 0) + topOffset, message.0.size.width, message.0.size.height), in: ctx, backingScaleFactor: view.backingScaleFactor, backgroundColor: presentation.background)
//                }
//            }
//        }
//
//    }

}
