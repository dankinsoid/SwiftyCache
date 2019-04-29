import Foundation

/// A protocol used for saving and loading from storage
public protocol GenericStorage {
	associatedtype T
}

/// A protocol used for saving and loading from storage
public protocol StorageAware: GenericStorage {
	/**
	The number of cached objects
	*/
	var count: Int { get }
	
	/**
	Tries to retrieve the object from the storage.
	- Parameter key: Unique key to identify the object in the cache
	- Returns: Cached object or error if not found
	*/
	func object(forKey key: String) -> T?
	
	/**
	Tries to retrieve the object from the storage.
	- Parameter key: Unique key to identify the object in the cache
	- Returns: Cached object or error if not found
	*/
	func entry(forKey key: String) throws -> Entry<T>
	
	/**
	Tries to retrieve the objects from the storage.
	- Returns: Cached objects
	*/
	func allObjects() -> [T]
	
	/**
	Removes the object by the given key.
	- Parameter key: Unique key to identify the object.
	*/
	func removeObject(forKey key: String) throws
	
	/**
	Saves passed object.
	- Parameter key: Unique key to identify the object in the cache.
	- Parameter object: Object that needs to be cached.
	- Parameter expiry: Overwrite expiry for this object only.
	*/
	func setObject(_ object: T, forKey key: String, expiry: Expiry?) throws
	
	/**
	Check if an object exist by the given key.
	- Parameter key: Unique key to identify the object.
	*/
	func existsObject(forKey key: String) -> Bool
	
	/**
	Removes all objects from the cache storage.
	*/
	func removeAll() throws
	
	/**
	Clears all expired objects.
	*/
	func removeExpiredObjects() throws
	
	/**
	Check if an expired object by the given key.
	- Parameter key: Unique key to identify the object.
	*/
	func isExpiredObject(forKey key: String) -> Bool
}

extension StorageAware where T: CacheReferenceable {
	
	@discardableResult
	public func setObject(_ object: T, expiry: Expiry? = nil) throws -> String {
		try setObject(object, forKey: object.cachePrimaryKey, expiry: expiry)
		return object.cachePrimaryKey
	}
	
}
