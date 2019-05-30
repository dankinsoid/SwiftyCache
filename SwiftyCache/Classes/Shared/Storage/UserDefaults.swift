//  UserDefaults.swift
//
//  Created by Данил Войдилов on 29/05/2019.
//

import Foundation

public final class UserDefaultsStorage<T>: StorageAware {
	public var count: Int {
		return dictionary.count
	}
	private var defaults: UserDefaults
	private let transformer: Transformer<T>
	private let name: String
	private var dictionary: [String: Any] {
		return UserDefaults.standard.persistentDomain(forName: name) ?? [:]
	}
	public var allKeys: Set<String> {
		return Set(dictionary.keys)
	}
	private(set) var storageObservations = [UUID: (UserDefaultsStorage, StorageChange) -> Void]()
	private(set) var keyObservations: [String: [UUID: (UserDefaultsStorage, KeyChange<T>) -> Void]] = [:]
	
	public init(transformer: Transformer<T>, name: String = String(reflecting: T.self)) {
		self.transformer = transformer
		let name = MD5(name)
		UserDefaults.standard.addSuite(named: name)
		self.defaults = UserDefaults(suiteName: name) ?? UserDefaults.standard
		self.name = name
	}
	
	public func object(forKey key: String) -> T? {
		return try? transformer.fromData(defaults.data(forKey: key)~!)
	}
	
	public func entry(forKey key: String) throws -> Entry<T> {
		return try Entry.init(object: object(forKey: key)~!, expiry: .never)
	}
	
	public func allObjects() -> [T] {
		return (try? dictionary.values.map({
			try transformer.fromData(($0 as? Data)~!)
		})) ?? []
	}
	
	public func removeObject(forKey key: String) throws {
		defaults.removeObject(forKey: key)
		notifyStorageObservers(about: .remove(key: key))
		notifyObserver(forKey: key, about: .remove)
	}
	
	public func setObject(_ object: T, forKey key: String, expiry: Expiry? = nil) throws {
		try defaults.set(transformer.toData(object), forKey: key)
		notifyStorageObservers(about: .set(key: key))
		notifyObserver(forKey: key, about: .set(value: object))
	}
	
	public func existsObject(forKey key: String) -> Bool {
		return defaults.value(forKey: key) != nil
	}
	
	public func removeAll() throws {
		UserDefaults.standard.removePersistentDomain(forName: name)
		notifyStorageObservers(about: .removeAll)
		notifyKeyObservers(about: .remove)
	}
	
	public func synchronize() throws {
		guard defaults.synchronize() else {
			throw StorageError.decodingFailed
		}
	}
	
	public func removeExpiredObjects() throws {}
	
	public func isExpiredObject(forKey key: String) -> Bool {
		return false
	}
	
}

extension UserDefaultsStorage where T: Codable {
	
	public convenience init(name: String = String(reflecting: T.self)) {
		self.init(transformer: Transformer(), name: name)
	}
	
}

extension UserDefaultsStorage: StorageObservationRegistry {
	
	@discardableResult
	public func addStorageObserver<O: AnyObject>(_ observer: O, closure: @escaping (O, UserDefaultsStorage, StorageChange) -> Void) -> ObservationToken {
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

extension UserDefaultsStorage: KeyObservationRegistry {
	
	@discardableResult
	public func addObserver<O: AnyObject>(_ observer: O, forKey key: String,
										  closure: @escaping (O, UserDefaultsStorage<T>, KeyChange<T>) -> Void) -> ObservationToken {
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
