//
//  Entity.swift
//  MolecularRenderer
//
//  Created by Philip Turner on 10/22/23.
//

public enum EntityType: RawRepresentable {
  case atom(Element)
  case empty
  
  @inlinable
  public init(rawValue: Float) {
    if rawValue > 0 {
      guard let uint = UInt8(exactly: rawValue),
            let element = Element(rawValue: uint) else {
        fatalError("Invalid raw value.")
      }
      self = .atom(element)
    } else {
      // NaN or zero
      self = .empty
    }
  }
  
  init(compactRepresentation: Int8) {
    if compactRepresentation > 0 {
      guard let uint = UInt8(exactly: compactRepresentation),
            let element = Element(rawValue: uint) else {
        fatalError("Invalid raw value.")
      }
      self = .atom(element)
    } else if compactRepresentation < 0 {
      fatalError("Not implemented.")
    } else {
      self = .empty
    }
  }
  
  @inlinable
  public var rawValue: Float {
    switch self {
    case .atom(let atomicNumber):
      return Float(atomicNumber.rawValue)
    case .empty:
      return 0
    }
  }
  
  var compactRepresentation: Int8 {
    switch self {
    case .atom(let atomicNumber):
      return Int8(clamping: atomicNumber.rawValue)
    case .empty:
      return 0
    }
  }
}

public struct Entity {
  public var storage: SIMD4<Float>
  
  @inlinable @inline(__always)
  public var position: SIMD3<Float> {
    get {
      unsafeBitCast(storage, to: SIMD3<Float>.self)
    }
    set {
      storage = SIMD4(newValue, storage.w)
    }
  }
  
  @inlinable @inline(__always)
  public var atomicNumber: UInt8 {
    get {
      UInt8(storage.w)
    }
    set {
      storage.w = Float(newValue)
    }
  }
  
  @inlinable @inline(__always)
  public var type: EntityType {
    get {
      EntityType(rawValue: storage.w)
    }
    set {
      storage.w = newValue.rawValue
    }
  }
  
  @inlinable @inline(__always)
  public var isEmpty: Bool {
    storage.w == 0
  }
  
  @inlinable @inline(__always)
  public init(storage: SIMD4<Float>) {
    self.storage = storage
  }
  
  @inlinable @inline(__always)
  public init(position: SIMD3<Float>, type: EntityType) {
    self.storage = SIMD4(position, type.rawValue)
  }
}

/// A block of entities for processing in parallel in a SIMD instruction.
struct EntityBlock {
  var x: SIMD8<Float> = .zero
  var y: SIMD8<Float> = .zero
  var z: SIMD8<Float> = .zero
  var w: SIMD8<Float> = .zero
}
