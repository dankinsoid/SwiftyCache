//
//  VdRx.swift
//  RxTableView
//
//  Created by Данил Войдилов on 26/03/2019.
//  Copyright © 2019 Pochtabank. All rights reserved.
//

import Foundation

public protocol CacheReferenceable: Codable {
	var cachePrimaryKey: String { get }
}

protocol CacheStorageProtocol: class {
	func removeAll() throws
	func removeObject(forKey key: String) throws
	func removeFromMemory(forKey key: String)
	func dataDiskStorage() -> DiskStorage<Data>
	func synchronize() throws
	func removeExpiredObjects() throws
}

public final class CacheContext {
	
	public static let `default` = CacheContext()
	
	fileprivate static var contexts: [String: CacheContext] = [:]
	fileprivate static let fileManager = FileManager.default
	private(set) var storages: [String: CacheStorageProtocol] = [:]
	private let memoryConfig: MemoryConfig
	private let diskConfig: DiskConfig
	private let path: String?
	public let name: String
	public let immediatelyOnDisk: Bool
	
	private convenience init() {
		self.init(name: "DefaultCacheContext")
	}
	
	public init(name: String, immediatelyOnDisk: Bool = true, defaultMemoryConfig: MemoryConfig? = nil, defaultDiskConfig: DiskConfig? = nil) {
		self.name = name
		self.immediatelyOnDisk = immediatelyOnDisk
		self.memoryConfig = defaultMemoryConfig ?? MemoryConfig(expiry: .never, countLimit: 0, totalCostLimit: 0)
		let url = defaultDiskConfig?.directory ?? CacheContext.createCacheDirectory(name: name)
		self.diskConfig = defaultDiskConfig ?? DiskConfig(name: name, expiry: .never, directory: url)
		self.path = url?.path
		CacheContext.contexts[name] = self
	}
	
	fileprivate static func createCacheDirectory(name: String) -> URL? {
		do {
			let url = try fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first~!.appendingPathComponent("StoragesContextCaches/\(MD5(name))")
			try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
			return url
		} catch {
			return nil
		}
	}
	
	//Storages
	
	func nameForStorage<T>(of type: T.Type, name: String?) -> String {
		return String(reflecting: type) + (name ?? "")
	}
	
	fileprivate func cacheStorage<T>(for type: T.Type, name storageName: String?) -> Storage<T>? {
		let name = nameForStorage(of: type, name: storageName)
		return (storages[name] as? CStorage<T>)?.storage
	}
	
	func createStorage<T>(of type: T.Type, transformer: Transformer<T>, diskConfig dc: DiskConfig? = nil, memoryConfig mc: MemoryConfig? = nil) -> Storage<T> {
		let name = nameForStorage(of: type, name: dc?.name)
		let storage: Storage<T>
		let _diskConfig = DiskConfig(name: name, expiry: (dc ?? diskConfig).expiry, maxSize: (dc ?? diskConfig).maxSize, directory: (dc ?? diskConfig).directory, protectionType: (dc ?? diskConfig).protectionType)
		let memoryStorage = MemoryStorage<T>(config: mc ?? memoryConfig)
		let diskStorage: DiskStorage<T>
		do {
			diskStorage = try DiskStorage<T>(config: _diskConfig, _expireWhenNoReferences: false, transformer: transformer)
		} catch {
			diskStorage = DiskStorage<T>(config: _diskConfig, path: "", _expireWhenNoReferences: false, transformer: transformer)
		}
		let hybridStorage = HybridStorage<T>(memoryStorage: memoryStorage, diskStorage: diskStorage, immediatelyOnDisk: immediatelyOnDisk)
		storage = Storage<T>(hybridStorage: hybridStorage)
		storage.diskStorage.context = self
		storage.diskStorage.storageName = name
		storages[name] = CStorage(storage)
		return storage
	}
	
	public func storage<T: Codable>(for type: T.Type, memoryConfig: MemoryConfig? = nil, diskConfig: DiskConfig? = nil) -> Storage<T> {
		if let result = cacheStorage(for: type, name: diskConfig?.name) {
			return result
		}
		return createStorage(of: type, transformer: transformer(), diskConfig: diskConfig, memoryConfig: memoryConfig)
	}
	
	public func storage<T>(for type: T.Type, transformer: Transformer<T>, memoryConfig: MemoryConfig? = nil, diskConfig: DiskConfig? = nil) -> Storage<T> {
		if let result = cacheStorage(for: type, name: diskConfig?.name) {
			return result
		}
		return createStorage(of: type, transformer: transformer, diskConfig: diskConfig, memoryConfig: memoryConfig)
	}
	
	func anyStorage<T>(of type: T.Type) -> Storage<T> {
		if let result = cacheStorage(for: type, name: nil) {
			return result
		}
		return createStorage(of: type, transformer: anyTransformer())
	}
	
	func diskStorage(name: String) -> DiskStorage<Data>? {
		if let storage = storages[name] {
			return storage.dataDiskStorage()
		}
		let _diskConfig = DiskConfig(name: MD5(name), expiry: diskConfig.expiry, maxSize: diskConfig.maxSize, directory: diskConfig.directory, protectionType: diskConfig.protectionType)
		let disk = try? DiskStorage(config: _diskConfig, fileManager: CacheContext.fileManager, transformer: Transformer<Data>())
		disk?.context = self
		disk?.storageName = name
		return disk
	}
	
	//Transformers
	
	fileprivate func transformer<T: Codable>() -> Transformer<T> {
		let decoder = CacheJSONDecoder()
		let encoder = CacheJSONEncoder()
		return Transformer(toData: encoder.encode,
						   fromData: {[weak self, name] data in
							let context = self ?? CacheContext(name: name)
							return try decoder.getObject(T.self, from: data, for: context)
		})
	}
	
	fileprivate func anyTransformer<T>() -> Transformer<T> {
		let decoder = CacheJSONDecoder()
		let encoder = CacheJSONEncoder()
		return Transformer(toData: encoder.encodeAny,
						   fromData: {[weak self, name] data in
							let context = self ?? CacheContext(name: name)
							return try decoder.getAnyObject(T.self, from: data, for: context)
		})
	}
	
	
	//Objects
	
	public func set<T: CacheReferenceable>(_ object: T) throws {
		try storage(for: T.self).setObject(object)
	}
	
	public func existsObject<T>(_ type: T.Type, forKey key: String) -> Bool {
		return anyStorage(of: T.self).existsObject(forKey: key)
	}
	
	//Common
	
	public func clean() throws {
		try storages.forEach {
			try $0.value.removeAll()
		}
	}
	
	public func synchronize(completion: Completion<Void>? = nil) {
		DispatchQueue.global().async {
			do {
				for storage in self.storages.values {
					try storage.synchronize()
				}
				completion?(.success(()))
			} catch {
				completion?(.failure(error))
			}
		}
	}
	
	public func removeExpiredObjects(completion: Completion<Void>? = nil) {
		DispatchQueue.global().async {
			do {
				for storage in self.storages.values {
					try storage.removeExpiredObjects()
				}
				completion?(.success(()))
			} catch {
				completion?(.failure(error))
			}
		}
	}
	
}

fileprivate final class CStorage<T>: CacheStorageProtocol {
	private weak var _storage: Storage<T>?
	let disk: DiskStorage<T>
	let memoryConfig: MemoryConfig
	let immediatelyOnDisk: Bool
	
	var storage: Storage<T> {
		return _storage ?? Storage(hybridStorage: HybridStorage(
			memoryStorage: MemoryStorage(config: memoryConfig),
			diskStorage: disk,
			immediatelyOnDisk: immediatelyOnDisk))
	}
	
	init(_ storage: Storage<T>) {
		_storage = storage
		disk = storage.diskStorage
		memoryConfig = storage.memoryStorage.config
		immediatelyOnDisk = storage.immediatelyOnDisk
	}
	
	func removeAll() throws {
		if let storage = _storage {
			try storage.removeAll()
		} else {
			try disk.removeAll()
		}
	}
	
	func removeObject(forKey key: String) throws {
		if let storage = _storage {
			try storage.removeObject(forKey: key)
		} else {
			try disk.removeObject(forKey: key)
		}
	}
	
	func removeFromMemory(forKey key: String) {
		_storage?.memoryStorage.removeObject(forKey: key)
	}
	
	func dataDiskStorage() -> DiskStorage<Data> {
		return disk.transform(transformer: Transformer())
	}
	
	func synchronize() throws {
		try? _storage?.synchronize()
	}
	
	func removeExpiredObjects() throws {
		if let storage = _storage {
			try storage.removeExpiredObjects()
		} else {
			try disk.removeExpiredObjects()
		}
	}
	
}
