import Foundation

public class TransformerFactory {
	
	public static func forData() -> Transformer<Data> {
		let toData: (Data) throws -> Data = { $0 }
		let fromData: (Data) throws -> Data = { $0 }
		return Transformer<Data>(toData: toData, fromData: fromData)
	}
	
	public static func forString() -> Transformer<String> {
		let toData: (String) throws -> Data = { try $0.data(using: .utf8)~! }
		let fromData: (Data) throws -> String = { try String(data: $0, encoding: .utf8)~! }
		return Transformer<String>(toData: toData, fromData: fromData)
	}
	
	public static func forImage() -> Transformer<Image> {
		let toData: (Image) throws -> Data = { image in
			return try image.cache_toData().unwrap(catch: StorageError.transformerFail)
		}
		
		let fromData: (Data) throws -> Image = { data in
			return try Image(data: data).unwrap(catch: StorageError.transformerFail)
		}
		
		return Transformer<Image>(toData: toData, fromData: fromData)
	}
	
	public static func forCodable<U: Codable>(ofType: U.Type) -> Transformer<U> {
		let coder = CacheJSONCoder()
		return Transformer<U>(toData: coder.encode, fromData: coder.decode)
	}
	
}

class CacheJSONCoder {
	
	private let decoder = CacheJSONDecoder()
	private let encoder = CacheJSONEncoder()
	
	func decode<T: Decodable>(data: Data) throws -> T {
		return try decoder.decode(T.self, from: data)
	}
	
	func encode<T: Encodable>(_ value: T) throws -> Data {
		return try encoder.encode(value)
	}
	
}
