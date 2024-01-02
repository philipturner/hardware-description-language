//
//  Map.swift
//  HDLTests
//
//  Created by Philip Turner on 1/2/24.
//

import Atomics
import Dispatch

extension Topology {
  public enum MapType {
    case atoms
    case bonds
  }
  
  public struct MapStorage: Collection {
    var storage: SIMD8<Int32>
    
    public typealias Index = Int
    
    public typealias Element = UInt32
    
    public var startIndex: Int { 0 }
    
    public var endIndex: Int {
      Int(truncatingIfNeeded: storage[7])
    }
    
    public func index(after i: Int) -> Int {
      i + 1
    }
    
    public subscript(position: Int) -> UInt32 {
      _read {
         yield UInt32(truncatingIfNeeded: storage[position])
      }
    }
  }
  
  public func map(
    _ primaryType: MapType,
    to secondaryType: MapType
  ) -> [ArraySlice<UInt32>] {
    switch (primaryType, secondaryType) {
    case (.atoms, _):
      let connectionsMap = createConnnectionsMap(secondaryType: secondaryType)
      
      var outputArray: [UInt32] = []
      outputArray.reserveCapacity(atoms.count * 4)
      var outputRanges: [Range<UInt32>] = []
      outputRanges.reserveCapacity(atoms.count)
      var outputSlices: [ArraySlice<UInt32>] = []
      outputSlices.reserveCapacity(atoms.count)
      
      for atomID in atoms.indices {
        let element = connectionsMap[atomID]
        let rangeStart = UInt32(truncatingIfNeeded: outputArray.count)
        for lane in 0..<8 {
          if element[lane] == -1 {
            break
          }
          outputArray.append(
            UInt32(truncatingIfNeeded: element[lane]))
        }
        let rangeEnd = UInt32(truncatingIfNeeded: outputArray.count)
        outputRanges.append(rangeStart..<rangeEnd)
      }
      
      for range in outputRanges {
        let rangeStart = Int(truncatingIfNeeded: range.lowerBound)
        let rangeEnd = Int(truncatingIfNeeded: range.upperBound)
        let slice = outputArray[rangeStart..<rangeEnd]
        outputSlices.append(slice)
      }
      return outputSlices
    case (.bonds, .atoms):
      var outputArray: [UInt32] = []
      outputArray.reserveCapacity(bonds.count * 2)
      for i in bonds.indices {
        let bond = bonds[i]
        outputArray.append(bond[0])
        outputArray.append(bond[1])
      }
      
      var outputSlices: [ArraySlice<UInt32>] = []
      outputSlices.reserveCapacity(bonds.count)
      for i in bonds.indices {
        let rangeStart = 2 &* i
        let rangeEnd = 2 &* (i &+ 1)
        let slice = outputArray[rangeStart..<rangeEnd]
        outputSlices.append(slice)
      }
      return outputSlices
    case (.bonds, .bonds):
      fatalError("Bonds to bonds map is not supported.")
    }
  }
}

extension Topology {
  // Internal API used to avoid the overhead of creating an array of object
  // references.
  func createConnnectionsMap(secondaryType: MapType) -> [SIMD8<Int32>] {
    var connectionsMap = [SIMD8<Int32>](
      repeating: .init(repeating: -1), count: atoms.count)
    guard atoms.count > 0 else {
      return []
    }
    
    // Optimization: try atomics with smaller numbers of bits
    let atomicPointer: UnsafeMutablePointer<Int16.AtomicRepresentation> =
      .allocate(capacity: atoms.count)
    do {
      let opaque = OpaquePointer(atomicPointer)
      let casted = UnsafeMutablePointer<Int16>(opaque)
      casted.initialize(repeating: .zero, count: atoms.count)
    }
    
    connectionsMap.withUnsafeMutableBufferPointer {
      let connectionsPointer = $0.baseAddress.unsafelyUnwrapped
      let connectionsOpaque = OpaquePointer(connectionsPointer)
      let connectionsCasted = UnsafeMutablePointer<Int32>(connectionsOpaque)
      
      bonds.withUnsafeBufferPointer {
        let opaque = OpaquePointer($0.baseAddress.unsafelyUnwrapped)
        let casted = UnsafePointer<UInt32>(opaque)
        
        let taskSize: Int = 5_000
        let taskCount = (2 * bonds.count + taskSize - 1) / taskSize
        
        func execute(taskID: Int) {
          let scalarStart = taskID &* taskSize
          let scalarEnd = min(scalarStart &+ taskSize, 2 * bonds.count)
          
          for i in scalarStart..<scalarEnd {
            let atomID = Int(truncatingIfNeeded: casted[i])
            var idToWrite: Int32
            if secondaryType == .atoms {
              let otherID = (i % 2 == 0) ? casted[i &+ 1] : casted[i &- 1]
              idToWrite = Int32(truncatingIfNeeded: otherID)
            } else {
              idToWrite = Int32(truncatingIfNeeded: i / 2)
            }
            
            let pointer = atomicPointer.advanced(by: atomID)
            let atomic = UnsafeAtomic<Int16>(at: pointer)
            let lane = atomic.loadThenWrappingIncrement(ordering: .relaxed)
            let lane64 = Int(truncatingIfNeeded: lane)
            
            if lane < 8 {
              connectionsCasted[atomID &* 8 &+ lane64] = Int32(
                truncatingIfNeeded: idToWrite)
            }
          }
        }
        
        if taskCount <= 1 {
          for taskID in 0..<taskCount {
            execute(taskID: taskID)
          }
        } else {
          DispatchQueue.concurrentPerform(iterations: taskCount) { z in
            execute(taskID: z)
          }
        }
      }
    }
    atomicPointer.deallocate()
    return connectionsMap
  }
}
