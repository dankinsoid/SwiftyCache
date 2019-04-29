//
//  EncodingOptions.swift
//  RxTableView
//
//  Created by Данил Войдилов on 05/04/2019.
//  Copyright © 2019 Pochtabank. All rights reserved.
//

import Foundation

extension CacheJSONEncoder {
	
	/// The strategy to use for decoding `Date` values.
	public enum DateEncodingStrategy {
		/// Defer to `Date` for decoding. This is the default strategy.
		case deferredFromDate
		
		/// Decode the `Date` as a UNIX timestamp from a JSON number.
		case secondsSince1970
		
		/// Decode the `Date` as UNIX millisecond timestamp from a JSON number.
		case millisecondsSince1970
		
		/// Decode the `Date` as an ISO-8601-formatted string (in RFC 3339 format).
		case iso8601
		
		/// Decode the `Date` as a string parsed by the given formatter.
		case formatted(DateFormatter)
		
		/// Decode the `Date` as a custom value decoded by the given closure.
		case custom((_ value: Date, _ encoder: Encoder) throws -> ())
	}
	
	/// The strategy to use for automatically changing the value of keys before decoding.
	public enum KeyEncodingStrategy {
		/// Use the keys specified by each type. This is the default strategy.
		case useDefaultKeys
		
		/// Convert from "snake_case_keys" to "camelCaseKeys" before attempting to match a key with the one specified by each type.
		///
		/// The conversion to upper case uses `Locale.system`, also known as the ICU "root" locale. This means the result is consistent regardless of the current user's locale and language preferences.
		///
		/// Converting from snake case to camel case:
		/// 1. Capitalizes the word starting after each `_`
		/// 2. Removes all `_`
		/// 3. Preserves starting and ending `_` (as these are often used to indicate private variables or other metadata).
		/// For example, `one_two_three` becomes `oneTwoThree`. `_one_two_three_` becomes `_oneTwoThree_`.
		///
		/// - Note: Using a key decoding strategy has a nominal performance cost, as each string key has to be inspected for the `_` character.
		case convertToSnakeCase
		
		/// Provide a custom conversion from the key in the encoded JSON to the keys specified by the decoded types.
		/// The full path to the current decoding position is provided for context (in case you need to locate this key within the payload). The returned key is used in place of the last component in the coding path before decoding.
		/// If the result of the conversion is a duplicate key, then only one value will be present in the container for the type to decode from.
		case custom((_ path: [CodingKey]) -> String)
	
		static func _convertToSnakeCase(_ stringKey: String) -> String {
			guard !stringKey.isEmpty else { return stringKey }
			
			var words : [Range<String.Index>] = []
			// The general idea of this algorithm is to split words on transition from lower to upper case, then on transition of >1 upper case characters to lowercase
			//
			// myProperty -> my_property
			// myURLProperty -> my_url_property
			//
			// We assume, per Swift naming conventions, that the first character of the key is lowercase.
			var wordStart = stringKey.startIndex
			var searchRange = stringKey.index(after: wordStart)..<stringKey.endIndex
			
			// Find next uppercase character
			while let upperCaseRange = stringKey.rangeOfCharacter(from: CharacterSet.uppercaseLetters, options: [], range: searchRange) {
				let untilUpperCase = wordStart..<upperCaseRange.lowerBound
				words.append(untilUpperCase)
				
				// Find next lowercase character
				searchRange = upperCaseRange.lowerBound..<searchRange.upperBound
				guard let lowerCaseRange = stringKey.rangeOfCharacter(from: CharacterSet.lowercaseLetters, options: [], range: searchRange) else {
					// There are no more lower case letters. Just end here.
					wordStart = searchRange.lowerBound
					break
				}
				
				// Is the next lowercase letter more than 1 after the uppercase? If so, we encountered a group of uppercase letters that we should treat as its own word
				let nextCharacterAfterCapital = stringKey.index(after: upperCaseRange.lowerBound)
				if lowerCaseRange.lowerBound == nextCharacterAfterCapital {
					// The next character after capital is a lower case character and therefore not a word boundary.
					// Continue searching for the next upper case for the boundary.
					wordStart = upperCaseRange.lowerBound
				} else {
					// There was a range of >1 capital letters. Turn those into a word, stopping at the capital before the lower case character.
					let beforeLowerIndex = stringKey.index(before: lowerCaseRange.lowerBound)
					words.append(upperCaseRange.lowerBound..<beforeLowerIndex)
					
					// Next word starts at the capital before the lowercase we just found
					wordStart = beforeLowerIndex
				}
				searchRange = lowerCaseRange.upperBound..<searchRange.upperBound
			}
			words.append(wordStart..<searchRange.upperBound)
			let result = words.map({ (range) in
				return stringKey[range].lowercased()
			}).joined(separator: "_")
			return result
		}
		
	}
	
}

