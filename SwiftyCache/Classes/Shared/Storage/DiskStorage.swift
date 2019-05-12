import Foundation

/// Save objects to file on disk
final public class DiskStorage<T> {
	
	enum Error: Swift.Error {
		case fileEnumeratorFailed
	}
	
	//public var count: Int { return infoAtPath.count }
	/// File manager to read/write to the disk
	public let fileManager: FileManager
	/// Configuration
	private let config: DiskConfig
	private var _expireWhenNoReferences: Bool
	private let path: String
	private lazy var info: [String: EntityInfo] = getAllInfo()
	public var allKeys: Set<String> {
		return Set(info.map { $0.value.entity.key })
	}
	public var count: Int { return info.count }
	/// The closure to be called when single file has been removed
	var onRemove: ((String) -> Void)?
	
	weak var context: CacheContext?
	var storageName: String?
	//public var keys: [String] { return infoAtPath.map { $0.value.key } }
	//fileprivate lazy var infoAtPath: [String: DiskEntity] = self.getInfo()
	fileprivate lazy var cacheEncoder = CacheJSONEncoder()
	fileprivate lazy var cacheDecoder = CacheJSONDecoder()

	private let transformer: Transformer<T>
	
	fileprivate let resourceKeys: [URLResourceKey] = [
		.isDirectoryKey,
		.contentModificationDateKey,
		.totalFileAllocatedSizeKey
	]
	
	convenience init(config: DiskConfig, fileManager: FileManager = FileManager.default, _expireWhenNoReferences: Bool, transformer: Transformer<T>) throws {
		let url: URL
		if let directory = config.directory {
			url = directory
		} else {
			url = try fileManager.url(
				for: .cachesDirectory,
				in: .userDomainMask,
				appropriateFor: nil,
				create: true
			)
		}
		let path = url.appendingPathComponent(MD5(config.name)).path
		self.init(config: config, fileManager: fileManager, path: path, _expireWhenNoReferences: _expireWhenNoReferences, transformer: transformer)
		try createDirectory()
		#if os(iOS) || os(tvOS)
		if let protectionType = config.protectionType {
			try fileManager.setAttributes([.protectionKey: protectionType], ofItemAtPath: path)
		}
		#endif
	}
	
	required init(config: DiskConfig, fileManager: FileManager = FileManager.default, path: String, _expireWhenNoReferences: Bool, transformer: Transformer<T>) {
		self.config = config
		self.fileManager = fileManager
		self.path = path
		self.transformer = transformer
		self._expireWhenNoReferences = _expireWhenNoReferences
	}
	
	public convenience init(config: DiskConfig, fileManager: FileManager = FileManager.default, transformer: Transformer<T>) throws {
		try self.init(config: config, fileManager: fileManager, _expireWhenNoReferences: false, transformer: transformer)
	}
	
	public convenience init(config: DiskConfig, fileManager: FileManager = FileManager.default, path: String, transformer: Transformer<T>) {
		self.init(config: config, fileManager: fileManager, path: path, _expireWhenNoReferences: false, transformer: transformer)
	}
	
}

extension DiskStorage: StorageAware {
	
	public func existsObject(forKey key: String) -> Bool {
		return fileManager.fileExists(atPath: makeFilePath(for: key))
	}
	
	public func isExpiredObject(forKey key: String) -> Bool {
		return isExpiredObject(atPath: makeFilePath(for: key))
	}
	
	public func object(forKey key: String) -> T? {
		return try? entity(forKey: key).1.object
	}
	
	public func entry(forKey key: String) throws -> Entry<T> {
		return try entity(forKey: key).1
	}
	
	private func isExpiredObject(atPath path: String) -> Bool {
		guard var info = self.info[path] else { return true }
		if let context = self.context {
			let referenced = info.entity.referencedKeys
			for (name, keys) in referenced {
				guard let disk = context.diskStorage(name: name) else { continue }
				for _key in keys {
					if !disk.isExpiredObject(forKey: _key) {
						return false
					} else {
						info.entity.referencedKeys[name]?.remove(_key)
					}
				}
			}
			self.info[path] = info
			return info.entity.referencedKeys.isEmpty && (info.entity.removeIfNoRef ?? _expireWhenNoReferences) || info.expiry.isExpired
		}
		return info.expiry.isExpired
	}
	
	private func getAllInfo() -> [String: EntityInfo] {
		do {
			let urlArray = try allURLs()
			var result = [String: EntityInfo].init(minimumCapacity: urlArray.count)
			let resourceKeysSet = Set(resourceKeys)
			for url in urlArray {
				do {
					let resourceValues = try url.resourceValues(forKeys: resourceKeysSet)
					guard resourceValues.isDirectory != true else {
						continue
					}
					let path = url.path
					let data = try (NSKeyedUnarchiver.unarchiveObject(withFile: path) as? Data)~!
					let expiryDate = try resourceValues.contentModificationDate~!
					let fileSize = resourceValues.totalFileAllocatedSize ?? data.count
					let entity = try DataSerializer.getInfo(from: data)
					result[path] = EntityInfo(expiry: Expiry.date(expiryDate), entity: entity, fileSize: fileSize)
				} catch {}
			}
			return result
		} catch {
			return [:]
		}
	}
	
	private func entity(atPath path: String) throws -> (EntityInfo, Entry<T>) {
		guard let info = info[path] else {throw StorageError.notFound }
		let data = try (NSKeyedUnarchiver.unarchiveObject(withFile: path) as? Data)~!
		let attributes = try fileManager.attributesOfItem(atPath: path)
		let (_, object) = try DataSerializer.deserialize(data: data, transformer: transformer)
		guard let date = attributes[.modificationDate] as? Date else {
			throw StorageError.malformedFileAttributes
		}
		return (info, Entry(object: object, expiry: Expiry.date(date), filePath: path))
	}
	
	private func entity(forKey key: String) throws -> (EntityInfo, Entry<T>) {
		let path = makeFilePath(for: key)
		let (info, object) = try entity(atPath: path)
		self.info[path] = info
		return (info, object)
	}
	
	public func setObject(_ object: T, forKey key: String, expiry: Expiry? = nil) throws {
		try setObject(object, forKey: key, referencedBy: nil, expiry: expiry)
	}
	
	func setObject(_ object: T, forKey key: String, referencedBy referenced: (String, String)?, expiry: Expiry? = nil, expireWhenNoReferences: Bool? = nil) throws {
		let expiry = expiry ?? config.expiry
		var objectInfo = getInfo(forKey: key)
		objectInfo.expiry = expiry
		objectInfo.entity.removeIfNoRef = expireWhenNoReferences ?? objectInfo.entity.removeIfNoRef
		if let refs = referenced {
			objectInfo.entity.referencedKeys[refs.0, default: []].insert(refs.1)
		}
		let data: Data
		if let context = self.context, let _data = encode(object: object, forKey: key, getData: true) {
			try objectInfo.entity.referencedKeys.forEach {
				guard let storage = context.storages[$0.key] else { return }
				for key in $0.value {
					guard !(referenced?.0 == $0.key && referenced?.1 == key) else { continue }
					try storage.removeFromMemory(forKey: key)
				}
			}
			data = try DataSerializer.serialize(data: _data, info: objectInfo.entity)
		} else {
			data = try DataSerializer.serialize(object: object, info: objectInfo.entity, transformer: transformer)
		}
		objectInfo.fileSize = data.count
		try set(data, forKey: key, expiry: expiry)
		try set(info: objectInfo, forKey: key)
	}
	
	@discardableResult
	func encode(object: T, forKey key: String, getData: Bool) -> Data? {
		if let context = self.context, (object as? Encodable) != nil, let selfStorage = storageName {
			if getData {
			let data = try? cacheEncoder.saveAny(object, to: context, key: key, storage: selfStorage).0
			return data
			} else {
				_ = try? cacheEncoder.goThrough(object, to: context, key: key, storage: selfStorage)
			}
		}
		return nil
	}
	
	private func set(info: EntityInfo, forKey key: String) throws {
		self.info[makeFilePath(for: key)] = info
	}
	
	private func getInfo(forKey key: String) -> EntityInfo {
		if let info = self.info[makeFilePath(for: key)] {
			return info
		}
		return EntityInfo(expiry: config.expiry, entity: DiskEntity(key: key), fileSize: 0)
	}
	
	private func infoKey(for key: String) -> String {
		return key + "_info"
	}
	
	private func set(_ data: Data, forKey key: String, expiry: Expiry? = nil) throws {
		let expiry = expiry ?? config.expiry
		let filePath = makeFilePath(for: key)
		NSKeyedArchiver.archiveRootObject(data as NSData, toFile: filePath)
		try fileManager.setAttributes([.modificationDate: expiry.date], ofItemAtPath: filePath)
		info[filePath]?.expiry = expiry
	}
	
	public func removeObject(forKey key: String) throws {
		let path = makeFilePath(for: key)
		guard let objectInfo = info[path] else { return }
		if let context = context {
			for (name, keys) in objectInfo.entity.referencedKeys {
				for _key in keys {
					if let disk = context.diskStorage(name: name), !disk.isExpiredObject(forKey: _key) {
						throw StorageError.objectIsReferenced
					}
				}
			}
		}
		try removeObject(atPath: path)
	}
	
	fileprivate func removeObject(atPath path: String) throws {
		try fileManager.removeItem(atPath: path)
		let key = info[path]?.entity.key
		info[path] = nil
		if let _key = key {
			onRemove?(_key)
		}
	}
	
	public func removeAll() throws {
		try removeAllBlock()()
	}
	
	func removeAllBlock() -> () throws -> () {
		return { [weak self, fileManager, path] in
			try fileManager.removeItem(atPath: path)
			self?.info = [:]
			try self?.createDirectory()
		}
	}
	
	public func allEntries() throws -> [Entry<T>] {
		let result = try allURLs().map({ try entity(atPath: $0.path).1 })
		return result
	}
	
	public func allObjects() -> [T] {
		let result = try? allURLs().map({ try entity(atPath: $0.path).1.object })
		return result ?? []
	}
	
	public func removeExpiredObjects() throws {
		var resourceObjects = [ResourceObject]()
		var filesToDelete = [String]()
		var totalSize: UInt = 0
		filesToDelete.reserveCapacity(self.info.count)
		resourceObjects.reserveCapacity(self.info.count)
		let resourceKeysSet = Set(resourceKeys)
		for (path, _) in self.info {
			let url = URL(fileURLWithPath: path)
			let resourceValues = try url.resourceValues(forKeys: resourceKeysSet)
			guard resourceValues.isDirectory != true else {
				continue
			}
			if isExpiredObject(atPath: path) {
				filesToDelete.append(path)
				continue
			}
			if let fileSize = resourceValues.totalFileAllocatedSize {
				totalSize += UInt(fileSize)
				resourceObjects.append((url: url, resourceValues: resourceValues))
			}
		}
		// Remove expired objects
		for path in filesToDelete {
			try removeObject(atPath: path)
		}
		// Remove objects if storage size exceeds max size
		try removeResourceObjects(resourceObjects, totalSize: totalSize)
	}
	
}

extension DiskStorage {
	/**
	Sets attributes on the disk cache folder.
	- Parameter attributes: Directory attributes
	*/
	func setDirectoryAttributes(_ attributes: [FileAttributeKey: Any]) throws {
		//try fileManager.setAttributes(attributes, ofItemAtPath: path)
	}
}

typealias ResourceObject = (url: Foundation.URL, resourceValues: URLResourceValues)

extension DiskStorage {
	/**
	Builds file name from the key.
	- Parameter key: Unique key to identify the object in the cache
	- Returns: A md5 string
	*/
	func makeFileName(for key: String) -> String {
		let result: String
		let fileExtension = URL(fileURLWithPath: key).pathExtension
		let fileName = MD5(key)
		switch fileExtension.isEmpty {
		case true:
			result = fileName
		case false:
			result = "\(fileName).\(fileExtension)"
		}
		return result
	}
	
	/**
	Builds file path from the key.
	- Parameter key: Unique key to identify the object in the cache
	- Returns: A string path based on key
	*/
	func makeFilePath(for key: String) -> String {
		return "\(path)/\(makeFileName(for: key))"
	}
	
	func allURLs() throws -> [URL] {
		let storageURL = URL(fileURLWithPath: path)
		let fileEnumerator = fileManager.enumerator(
			at: storageURL,
			includingPropertiesForKeys: resourceKeys,
			options: .skipsHiddenFiles,
			errorHandler: nil
		)
		
		guard let urlArray = fileEnumerator?.allObjects as? [URL] else {
			throw Error.fileEnumeratorFailed
		}
		return urlArray
	}
	
	/// Calculates total disk cache size.
	public func totalSize() throws -> UInt64 {
		var size: UInt64 = 0
		let contents = try fileManager.contentsOfDirectory(atPath: path)
		for pathComponent in contents {
			let filePath = NSString(string: path).appendingPathComponent(pathComponent)
			let attributes = try fileManager.attributesOfItem(atPath: filePath)
			if let fileSize = attributes[.size] as? UInt64 {
				size += fileSize
			}
		}
		return size
	}
	
	/**
	Removes objects if storage size exceeds max size.
	- Parameter objects: Resource objects to remove
	- Parameter totalSize: Total size
	*/
	func removeResourceObjects(_ objects: [ResourceObject], totalSize: UInt) throws {
		guard config.maxSize > 0 && totalSize > config.maxSize else {
			return
		}
		
		var totalSize = totalSize
		let targetSize = config.maxSize / 2
		
		let sortedFiles = objects.sorted {
			if let time1 = $0.resourceValues.contentModificationDate?.timeIntervalSinceReferenceDate,
				let time2 = $1.resourceValues.contentModificationDate?.timeIntervalSinceReferenceDate {
				return time1 > time2
			} else {
				return false
			}
		}
		
		for file in sortedFiles {
			try removeObject(atPath: file.url.path)
			if let fileSize = file.resourceValues.totalFileAllocatedSize {
				totalSize -= UInt(fileSize)
			}
			if totalSize < targetSize {
				break
			}
		}
	}
	
	func createDirectory() throws {
		guard !fileManager.fileExists(atPath: path) else {
			return
		}
		
		try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true,
										attributes: nil)
	}
	
	/**
	Removes the object from the cache if it's expired.
	- Parameter key: Unique key to identify the object in the cache
	*/
	public func removeObjectIfExpired(forKey key: String) throws {
		let path = makeFilePath(for: key)
		if isExpiredObject(atPath: path) {
			try removeObject(atPath: path)
		}
	}
	
}

extension DiskStorage {
	
	public func transform<U>(transformer: Transformer<U>) -> DiskStorage<U> {
		let result = DiskStorage<U>(config: config, fileManager: fileManager, path: path, transformer: transformer)
		result.context = context
		result.storageName = storageName
		result.onRemove = onRemove
		result.info = info
		result._expireWhenNoReferences = _expireWhenNoReferences
		return result
	}
	
}

extension DiskStorage where T: CacheReferenceable {
	
	public var expireWhenNoReferences: Bool {
		get { return _expireWhenNoReferences }
		set { _expireWhenNoReferences = newValue }
	}
	
	public convenience init(config: DiskConfig, fileManager: FileManager = FileManager.default, path: String, expireWhenNoReferences: Bool, transformer: Transformer<T>) {
		self.init(config: config, fileManager: fileManager, path: path, _expireWhenNoReferences: expireWhenNoReferences, transformer: transformer)
	}
	
	public convenience init(config: DiskConfig, fileManager: FileManager = FileManager.default, expireWhenNoReferences: Bool, transformer: Transformer<T>) throws {
		try self.init(config: config, fileManager: fileManager, _expireWhenNoReferences: expireWhenNoReferences, transformer: transformer)
	}
	
	public func setObject(_ object: T, forKey key: String, expiry: Expiry? = nil, expireWhenNoReferences: Bool) throws {
		try setObject(object, forKey: key, referencedBy: nil, expiry: expiry, expireWhenNoReferences: expireWhenNoReferences)
	}
	
}

private struct EntityInfo {
	var expiry: Expiry
	var entity: DiskEntity
	var fileSize: Int
}

