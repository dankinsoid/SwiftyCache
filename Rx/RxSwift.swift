//
//  Storage++.swift
//  TSUMCountries
//
//  Created by Данил Войдилов on 14/03/2019.
//  Copyright © 2019 danil.voidilov. All rights reserved.
//

import RxSwift

extension Reactive where Base: StorageObservationRegistry {
	
	public var change: Observable<StorageChange> {
		return Observable.create({[base] observer -> Disposable in
			var storageObserver: StorageObserver? = StorageObserver()
			let token = base.addStorageObserver(storageObserver!) { (_, _, change) in
				observer.onNext(change)
			}
			return Disposables.create {
				storageObserver = nil
				token.cancel()
			}
		})
	}
}

extension Reactive where Base: KeyObservationRegistry, Base.S: StorageAware {

	public func object(for key: String) -> StorageSubject<Base.S.T> {
		return StorageSubject(observer: base, key: key)
	}
	
}

extension Reactive where Base: KeyObservationRegistry, Base.S: MemoryStorageAware {
	
	public func object(for key: String) -> StorageSubject<Base.S.T> {
		return StorageSubject(observer: base, key: key)
	}
	
}

extension Reactive where Base: AsyncStorageAware, Base.Storage: KeyObservationRegistry, Base.Storage.S == Base.Storage {
	
	public func object(for key: String) -> StorageSubject<Base.T> {
		return StorageSubject(observer: base, key: key)
	}
	
}

public final class StorageSubject<S>: ObserverType, ObservableType {
	public typealias E = S?
	
	public let key: String
	
	private let setObject: (S, String, Expiry?) throws -> ()
	private let removeObject: (String) throws -> ()
	private let object: (String) -> S?
	private let addObserver: (StorageObserver, @escaping (KeyChange<S>) -> ()) -> ObservationToken
	
	public init<O: KeyObservationRegistry>(observer: O, key: String) where O.S.T == S, O.S: StorageAware {
		self.setObject = observer.observedStorage.setObject
		self.removeObject = observer.observedStorage.removeObject
		self.object = observer.observedStorage.object
		self.addObserver = { anyObj, block in
			return observer.addObserver(anyObj, forKey: key, closure: { (_, _, change) in block(change) })
		}
		self.key = key
	}
	
	public init<O: KeyObservationRegistry>(observer: O, key: String) where O.S.T == S, O.S: MemoryStorageAware {
		self.setObject = observer.observedStorage.setObject
		self.removeObject = observer.observedStorage.removeObject
		self.object = observer.observedStorage.object
		self.addObserver = { anyObj, block in
			return observer.addObserver(anyObj, forKey: key, closure: { (_, _, change) in block(change) })
		}
		self.key = key
	}
	
	public init<O: AsyncStorageAware>(observer: O, key: String) where O.Storage.T == S, O.Storage: KeyObservationRegistry, O.Storage.S.T == S {
		self.setObject = { observer.setObject($0, forKey: $1, expiry: $2, completion: nil) }
		self.removeObject = { observer.removeObject(forKey: $0, completion: nil ) }
		self.object = observer.innerStorage.object
		self.addObserver = { anyObj, block in
			return observer.innerStorage.addObserver(anyObj, forKey: key, closure: { (_, _, change) in block(change) })
		}
		self.key = key
	}
	
	public var value: E {
		return object(key)
	}
	
	public func on(_ event: Event<E>) {
		switch event {
		case .next(let value):
			if let newValue = value {
			try? setObject(newValue, key, nil)
		} else {
			try? removeObject(key)
			}
		case .error(_):
			break
		case .completed:
			break
		}
	}
	
	public func subscribe<O: ObserverType>(_ observer: O) -> Disposable where E == O.E {
		var storageObserver: StorageObserver? = StorageObserver()
		observer.onNext(value)
		let token = addObserver(storageObserver!) { change in
			switch change {
			case .set(let new):
				observer.onNext(new)
			case .remove:
				observer.onNext(nil)
			}
		}
		return Disposables.create {
			storageObserver = nil
			token.cancel()
		}
	}
	
	public func subscribe(_ observer: @escaping (KeyChange<S>) -> ()) -> Disposable {
		var storageObserver: StorageObserver? = StorageObserver()
		let token = addObserver(storageObserver!, observer)
		return Disposables.create {
			storageObserver = nil
			token.cancel()
		}
	}
	
	public func subscribe(onSet: @escaping (S) -> (), onRemove: @escaping () -> () = {}) -> Disposable {
		var storageObserver: StorageObserver? = StorageObserver()
		let token = addObserver(storageObserver!) {
			switch $0 {
			case .set(let value): onSet(value)
			case .remove: 		  onRemove()
			}
		}
		return Disposables.create {
			storageObserver = nil
			token.cancel()
		}
	}
	
}

fileprivate final class StorageObserver {}

extension StorageAware where Self: StorageObservationRegistry & KeyObservationRegistry {
	
	public var rx: Reactive<Self> {
		return Reactive(self)
	}
	
}

extension AsyncStorageAware where Storage: KeyObservationRegistry, Storage.S == Storage {
	
	public var rx: Reactive<Self> {
		return Reactive(self)
	}
	
}

extension CacheContext {
	
	public var rx: Reactive<CacheContext> { return Reactive(self) }
	
}

extension Reactive where Base: CacheContext {
	
	public var clean: AnyObserver<Void> {
		return AnyObserver {[weak base] in
			if case .next = $0 {
				try? base?.clean()
			}
		}
	}
	
	public func storage<T>(for type: T.Type) -> Observable<StorageChange> {
		return base.anyStorage(of: type).rx.change
	}
	
	public func object<T>(of type: T.Type, for key: String) -> StorageSubject<T> {
		return base.anyStorage(of: type).rx.object(for: key)
	}
	
}
