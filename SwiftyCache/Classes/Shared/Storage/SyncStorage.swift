import Foundation
import Dispatch

/// Manipulate storage in a "all sync" manner.
/// Block the current queue until the operation completes.
public class SyncStorage<T>: StorageAware {//where T == Storage.T {
	public let innerStorage: HybridStorage<T>
	private let serialQueue: DispatchQueue
	private let observersQueue = DispatchQueue(label: "Cache.SyncStorage.ObserversSerialQueue." + UUID().uuidString)
	private var isCurrentQueue = false
	
	public convenience init(_ storage: HybridStorage<T>) {
		self.init(storage, queue: DispatchQueue(label: "Cache.SyncStorage.SerialQueue." + UUID().uuidString))
	}
	
	private init(_ storage: HybridStorage<T>, queue: DispatchQueue) {
		innerStorage = storage
		serialQueue = queue
	}
}

extension SyncStorage {
	
	public var count: Int {
		return sync( { _ in innerStorage.count } , value: ())
	}
	
	public func object(forKey key: String) -> T? {
		return sync(innerStorage.object, value: key)
	}
	
	public func existsObject(forKey key: String) -> Bool {
		return sync(innerStorage.existsObject, value: key)
	}
	
	public func isExpiredObject(forKey key: String) -> Bool {
		return sync(innerStorage.isExpiredObject, value: key)
	}
	
	
	public func allObjects() -> [T] {
		return sync(innerStorage.allObjects, value: ())
	}
	
	public func entry(forKey key: String) throws -> Entry<T> {
		return try sync(innerStorage.entry, value: key)
	}
	
	public func removeObject(forKey key: String) throws {
		try sync(innerStorage.removeObject, value: key)
	}
	
	public func setObject(_ object: T, forKey key: String, expiry: Expiry? = nil) throws {
		try sync(innerStorage.setObject, value: (object, key, expiry))
	}
	
	public func removeAll() throws {
		try sync(innerStorage.removeAll)
	}
	
	public func removeExpiredObjects() throws {
		try sync(innerStorage.removeExpiredObjects)
	}
	
	private func sync<R>(_ block: () throws -> R) rethrows -> R {
		if isCurrentQueue {
			return try block()
		}
		var result: R?
		try serialQueue.sync {
			isCurrentQueue = true
			result = try block()
			isCurrentQueue = false
		}
		return result!
	}
	
	private func sync<T, R>(_ block: (T) throws -> R, value: T) rethrows -> R {
		if isCurrentQueue {
			return try block(value)
		}
		var result: R?
		try serialQueue.sync {
			isCurrentQueue = true
			result = try block(value)
			isCurrentQueue = false
		}
		return result!
	}
	
	func setObject(_ object: T, forKey key: String, referenced: (String, String)?, expiry: Expiry? = nil) throws {
		try sync(innerStorage.setObject, value: (object, key, referenced, expiry))
	}
	
	public func synchronize() throws {
		try sync(innerStorage.synchronize)
	}
	
	func transform<U>(transformer: Transformer<U>) -> SyncStorage<U> {
		let storage = SyncStorage<U>(
			innerStorage.transform(transformer: transformer),
			queue: serialQueue
		)
		return storage
	}
	
	@discardableResult
	public func addStorageObserver<O: AnyObject>(_ observer: O, closure: @escaping (O, Storage<T>, StorageChange) -> Void, storage: Storage<T>) -> ObservationToken {
		return innerStorage.addStorageObserver(observer) { [weak self, weak storage] observer, _, change in
			guard let strongSelf = self, let storage = storage else { return }
			strongSelf.observersQueue.async {
				closure(observer, storage, change)
			}
		}
	}
	
	public func removeAllStorageObservers() {
		sync(innerStorage.removeAllStorageObservers)
	}
	
	@discardableResult
	public func addObserver<O: AnyObject>(_ observer: O, forKey key: String, closure: @escaping (O, Storage<T>, KeyChange<T>) -> Void, storage: Storage<T>) -> ObservationToken {
		return innerStorage.addObserver(observer, forKey: key) { [weak self, weak storage] observer, _, change in
			guard let strongSelf = self, let storage = storage else { return }
			strongSelf.observersQueue.async {
				closure(observer, storage, change)
			}
		}
	}
	
	public func removeObserver(forKey key: String) {
		sync(innerStorage.removeObserver, value: key)
	}
	
	public func removeAllKeyObservers() {
		sync(innerStorage.removeAllKeyObservers)
	}
	
}
