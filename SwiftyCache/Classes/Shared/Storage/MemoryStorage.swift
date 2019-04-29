import Foundation

public protocol MemoryStorageAware: GenericStorage {
	func object(forKey: String) -> T?
	func removeObject(forKey key: String)
	func setObject(_ object: T, forKey key: String, expiry: Expiry?)
}

public class MemoryStorage<T> {
	
	public typealias S = MemoryStorage
	
	fileprivate let cache = MemoryCache<String, Entry<T>>()
	// Memory cache keys
	public var allKeys: Set<String> { return cache.allKeys }
	public var count: Int { return cache.count }
	/// Configuration
	fileprivate let config: MemoryConfig
	var willEvict: ((String, T) -> ())?
	
	private(set) var storageObservations = [UUID: (MemoryStorage, StorageChange) -> Void]()
	private(set) var keyObservations: [String: [UUID: (MemoryStorage, KeyChange<T>) -> Void]] = [:]
	
	init(config: MemoryConfig = MemoryConfig()) {
		self.config = config
		self.cache.countLimit = Int(config.countLimit)
		self.cache.totalCostLimit = Int(config.totalCostLimit)
		self.cache.willEvict = { [weak self] value, key in
			self?.willEvict?(key, value.object)
		}
		self.cache.didEvict = {[weak self] _, key in
			self?.notifyStorageObservers(about: .remove(key: key))
			self?.notifyObserver(forKey: key, about: .remove)
		}
	}
	
}

extension MemoryStorage: MemoryStorageAware {
	
	public func existsObject(forKey key: String) -> Bool {
		return cache.exist(forKey: key)
	}
	
	public func setObject(_ object: T, forKey key: String, expiry: Expiry? = nil) {
		let entry = Entry(object: object, expiry: .date(expiry?.date ?? config.expiry.date))
		cache.setObject(entry, forKey: key)
		notifyStorageObservers(about: .set(key: key))
		notifyObserver(forKey: key, about: .set(value: object))
	}
	
	public func removeAll() {
		cache.removeAllObjects()
		notifyStorageObservers(about: .removeAll)
		notifyKeyObservers(about: .remove)
	}
	
	public func removeExpiredObjects() {
		for key in allKeys {
			removeObjectIfExpired(forKey: key)
			notifyObserver(forKey: key, about: .remove)
		}
		notifyStorageObservers(about: .removeExpired)
	}
	
	public func removeObjectIfExpired(forKey key: String) {
		if let capsule = cache.object(forKey: key), capsule.expiry.isExpired {
			removeObject(forKey: key)
		}
	}
	
	public func removeObject(forKey key: String) {
		cache.removeObject(forKey: key)
		notifyStorageObservers(about: .remove(key: key))
		notifyObserver(forKey: key, about: .remove)
	}
	
	public func object(forKey key: String) -> T? {
		return cache.object(forKey: key)?.object
	}
	
	public func entry(forKey key: String) -> Entry<T>? {
		return cache.object(forKey: key)
	}
	
	public func allObjects() -> [T] {
		return cache.allValues.map({ $0.object })
	}
	
}

extension MemoryStorage {
	public func transform<U>() -> MemoryStorage<U> {
		let storage = MemoryStorage<U>(config: config)
		return storage
	}
}

extension MemoryStorage: StorageObservationRegistry {
	
	@discardableResult
	public func addStorageObserver<O: AnyObject>(_ observer: O, closure: @escaping (O, MemoryStorage, StorageChange) -> Void) -> ObservationToken {
		let id = UUID()
		
		storageObservations[id] = { [weak self, weak observer] storage, change in
			guard let observer = observer else {
				self?.storageObservations.removeValue(forKey: id)
				return
			}
			
			closure(observer, storage, change)
		}
		
		return ObservationToken { [weak self] in
			self?.storageObservations.removeValue(forKey: id)
		}
	}
	
	public func removeAllStorageObservers() {
		storageObservations.removeAll()
	}
	
	private func notifyStorageObservers(about change: StorageChange) {
		storageObservations.values.forEach { closure in
			closure(self, change)
		}
	}
	
}

extension MemoryStorage: KeyObservationRegistry {
	
	@discardableResult
	public func addObserver<O: AnyObject>(_ observer: O, forKey key: String,
										  closure: @escaping (O, MemoryStorage<T>, KeyChange<T>) -> Void) -> ObservationToken {
		let id = UUID()
		keyObservations[key, default: [:]][id] = { [weak self, weak observer] storage, change in
			guard let observer = observer else {
				self?.removeObserver(forKey: key)
				return
			}
			closure(observer, storage, change)
		}
		return ObservationToken { [weak self] in
			self?.keyObservations[key]?[id] = nil
			if self?.keyObservations[key]?.isEmpty == true {
				self?.keyObservations[key] = nil
			}
		}
	}
	
	public func removeObserver(forKey key: String) {
		keyObservations.removeValue(forKey: key)
	}
	
	public func removeAllKeyObservers() {
		keyObservations.removeAll()
	}
	
	private func notifyObserver(forKey key: String, about change: KeyChange<T>) {
		keyObservations[key]?.forEach( { $0.value(self, change) } )
	}
	
	private func notifyKeyObservers(about change: KeyChange<T>) {
		keyObservations.values.forEach { observers in
			observers.forEach { $0.value(self, change) }
		}
	}
}
