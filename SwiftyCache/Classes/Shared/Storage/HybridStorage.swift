import Foundation
import UIKit

//public struct HybridConfig {
//	let immediatelyOnDisk: Bool
//}

/// Use both memory and disk storage. Try on memory first.
public final class HybridStorage<T> {
	public let memoryStorage: MemoryStorage<T>
	public let diskStorage: DiskStorage<T>
	public var immediatelyOnDisk: Bool {
		didSet {
			if immediatelyOnDisk != oldValue {
				configSynchronize()
			}
		}
	}
	
	private(set) var storageObservations = [UUID: (HybridStorage, StorageChange) -> Void]()
	private(set) var keyObservations: [String: [UUID: (HybridStorage, KeyChange<T>) -> Void]] = [:]
	private var resignObserver: NSObjectProtocol?
	private var terminateObserver: NSObjectProtocol?
	
	init(memoryStorage: MemoryStorage<T>, diskStorage: DiskStorage<T>, immediatelyOnDisk: Bool = false) {
		self.memoryStorage = memoryStorage
		self.diskStorage = diskStorage
		self.immediatelyOnDisk = immediatelyOnDisk//HybridConfig(immediatelyOnDisk: immediatelyOnDisk)
		diskStorage.onRemove = { [weak self] key in
			self?.notifyObserver(forKey: key, about: .remove)
			self?.notifyStorageObservers(about: .remove(key: key))
		}
		if !immediatelyOnDisk {
			configSynchronize()
		}
		resignObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) {[weak self] _ in
			self?.appWillTerminate()
		}
		terminateObserver = NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: nil) {[weak self] _ in
			self?.appWillTerminate()
		}
	}
	
	private func configSynchronize() {
		if immediatelyOnDisk {
			memoryStorage.willEvict = nil
			try? synchronize()
		} else {
			memoryStorage.willEvict = {[weak self] key, value in
				try? self?.diskStorage.setObject(value, forKey: key)
			}
		}
	}
	
	@objc func appWillTerminate() {
		DispatchQueue.global().async {[diskStorage, memoryStorage, immediatelyOnDisk] in
			memoryStorage.removeExpiredObjects()
			try? diskStorage.removeExpiredObjects()
			try? HybridStorage<T>.synchronize(disk: diskStorage, memory: memoryStorage, immediatelyOnDisk: immediatelyOnDisk)
		}
	}
	
	deinit {
		NotificationCenter.default.removeObserver(resignObserver)
		NotificationCenter.default.removeObserver(terminateObserver)
		appWillTerminate()
	}
	
}

extension HybridStorage: StorageAware {
	
	public var count: Int {
		return diskStorage.count
	}
	
	public func object(forKey key: String) -> T? {
		return try? entry(forKey: key).object
	}
	
	
	public func existsObject(forKey key: String) -> Bool {
		return memoryStorage.existsObject(forKey: key) || diskStorage.existsObject(forKey: key)
	}
	
	public func isExpiredObject(forKey key: String) -> Bool {
		if let entry = memoryStorage.entry(forKey: key) {
			return entry.expiry.isExpired
		}
		return diskStorage.isExpiredObject(forKey: key)
	}
	
	public func entry(forKey key: String) throws -> Entry<T> {
		do {
			return try memoryStorage.entry(forKey: key)~!
		} catch {
			let entry = try diskStorage.entry(forKey: key)
			// set back to memoryStorage
			memoryStorage.setObject(entry.object, forKey: key, expiry: entry.expiry)
			return entry
		}
	}
	
	public func removeObject(forKey key: String) throws {
		memoryStorage.removeObject(forKey: key)
		try diskStorage.removeObject(forKey: key)
		notifyStorageObservers(about: .remove(key: key))
	}
	
	public func setObject(_ object: T, forKey key: String, expiry: Expiry? = nil) throws {
		try setObject(object, forKey: key, referenced: nil, expiry: expiry)
	}
	
	func setObject(_ object: T, forKey key: String, referenced: (String, String)?, expiry: Expiry? = nil) throws {
		memoryStorage.setObject(object, forKey: key, expiry: expiry)
		notifyObserver(forKey: key, about: .set(value: object))
		notifyStorageObservers(about: .set(key: key))
		if immediatelyOnDisk {
			try diskStorage.setObject(object, forKey: key, referencedBy: referenced, expiry: expiry)
		} else {
			diskStorage.encode(object: object, forKey: key, getData: false)
		}
	}
	
	public func synchronize() throws {
		//try removeExpiredObjects()
		try HybridStorage<T>.synchronize(disk: diskStorage, memory: memoryStorage, immediatelyOnDisk: immediatelyOnDisk)
	}
	
	private static func synchronize(disk: DiskStorage<T>, memory: MemoryStorage<T>, immediatelyOnDisk: Bool) throws {
		guard !immediatelyOnDisk || (T.self as? AnyObject.Type) != nil else { return }
		for key in memory.allKeys {
			guard let value = memory.object(forKey: key) else { continue }
			try disk.setObject(value, forKey: key)
		}
	}
	
	public func allObjects() -> [T] {
		let diskKeys = diskStorage.allKeys
		let memoryKeys = memoryStorage.allKeys
		var result: [T] = memoryStorage.allObjects()
		result.reserveCapacity(max(diskKeys.count, memoryKeys.count))
		for key in diskKeys.subtracting(memoryKeys) {
			guard let object = diskStorage.object(forKey: key) else { continue }
			result.append(object)
		}
		return result
	}
	
	public func removeAll() throws {
		memoryStorage.removeAll()
		try diskStorage.removeAll()
		notifyStorageObservers(about: .removeAll)
		notifyKeyObservers(about: .remove)
	}
	
	public func removeExpiredObjects() throws {
		memoryStorage.removeExpiredObjects()
		try diskStorage.removeExpiredObjects()
		notifyStorageObservers(about: .removeExpired)
	}
	
}

public extension HybridStorage {
	func transform<U>(transformer: Transformer<U>) -> HybridStorage<U> {
		let storage = HybridStorage<U>(
			memoryStorage: memoryStorage.transform(),
			diskStorage: diskStorage.transform(transformer: transformer)
		)
		return storage
	}
}

extension HybridStorage: StorageObservationRegistry {
	@discardableResult
	public func addStorageObserver<O: AnyObject>(
		_ observer: O,
		closure: @escaping (O, HybridStorage, StorageChange) -> Void
		) -> ObservationToken {
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

extension HybridStorage: KeyObservationRegistry {
	@discardableResult
	public func addObserver<O: AnyObject>(_ observer: O, forKey key: String,
										  closure: @escaping (O, HybridStorage, KeyChange<T>) -> Void) -> ObservationToken {
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
