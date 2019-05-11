import Foundation

public class Transformer<T> {
	public let toData: (T) throws -> Data
	public let fromData: (Data) throws -> T
	
	public init(toData: @escaping (T) throws -> Data, fromData: @escaping (Data) throws -> T) {
		self.toData = toData
		self.fromData = fromData
	}
}

extension Transformer where T: Codable {
	
	public convenience init() {
		let encoder = CacheJSONEncoder()
		let decoder = CacheJSONDecoder()
		self.init(toData: encoder.encode, fromData: { try decoder.decode(T.self, from: $0) } )
	}
	
}

extension Transformer where T == String {
	
	public convenience init() {
		let toData: (String) throws -> Data = { try $0.data(using: .utf8)~! }
		let fromData: (Data) throws -> String = { try String(data: $0, encoding: .utf8)~! }
		self.init(toData: toData, fromData: fromData)
	}
	
}

extension Transformer where T == Data {
	
	public convenience init() {
		let toData: (Data) throws -> Data = { $0 }
		let fromData: (Data) throws -> Data = { $0 }
		self.init(toData: toData, fromData: fromData)
	}
	
}

extension Transformer where T: Image {
	
	public convenience init() {
		let toData: (T) throws -> Data = { image in
			return try image.cache_toData().unwrap(catch: StorageError.transformerFail)
		}
		let fromData: (Data) throws -> T = { data in
			return try T(data: data).unwrap(catch: StorageError.transformerFail)
		}
		self.init(toData: toData, fromData: fromData)
	}
	
}
