import Foundation
import Dispatch

/// Manage storage. Use memory storage if specified.
/// Synchronous by default. Use `async` for asynchronous operations.
public final class Storage<T> {
	/// Used for sync operations
	private let syncStorage: SyncStorage<T>
	private let asyncStorage: AsyncStorage<HybridStorage<T>>
	private let hybridStorage: HybridStorage<T>
	public var diskStorage: DiskStorage<T> { return hybridStorage.diskStorage }
	public var memoryStorage: MemoryStorage<T> { return hybridStorage.memoryStorage }
	/// Used for async operations
	public var async: AsyncStorage<HybridStorage<T>> { return self.asyncStorage }
	public var immediatelyOnDisk: Bool {
		get { return hybridStorage.immediatelyOnDisk }
		set { hybridStorage.immediatelyOnDisk = newValue }
	}
	
	//public var name: String
	/// Initialize storage with configuration options.
	///
	/// - Parameters:
	///   - diskConfig: Configuration for disk storage
	///   - memoryConfig: Optional. Pass config if you want memory cache
	/// - Throws: Throw StorageError if any.
	public convenience init(diskConfig: DiskConfig, memoryConfig: MemoryConfig, transformer: Transformer<T>, immediatelyOnDisk: Bool = true) throws {
		let disk = try DiskStorage(config: diskConfig, transformer: transformer)
		let memory = MemoryStorage<T>(config: memoryConfig)
		let hybridStorage = HybridStorage(memoryStorage: memory, diskStorage: disk, immediatelyOnDisk: immediatelyOnDisk)
		self.init(hybridStorage: hybridStorage)
	}
	
	/// Initialise with sync and async storages
	///
	/// - Parameter syncStorage: Synchronous storage
	/// - Paraeter: asyncStorage: Asynchronous storage
	public init(hybridStorage: HybridStorage<T>) {
		self.hybridStorage = hybridStorage
		self.syncStorage = SyncStorage(
			storage: hybridStorage,
			serialQueue: DispatchQueue(label: "Cache.SyncStorage.SerialQueue")
		)
		self.asyncStorage = AsyncStorage(
			storage: hybridStorage,
			serialQueue: DispatchQueue(label: "Cache.AsyncStorage.SerialQueue")
		)
	}
	
}

extension Storage: StorageAware {
	
	public var count: Int {
		return self.syncStorage.count
	}
	
	public func object(forKey key: String) -> T? {
		return self.syncStorage.object(forKey: key)
	}
	
	public func entry(forKey key: String) throws -> Entry<T> {
		return try self.syncStorage.entry(forKey: key)
	}
	
	public func existsObject(forKey key: String) -> Bool {
		return self.syncStorage.existsObject(forKey: key)
	}
	
	public func isExpiredObject(forKey key: String) -> Bool {
		return self.syncStorage.isExpiredObject(forKey: key)
	}
	
	public func allObjects() -> [T] {
		return syncStorage.allObjects()
	}
	
	public func removeObject(forKey key: String) throws {
		try self.syncStorage.removeObject(forKey: key)
	}
	
	public func setObject(_ object: T, forKey key: String, expiry: Expiry? = nil) throws {
		try self.syncStorage.setObject(object, forKey: key, expiry: expiry)
	}
	
	public func removeAll() throws {
		try self.syncStorage.removeAll()
	}
	
	public func removeExpiredObjects() throws {
		try self.syncStorage.removeExpiredObjects()
	}
	
	func setObject(_ object: T, forKey key: String, referenced: (String, String)?, expiry: Expiry? = nil) throws {
		try self.syncStorage.setObject(object, forKey: key, referenced: referenced, expiry: expiry)
	}
	
}

public extension Storage {
	func transform<U>(transformer: Transformer<U>) -> Storage<U> {
		return Storage<U>(hybridStorage: hybridStorage.transform(transformer: transformer))
	}
}

extension Storage: StorageObservationRegistry {
	
	@discardableResult
	public func addStorageObserver<O: AnyObject>(_ observer: O, closure: @escaping (O, Storage, StorageChange) -> Void) -> ObservationToken {
		return hybridStorage.addStorageObserver(observer) { [weak self] observer, _, change in
			guard let strongSelf = self else { return }
			closure(observer, strongSelf, change)
		}
	}
	
	public func removeAllStorageObservers() {
		hybridStorage.removeAllStorageObservers()
	}
	
	public func synchronize() throws {
		try syncStorage.synchronize()
	}
}

extension Storage: KeyObservationRegistry {
	
	@discardableResult
	public func addObserver<O: AnyObject>(_ observer: O, forKey key: String, closure: @escaping (O, Storage, KeyChange<T>) -> Void) -> ObservationToken {
		return hybridStorage.addObserver(observer, forKey: key) { [weak self] observer, _, change in
			guard let strongSelf = self else { return }
			closure(observer, strongSelf, change)
		}
	}
	
	public func removeObserver(forKey key: String) {
		hybridStorage.removeObserver(forKey: key)
	}
	
	public func removeAllKeyObservers() {
		hybridStorage.removeAllKeyObservers()
	}
	
}
