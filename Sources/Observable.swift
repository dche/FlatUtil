//
// FlatUtil - Observalbe.swift
//
// A simple implementation of ReactiveX.
//
// Copyright (c) 2017 The FlatUtil authors.
// Licensed under MIT License.

// Operators that are not implemented:
// - And/Then/When. Complex.
// - Join. Name is too general while the meaning is obscure.
// - Materialize/Dematerialize. Less useful.
// - Serialize. Not needed.
// - Using. Swift does not need it.
// - Connectable Observable Operators. Vague concept.
// - Backpressure. TBI.
// - To. Should not be an operator in Swift.
//

import Dispatch

/// The default dispatch queue for executing generators of `Observable`s.
/// This is a concurrent queue.
public let emittingQueue =
    DispatchQueue(
        label: "com.eleuth.FlatUtil.Observable.emittingQueue",
        qos: .background,
        attributes: .concurrent
    )

// Used when serialization is necessary.
private let serialQueue =
    DispatchQueue(
        label: "com.eleuth.FlatUtil.Observable.serialQueue",
        qos: .background
    )

// The dispatch queue for synchronizing critical region access in `Subject`.
private let subjectSyncQueue =
    DispatchQueue(
        label: "com.eleuth.FlatUtil.Observable.subjectSyncQueue",
        qos: .background
    )

// A simple circular buffer.
//
// NOTE: Not thread-safe.
private struct CircularQueue<Item> {

    private var _head = 0
    private var _tail = 0
    private var _buffer: [EmittingResult<Item>]
    private let capacityFixed: Bool

    init (capacity: Int, fixed: Bool = true) {
        assert(capacity > 0)
        self._buffer = [EmittingResult<Item>](
            repeating: .complete,
            // 1 for separating space.
            count: capacity + 1
        )
        self.capacityFixed = fixed
    }

    var iterator: AnyIterator<EmittingResult<Item>> {
        var p = _head
        return AnyIterator { () -> EmittingResult<Item>? in
            guard p != self._tail else { return nil }
            let item = self._buffer[p]
            p = (p + 1) % self._buffer.capacity
            return item
        }
    }

    var count: Int {
        if _head == _tail { return 0 }
        if _head < _tail { return _tail - _head }
        return _buffer.capacity - _head + _tail
    }

    var isEmpty: Bool {
        return _head == _tail
    }

    var isFull: Bool {
        return count == _buffer.capacity - 1
    }

    var head: EmittingResult<Item>? {
        guard !isEmpty else { return nil }
        return _buffer[_head]
    }

    var last: EmittingResult<Item>? {
        guard !isEmpty else { return nil }
        let cap = _buffer.capacity
        return _buffer[(_tail + cap - 1) % cap]
    }

    mutating func push(item: EmittingResult<Item>) {
        let cap = _buffer.capacity
        if capacityFixed || count < cap - 1 {
            _buffer[_tail] = item
            _tail = (_tail + 1) % cap
            // Release value.
            _buffer[_tail] = .complete
            if (_head == _tail) {
                _head = (_head + 1) % cap
            }
        } else {
            var cq = CircularQueue(capacity: (cap - 1) * 2 + 1)
            for i in self.iterator {
                cq.push(item: i)
            }
            cq.push(item: item)
            self = cq
        }
    }

    mutating func pop() -> EmittingResult<Item>? {
        guard !isEmpty else { return nil }
        let h = _buffer[_head]
        // Release value.
        _buffer[_head] = .complete
        _head = (_head + 1) % _buffer.capacity
        return h
    }
}

/// Standard `Observer` protocol.
public protocol ObserverProtocol {

    associatedtype Item

    func onNext(_ item: Item)

    func onComplete()

    func onError(_ error: Error)
}

/// A general implementation of `ObserverProtocol`.
public struct Observer<T>: ObserverProtocol {

    public typealias Item = T

    private let next: (Item) -> Void

    private let complete: () -> Void

    private let error: (Error) -> Void

    /// Creates an `Observer` with given callbacks.
    ///
    /// - parameters:
    ///   - complete: Called within `onComplete`.
    ///   - error: Called within `onError`.
    ///   - next: Called within `onNext`.
    public init (
        complete: @escaping () -> Void = { },
        error: @escaping (Error) -> Void = { _ in },
        next: @escaping (Item) -> Void
    ) {
        self.next = next
        self.complete = complete
        self.error = error
    }

    public func onNext(_ item: Item) {
        self.next(item)
    }

    public func onComplete() {
        self.complete()
    }

    public func onError(_ error: Error) {
        self.error(error)
    }
}

/// Emitting result of observables.
public enum EmittingResult<T> {

    case item(T)
    case error(Error)
    case complete

    /// Returns `true` if the receiver is a termination notification.
    public var isTermination: Bool {
        switch self {
        case .item(_): return false
        default: return true
        }
    }

    /// Returns the item or `nil` if the receiver is termination.
    public var item: T? {
        switch self {
        case let .item(itm): return itm
        default: return nil
        }
    }
}

extension EmittingResult where T: Equatable {

    // SWIFT EVOLUTION: extension EmittingResult: Equatable where T: Equatable {}

    public static func == (lhs: EmittingResult<T>, rhs: EmittingResult<T>) -> Bool {
        switch (lhs, rhs) {
        case let (.item(li), .item(ri)) where li == ri:
            return true
        case (.complete, .complete):
            return true
        default:
            return false
        }
    }
}

public final class Subscription<I> {

    public typealias Item = I

    private var _cancelled = false

    private let _epoch: Time

    fileprivate init<S: ObservableProtocol, T: ObserverProtocol> (
        on queue: DispatchQueue = emittingQueue,
        observable: S,
        observer: T
    ) where S.Item == Item, T.Item == Item {
        _epoch = Time.now
        observable.subscribe(at: _epoch, on: queue) { er in
            if self._cancelled { return false }
            switch er {
            case let .item(itm):
                observer.onNext(itm)
                return !self._cancelled
            case .complete:
                observer.onComplete()
            case let .error(e):
                observer.onError(e)
            }
            return false
        }
    }

    public func unsubscribe() {
        self._cancelled = true
    }
}

/// Base _Observable_ type.
public protocol ObservableProtocol {

    /// Type of item to be emitted.
    associatedtype Item

    /// This method defines the protocol between an _observable_ and its
    /// users, which can be either _oberver_s or other _observable_s.
    ///
    /// - parameters:
    ///   - time: When the subscription is created.
    ///   - queue: The dispatch queue in which the `callback` should be
    ///     executed.
    ///   - callback: User provided callback function. If this function
    ///     returns `false`, the receiver shall stop emitting anything,
    ///     including termianting notifications.
    func subscribe(
        at time: Time,
        on queue: DispatchQueue,
        callback: @escaping (EmittingResult<Item>) -> Bool
    )
}

extension ObservableProtocol {

    public func subscribe<O: ObserverProtocol>(
        on queue: DispatchQueue = emittingQueue,
        observer o: O
    ) -> Subscription<Item> where O.Item == Item {
        return Subscription(on: queue, observable: self, observer: o)
    }

    public func subscribe(
        on queue: DispatchQueue = emittingQueue,
        complete: @escaping () -> Void = {  },
        error: @escaping (Error) -> Void = { _ in },
        next: @escaping (Item) -> Void
    ) -> Subscription<Item> {
        let o = Observer<Item>(complete: complete, error: error, next: next)
        return Subscription(on: queue, observable: self, observer: o)
    }
}

/// A general implementation of `ObservableProtocol` based on a generator
/// function.
public struct Observable<I>: ObservableProtocol {

    public typealias Item = I

    private let gen: (Time, DispatchQueue, @escaping (EmittingResult<I>) -> Bool) -> Void

    /// Creates an `Observable` by providing a generator function.
    ///
    /// - parameter generator: The generator function. Obviously it is
    ///   used to impelent the `subscribe(at:on:callback:)` method.
    ///
    /// - seealso: [`Defer` operator documentation]
    ///   (http://reactivex.io/documentation/operators/defer.html) on ReactiveX.
    public init (generator: @escaping (Time, DispatchQueue, @escaping (EmittingResult<Item>) -> Bool) -> Void) {
        self.gen = generator
    }

    /// Creates an `Observable` which emits items by directly using the
    /// observer interface.
    ///
    /// - note: This is the only way to create an ill-behaved observable.
    ///
    /// - seealso: [`Create` operator documentation]
    ///   (http://reactivex.io/documentation/operators/create.html) on ReactiveX.
    public init(callback: @escaping (Observer<Item>) -> Void) {
        self.gen = { _, _, cb in
            var isCancelled = false
            let o = Observer<Item>(complete: {
                guard !isCancelled else { return }
                isCancelled = !cb(.complete)
            }, error: {
                guard !isCancelled else { return }
                isCancelled = !cb(.error($0))
            }, next: {
                guard !isCancelled else { return }
                isCancelled = !cb(.item($0))
            })
            callback(o)
        }
    }

    public func subscribe(
        at time: Time,
        on queue: DispatchQueue,
        callback: @escaping (EmittingResult<Item>
    ) -> Bool) {
        queue.async {
            self.gen(time, queue, callback)
        }
    }
}

// MARK: Subject

/// Generic `Subject` type.
///
/// - seealso: [Subject documentation on ReactiveX]
///   (http://reactivex.io/documentation/subject.html) on ReactiveX..
public protocol Subject: ObservableProtocol, ObserverProtocol {}

// This class is used for:
// 1. Sharing implementations,
// 2. Breaking the cycle of type dependencies.
private final class SubjectImpl<Item> {

    typealias Callback = (EmittingResult<Item>) -> Void

    private var _nextHandle: Int = 0

    private var _callbacks: [Int:Callback] = [:]

    var nextHandle: Int {
        self._nextHandle += 1
        return self._nextHandle
    }

    func emit(item: EmittingResult<Item>) {
        for cb in _callbacks.values {
            cb(item)
        }
    }

    // Returns the handle of registration.
    func register(handle: Int, callback: @escaping Callback) {
        assert(handle == self._nextHandle)
        assert(_callbacks[handle] == nil)
        _callbacks[handle] = callback
    }

    func emit(item: EmittingResult<Item>, to handle: Int, on queue: DispatchQueue) -> Bool {
        guard let cb = _callbacks[handle] else { return false }
        queue.async {
            cb(item)
        }
        return true
    }

    // Triggered when an `Observer` cancelled subscription.
    func unregister(handle: Int) {
        subjectSyncQueue.sync {
            assert(handle > 0)
            assert(self._callbacks[handle] != nil)
            self._callbacks.removeValue(forKey: handle)
        }
    }
}

/// An `AsyncSubject` emits the last value (and only the last value) emitted
/// by the source observable, and only after that source observable completes.
///
/// - seealso: [Subject documentation]
///   (http://reactivex.io/documentation/subject.html) on ReactiveX.
public final class AsyncSubject<I>: Subject {

    public typealias Item = I

    private var _last: EmittingResult<Item>? = nil

    private var _impl: SubjectImpl<Item>?

    public init () {
        self._impl = SubjectImpl<Item>()
    }

    public func subscribe(
        at time: Time,
        on queue: DispatchQueue,
        callback: @escaping (EmittingResult<Item>) -> Bool
    ) {
        subjectSyncQueue.async {
            guard let impl = self._impl else {
                assert(self._last != nil)
                let last = self._last!
                queue.async {
                    switch last {
                    case .item(_):
                        let _ = callback(last) && callback(.complete)
                    default:
                        let _ = callback(last)
                    }
                }
                return
            }
            let h = impl.nextHandle
            impl.register(handle: h) { er in
                queue.async {
                    switch er {
                    case .item(_):
                        let _ = callback(er) && callback(.complete)
                    default:
                        let _ = callback(er)
                    }
                    // Unregister is unnecessary.
                }
            }
        }
    }

    public func onNext(_ item: Item) {
        subjectSyncQueue.async {
            guard self._impl != nil else { return }
            self._last = .item(item)
        }
    }

    public func onComplete() {
        subjectSyncQueue.async {
            guard let impl = self._impl else { return }
            // No items at all.
            guard let last = self._last else {
                impl.emit(item: .complete)
                self._impl = nil
                self._last = .complete
                return
            }
            switch last {
            case .item(_):
                impl.emit(item: last)
                self._impl = nil
            default:
                fatalError("Unreachable.")
            }
        }
    }

    public func onError(_ error: Error) {
        subjectSyncQueue.async {
            guard let impl = self._impl else { return }
            impl.emit(item: .error(error))
            self._impl = nil
            self._last = .error(error)
        }
    }
}

/// `BehaviorSubject` emits the most recent item emitted by
/// the source, or a default item if none has yet been emitted.
///
/// - seealso: [Subject documentation]
///   (http://reactivex.io/documentation/subject.html) on ReactiveX.
public final class BehaviorSubject<I>: Subject {

    public typealias Item = I

    private var _current: EmittingResult<Item>

    private var _impl: SubjectImpl<Item>?

    /// Returns the latest item of the receiver.
    public var latestItem: Item? {
        return _current.item
    }

    public init (initial: Item) {
        self._current = .item(initial)
        self._impl = SubjectImpl<Item>()
    }

    public func subscribe(
        at time: Time,
        on queue: DispatchQueue,
        callback: @escaping (EmittingResult<Item>) -> Bool
    ) {
        subjectSyncQueue.async {
            switch self._current {
            case .item(_):
                guard let impl = self._impl else {
                    queue.async {
                        let _ = callback(self._current) && callback(.complete)
                    }
                    return
                }
                let h = impl.nextHandle
                impl.register(handle: h) { er in
                    queue.async {
                        switch er {
                        case .item(_):
                            if !callback(er) {
                                impl.unregister(handle: h)
                            }
                        default:
                            let _ = callback(er)
                        }
                    }
                }
                let _ = impl.emit(item: self._current, to: h, on: queue)
            case .complete:
                fatalError("Unreachable.")
            case .error(_):
                queue.async {
                    let _ = callback(self._current)
                }
            }
        }
    }

    public func onNext(_ item: Item) {
        subjectSyncQueue.async {
            guard let impl = self._impl else { return }
            self._current = .item(item)
            impl.emit(item: self._current)
        }
    }

    public func onComplete() {
        subjectSyncQueue.async {
            guard let impl = self._impl else { return }
            self._impl = nil
            impl.emit(item: .complete)
        }
    }

    public func onError(_ error: Error) {
        subjectSyncQueue.async {
            guard let impl = self._impl else { return }
            self._impl = nil
            self._current = .error(error)
            impl.emit(item: self._current)
        }
    }
}


/// `PublishSubject` emits only those items that are emitted by the source
///  observable subsequent to the time of the subscription.
///
/// - seealso: [Subject documentation]
///   (http://reactivex.io/documentation/subject.html) on ReactiveX.
public final class PublishSubject<I>: Subject {

    public typealias Item = I

    private var _termination: EmittingResult<Item>? = nil

    private var _impl: SubjectImpl<Item>?

    public init () {
        self._impl = SubjectImpl<Item>()
    }

    public func subscribe(
        at time: Time,
        on queue: DispatchQueue,
        callback: @escaping (EmittingResult<Item>) -> Bool
    ) {
        subjectSyncQueue.async {
            guard let impl = self._impl else {
                assert(self._termination != nil)
                let term = self._termination!
                assert(term.isTermination)
                queue.async {
                    let _ = callback(term)
                }
                return
            }
            let h = impl.nextHandle
            impl.register(handle: h) { er in
                queue.async {
                    switch er {
                    case .item(_):
                        if !callback(er) {
                            impl.unregister(handle: h)
                        }
                    default:
                        let _ = callback(er)
                    }
                }
            }
        }
    }

    public func onNext(_ item: Item) {
        subjectSyncQueue.async {
            guard let impl = self._impl else { return }
            assert(self._termination == nil)
            impl.emit(item: .item(item))
        }
    }

    public func onComplete() {
        subjectSyncQueue.async {
            guard let impl = self._impl else { return }
            self._impl = nil
            self._termination = .complete
            impl.emit(item: .complete)
        }
    }

    public func onError(_ error: Error) {
        subjectSyncQueue.async {
            guard let impl = self._impl else { return }
            self._impl = nil
            self._termination = .error(error)
            impl.emit(item: self._termination!)
        }
    }
}

/// `ReplaySubject` emits to any observer all of the items it receives,
///  regardless of when the observer subscribes.
///
/// - note: `ReplaySubject` does not record the time intervals between items.
///
/// - seealso: [Subject documentation]
///   (http://reactivex.io/documentation/subject.html) on ReactiveX.
public final class ReplaySubject<I>: Subject {

    public typealias Item = I

    private var _records: CircularQueue<Item>

    private var _impl: SubjectImpl<Item>?

    public init (capacity: Int) {
        self._records = CircularQueue<Item>(capacity: Swift.max(capacity + 1, 2))
        self._impl = SubjectImpl<Item>()
    }

    public func subscribe(
        at time: Time,
        on queue: DispatchQueue,
        callback: @escaping (EmittingResult<Item>) -> Bool
    ) {
        subjectSyncQueue.async {
            guard let impl = self._impl else {
                queue.async {
                    for item in self._records.iterator {
                        var cancelled = false
                        switch item {
                        case .item(_):
                            cancelled = !callback(item)
                        default:
                            let _ = callback(item)
                            cancelled = true
                        }
                        if cancelled { break }
                    }
                }
                return
            }
            let h = impl.nextHandle
            impl.register(handle: h) { er in
                queue.async {
                    switch er {
                    case .item(_):
                        if !callback(er) {
                            impl.unregister(handle: h)
                        }
                    default:
                        let _ = callback(er)
                    }
                }
            }
            for item in self._records.iterator {
                guard impl.emit(item: item, to: h, on: queue) else { break }
            }
        }
    }

    public func onNext(_ item: Item) {
        subjectSyncQueue.async {
            guard let impl = self._impl else { return }
            let e: EmittingResult<Item> = .item(item)
            impl.emit(item: e)
            self._records.push(item: e)
        }
    }

    public func onComplete() {
        subjectSyncQueue.async {
            guard let impl = self._impl else { return }
            self._records.push(item: .complete)
            self._impl = nil
            impl.emit(item: .complete)
        }
    }

    public func onError(_ error: Error) {
        subjectSyncQueue.async {
            guard let impl = self._impl else { return }
            let e: EmittingResult<Item> = .error(error)
            self._records.push(item: e)
            self._impl = nil
            impl.emit(item: e)
        }
    }
}

// MARK: Creating

extension Observable {

    /// Creates an `Observale` that emits items produced by a generator
    /// function.
    ///
    /// - example:
    ///
    /// ```swift
    /// Observable.generate(
    ///     first: 1,
    ///     until: { $0 > 100 }
    ///     next: { $0 + 1 }
    /// )
    /// ```
    public static func generate(
        first: Item,
        until: @escaping (Item) -> Bool,
        next: @escaping (Item) throws -> Item
    ) -> Observable<Item> {
        return Observable<Item>.init() { _, _, cb in
            var pi = first
            if until(pi) {
                let _ = cb(.complete)
                return
            }
            while cb(.item(pi)) {
                do {
                    pi = try next(pi)
                } catch {
                    let _ = cb(.error(error))
                    break
                }
                if until(pi) {
                    let _ = cb(.complete)
                    break
                }
            }
        }
    }

    /// Creates an `Observable` that emits no items but terminates normally.
    ///
    /// - seealso: [`Empty` operator documentation]
    ///   (http://reactivex.io/documentation/operators/empty-never-throw.html) on ReactiveX.
    public static func empty() -> Observable<Item> {
        return Observable<Item>() { _, _, cb in
            let _ = cb(.complete)
        }
    }

    /// Creates an `Observable` that emits no items and terminates with an
    /// error.
    ///
    /// - seealso: [`Throw` operator documentation]
    ///   (http://reactivex.io/documentation/operators/empty-never-throw.html) on ReactiveX.
    public static func error(_ err: Error) -> Observable<Item> {
        return Observable<Item>() { _, _, cb in
            let _ = cb(.error(err))
        }
    }

    /// Creates an `Observable` from a `Sequence`.
    ///
    /// - seealso: [`From` operator documentation]
    ///   (http://reactivex.io/documentation/operators/from.html) on ReactiveX.
    public static func from<S: Sequence>(sequence: S) -> Observable<Item>
        where S.Iterator.Element == Item
    {
        return Observable<Item>() { _, _, cb in
            var iter = sequence.makeIterator()
            while let itm = iter.next() {
                guard cb(.item(itm)) else { return }
            }
            let _ = cb(.complete)
        }
    }

    /// Creates an `Observable` that only emits the given item and then
    /// completes.
    ///
    /// - seealso: [`Just` operator documentation]
    ///   (http://reactivex.io/documentation/operators/just.html) on ReactiveX.
    public static func just(_ item: Item) -> Observable<Item> {
        return Observable<Item>() { _, _, cb in
            let _ = cb(.item(item)) && cb(.complete)
        }
    }

    /// Creates an `Observable` that does not emit anything.
    ///
    /// - seealso: [`Never` operator documentation]
    ///   (http://reactivex.io/documentation/operators/empty-never-throw.html) on ReactiveX.
    public static func never() -> Observable<Item> {
        return Observable<Item>() { _, _, _ in }
    }

    /// Creates an `Observable` that emits given item repeatedly.
    ///
    /// - seealso: [`Repeat` operator documentation]
    ///   (http://reactivex.io/documentation/operators/repeat.html) on ReactiveX.
    public static func `repeat`(_ item: Item, count: Int) -> Observable<Item> {
        return Observable<Item>() { _, _, cb in
            var i = 0
            while i < count {
                guard cb(.item(item)) else { return }
                i += 1
            }
            let _ = cb(.complete)
        }
    }

    /// Creates an `Observable` that emits the return value of given
    /// closure.
    ///
    /// - seealso: [`Start` operator documentation]
    ///   (http://reactivex.io/documentation/operators/start.html) on ReactiveX.
    public static func start(_ operation: @autoclosure @escaping () -> Item) -> Observable<Item> {
        return Observable<Item>() { _, _, cb in
            let _ = cb(.item(operation())) && cb(.complete)
        }
    }

    /// Creates an `Observable` that emits given item at given time.
    /// If `at` is a past time, it emits nothing.
    ///
    /// - seealso: [`Timer` operator documentation]
    ///   (http://reactivex.io/documentation/operators/timer.html) on ReactiveX.
    public static func timer(_ item: Item, at: Time) -> Observable<Item> {
        return Observable<Item>() { _, q, cb in
            guard Time.now < at else {
                let _ = cb(.complete)
                return
            }
            let ns = DispatchTime.now() + (at - Time.now).seconds
            q.asyncAfter(deadline: ns) {
                let _ = cb(.item(item)) && cb(.complete)
            }
        }
    }

    /// Creates an `Observable` that emits given item after a given delay.
    ///
    /// - seealso: [`Timer` operator documentation]
    ///   (http://reactivex.io/documentation/operators/timer.html) on ReactiveX.
    public static func timer(_ item: Item, after: TimeInterval) -> Observable<Item> {
        return Observable<Item>() { t, q, cb in
            assert(t <= Time.now)
            let ns = DispatchTime.now() + (after - (Time.now - t)).seconds
            q.asyncAfter(deadline: ns) {
                let _ = cb(.item(item)) && cb(.complete)
            }
        }
    }
}

extension Observable where Item == Int {

    /// Creates an `Observable` that emits a sequence of intergers spaced
    /// by a given time interval.
    ///
    /// - seealso: [`Interval` operator documentation]
    ///   (http://reactivex.io/documentation/operators/interval.html) on ReactiveX.
    public static func interval(_ ti: TimeInterval) -> Observable<Int> {
        return Observable<Int>() { t, q, cb in
            var i = 0
            func schedule() {
                guard cb(.item(i)) else { return }
                i += 1
                let et = ti * i
                let now = Time.now - t
                guard et > now else {
                    q.async { schedule() }
                    return
                }
                let after = et - now
                q.asyncAfter(deadline: DispatchTime.now() + after.seconds) {
                    schedule()
                }
            }
            q.async { schedule() }
        }
    }

    /// Creates an `Observable` that emits a particular range of sequential
    /// integers.
    ///
    /// - seealso: [`Range` operator documentation]
    ///   (http://reactivex.io/documentation/operators/range.html) on ReactiveX.
    public static func range(start: Int, count: Int) -> Observable<Int> {
        return Observable<Int>() { _, _, cb in
            var i = start
            while i < start + count {
                guard cb(.item(i)) else { return }
                i += 1
            }
            let _ = cb(.complete)
        }
    }
}

// MARK: Transforming

extension ObservableProtocol {

    /// Returns an `Observable` that forwards anything the receiver emits.
    public func mirror() -> Observable<Item> {
        return Observable<Item> { t, q, cb in
            self.subscribe(at: t, on: q, callback: { er in
                switch er {
                case .item(_):
                    return cb(er)
                default:
                    let _ = cb(er)
                }
                return false
            })
        }
    }

    /// Returns an `Observable` that periodically gather items emitted by the
    /// receiver into bundles and emits these bundles rather than emitting the
    /// items one at a time.
    ///
    /// - seealso: [`Buffer` operator documentation]
    ///   (http://reactivex.io/documentation/operators/buffer.html) on ReactiveX.
    public func buffer(count: Int) -> Observable<[Item]> {
        guard count > 0 else {
            return Observable<[Item]>.empty()
        }
        return Observable<[Item]>() { t, q, cb in
            var buf: [Item] = []
            self.subscribe(at: t, on: q) { er in
                switch er {
                case let .item(itm):
                    buf.append(itm)
                    guard buf.count < count else {
                        let b = cb(.item(buf))
                        buf = []
                        return b
                    }
                    return true
                case let .error(e):
                    let _ = cb(.error(e))
                case .complete:
                    if buf.count > 0 {
                        let _ = cb(.item(buf)) && cb(.complete)
                        buf = []
                    } else {
                        let _ = cb(.complete)
                    }
                }
                return false
            }
        }
    }

    /// Transform the items emitted by an observable into Observables,
    /// then flatten the emissions from those into a single Observable.
    ///
    /// - note: The result `Observable` is terminated when:
    ///   1. Error is emitted by either the receiver or any generated
    ///      Observables.
    ///   2. The receiver and all generated observables complete.
    ///
    /// - seealso: ['FlatMap' operator documentation]
    ///   (http://reactivex.io/documentation/operators/flatmap.html) on ReactiveX.
    public func flatMap<T>(
        _ operation: @escaping (Item) -> Observable<T>
    ) -> Observable<T> {
        return Observable<T>() { t, q, cb in
            var count = 1
            var isTerminated = false
            let lcb = { (er: EmittingResult<T>) -> Bool in
                guard !isTerminated else {
                    return false
                }
                switch er {
                case .item(_):
                    q.async {
                        isTerminated = !cb(er)
                    }
                    return true
                case .complete:
                    count -= 1
                    if count == 0 {
                        q.async {
                            let _ = cb(.complete)
                        }
                    }
                case .error(_):
                    q.async {
                        let _ = cb(er)
                    }
                    isTerminated = true
                }
                return false
            }
            self.observe(on: emittingQueue)
                .subscribe(at: t, on: serialQueue, callback: { er in
                guard !isTerminated else {
                    return false
                }
                switch er {
                case let .item(itm):
                    let o = operation(itm)
                    count += 1
                    o.observe(on: emittingQueue).subscribe(at: t, on: serialQueue, callback: lcb)
                    return true
                case .complete:
                    count -= 1
                    if count == 0 {
                        q.async {
                            let _ = cb(.complete)
                        }
                    }
                case let .error(e):
                    q.async {
                        let _ = cb(.error(e))
                    }
                    isTerminated = true
                }
                return false
            })
        }
    }

    /// Transforms the emission of the receiver into `Observable`s, and returns
    /// an `Observable` that emits the items emitted by the latest one.
    ///
    /// - note: This operator is also called `SwitchMap`.
    ///
    /// - seealso: ['FlatMap' operator documentation]
    ///   (http://reactivex.io/documentation/operators/flatmap.html) on ReactiveX.
    public func flatMapLatest<T>(
        _ operation: @escaping (Item) -> Observable<T>
    ) -> Observable<T> {
        return Observable<T> { t, q, cb in
            var i = -1
            var count = 1
            var isTerminated = false
            func subscribe(_ o: Observable<T>, tag: Int) {
                o.observe(on: emittingQueue).subscribe(at: Time.now, on: serialQueue) { er in
                    guard i == tag else {
                        return false
                    }
                    switch er {
                    case .item(_):
                        q.async {
                            isTerminated = !cb(er)
                        }
                        return true
                    case .complete:
                        count -= 1
                        if count == 0 {
                            q.async {
                                let _ = cb(.complete)
                            }
                        }
                    case .error(_):
                        q.async {
                            let _ = cb(er)
                        }
                        isTerminated = true
                    }
                    return false
                }
            }
            self.observe(on: emittingQueue).subscribe(at: t, on: serialQueue) { er in
                switch er {
                case let .item(o):
                    i += 1
                    if count == 1 {
                        count = 2
                    }
                    let tag = i
                    q.async {
                        subscribe(operation(o), tag: tag)
                    }
                    return true
                case .complete:
                    count -= 1
                    if count == 0 {
                        q.async {
                            let _ = cb(.complete)
                        }
                    }
                case let .error(e):
                    q.async {
                        let _ = cb(.error(e))
                        isTerminated = true
                    }
                }
                return false
            }
        }
    }

    /// Returns an `Observable` that divides the emission of the receiver
    /// into a set of `Observable`s. The division is based on a selector
    /// function.
    ///
    /// - note: Cancellation of the receiver does not stop the emission of
    ///   emitted `Observable`s.
    ///
    /// - note: Observables emitted by the result `Observable` are _hot_
    ///   even if the receiver is _cold_. See (Observalbe documentation)
    ///   (http://reactivex.io/documentation/observable.html) on ReactiveX.
    ///
    /// - seealso: ['GroupBy' operator documentation]
    ///   (http://reactivex.io/documentation/operators/groupby.html) on ReactiveX.
    public func group<Key>(
        by selector: @escaping (Item) -> Key
    ) -> Observable<Observable<Item>> where Key: Hashable {
        return Observable<Observable<Item>> { t, q, cb in
            var os: [Key:BehaviorSubject<Item>] = [:]
            var isCancelled = false
            self.observe(on: emittingQueue)
                .subscribe(at: t, on: serialQueue, callback: { er in
                switch er {
                case let .item(itm):
                    // TODO: Remove cancelled Observables in `os`.
                    let key = selector(itm)
                    if let o = os[key] {
                        o.onNext(itm)
                    } else {
                        guard !isCancelled else {
                            return !os.isEmpty
                        }
                        let o = BehaviorSubject<Item>(initial: itm)
                        os[key] = o
                        q.async {
                            isCancelled = !cb(.item(o.mirror()))
                        }
                    }
                    return true
                case .complete:
                    if (!isCancelled) {
                        q.async {
                            let _ = cb(.complete)
                        }
                    }
                    for o in os.values {
                        o.onComplete()
                    }
                case let .error(e):
                    if (!isCancelled) {
                        q.async {
                            let _ = cb(.error(e))
                        }
                    }
                    for o in os.values {
                        o.onError(e)
                    }
                }
                return false
            })
        }
    }

    /// Returns an `Observable` that transforms the items emitted by the
    /// receiver by applying a function to each item.
    ///
    /// - seealso: ['Map' operator documentation]
    ///   (http://reactivex.io/documentation/operators/map.html) on ReactiveX.
    public func map<T>(
        _ operation: @escaping (Item) -> T
    ) -> Observable<T> {
        return Observable<T>() { t, q, cb in
            self.subscribe(at: t, on: q) { er in
                switch er {
                case let .item(itm):
                    return cb(.item(operation(itm)))
                case .complete:
                    let _ = cb(.complete)
                case let .error(e):
                    let _ = cb(.error(e))
                }
                return false
            }
        }
    }

    /// Returns an `Observable` that applies an function to each item
    /// emitted by the receiver, sequentially, and emit each successive value.
    ///
    /// - seealso: ['Scan' operator documentation]
    ///   (http://reactivex.io/documentation/operators/scan.html) on ReactiveX.
    public func scan(
        _ operation: @escaping (Item, Item) -> Item
    ) -> Observable<Item> {
        return Observable<Item> { t, q, cb in
            var acc: Item? = nil
            self.subscribe(at: t, on: q) { er in
                switch er {
                case let .item(itm):
                    guard let pv = acc else {
                        acc = itm
                        return cb(er)
                    }
                    acc = operation(pv, itm)
                    return cb(.item(acc!))
                default:
                    let _ = cb(er)
                    return false
                }
            }
        }
    }

    /// Returns an `Observable` that subdivides items emitted by the
    /// receiver into `Observable` windows and emits these windows.
    ///
    /// The subdivision is determined by a condition function. When the
    /// function returns `true`, current window completes and a new window
    /// is created and emitted.
    ///
    /// - note: Cancellation of the receiver does not stop the emission of
    ///   emitted `Observable`s.
    ///
    /// - note: Observables emitted by the result `Observable` are _hot_
    ///   even if the receiver is _cold_. See (Observalbe documentation)
    ///   (http://reactivex.io/documentation/observable.html) on ReactiveX.
    ///
    /// - seealso: ['Window' operator documentation]
    ///   (http://reactivex.io/documentation/operators/window.html) on ReactiveX.
    public func window(
        by cond: @escaping (Item, TimeInterval) -> Bool
    ) -> Observable<Observable<Item>> {
        return Observable<Observable<Item>> { t, q, cb in
            var o: BehaviorSubject<Item>? = nil
            var isCancelled = false
            self.subscribe(at: t, on: q, callback: { er in
                switch er {
                case let .item(itm):
                    if o == nil || cond(itm, Time.now - t) {
                        o?.onComplete()
                        if (!isCancelled) {
                            o = BehaviorSubject<Item>(initial: itm)
                            isCancelled = !cb(.item(o!.mirror()))
                            return true
                        } else {
                            o = nil
                            return false
                        }
                    } else {
                        o?.onNext(itm)
                        return true
                    }
                case .complete:
                    o?.onComplete()
                    if (!isCancelled) {
                        let _ = cb(.complete)
                    }
                case let .error(e):
                    o?.onError(e)
                    if (!isCancelled) {
                        let _ = cb(.error(e))
                    }
                }
                return false
            })
        }
    }

    /// A variety of the `Window` operator. This method closes current window
    /// if its life span exceeds given time interval.
    ///
    /// - seealso: ['Window' operator documentation]
    ///   (http://reactivex.io/documentation/operators/window.html) on ReactiveX.
    ///
    /// - seealso: `window(by:)`
    public func windowWith(timer: TimeInterval) -> Observable<Observable<Item>> {
        var t = TimeInterval.zero
        return self.window(by: { _, now in
            guard now - t < timer else {
                t = now
                return true
            }
            return false
        })
    }

    /// A variety of the `Window` operator. This method closes current
    /// window if the nubmer of items it emitted equals to given number.
    ///
    /// - seealso: ['Window' operator documentation]
    ///   (http://reactivex.io/documentation/operators/window.html) on ReactiveX.
    ///
    /// - seealso: `window(by:)`
    public func windowWith(count: Int) -> Observable<Observable<Item>> {
        return self.zipWithIndex().window(by: { z, _ in
            return count < 1 || z.1 % count == 0
        }).map { $0.map { $0.0 } }
    }

    /// Returns an `Observable` that transforms each item emitted by the
    /// receiver to a pair of the item and its index.
    ///
    /// - note: The index is 0-based, of course.
    public func zipWithIndex() -> Observable<(Item, Int)> {
        return Observable<(Item, Int)> { t, q, cb in
            var i = -1
            return self.subscribe(at: t, on: q) { er in
                switch er {
                case let .item(itm):
                    i += 1
                    return cb(.item((itm, i)))
                case .complete:
                    let _ = cb(.complete)
                case let .error(e):
                    let _ = cb(.error(e))
                }
                return false
            }
        }
    }
}

// MARK: Filtering

extension ObservableProtocol {

    /// Returns an `Observable` that only emit an item from an Observable if a
    /// particular timespan has passed without it emitting another item.
    ///
    /// - seealso: ['Debounce' operator documentation]
    ///   (http://reactivex.io/documentation/operators/debounce.html) on ReactiveX.
    ///
    /// - seealso: `throttle()`
    public func debounce(_ ti: TimeInterval) -> Observable<Item> {
        return Observable<Item> { t, q, cb in
            var st = Time.now - ti
            self.subscribe(at: t, on: q) { er in
                switch er {
                case .item(_):
                    let now = Time.now
                    guard now - st > ti else {
                        st = now
                        return true
                    }
                    st = now
                    return cb(er)
                default:
                    let _ = cb(er)
                }
                return false
            }
        }
    }

    /// Returns an `Observable` that only emits the `i`th item emitted by
    /// the receiver.
    ///
    /// - seealso: ['ElementAt' operator documentation]
    ///   (http://reactivex.io/documentation/operators/elementat.html) on ReactiveX.
    public func element(at i: Int) -> Observable<Item> {
        guard i >= 0 else {
            return Observable<Item>.empty()
        }
        return Observable<Item>() { t, q, cb in
            var j = 0
            self.subscribe(at: t, on: q) { er in
                switch er {
                case .item(_):
                    guard j >= i else {
                        j += 1
                        return true
                    }
                    guard j == i else { fatalError("Unreachable.") }
                    let _ =  cb(er) && cb(.complete)
                default:
                    let _ = cb(er)
                }
                return false
            }
        }
    }

    /// Returns an `Observable` that emits only items from the receiver that
    /// pass a predication test.
    ///
    /// - seealso: ['Filter' operator documentation]
    ///   (http://reactivex.io/documentation/operators/filter.html) on ReactiveX.
    public func filter(
        _ predication: @escaping (Item) -> Bool
    ) -> Observable<Item> {
        return Observable<Item>() { t, q, cb in
            self.subscribe(at: t, on: q) { er in
                switch er {
                case let .item(itm):
                    guard predication(itm) else { return true }
                    return cb(er)
                default:
                    let _ = cb(er)
                }
                return false
            }
        }
    }

    /// Returns an `Observable` that emits only the first item, or the first
    /// item that meets a condition, of the receiver.
    ///
    /// - seealso: ['First' operator documentation]
    ///   (http://reactivex.io/documentation/operators/first.html) on ReactiveX.
    public func first(
        _ cond: @escaping (Item) -> Bool = { _ in true }
    ) -> Observable<Item> {
        return Observable<Item>() { t, q, cb in
            self.subscribe(at: t, on: q) { er in
                switch er {
                case let .item(itm):
                    guard cond(itm) else { return true }
                    let _ = cb(er) && cb(.complete)
                default:
                    let _ = cb(er)
                }
                return false
            }
        }
    }

    /// Returns an `Observable` that only emits the termination notification of
    /// the receiver.
    ///
    /// - seealso: ['IgnoreElements' operator documentation]
    ///   (http://reactivex.io/documentation/operators/ignoreelements.html) on ReactiveX.
    public func ignore() -> Observable<Item> {
        return Observable<Item>() { t, q, cb in
            self.subscribe(at: t, on: q) { er in
                switch er {
                case .item(_):
                    return true
                default:
                    let _ = cb(er)
                }
                return false
            }
        }
    }

    /// Returns an `Observable` that emits only the last item emitted by the
    /// receiver.
    ///
    /// - seealso: ['Last' operator documentation]
    ///   (http://reactivex.io/documentation/operators/last.html) on ReactiveX.
    public func last() -> Observable<Item> {
        return Observable<Item>() { t, q, cb in
            var last: EmittingResult<Item> = .complete
            self.subscribe(at: t, on: q) { er in
                switch er {
                case .item(_):
                    last = er
                    return true
                case .complete:
                    switch last {
                    case .item(_):
                        let _ = cb(last) && cb(.complete)
                    default:
                        let _ = cb(er)
                    }
                case .error(_):
                    let _ = cb(er)
                }
                return false
            }
        }
    }

    /// Returns an `Observable` that emits the most recent item emitted by
    /// receiver at the time the given sampler observable emits an item.
    ///
    /// - note: If both `sampler` and the receiver are cold observables,
    ///   the `sampler` starts *after* the receiver starts. There is a latency
    ///   between them.
    ///
    /// - note: If the receiver is terminated, normally or by error, the
    ///   result `Observable` does not terminate.
    ///
    /// - seealso: ['Sample' operator documentation]
    ///   (http://reactivex.io/documentation/operators/sample.html) on ReactiveX.
    ///
    /// - seealso: `sample(interval:)`
    public func sample<O: ObservableProtocol>(_ sampler: O) -> Observable<Item> {
        return Observable<Item>() { t, q, cb in
            var latest: Item? = nil
            //
            var cancelled = false
            self.subscribe(at: t, on: q) { er in
                guard !cancelled else { return false }
                switch er {
                case let .item(itm):
                    latest = itm
                    return true
                default:
                    return false
                }
            }
            sampler.subscribe(at: t, on: q) { er in
                assert(!cancelled)
                switch er {
                case .item(_):
                    guard let li = latest else {
                        // Sampled but no item.
                        return true
                    }
                    cancelled = !cb(.item(li))
                    return !cancelled
                case .complete:
                    let _ = cb(.complete)
                case let .error(e):
                    let _ = cb(.error(e))
                }
                cancelled = true
                return false
            }
        }
    }

    /// Samples the receiver with fixed time intervals.
    ///
    /// - seealso: `sample(:)`
    public func sample(interval ti: TimeInterval) -> Observable<Item> {
        return self.sample(Observable.interval(ti))
    }

    /// Returns an `Observable` that mirrors the receiver but discards items
    /// until a specified condition becomes false.
    ///
    /// - seealso: ['SkipWhile' operator documentation]
    ///   (http://reactivex.io/documentation/operators/skipwhile.html) on ReactiveX.
    public func skip(while cond: @escaping (Item) -> Bool) -> Observable<Item> {
        return Observable<Item> { t, q, cb in
            var skipping = true
            self.subscribe(at: t, on: q) { er in
                switch er {
                case let .item(itm):
                    if skipping { skipping = cond(itm) }
                    if skipping { return true }
                    return cb(er)
                default:
                    let _ = cb(er)
                }
                return false
            }
        }
    }

    /// Returns an `Observable` that mirrors the receiver but suppress the
    /// first `count` items.
    ///
    /// - seealso: ['Skip' operator documentation]
    ///   (http://reactivex.io/documentation/operators/skip.html) on ReactiveX.
    public func skip(_ count: Int) -> Observable<Item> {
        guard count > 0 else {
            return self.mirror()
        }
        return self.zipWithIndex().skip(while: {
            return $0.1 < count
        }).map { $0.0 }
    }

    /// Returns an `Observable` that mirrors the receiver but suppress the
    /// last `n` items.
    ///
    /// - seealso: ['Skip' operator documentation]
    ///   (http://reactivex.io/documentation/operators/skip.html) on ReactiveX.
    public func skip(last n: Int) -> Observable<Item> {
        guard n > 0 else {
            return self.mirror()
        }
        return Observable<Item> { t, q, cb in
            var cq = CircularQueue<Item>(capacity: n)
            self.subscribe(at: t, on: q) { er in
                switch er {
                case .item(_):
                    if cq.isFull {
                        let h = cq.head!
                        assert(!h.isTermination)
                        cq.push(item: er)
                        return cb(h)
                    }
                    cq.push(item: er)
                    return true
                default:
                    let _ = cb(er)
                }
                return false
            }
        }
    }

    /// Returns an `Observable` that mirrors the receiver but discards items
    /// until a specified observable emits an item or terminates.
    ///
    /// - seealso: ['SkipUntil' operator documentation]
    ///   (http://reactivex.io/documentation/operators/skipuntil.html) on ReactiveX.
    public func skip<O: ObservableProtocol>(until cond: O) -> Observable<Item> {
        return Observable<Item> { t, q, cb in
            var stop = false
            self.subscribe(at: t, on: q, callback: { er in
                switch er {
                case .item(_):
                    if stop { return cb(er) }
                    return true
                default:
                    let _ = cb(er)
                }
                return false
            })
            cond.subscribe(at: t, on: emittingQueue, callback: { er in
                stop = true
                return false
            })
        }
    }

    /// Returns an `Observable` that mirrors items emitted by the receiver
    /// until given condition becomes false.
    ///
    /// - seealso: ['TakeWhile' operator documentation]
    ///   (http://reactivex.io/documentation/operators/takewhile.html) on ReactiveX.
    public func take(while cond: @escaping (Item) -> Bool) -> Observable<Item> {
        return Observable<Item>() { t, q, cb in
            self.subscribe(at: t, on: q) { er in
                switch er {
                case let .item(itm):
                    guard cond(itm) else {
                        let _ = cb(.complete)
                        return false
                    }
                    return cb(er)
                default:
                    let _ = cb(er)
                    return false
                }
            }
        }
    }

    /// Returns an `Observable` that emits only the first `count` items
    /// emitted by the receiver.
    ///
    /// - seealso: ['Take' operator documentation]
    ///   (http://reactivex.io/documentation/operators/take.html) on ReactiveX.
    public func take(_ count: Int) -> Observable<Item> {
        guard count > 0 else {
            return Observable<Item>.empty()
        }
        return zipWithIndex().take(while: {
            $0.1 < count
        }).map { $0.0 }
    }

    /// Returns an `Observable` that emits only the final `n` items emitted
    /// by the receiver.
    ///
    /// - seealso: ['TakeLast' operator documentation]
    ///   (http://reactivex.io/documentation/operators/takelast.html) on ReactiveX.
    public func take(last n: Int) -> Observable<Item> {
        guard n > 0 else {
            return self.mirror()
        }
        return Observable<Item> { t, q, cb in
            var cq = CircularQueue<Item>(capacity: n)
            self.subscribe(at: t, on: q) { er in
                switch er {
                case .item(_):
                    cq.push(item: er)
                    return true
                case .complete:
                    for i in cq.iterator {
                        if !cb(i) {
                            return false
                        }
                    }
                    let _ = cb(.complete)
                case .error(_):
                    let _ = cb(er)
                }
                return false
            }
        }
    }

    /// Returns an `Observable` that discards any items emitted by the
    /// receiver after a second observable emits an item or terminates.
    ///
    /// - seealso: ['TakeUntil' operator documentation]
    ///   (http://reactivex.io/documentation/operators/takeuntil.html) on ReactiveX.
    public func take<O: ObservableProtocol>(until cond: O) -> Observable<Item> {
        return Observable<Item> { t, q, cb in
            var stop = false
            cond.subscribe(at: t, on: emittingQueue, callback: { er in
                stop = true
                return false
            })
            self.subscribe(at: t, on: q, callback: { er in
                switch er {
                case .item(_):
                    if !stop { return cb(er) }
                    let _ = cb(.complete)
                default:
                    let _ = cb(er)
                }
                return false
            })
        }
    }

    /// Returns an `Observable` that mirrors the receiver, but for each
    /// periodic time interval, only emits the first item within it.
    ///
    /// - seealso: `debounce()`
    public func throttle(_ rate: TimeInterval) -> Observable<Item> {
        guard !rate.isZero else {
            return self.mirror()
        }
        return Observable<Item> { t, q, cb in
            var i = 0.0
            self.subscribe(at: t, on: q) { er in
                switch er {
                case .item(_):
                    let span = Time.now - t
                    if span > rate * i {
                        let b = cb(er)
                        if b {
                            i = (span.seconds / rate.seconds).rounded(.down) + 1
                        }
                        return b
                    }
                    return true
                default:
                    let _ = cb(er)
                }
                return false
            }
        }
    }
}

extension ObservableProtocol where Item: Equatable {

    /// Returns an `Observable` that mirrors the emission of the receiver
    /// but drops items that
    ///
    /// - note: This method's behavior is actually `DistinctUntilChange`
    ///
    /// - seealso: ['Distinct' operator documentation]
    ///   (http://reactivex.io/documentation/operators/distinct.html) on ReactiveX.
    ///
    /// - seealso: `uniq()`
    public func distinct() -> Observable<Item> {
        return Observable<Item>() { t, q, cb in
            var last: Item? = nil
            self.subscribe(at: t, on: q) { er in
                switch er {
                case let .item(itm):
                    guard let pv = last else {
                        last = itm
                        return cb(er)
                    }
                    last = itm
                    return (pv == itm) || cb(er)
                default:
                    let _ = cb(er)
                }
                return false
            }
        }
    }
}

extension ObservableProtocol where Item: Hashable {

    /// Returns an `Observable` that mirrors the emission of the receiver
    /// but suppress all duplicated items.
    ///
    /// - note: This method
    ///
    /// - seealso: ['Distinct' operator documentation]
    ///   (http://reactivex.io/documentation/operators/distinct.html) on ReactiveX.
    ///
    /// - seealso: `distinct()`
    public func uniq() -> Observable<Item> {
        return Observable<Item> { t, q, cb in
            var keys = Set<Int>.init()
            self.subscribe(at: t, on: q, callback: { er in
                switch er {
                case let .item(itm):
                    let key = itm.hashValue
                    guard !keys.contains(key) else {
                        return true
                    }
                    keys.insert(key)
                    return cb(er)
                default:
                    let _ = cb(er)
                }
                return false
            })
        }
    }
}

// MARK: Combining

extension ObservableProtocol {

    /// Returns an `Observable` that emits a tuple, which combines the lastest
    /// items emitted by the receiver and another observable.
    ///
    /// - seealso: ['Merge' operator documentation]
    ///   (http://reactivex.io/documentation/operators/merge.html) on ReactiveX.
    ///
    /// - seealso: `zip(:)`
    public func combine<O: ObservableProtocol>(
        latest that: O
    ) -> Observable<(Item, O.Item)> {
        return Observable<(Item, O.Item)> { t, q, cb in
            var left: Item? = nil
            var right: O.Item? = nil
            var count = 2
            var isTerminated = false

            self.observe(on: emittingQueue)
                .subscribe(at: t, on: serialQueue, callback: { er in
                guard !isTerminated else { return false }
                switch er {
                case let .item(itm):
                    left = itm
                    guard let ri = right else { return true }
                    q.async {
                        isTerminated = !cb(.item((itm, ri)))
                    }
                    return true
                case .complete:
                    count -= 1
                    if count == 0 {
                        q.async {
                            let _ = cb(.complete)
                        }
                    }
                case let .error(e):
                    isTerminated = true
                    q.async {
                        let _ = cb(.error(e))
                    }
                }
                return false
            })
            that.observe(on: emittingQueue)
                .subscribe(at: t, on: serialQueue, callback: { er in
                guard !isTerminated else { return false }
                switch er {
                case let .item(itm):
                    right = itm
                    guard let li = left else { return true }
                    q.async {
                        isTerminated = !cb(.item((li, itm)))
                    }
                    return true
                case .complete:
                    count -= 1
                    if count == 0 {
                        q.async {
                            let _ = cb(.complete)
                        }
                    }
                case let .error(e):
                    isTerminated = true
                    q.async {
                        let _ = cb(.error(e))
                    }
                }
                return false
            })
        }
    }

    /// Returns an `Observable` that
    ///
    /// - note: In other Rx implementations, this method is normally called
    ///   `withLatestFrom`.
    ///
    /// - seealso: ['Merge' operator documentation]
    ///   (http://reactivex.io/documentation/operators/merge.html) on ReactiveX.
    public func zipWith<O: ObservableProtocol>(latest that: O) -> Observable<(Item, O.Item)> {
        return Observable<(Item, O.Item)> { t, q, cb in
            var right: O.Item? = nil
            var isTerminated = false
            self.observe(on: emittingQueue)
                .subscribe(at: t, on: serialQueue, callback: { er in
                guard !isTerminated else { return false }
                switch er {
                case let .item(itm):
                    guard let ri = right else { return true }
                    q.async {
                        isTerminated = !cb(.item((itm, ri)))
                    }
                    return true
                case .complete:
                    q.async {
                        let _ = cb(.complete)
                    }
                case let .error(e):
                    q.async {
                        let _ = cb(.error(e))
                    }
                }
                isTerminated = true
                return false
            })
            that.observe(on: emittingQueue)
                .subscribe(at: t, on: serialQueue, callback: { er in
                guard !isTerminated else { return false }
                switch er {
                case let .item(itm):
                    right = itm
                    return true
                case .complete:
                    break
                case let .error(e):
                    isTerminated = true
                    q.async {
                        let _ = cb(.error(e))
                    }
                }
                return false
            })
        }
    }

    /// Returns an `Observable` that combines the emissions of multiple
    /// observables into one.
    ///
    /// - seealso: ['Merge' operator documentation]
    ///   (http://reactivex.io/documentation/operators/merge.html) on ReactiveX.
    ///
    /// - seealso: `flatMap(:)`.
    public static func merge<O: ObservableProtocol>(_ os: O...) -> Observable<Item> where O.Item == Item {
        return Observable.from(sequence: os).merge()
    }

    /// Returns an `Observable` that emits items of given observale before
    /// mirrors the receiver.
    ///
    /// - seealso: ['StartWith' operator documentation]
    ///   (http://reactivex.io/documentation/operators/startwith.html) on ReactiveX.
    public func start<O: ObservableProtocol>(with that: O) -> Observable<Item> where O.Item == Item {
        return Observable<Item> { t, q, cb in
            that.subscribe(at: t, on: q) { er in
                switch er {
                case .item(_): return cb(er)
                case .complete:
                    self.subscribe(at: t, on: q) { er in
                        switch er {
                        case .item(_): return cb(er)
                        default: let _ = cb(er)
                        }
                        return false
                    }
                case .error(_):
                    let _ = cb(er)
                }
                return false
            }
        }
    }

    /// Returns an `Observable` that combines the emissions of two
    /// observables into a pair of items.
    ///
    /// - note: For simplicity reason, the behavior of this method is not
    ///   same as standard `Zip` operator but it is easily achieved by
    ///   composing operators.
    ///
    /// - seealso: ['Zip' operator documentation]
    ///   (http://reactivex.io/documentation/operators/zip.html) on ReactiveX.
    public func zip<O: ObservableProtocol>(_ that: O) -> Observable<(Item, O.Item)> {
        return Observable<(Item, O.Item)> { t, q, cb in
            var left = CircularQueue<Item>(capacity: 4, fixed: false)
            var right = CircularQueue<O.Item>(capacity: 4, fixed: false)
            var isTerminated = false

            self.observe(on: emittingQueue)
                .subscribe(at: t, on: serialQueue) { er in
                guard !isTerminated else { return false }
                switch er {
                case let .item(itm):
                    let rr = right.pop()
                    guard let r = rr else {
                        left.push(item: er)
                        return true
                    }
                    switch r {
                    case .complete:
                        q.async {
                            let _ = cb(.complete)
                        }
                        isTerminated = true
                    case let .item(ri):
                        q.async {
                            isTerminated = !cb(.item((itm, ri)))
                        }
                    default:
                        fatalError("Unreachable.")
                    }
                    return true
                case .complete:
                    if left.count == 0 {
                        q.async {
                            let _ = cb(.complete)
                        }
                        isTerminated = true
                    } else {
                        left.push(item: .complete)
                    }
                case let .error(e):
                    q.async {
                        let _ = cb(.error(e))
                    }
                    isTerminated = true
                }
                return false
            }
            that.observe(on: emittingQueue)
                .subscribe(at: t, on: serialQueue) { er in
                guard !isTerminated else { return false }
                switch er {
                case let .item(itm):
                    guard let l = left.pop() else {
                        right.push(item: er)
                        return true
                    }
                    switch l {
                    case .complete:
                        q.async {
                            let _ = cb(.complete)
                        }
                        isTerminated = true
                        return false
                    case let .item(li):
                        q.async {
                            isTerminated = !cb(.item((li, itm)))
                        }
                    default:
                        fatalError("Unreachable.")
                    }
                    return true
                case .complete:
                    if right.count == 0 {
                        q.async {
                            let _ = cb(.complete)
                        }
                        isTerminated = true
                    } else {
                        right.push(item: .complete)
                    }
                case let .error(e):
                    q.async {
                        let _ = cb(.error(e))
                    }
                    isTerminated = true
                }
                return false
            }
        }
    }
}

extension ObservableProtocol where Item: ObservableProtocol {

    /// Returns an `Observable` that combines the observables emitted by the
    /// receiver into one.
    ///
    /// - seealso: ['Merge' operator documentation]
    ///   (http://reactivex.io/documentation/operators/merge.html) on ReactiveX.
    public func merge() -> Observable<Item.Item> {
        return self.flatMap { $0.mirror() }
    }

    /// Returns an `Observable` that mirrors the observable most recently
    /// emitted by the receiver.
    ///
    /// - note: The result `Observable` is terminated when:
    ///   1. Error occurs in either the latest observable or the receiver,
    ///   2. Both the latest observable and the receiver complete.
    ///
    /// - seealso: ['Switch' operator documentation]
    ///   (http://reactivex.io/documentation/operators/switch.html) on ReactiveX.
    public func switchLatest() -> Observable<Item.Item> {
        return Observable<Item.Item> { t, q, cb in
            var count = 1
            var isTerminated = false
            var current = -1

            func subscribe(item: Item, tag: Int) {
                item.observe(on: emittingQueue)
                    .subscribe(at: Time.now, on: serialQueue, callback: { er in
                    guard !isTerminated else { return false }
                    // NOTE:
                    guard tag == current else { return false }
                    switch er {
                    case .item(_):
                        q.async {
                            isTerminated = !cb(er)
                        }
                        return true
                    case .complete:
                        count -= 1
                        if count == 0 {
                            q.async {
                                let _ = cb(.complete)
                            }
                        }
                    case .error(_):
                        isTerminated = true
                        q.async {
                            let _ = cb(er)
                        }
                    }
                    return false
                })
            }
            self.observe(on: emittingQueue)
                .subscribe(at: t, on: serialQueue, callback: { er in
                guard !isTerminated else { return false }
                switch er {
                case let .item(o):
                    if count == 1 { count = 2 }
                    current += 1
                    subscribe(item: o, tag: current)
                    return true
                case .complete:
                    count -= 1
                    if count == 0 {
                        q.async {
                            let _ = cb(.complete)
                        }
                    }
                case let .error(e):
                    isTerminated = true
                    q.async {
                        let _ = cb(.error(e))
                    }
                }
                return false
            })
        }
    }
}

// MARK: Error Handling

extension ObservableProtocol {

    /// Returns an `Observable` that mirrors the receiver, but when error
    /// notification is emitted, it tries to recover to an `Observable` derived
    /// from the error.
    ///
    /// - seealso: ['Catch' operator documentation]
    ///   (http://reactivex.io/documentation/operators/catch.html) on ReactiveX.
    public func `catch`(
        _ operation: @escaping (Error) -> Observable<Item>
    ) -> Observable<Item> {
        return Observable<Item>() { t, q, cb in
            self.subscribe(at: t, on: q) { er in
                switch er {
                case let .item(itm):
                    return cb(.item(itm))
                case let .error(e):
                    let o = operation(e)
                    o.subscribe(at: t, on: q, callback: { er in
                        switch er {
                        case .item(_): return cb(er)
                        default:
                            let _ = cb(er)
                        }
                        return false
                    })
                case .complete:
                    let _ = cb(.complete)
                }
                return false
            }
        }
    }

    /// Returns an `Observable` that mirrors the receiver, but when error
    /// notification is emitted, it
    ///
    /// - note: To use this operator, the receiver must be ill-behaved. That
    ///   is, it can emit items after emitting error notifications. The only
    ///   way to create such an observable is to use `Observable.init(callback:)`.
    ///
    /// - note: To ignore error notification altogether, pass `0` to the
    ///   method.
    ///
    /// - seealso: ['Retry' operator documentation]
    ///   (http://reactivex.io/documentation/operators/retry.html) on ReactiveX.
    ///
    /// - seealso: `Observable.init(callback:)`
    public func retry(count: Int) -> Observable<Item> {
        return Observable<Item>() { t, q, cb in
            var i = 0
            var cancelled = false
            // NOTE: The receiver IS not well-behaved. Can't use return
            // value to stop emitting.
            self.subscribe(at: t, on: q) { er in
                guard !cancelled else { return false }
                switch er {
                case let .item(itm):
                    cancelled = !cb(.item(itm))
                    return !cancelled
                case let .error(e):
                    guard count > 0 && i >= count else {
                        if count > 0 { i += 1 }
                        return true
                    }
                    let _ = cb(.error(e))
                case .complete:
                    let _ = cb(.complete)
                }
                cancelled = true
                return false
            }
        }
    }
}

// MARK: Utility

extension ObservableProtocol {

    /// Returns an `Observable` that shifts the emission from an Observable
    /// forward in time by a particular amount.
    ///
    /// - seealso: [`Delay` operator documentation]
    ///   (http://reactivex.io/documentation/operators/delay.html) on ReactiveX.
    public func delay(_ ti: TimeInterval) -> Observable<Item> {
        return Observable<Item>() { t, q, cb in
            emittingQueue.asyncAfter(deadline: DispatchTime.now() + ti.seconds) {
                self.subscribe(at: Time.now, on: q) { er in
                    return cb(er)
                }
            }
        }
    }

    /// Returns an `Observable` that mirrors the receiver and is able to
    /// execute a registered action if a given condition passes.
    ///
    /// - note: The action is executed on the same `DispatchQueue` as
    ///   subscription.
    ///
    /// - seealso: [`Do` operator documentation]
    ///   (http://reactivex.io/documentation/operators/do.html) on ReactiveX.
    public func tap(
        on cond: @escaping (EmittingResult<Item>) -> Bool,
        action: @escaping () -> Void
    ) -> Observable<Item> {
        return Observable<Item> { t, q, cb in
            self.subscribe(at: t, on: q, callback: { er in
                if cond(er) { action() }
                switch er {
                case .item(_):
                    return cb(er)
                default:
                    let _ = cb(er)
                }
                return false
            })
        }
    }

    /// Returns an `Observable` that emits the time intervals between
    /// emission of the receiver.
    ///
    /// - seealso: [`TimeInterval` operator documentation]
    ///   (http://reactivex.io/documentation/operators/timeinterval.html) on ReactiveX.
    public func interval() -> Observable<TimeInterval> {
        return Observable<TimeInterval> { t, q, cb in
            var it = t
            self.subscribe(at: t, on: q) { er in
                let now = Time.now
                let ti = EmittingResult<TimeInterval>.item(now - it)
                it = now

                switch er {
                case .item(_):
                    return cb(ti)
                case .complete:
                    let _ = cb(ti) && cb(.complete)
                case let .error(e):
                    let _ = cb(ti) && cb(.error(e))
                }
                return false
            }
        }
    }

    /// Returns an `Observable` that mirrors the receiver but it subscribes
    /// the receiver on a particular `DispatchQueue`.
    ///
    /// - note: This is a important method since it's the only way to
    ///   parallel execute chained operators.
    ///
    /// - seealso: [`ObserveOn` operator documentation]
    ///   (http://reactivex.io/documentation/operators/observeon.html) on ReactiveX.
    public func observe(on queue: DispatchQueue) -> Observable<Item> {
        return Observable<Item> { t, q, cb in
            var cancelled = false
            self.subscribe(at: t, on: queue) { er in
                guard !cancelled else { return false }
                q.async {
                    cancelled = !cb(er)
                }
                return !cancelled
            }
        }
    }

    /// Returns an `Observable` that mirrors the receiver, but emits an error
    /// notification if a particular period of time elapses without any emitted
    /// items.
    ///
    /// - seealso: [`Timeout` operator documentation]
    ///   (http://reactivex.io/documentation/operators/timeout.html) on ReactiveX.
    public func timeout(_ ti: TimeInterval) -> Observable<Item> {
        return Observable<Item> { t, q, cb in
            // Last emitting time.
            var ct = t
            var isTerminated = false
            func timer(_ dl: TimeInterval) {
                serialQueue.asyncAfter(deadline: DispatchTime.now() + dl.seconds, execute: {
                    guard !isTerminated else { return }
                    let dt = Time.now - ct
                    guard dt < ti else {
                        q.async {
                            let _ = cb(.error(RuntimeError.timeout))
                        }
                        isTerminated = true
                        return
                    }
                    timer(ti - dt)
                })
            }
            timer(ti)
            self.observe(on: emittingQueue).subscribe(at: t, on: serialQueue) { er in
                guard !isTerminated else {
                    return false
                }
                switch er {
                case .item(_):
                    ct = Time.now
                    q.async {
                        isTerminated = !cb(er)
                    }
                    return true
                default:
                    q.async {
                        let _ = cb(er)
                    }
                    isTerminated = true
                    return false
                }
            }
        }
    }

    /// Returns an `Observable` that attaches a timestamp to each item
    /// emitted by the receiver indicating when it is emitted.
    ///
    /// - seealso: [`Timestamp` operator documentation]
    ///   (http://reactivex.io/documentation/operators/timestamp.html) on ReactiveX.
    public func timestamp() -> Observable<(Item, TimeInterval)> {
        return Observable<(Item, TimeInterval)> { t, q, cb in
            self.subscribe(at: t, on: q) { er in
                switch er {
                case let .item(itm):
                    return cb(.item((itm, Time.now - t)))
                case .complete:
                    let _ = cb(.complete)
                case let .error(e):
                    let _ = cb(.error(e))
                }
                return false
            }
        }
    }
}

// MARK: Conditional

extension ObservableProtocol {

    /// Returns an `Observable` that determines if all the items emitted
    /// by the receiver pass a predication test, and then emits the result.
    ///
    /// - note: If the receiver is empty or terminated by an error, the
    ///   returned `Observable` emits nothing.
    ///
    /// - seealso: ['All' operator documentation]
    ///   (http://reactivex.io/documentation/operators/all.html) on ReactiveX.
    public func all(
        _ predication: @escaping (Item) -> Bool
    ) -> Observable<Bool> {
        return Observable<Bool> { t, q, cb in
            var b = false
            self.subscribe(at: t, on: q) { er in
                switch er {
                case let .item(itm):
                    guard !predication(itm) else {
                        b = true
                        return true
                    }
                    let _ = cb(.item(false)) && cb(.complete)
                case .complete:
                    if !b {
                        // Empty.
                        let _ = cb(.complete)
                    } else {
                        let _ = cb(.item(true)) && cb(.complete)
                    }
                case let .error(err):
                    let _ = cb(.error(err))
                }
                return false
            }
        }
    }

    /// Returns an `Observable` that mirrors the emission of the observable
    /// that first emits.
    ///
    /// - seealso: ['Amb' operator documentation]
    ///   (http://reactivex.io/documentation/operators/amb.html) on ReactiveX.
    public static func amb(_ os: Self...) -> Observable<Item> {
        return Observable<Item> { t, q, cb in
            var chosen = -1
            for i in 0..<os.count {
                let o = os[i]
                o.subscribe(at: t, on: q, callback: { er in
                    if chosen < 0 { chosen = i }
                    if chosen != i { return false }
                    switch er {
                    case .item(_): return cb(er)
                    default: let _ = cb(er)
                    }
                    return false
                })
            }
        }
    }

    /// Returns an `Observable` that emits given default item if the
    /// receiver emits nothing.
    ///
    /// - seealso: ['DefaultIfEmpty' operator documentation]
    ///   (http://reactivex.io/documentation/operators/defaultifempty.html) on ReactiveX.
    public func defaultItem(_ itm: Item) -> Observable<Item> {
        return Observable<Item>() { t, q, cb in
            var isEmpty = true
            self.subscribe(at: t, on: q) { er in
                switch er {
                case .item(_):
                    isEmpty = false
                    return cb(er)
                case .complete:
                    if isEmpty {
                        let _ = cb(.item(itm)) && cb(.complete)
                    } else {
                        let _ = cb(.complete)
                    }
                case .error(_):
                    let _ = cb(er)
                }
                return false
            }
        }
    }
}

extension ObservableProtocol where Item: Equatable {

    /// Returns an `Observable` that determines whether the receiver emits a
    /// particular item or not, and emits the result.
    ///
    /// - seealso: ['Contains' operator documentation]
    ///   (http://reactivex.io/documentation/operators/contains.html) on ReactiveX.
    public func contains(_ item: Item) -> Observable<Bool> {
        return Observable<Bool> { t, q, cb in
            self.subscribe(at: t, on: q) { er in
                switch er {
                case let .item(itm):
                    guard itm == item else {
                        return true
                    }
                    if cb(.item(true)) {
                        let _ =  cb(.complete)
                    }
                case let .error(e):
                    let _ = cb(.error(e))
                case .complete:
                    if cb(.item(false)) {
                        let _ =  cb(.complete)
                    }
                }
                return false
            }
        }
    }

    /// Returns an `Observable` that determines whether the receiver and
    /// another observable emit the same sequence of items, and then emits the
    /// result.
    ///
    /// - seealso: ['SequenceEqual' operator documentation]
    ///   (http://reactivex.io/documentation/operators/sequenceequal.html) on ReactiveX.
    public func sequenceEqual<O: ObservableProtocol>(_ that: O) -> Observable<Bool> where O.Item == Item {
        return Observable<Bool> { t, q, cb in
            var seq = CircularQueue<Item>(capacity: 16, fixed: false)
            var hasError = false
            var top = 0
            let lcb = { (er: EmittingResult<(Item, Int)>) -> Bool in
                guard !hasError else { return false }
                switch er {
                case let .item((itm, i)):
                    if i == top {
                        top += 1
                        seq.push(item: .item(itm))
                        return true
                    } else {
                        assert(i < top)
                        let h = seq.pop()!
                        switch h {
                        case let .item(hv) where itm == hv:
                            return true
                        default:
                            // Always run user provided callbacks on user
                            // specified queue.
                            q.async {
                                // FIXME: return value of `cb(.item(_))` is ignored.
                                let _ = cb(.item(false)) && cb(.complete)
                            }
                        }
                    }
                case .complete:
                    guard let last = seq.last, last == EmittingResult<Item>.complete else {
                        top += 1
                        seq.push(item: .complete)
                        return false
                    }
                    q.async {
                        let _ = cb(.item(seq.count == 1)) && cb(.complete)
                    }
                case let .error(e):
                    hasError = true
                    q.async {
                        let _ = cb(.error(e))
                    }
                }
                return false
            }
            self.zipWithIndex()
                .observe(on: emittingQueue)
                .subscribe(at: t, on: serialQueue, callback: lcb)
            that.zipWithIndex()
                .observe(on: emittingQueue)
                .subscribe(at: t, on: serialQueue, callback: lcb)
        }
    }
}

// MARK: Mathematical & Aggregate

extension ObservableProtocol {

    /// Returns an `Observable` that emits items emitted by the receiver,
    /// and then items emitted by another observable.
    ///
    /// - note: This function concat only *2* observables. This is different
    ///   than the standard `Concat` operator. However, you can achieve that
    ///   behavior by calling `concat` as many times as needed.
    ///
    /// - note: If the receiver emits an error, the emission of returned
    ///   `Observable` terminates as well.
    ///
    /// - seealso: ['Concat' operator documentation]
    ///   (http://reactivex.io/documentation/operators/concat.html) on ReactiveX.
    ///
    /// - seealso: `start(with:)`
    public func concat<O: ObservableProtocol>(
        _ that: O
    ) -> Observable<Item> where O.Item == Item {
        return that.start(with: self)
    }

    /// Returns an `Observable` that emits the number of items emitted by
    /// the receiver.
    ///
    /// - note: If the receiver emits only termination notifications, the
    ///   returned `Observable` does not emit `0`, instead it emits the same
    ///   termination notification as the receiver does.
    ///
    /// - seealso: ['Count' operator documentation]
    ///   (http://reactivex.io/documentation/operators/count.html) on ReactiveX.
    public func count() -> Observable<Int> {
        return self.reduce({ _ in 1 }, { i, _ in
            i + 1
        })
    }

    /// Returns an `Observable` that applies `initial` fucntion to the first
    /// item emitted by the receiver, and then applies `operation` function
    /// to all subsequent items, sequentially. It emits only the final value.
    ///
    /// - seealso: ['Reduce' operator documentation]
    ///   (http://reactivex.io/documentation/operators/reduce.html) on ReactiveX.
    public func reduce<T>(
        _ initial: @escaping (Item) -> T,
        _ operation: @escaping (T, Item) -> T
    ) -> Observable<T> {
        return Observable<T>() { t, q, cb in
            var acc: T? = nil
            self.subscribe(at: t, on: q) { er in
                switch er {
                case let .item(itm):
                    guard let a = acc else {
                        acc = initial(itm)
                        return true
                    }
                    acc = operation(a, itm)
                    return true
                case .complete:
                    if let acc = acc {
                        if !cb(.item(acc)) { break }
                    }
                    let _ = cb(.complete)
                case let .error(e):
                    let _ = cb(.error(e))
                }
                return false
            }
        }
    }

    /// Reduced verion of `reduce` for the situations where types of `Item`
    /// of result `Observable` and `Item` of the receiver are same.
    ///
    /// - note: The `initial` function just returns the first item intact.
    public func reduce(
        _ operation: @escaping (Item, Item) -> Item
    ) -> Observable<Item> {
        return self.reduce({ $0 }, operation)
    }
}

extension ObservableProtocol where Item: FloatingPoint {

    /// Returns an `Observable` that calculates the average of numbers
    /// emitted by the receiver and emits only this average value.
    ///
    /// - seealso: ['Average' operator documentation]
    ///   (http://reactivex.io/documentation/operators/average.html) on ReactiveX.
    public func average() -> Observable<Item> {
        return self.zipWithIndex().reduce({ a, b in
            (a.0 + b.0,  b.1 + 1)
        }).map { $0.0 / Item($0.1) }
    }

    /// Returns an `Observable` that calculates the sum of numbers
    /// emitted by the receiver and emits only this sum value.
    ///
    /// - seealso: ['Sum' operator documentation]
    ///   (http://reactivex.io/documentation/operators/sum.html) on ReactiveX.
    public func sum() -> Observable<Item> {
        return self.reduce(+)
    }
}

extension ObservableProtocol where Item: Comparable {

    /// Returns an `Observable` that determines and emits the maximum-valued
    /// items emitted by the receiver.
    ///
    /// - seealso: ['Max' operator documentation]
    ///   (http://reactivex.io/documentation/operators/max.html) on ReactiveX.
    public func max() -> Observable<Item> {
        return self.reduce {
            $0 > $1 ? $0 : $1
        }
    }

    /// Returns an `Observable` that determines and emits the minimum-valued
    /// items emitted by the receiver.
    ///
    /// - seealso: ['Min' operator documentation]
    ///   (http://reactivex.io/documentation/operators/min.html) on ReactiveX.
    public func min() -> Observable<Item> {
        return self.reduce {
            $0 < $1 ? $0 : $1
        }
    }
}
