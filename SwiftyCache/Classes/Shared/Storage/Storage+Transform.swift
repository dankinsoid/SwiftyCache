import Foundation

public extension Storage {
	func transformData() -> Storage<Data> {
		return transform(transformer: Transformer())
	}
	
	func transformImage() -> Storage<Image> {
		return transform(transformer: Transformer())
	}
	
	func transformCodable<U: Codable>(ofType: U.Type) -> Storage<U> {
		return transform(transformer: Transformer())
	}
}
