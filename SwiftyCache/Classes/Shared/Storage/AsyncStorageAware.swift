//
//  AsyncStorageAware.swift
//  RxTableView
//
//  Created by Данил Войдилов on 12/04/2019.
//  Copyright © 2019 Pochtabank. All rights reserved.
//

import Foundation

/// A protocol used for saving and loading from storage
public protocol AsyncStorageAware where Storage.T == T {
	associatedtype T
	associatedtype Storage: StorageAware
	var innerStorage: Storage { get }
	
	func count(completion: @escaping (Int) -> ())
	
	/**
	Tries to retrieve the object from the storage.
	- Parameter key: Unique key to identify the object in the cache
	- Returns: Cached object or nil if not found
	*/
	func object(forKey key: String, completion: @escaping (T?) -> ())
	
	func allObjects(completion: @escaping ([T]) -> ())
	
	
	/**
	Removes the object by the given key.
	- Parameter key: Unique key to identify the object.
	*/
	func removeObject(forKey key: String, completion: Completion<()>?)
	
	/**
	Saves passed object.
	- Parameter key: Unique key to identify the object in the cache.
	- Parameter object: Object that needs to be cached.
	- Parameter expiry: Overwrite expiry for this object only.
	*/
	func setObject(_ object: T, forKey key: String, expiry: Expiry?, completion: Completion<()>?)
	
	/**
	Check if an object exist by the given key.
	- Parameter key: Unique key to identify the object.
	*/
	func existsObject(forKey key: String, completion: @escaping (Bool) -> ())
	
	/**
	Removes all objects from the cache storage.
	*/
	func removeAll(completion: Completion<()>?)
	
	/**
	Clears all expired objects.
	*/
	func removeExpiredObjects(completion: Completion<()>?)
	
	/**
	Check if an expired object by the given key.
	- Parameter key: Unique key to identify the object.
	*/
	func isExpiredObject(forKey key: String, completion: @escaping (Bool) -> ())
}

extension AsyncStorageAware where Storage.T: CacheReferenceable {
	
	public func set(_ object: Storage.T, expiry: Expiry, completion: Completion<()>? = nil) {
		setObject(object, forKey: object.cachePrimaryKey, expiry: expiry, completion: completion)
	}
	
}
