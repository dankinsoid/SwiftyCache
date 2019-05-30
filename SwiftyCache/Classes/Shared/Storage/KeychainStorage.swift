//
//  KeyChan.swift
//  RxTableView
//
//  Created by Данил Войдилов on 29/05/2019.
//  Copyright © 2019 Pochtabank. All rights reserved.
//

import Foundation
import Security
import VDCache

public enum KeychainRegulator {
	public static func clearKeychain() throws {
		let lock = NSLock()
		lock.lock()
		defer { lock.unlock() }
		let query: [String: Any] = [:]
		let lastResultCode = SecItemDelete(query as CFDictionary)
		guard lastResultCode == noErr else {
			throw KeychainError.unhandledError(status: lastResultCode)
		}
	}
}

public final class KeychainStorage<T>: StorageAware {
	
	public let accessGroup: String?
	public let access: KeychainSwiftAccessOptions?
	public let synchronizeWithICloud: Bool
	private let lock = NSLock()
	//private var lastResultCode: OSStatus = noErr
	public let name: String
	private let transformer: Transformer<T>
	
	public init(name: String, synchronizeWithICloud: Bool = false, accessGroup: String? = nil, withAccess access: KeychainSwiftAccessOptions? = nil, transformer: Transformer<T>) {
		self.name = name
		self.transformer = transformer
		self.synchronizeWithICloud = synchronizeWithICloud
		self.accessGroup = accessGroup
		self.access = access
	}
	
	public var count: Int {
		return (try? getCount()) ?? 0
	}
	
	public func object(forKey key: String) -> T? {
		lock.lock()
		defer { lock.unlock() }
		return try? transformer.fromData(getDataNoLock(key)~!)
	}
	
	public func entry(forKey key: String) throws -> Entry<T> {
		lock.lock()
		defer { lock.unlock() }
		let any = try getItemsNoLock(data: true, attributes: true, finalKey: getKey(key))
		guard let dict = any as? [String: Any],
			let data = dict[KeychainSwiftConstants.valueData] as? Data else {
				throw KeychainError.unexpectedPasswordData
		}
		let object = try transformer.fromData(data)
		var expiry = Expiry.never
		if let string = dict[KeychainSwiftConstants.description] as? String,
			let date = try? expiryDate(attribute: string) {
			expiry = .date(date)
		}
		return Entry(object: object, expiry: expiry, filePath: nil)
	}
	
	public func allObjects() -> [T] {
		lock.lock()
		defer { lock.unlock() }
		return (try? getAllData()?.map({ try transformer.fromData($0) })) ?? []
	}
	
	public func removeObject(forKey key: String) throws {
		lock.lock()
		defer { lock.unlock() }
		try deleteNoLock(key)
	}
	
	public func setObject(_ object: T, forKey key: String, withAccess access: KeychainSwiftAccessOptions?, expiry: Expiry? = nil) throws {
		// The lock prevents the code to be run simlultaneously
		// from multiple threads which may result in crashing
		lock.lock()
		defer { lock.unlock() }
		try setNoLock(transformer.toData(object), forKey: key, withAccess: access ?? self.access, expiry: expiry)
	}
	
	public func setObject(_ object: T, forKey key: String, expiry: Expiry? = nil) throws {
		try setObject(object, forKey: key, withAccess: access, expiry: expiry)
	}
	
	public func existsObject(forKey key: String) -> Bool {
		lock.lock()
		defer { lock.unlock() }
		let result = try? getItemsNoLock(data: false, attributes: true, finalKey: getKey(key))
		return result != nil
	}
	
	public func removeAll() throws {
		lock.lock()
		defer { lock.unlock() }
		
		var query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			KeychainSwiftConstants.label: name
		]
		addAccessGroupWhenPresent(&query)
		addSynchronizableIfRequired(&query, addingItems: false)
		let lastResultCode = SecItemDelete(query as CFDictionary)
		guard lastResultCode == noErr else {
			throw KeychainError.unhandledError(status: lastResultCode)
		}
	}
	
	public func isExpiredObject(forKey key: String) -> Bool {
		lock.lock()
		defer { lock.unlock() }
		let any = try? getItemsNoLock(data: false, attributes: true, finalKey: getKey(key))
		guard let dict = any as? [String: Any],
			let data = dict[KeychainSwiftConstants.description] as? String,
			let date = try? expiryDate(attribute: data) else {
				return false
		}
		return date < Date()
	}
	
	private func setNoLock(_ value: Data, forKey key: String, withAccess access: KeychainSwiftAccessOptions?, expiry: Expiry?) throws {
		try? deleteNoLock(key) // Delete any existing key before saving it
		let accessible = access?.value ?? KeychainSwiftAccessOptions.defaultOption.value
		
		var query: [String : Any] = [
			KeychainSwiftConstants.klass       : kSecClassGenericPassword,
			KeychainSwiftConstants.attrAccount : getKey(key),
			KeychainSwiftConstants.valueData   : value,
			KeychainSwiftConstants.label	   : name,
			KeychainSwiftConstants.accessible  : accessible
		]
		addExpiry(&query, expiry: expiry)
		addAccessGroupWhenPresent(&query)
		addSynchronizableIfRequired(&query, addingItems: true)
		let lastResultCode = SecItemAdd(query as CFDictionary, nil)
		guard lastResultCode == noErr else {
			throw KeychainError.unhandledError(status: lastResultCode)
		}
	}
	
	private func getDataNoLock(_ key: String) -> Data? {
		let result = try? getItemsNoLock(data: true, attributes: false, finalKey: getKey(key))
		return result as? Data
	}
	
	private func getAllData() -> [Data]? {
		let result = try? getItemsNoLock(data: true, attributes: false, finalKey: nil)
		return result as? [Data]
	}
	
	private func getItemsNoLock(data: Bool, attributes: Bool, finalKey: String?) throws -> AnyObject? {
		var query: [String: Any] = [
			KeychainSwiftConstants.klass       : kSecClassGenericPassword,
			KeychainSwiftConstants.label	   : name,
			KeychainSwiftConstants.returnData  : data,
			KeychainSwiftConstants.returnAttributes  : attributes
		]
		if let key = finalKey {
			query[KeychainSwiftConstants.attrAccount] = key
			query[KeychainSwiftConstants.matchLimit] = kSecMatchLimitOne
		} else {
			query[KeychainSwiftConstants.matchLimit] = kSecMatchLimitAll
		}
		addAccessGroupWhenPresent(&query)
		addSynchronizableIfRequired(&query, addingItems: false)
		
		var result: AnyObject?
		
		let lastResultCode = withUnsafeMutablePointer(to: &result) {
			SecItemCopyMatching(query as CFDictionary, UnsafeMutablePointer($0))
		}
		guard lastResultCode == noErr else {
			throw KeychainError.unhandledError(status: lastResultCode)
		}
		return result
	}
	
	private func getCount() throws -> Int {
		lock.lock()
		defer { lock.unlock() }
		let result: AnyObject? = try getItemsNoLock(data: false, attributes: true, finalKey: nil)
		guard let array = result as? [Any] else {
			throw KeychainError.unexpectedPasswordData
		}
		return array.count
	}
	
	public func removeExpiredObjects() throws {
		lock.lock()
		defer { lock.unlock() }
		let result: AnyObject? = try getItemsNoLock(data: false, attributes: true, finalKey: nil)
		
		guard let array = result as? [[String : Any]] else {
			throw KeychainError.unexpectedPasswordData
		}
		let date = Date()
		for dict in array {
			guard try expiryDate(attribute: (dict[KeychainSwiftConstants.description] as? String)~!) < date else { continue }
			let key = try (dict[KeychainSwiftConstants.attrAccount] as? String)~!
			try deleteNoLock(final: key)
		}
	}
	
	private func getKey(_ key: String) -> String {
		return name + key
	}
	
	private func deleteNoLock(_ key: String) throws {
		try deleteNoLock(final: getKey(key))
	}
	
	private func deleteNoLock(final key: String) throws {
		var query: [String: Any] = [
			KeychainSwiftConstants.klass       : kSecClassGenericPassword,
			KeychainSwiftConstants.attrAccount : key,
			KeychainSwiftConstants.label 	   : name
		]
		addAccessGroupWhenPresent(&query)
		addSynchronizableIfRequired(&query, addingItems: false)
		
		let lastResultCode = SecItemDelete(query as CFDictionary)
		
		guard lastResultCode == noErr else {
			throw KeychainError.unhandledError(status: lastResultCode)
		}
	}
	
	private func addExpiry(_ items: inout [String: Any], expiry: Expiry?) {
		guard let expiry = expiry else { return }
		if case .never = expiry { return }
		items[KeychainSwiftConstants.description] = expiryAttribute(expiry: expiry.date)
	}
	
	private func addAccessGroupWhenPresent(_ items: inout [String: Any]) {
		guard let accessGroup = accessGroup else { return }
		items[KeychainSwiftConstants.accessGroup] = accessGroup
	}
	
	private func addSynchronizableIfRequired(_ items: inout [String: Any], addingItems: Bool) {
		guard synchronizeWithICloud else { return }
		items[KeychainSwiftConstants.attrSynchronizable] = addingItems ? true : kSecAttrSynchronizableAny
	}
	
	private func expiryAttribute(expiry: Date) -> String {
		return "\(Int(expiry.timeIntervalSince1970))"
	}
	
	private func expiryDate(attribute: String) throws -> Date {
		return try Date(timeIntervalSince1970: Double(attribute)~!)
	}
	
}

extension KeychainStorage where T == String {
	
	public convenience init(name: String, synchronizeWithICloud: Bool = false, accessGroup: String? = nil, withAccess access: KeychainSwiftAccessOptions? = nil) {
		self.init(name: name, synchronizeWithICloud: synchronizeWithICloud, accessGroup: accessGroup, withAccess: access, transformer: Transformer())
	}
	
}

extension KeychainStorage where T == Data {
	
	public convenience init(name: String, synchronizeWithICloud: Bool = false, accessGroup: String? = nil, withAccess access: KeychainSwiftAccessOptions? = nil) {
		self.init(name: name, synchronizeWithICloud: synchronizeWithICloud, accessGroup: accessGroup, withAccess: access, transformer: Transformer())
	}
	
}

extension KeychainStorage where T: Codable {
	
	public convenience init(name: String = String(reflecting: T.self), synchronizeWithICloud: Bool = false, accessGroup: String? = nil, withAccess access: KeychainSwiftAccessOptions? = nil) {
		self.init(name: name, synchronizeWithICloud: synchronizeWithICloud, accessGroup: accessGroup, withAccess: access, transformer: Transformer())
	}
	
}

enum KeychainError: Error {
	case noPassword
	case unexpectedPasswordData
	case unhandledError(status: OSStatus)
}

public enum KeychainSwiftAccessOptions {
	
	case accessibleWhenUnlocked
	case accessibleWhenUnlockedThisDeviceOnly
	case accessibleAfterFirstUnlock
	case accessibleAfterFirstUnlockThisDeviceOnly
	case accessibleAlways
	case accessibleWhenPasscodeSetThisDeviceOnly
	case accessibleAlwaysThisDeviceOnly
	
	public static var defaultOption: KeychainSwiftAccessOptions {
		return .accessibleWhenUnlocked
	}
	
	var value: String {
		switch self {
		case .accessibleWhenUnlocked:
			return toString(kSecAttrAccessibleWhenUnlocked)
			
		case .accessibleWhenUnlockedThisDeviceOnly:
			return toString(kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
			
		case .accessibleAfterFirstUnlock:
			return toString(kSecAttrAccessibleAfterFirstUnlock)
			
		case .accessibleAfterFirstUnlockThisDeviceOnly:
			return toString(kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
			
		case .accessibleAlways:
			return toString(kSecAttrAccessibleAlways)
			
		case .accessibleWhenPasscodeSetThisDeviceOnly:
			return toString(kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly)
			
		case .accessibleAlwaysThisDeviceOnly:
			return toString(kSecAttrAccessibleAlwaysThisDeviceOnly)
		}
	}
	
	func toString(_ value: CFString) -> String {
		return KeychainSwiftConstants.toString(value)
	}
}

struct KeychainSwiftConstants {
	/// Specifies a Keychain access group. Used for sharing Keychain items between apps.
	public static var accessGroup: String { return toString(kSecAttrAccessGroup) }
	
	/**
	
	A value that indicates when your app needs access to the data in a keychain item. The default value is AccessibleWhenUnlocked. For a list of possible values, see KeychainSwiftAccessOptions.
	
	*/
	/// Used for specifying a String key when setting/getting a Keychain value.
	public static var label: String { return toString(kSecAttrLabel) }
	
	public static var comment: String { return toString(kSecAttrComment) }
	
	public static var accessible: String { return toString(kSecAttrAccessible) }
	
	/// Used for specifying a String key when setting/getting a Keychain value.
	public static var attrAccount: String { return toString(kSecAttrAccount) }
	
	/// Used for specifying synchronization of keychain items between devices.
	public static var attrSynchronizable: String { return toString(kSecAttrSynchronizable) }
	
	/// An item class key used to construct a Keychain search dictionary.
	public static var klass: String { return toString(kSecClass) }
	
	/// Specifies the number of values returned from the keychain. The library only supports single values.
	public static var matchLimit: String { return toString(kSecMatchLimit) }
	
	/// A return data type used to get the data from the Keychain.
	public static var returnData: String { return toString(kSecReturnData) }
	
	/// A return data type used to get the attributes from the Keychain.
	public static var returnAttributes: String { return toString(kSecReturnAttributes) }
	
	public static var description: String { return toString(kSecAttrDescription) }
	
	/// Used for specifying a value when setting a Keychain value.
	public static var valueData: String { return toString(kSecValueData) }
	
	/// Used for returning a reference to the data from the keychain
	public static var returnReference: String { return toString(kSecReturnPersistentRef) }
	
	static func toString(_ value: CFString) -> String {
		return value as String
	}
}
