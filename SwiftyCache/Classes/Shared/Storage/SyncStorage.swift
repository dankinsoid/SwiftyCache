import Foundation
import Dispatch

/// Manipulate storage in a "all sync" manner.
/// Block the current queue until the operation completes.
public class SyncStorage<T> {
	public let innerStorage: HybridStorage<T>
	public let serialQueue: DispatchQueue
	
	public init(storage: HybridStorage<T>, serialQueue: DispatchQueue) {
		self.innerStorage = storage
		self.serialQueue = serialQueue
	}
}

extension SyncStorage: StorageAware {
	
	public var count: Int {
		return sync( { _ in innerStorage.count } , value: ())
	}
	
	public func object(forKey key: String) -> T? {
		return sync(innerStorage.object , value: key)
	}
	
	public func existsObject(forKey key: String) -> Bool {
		return sync(innerStorage.existsObject , value: key)
	}
	
	public func isExpiredObject(forKey key: String) -> Bool {
		return sync(innerStorage.isExpiredObject , value: key)
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
	
	func setObject(_ object: T, forKey key: String, referenced: (String, String)?, expiry: Expiry? = nil) throws {
		try sync(innerStorage.setObject, value: (object, key, referenced, expiry))
	}
	
	public func removeAll() throws {
		try sync(innerStorage.removeAll)
	}
	
	public func removeExpiredObjects() throws {
		try sync(innerStorage.removeExpiredObjects)
	}
	
	private func sync<R>(_ block: () throws -> R) rethrows -> R {
		if OperationQueue.current?.underlyingQueue === serialQueue {
			return try block()
		}
		var result: R?
		try serialQueue.sync {
			result = try block()
		}
		return result!
	}
	
	private func sync<T, R>(_ block: (T) throws -> R, value: T) rethrows -> R {
		if OperationQueue.current?.underlyingQueue === serialQueue {
			return try block(value)
		}
		var result: R?
		try serialQueue.sync {
			result = try block(value)
		}
		return result!
	}
}

public extension SyncStorage {
	func transform<U>(transformer: Transformer<U>) -> SyncStorage<U> {
		let storage = SyncStorage<U>(
			storage: innerStorage.transform(transformer: transformer),
			serialQueue: serialQueue
		)
		
		return storage
	}
}

extension SyncStorage {// where Storage == HybridStorage<T> {
	
	public func synchronize() throws {
		try sync(innerStorage.synchronize)
	}
	
}
