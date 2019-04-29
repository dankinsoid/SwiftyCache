import Foundation

/// A protocol used for adding and removing key observations
public protocol KeyObservationRegistry {
	associatedtype S: GenericStorage
	var observedStorage: S { get }
	/**
	Registers observation closure which will be removed automatically
	when the weakly captured observer has been deallocated.
	- Parameter observer: Any object that helps determine if the observation is still valid
	- Parameter key: Unique key to identify the object in the cache
	- Parameter closure: Observation closure
	- Returns: Token used to cancel the observation and remove the observation closure
	*/
	@discardableResult
	func addObserver<O: AnyObject>(_ observer: O, forKey key: String, closure: @escaping (O, S, KeyChange<S.T>) -> Void) -> ObservationToken
	
	/**
	Removes observer by the given key.
	- Parameter key: Unique key to identify the object in the cache
	*/
	func removeObserver(forKey key: String)
	
	/// Removes all registered key observers
	func removeAllKeyObservers()
}

extension KeyObservationRegistry where S == Self {
	public var observedStorage: S { return self }
}
// MARK: - KeyChange

public enum KeyChange<T> {
	case set(value: T)
	case remove
}

extension KeyChange: Equatable where T: Equatable {
	public static func == (lhs: KeyChange<T>, rhs: KeyChange<T>) -> Bool {
		switch (lhs, rhs) {
		case (.set(let after1), .set(let after2)):
			return after1 == after2
		case (.remove, .remove):
			return true
		default:
			return false
		}
	}
}
