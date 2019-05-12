import Foundation
import Dispatch

/// Manipulate storage in a "all async" manner.
/// The completion closure will be called when operation completes.
public class AsyncStorage<Storage: StorageAware> {
	public typealias T = Storage.T
	public let innerStorage: Storage
	private let serialQueue: DispatchQueue
	
	init(_ storage: Storage, serialQueue: DispatchQueue? = nil) {
		self.innerStorage = storage
		self.serialQueue = serialQueue ?? DispatchQueue(label: "Cache.AsyncStorage.SerialQueue")
	}
	
}

extension AsyncStorage: AsyncStorageAware {
	
	public func count(completion: @escaping (Int) -> ()) {
		async({_ in self.innerStorage.count }, value: (), completion: completion)
	}
	
	public func entry(forKey key: String, completion: @escaping Completion<Entry<Storage.T>>) {
		async(innerStorage.entry, value: key, completion: completion)
	}
	
	public func allObjects(completion: @escaping ([Storage.T]) -> ()) {
		async(innerStorage.allObjects, value: (), completion: completion)
	}
	
	public func removeObject(forKey key: String, completion: Completion<()>? = nil) {
		async(innerStorage.removeObject, value: key, completion: completion)
	}
	
	public func setObject(_ object: Storage.T, forKey key: String, expiry: Expiry? = nil, completion: Completion<()>? = nil) {
		async(innerStorage.setObject, value: (object, key, expiry), completion: completion)
	}
	
	public func removeAll(completion: Completion<()>? = nil) {
		async(innerStorage.removeAll, value: (), completion: completion)
	}
	
	public func removeExpiredObjects(completion: Completion<()>? = nil) {
		async(innerStorage.removeExpiredObjects, value: (), completion: completion)
	}
	
	public func object(forKey key: String, completion: @escaping (Storage.T?) -> ()) {
		async(innerStorage.object, value: key, completion: completion)
	}
	
	public func existsObject(forKey key: String, completion: @escaping (Bool) -> ()) {
		async(innerStorage.existsObject, value: key, completion: completion)
	}
	
	public func isExpiredObject(forKey key: String, completion: @escaping (Bool) -> ()) {
		async(innerStorage.isExpiredObject, value: key, completion: completion)
	}
	
	private func async<T, R>(_ block: @escaping (T) -> R, value: T, completion: ((R) -> ())?) {
		serialQueue.async {
			let result = block(value)
			completion?(result)
		}
	}
	
	private func async<T, R>(_ block: @escaping (T) throws -> R, value: T, completion: Completion<R>?) {
		serialQueue.async {
			do {
				let result = try block(value)
				completion?(.success(result))
			} catch {
				completion?(.failure(error))
			}
		}
	}
	
}

extension AsyncStorageAware where Storage == HybridStorage<T> {
	
	public func synchronize(_ completion: Completion<()>? = nil) {
		//async(innerStorage.synchronize, value: (), completion: completion)
	}
	
}
