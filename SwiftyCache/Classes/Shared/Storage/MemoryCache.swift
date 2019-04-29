//
//  MemoryCache.swift
//  RxTableView
//
//  Created by Данил Войдилов on 12/04/2019.
//  Copyright © 2019 Pochtabank. All rights reserved.
//

import Foundation

private class CacheEntry<Key: Hashable, Value> {
	var key: Key
	var value: Value
	var cost: Int
	var prevByCost: CacheEntry?
	var nextByCost: CacheEntry?
	
	init(key: Key, value: Value, cost: Int) {
		self.key = key
		self.value = value
		self.cost = cost
	}
	
}

final class MemoryCache<Key: Hashable, Value> {
	
	private var _entries: [Key: CacheEntry<Key, Value>] = [:]
	private let _lock = NSLock()
	private var _totalCost = 0
	private var _head: CacheEntry<Key, Value>?
	var allKeys: Set<Key>  {
		let result: Set<Key>
		_lock.lock()
		result = Set(_entries.keys)
		_lock.unlock()
		return result
	}
	var allValues: [Value]  {
		let result: [Value]
		_lock.lock()
		result = _entries.map({ $0.value.value })
		_lock.unlock()
		return result
	}
	var asDictionary: [Key: Value]  {
		let result: [Key: Value]
		_lock.lock()
		result = _entries.mapValues({ $0.value })
		_lock.unlock()
		return result
	}
	var count: Int {
		let result: Int
		_lock.lock()
		result = _entries.count
		_lock.unlock()
		return result
	}
	var name: String = ""
	var totalCostLimit: Int = 0 // limits are imprecise/not strict
	var countLimit: Int = 0 // limits are imprecise/not strict
	var evictsObjectsWithDiscardedContent: Bool = false
	
	public init() {}
	
	var willEvict: ((Value, Key) -> ())?
	var didEvict: ((Value, Key) -> ())?
	
	func object(forKey key: Key) -> Value? {
		var object: Value?
		
		_lock.lock()
		if let entry = _entries[key] {
			object = entry.value
		}
		_lock.unlock()
		
		return object
	}
	
	func setObject(_ obj: Value, forKey key: Key) {
		setObject(obj, forKey: key, cost: 0)
	}
	
	func exist(forKey key: Key) -> Bool {
		return _entries[key] != nil
	}
	
	private func remove(_ entry: CacheEntry<Key, Value>) {
		let oldPrev = entry.prevByCost
		let oldNext = entry.nextByCost
		
		oldPrev?.nextByCost = oldNext
		oldNext?.prevByCost = oldPrev
		
		if entry === _head {
			_head = oldNext
		}
	}
	
	private func insert(_ entry: CacheEntry<Key, Value>) {
		guard var currentElement = _head else {
			// The cache is empty
			entry.prevByCost = nil
			entry.nextByCost = nil
			
			_head = entry
			return
		}
		
		guard entry.cost > currentElement.cost else {
			// Insert entry at the head
			entry.prevByCost = nil
			entry.nextByCost = currentElement
			currentElement.prevByCost = entry
			
			_head = entry
			return
		}
		
		while let nextByCost = currentElement.nextByCost, nextByCost.cost < entry.cost {
			currentElement = nextByCost
		}
		
		// Insert entry between currentElement and nextElement
		let nextElement = currentElement.nextByCost
		
		currentElement.nextByCost = entry
		entry.prevByCost = currentElement
		
		entry.nextByCost = nextElement
		nextElement?.prevByCost = entry
	}
	
	func setObject(_ obj: Value, forKey key: Key, cost g: Int) {
		let g = max(g, 0)
		
		_lock.lock()
		
		let costDiff: Int
		
		if let entry = _entries[key] {
			costDiff = g - entry.cost
			entry.cost = g
			
			entry.value = obj
			
			if costDiff != 0 {
				remove(entry)
				insert(entry)
			}
		} else {
			let entry = CacheEntry(key: key, value: obj, cost: g)
			_entries[key] = entry
			insert(entry)
			costDiff = g
		}
		
		_totalCost += costDiff
		
		var purgeAmount = (totalCostLimit > 0) ? (_totalCost - totalCostLimit) : 0
		while purgeAmount > 0 {
			if let entry = _head {
				willEvict?(entry.value, key)
				
				_totalCost -= entry.cost
				purgeAmount -= entry.cost
				
				remove(entry) // _head will be changed to next entry in remove(_:)
				_entries[key] = nil
				didEvict?(entry.value, key)
			} else {
				break
			}
		}
		
		var purgeCount = (countLimit > 0) ? (_entries.count - countLimit) : 0
		while purgeCount > 0 {
			if let entry = _head {
				willEvict?(entry.value, entry.key)
				_totalCost -= entry.cost
				purgeCount -= 1
				
				remove(entry) // _head will be changed to next entry in remove(_:)
				_entries[entry.key] = nil
				didEvict?(entry.value, entry.key)
			} else {
				break
			}
		}
		
		_lock.unlock()
	}
	
	func removeObject(forKey key: Key) {
		
		_lock.lock()
		if let entry = _entries.removeValue(forKey: key) {
			_totalCost -= entry.cost
			remove(entry)
		}
		_lock.unlock()
	}
	
	func removeAllObjects() {
		_lock.lock()
		_entries.removeAll()
		
		while let currentElement = _head {
			let nextElement = currentElement.nextByCost
			
			currentElement.prevByCost = nil
			currentElement.nextByCost = nil
			
			_head = nextElement
		}
		
		_totalCost = 0
		_lock.unlock()
	}
}
