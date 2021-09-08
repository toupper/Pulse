// The MIT License (MIT)
//
// Copyright (c) 2020–2021 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Automates URLSession request tracking.
public final class URLSessionProxyDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    private weak var actualDelegate: URLSessionDelegate?
    private weak var taskDelegate: URLSessionTaskDelegate?
    private let interceptedSelectors: Set<Selector>
    private let logger: NetworkLogger

    /// - parameter logger: By default, creates a logger with `LoggerStore.default`.
    /// - parameter delegate: The "actual" session delegate.
    public init(logger: NetworkLogger = .init(), delegate: URLSessionDelegate?) {
        self.actualDelegate = delegate
        self.taskDelegate = delegate as? URLSessionTaskDelegate
        self.interceptedSelectors = [
            #selector(URLSessionDataDelegate.urlSession(_:dataTask:didReceive:)),
            #selector(URLSessionTaskDelegate.urlSession(_:task:didCompleteWithError:)),
            #selector(URLSessionDataDelegate.urlSession(_:dataTask:didReceive:completionHandler:)),
            #selector(URLSessionTaskDelegate.urlSession(_:task:didFinishCollecting:))
        ]
        self.logger = logger
    }

   // public func urlSession(_ session: URLSession,//
    //                       didBecomeInvalidWithError error: Error?) {
      
    //}
  
    // MARK: URLSessionTaskDelegate

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        logger.logTask(task, didCompleteWithError: error)
        taskDelegate?.urlSession?(session, task: task, didCompleteWithError: error)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        logger.logTask(task, didFinishCollecting: metrics)
        taskDelegate?.urlSession?(session, task: task, didFinishCollecting: metrics)
    }

    // MARK: URLSessionDataDelegate

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        logger.logDataTask(dataTask, didReceive: response)
        if actualDelegate?.responds(to: #selector(URLSessionDataDelegate.urlSession(_:dataTask:didReceive:completionHandler:))) ?? false {
            (actualDelegate as? URLSessionDataDelegate)?.urlSession?(session, dataTask: dataTask, didReceive: response, completionHandler: completionHandler)
        } else {
            completionHandler(.allow)
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        logger.logDataTask(dataTask, didReceive: data)
        (actualDelegate as? URLSessionDataDelegate)?.urlSession?(session, dataTask: dataTask, didReceive: data)
    }

    // MARK: Proxy

    public override func responds(to aSelector: Selector!) -> Bool {
        if interceptedSelectors.contains(aSelector) {
          debugPrint("\(aSelector) intercepted selectors, true")
            return true
        }
      
      let actualDelegateRespondsToSelector = (actualDelegate?.responds(to: aSelector) ?? false)
      let superRespondsToSelector = super.responds(to: aSelector)
      
      debugPrint("\(aSelector) actualDelegateRespondsToSelector \(actualDelegateRespondsToSelector) superRespondsToSelector \(superRespondsToSelector)")
      
        return actualDelegateRespondsToSelector || superRespondsToSelector
    }

    public override func forwardingTarget(for selector: Selector!) -> Any? {
        let forwardingTarget = interceptedSelectors.contains(selector) ? nil : actualDelegate
      
      debugPrint("\(selector) forwardingTarget \(String(describing: forwardingTarget))")
      
      return forwardingTarget
    }
}

// MARK: - Automatic Registration

private extension URLSession {
    @objc class func pulse_init(configuration: URLSessionConfiguration, delegate: URLSessionDelegate?, delegateQueue: OperationQueue?) -> URLSession {
        let delegate = URLSessionProxyDelegate(logger: sharedLogger, delegate: delegate)
        return self.pulse_init(configuration: configuration, delegate: delegate, delegateQueue: delegateQueue)
    }
}

private var sharedLogger: NetworkLogger!

public extension URLSessionProxyDelegate {
    /// Enables automatic registration of `URLSessionProxyDelegate`. After calling this method, every time
    /// you initialize a `URLSession` using `init(configuration:delegate:delegateQueue:))` method, the
    /// delegate will automatically get replaced with a `URLSessionProxyDelegate` that logs all the
    /// needed events and forwards the methods to your original delegate.
    static func enableAutomaticRegistration(logger: NetworkLogger = .init()) {
        sharedLogger = logger
        if let lhs = class_getClassMethod(URLSession.self, #selector(URLSession.init(configuration:delegate:delegateQueue:))),
           let rhs = class_getClassMethod(URLSession.self, #selector(URLSession.pulse_init(configuration:delegate:delegateQueue:))) {
            method_exchangeImplementations(lhs, rhs)
        }
    }
}
