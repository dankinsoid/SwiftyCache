import Foundation

public struct DiskConfig {
	/// The name of disk storage, this will be used as folder name within directory
	public let name: String
	/// Expiry date that will be applied by default for every added object
	/// if it's not overridden in the add(key: object: expiry: completion:) method
	public let expiry: Expiry
	/// Maximum size of the disk cache storage (in bytes)
	public var maxSize: UInt
	/// A folder to store the disk cache contents. Defaults to a prefixed directory in Caches if nil
	public let directory: URL?
	
	public let useEncryption: Bool
	
	public let customCryptoKey: String?
	
	public var encryptionType: EncryptionType {
		if !useEncryption {
			return .none
		}
		if let key = customCryptoKey {
			return .withCustomKey(key)
		} else {
			return .withRandomKey
		}
	}
	
	#if os(iOS) || os(tvOS)
	/// Data protection is used to store files in an encrypted format on disk and to decrypt them on demand.
	/// Support only on iOS and tvOS.
	public let protectionType: FileProtectionType?
	public init(name: String?, expiry: Expiry = .never,
				maxSize: UInt = 0, directory: URL? = nil,
				protectionType: FileProtectionType? = nil,
				encryptionType: EncryptionType = .none) {
		self.name = name ?? ("DiskStorage" + UUID().uuidString)
		self.expiry = expiry
		self.maxSize = maxSize
		self.directory = directory
		self.protectionType = protectionType
		switch encryptionType {
		case .none:
			useEncryption = false
			customCryptoKey = nil
		case .withRandomKey:
			useEncryption = true
			customCryptoKey = nil
		case .withCustomKey(let key):
			useEncryption = true
			customCryptoKey = key
		}
	}
	#else
	public init(name: String?, expiry: Expiry = .never,
				maxSize: UInt = 0, directory: URL? = nil,
				encryptionType: EncryptionType = .none) {
		self.name = name ?? ("DiskStorage" + UUID().uuidString)
		self.expiry = expiry
		self.maxSize = maxSize
		self.directory = directory
		switch encryptionType {
		case .none:
			useEncryption = false
			customCryptoKey = nil
		case .withRandomKey:
			useEncryption = true
			customCryptoKey = nil
		case .withCustomKey(let key):
			useEncryption = true
			customCryptoKey = key
		}
	}
	#endif
	
	public enum EncryptionType {
		case none, withRandomKey, withCustomKey(String)
	}
	
}
