//
//  Database+Models.swift
//  
//
//  Created by Kevin McKee
//

import Algorithms
import Combine
import Foundation
import simd
import SwiftData

/// A type that specifies the model import priority.
public enum ModelImportPriority: Int, Sendable {
    /// The model type has a very low priority during the import process.
    case veryLow
    /// The model type has a low priority during the import process.
    case low
    /// The model type has a normal  priority during the import process.
    case normal
    /// The model type has a high priority during the import process.
    case high
    /// The model type has a very high priority during the import process.
    case veryHigh
}

public protocol IndexedPersistentModel: PersistentModel {

    /// Builds the index predicate for this model.
    /// - Parameter index: the unique index
    /// - Returns: the predicate used to lookup this indexed model.
    static func predicate(_ index: Int64) -> Predicate<Self>

    /// The model import priority used for sorting the models during the import process.
    static var importPriority: ModelImportPriority { get }

    /// The unique record id.
    var index: Int64 { get set }

    /// Required initializer.
    init()

    /// Updates the model from the hash data.
    /// - Parameters:
    ///   - data: the raw hash data
    ///   - cache: the import cache used to lookup other models that have relationships to this model.
    func update(from data: [String: AnyHashable], cache: Database.ImportCache)
}

extension IndexedPersistentModel {

    /// Returns the name of the model.
    static var modelName: String {
        String(describing: Self.self)
    }

    /// Finds or creates the model from the cache for the specified index.
    /// - Parameters:
    ///   - index: the model index
    ///   - cache: the import cache
    /// - Returns: the fetched model with the specified index or a new model instance if not found.
    static func findOrCreate(index: Int64, cache: Database.ImportCache) -> Self {
        cache.findOrCreate(index)
    }

    /// Warms the cache with the specified size.
    /// - Parameters:
    ///   - table: the database table that contains the raw data
    ///   - cache: the cache to warm
    /// - Returns: the cached objects.
    @discardableResult
    static func warm(table: Database.Table, cache: Database.ImportCache) -> [Self] {
        cache.warm(table)
    }

    /// Performs a fetch request for all models in the specified context.
    /// - Parameter modelContext: the model context to use.
    /// - Returns: a list of models in the provided model context.
    static func fetch(in modelContext: ModelContext) -> [Self] {
        let fetchDescriptor = FetchDescriptor<Self>(sortBy: [SortDescriptor(\.index)])
        guard let results = try? modelContext.fetch(fetchDescriptor), results.isNotEmpty else {
            return []
        }
        return results
    }
}

extension Database {

    /// Provides a static list of the indexed model types.
    /// See: https://github.com/vimaec/vim/blob/master/ObjectModel/object-model-schema.json
    static let models: [any IndexedPersistentModel.Type] = [
        AreaScheme.self,
        Area.self,
        AssemblyInstance.self,
        Asset.self,
        BimDocument.self,
        Camera.self,
        Category.self,
        CompoundStructure.self,
        CompoundStructureLayer.self,
        DesignOption.self,
        DisplayUnit.self,
        Element.self,
        Family.self,
        FamilyInstance.self,
        FamilyType.self,
        Group.self,
        Level.self,
        Material.self,
        MaterialInElement.self,
        Node.self,
        ParameterDescriptor.self,
        Parameter.self,
        Room.self,
        View.self,
        Workset.self,
    ]

    /// Provides a static list of all persistent types.
    static let allTypes: [any PersistentModel.Type] = [ModelMetadata.self] + models

    /// Registers the value transformers
    static func registerValueTransformers() {
        SIMD3FloatValueTransformer.register()
        SIMD3DoubleValueTransformer.register()
    }

    /// Provides a representation of an indexed model's import state information.
    @Model
    class ModelMetadata {

        enum State: Int, Codable {
            case unknown
            case importing
            case imported
            case failed
        }

        @Attribute(.unique)
        var name: String
        var state: State

        /// Initializer.
        required init() {
            name = .empty
            state = .unknown
        }
    }

    @Model
    public final class AreaScheme: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<AreaScheme> {
            #Predicate<AreaScheme> { $0.index == index }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .normal

        @Attribute(.unique)
        public var index: Int64
        public var isGrossBuildingArea: Bool
        public var element: Element?

        /// Initializer.
        public required init() {
            index = .empty
            isGrossBuildingArea = false
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            isGrossBuildingArea = data["IsGrossBuildingArea"] as? Bool ?? false
            if let idx = data["Element"] as? Int64, idx != .empty {
                element = cache.findOrCreate(idx)
            }
        }
    }

    @Model
    public final class Area: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<Area> {
            #Predicate<Area> { $0.index == index }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .normal

        @Attribute(.unique)
        public var index: Int64
        public var isGrossInterior: Bool
        public var perimeter: Double
        public var value: Double
        public var scheme: AreaScheme?
        public var element: Element?
        public var number: String?

        /// Initializer.
        public required init() {
            index = .empty
            isGrossInterior = false
            perimeter = 0
            value = 0
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            isGrossInterior = data["IsGrossInterior"] as? Bool ?? false
            perimeter = data["Perimeter"] as? Double ?? .zero
            value = data["Value"] as? Double ?? .zero
            number = data["Number"] as? String
            if let idx = data["AreaScheme"] as? Int64, idx != .empty {
                scheme = cache.findOrCreate(idx)
            }
            if let idx = data["Element"] as? Int64, idx != .empty {
                element = cache.findOrCreate(idx)
            }
        }
    }

    @Model
    public final class Asset: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<Asset> {
            #Predicate<Asset> { $0.index == index }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .veryHigh

        @Attribute(.unique)
        public var index: Int64
        public var bufferName: String?

        /// Initializer.
        public required init() {
            index = .empty
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            bufferName = data["BufferName"] as? String
        }
    }

    @Model
    public final class BimDocument: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<BimDocument> {
            #Predicate<BimDocument> { $0.index == index }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .normal

        @Attribute(.unique)
        public var index: Int64
        public var name: String?
        public var address: String?
        public var elevation: Double?
        public var latitude: Double?
        public var longitude: Double?
        public var number: String?
        public var title: String?
        public var user: String?
        public var element: Element?

        /// Initializer.
        public required init() {
            index = .empty
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            name = data["Name"] as? String
            address = data["Address"] as? String
            elevation = data["Elevation"] as? Double
            latitude = data["Latitude"] as? Double
            longitude = data["Longitude"] as? Double
            number = data["Number"] as? String
            title = data["Title"] as? String
            user = data["User"] as? String
            if let idx = data["Element"] as? Int64, idx != .empty {
                element = cache.findOrCreate(idx)
            }
        }
    }

    @Model
    public final class AssemblyInstance: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<AssemblyInstance> {
            #Predicate<AssemblyInstance> { $0.index == index }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .normal

        @Attribute(.unique)
        public var index: Int64
        public var typeName: String
        public var element: Element?

        var positionX: Float
        var positionY: Float
        var positionZ: Float
        public var position: SIMD3<Float> {
            [positionX, positionY, positionZ]
        }

        /// Initializer.
        public required init() {
            index = .empty
            typeName = .empty
            positionX = .zero
            positionY = .zero
            positionZ = .zero
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            typeName = data["AssemblyTypeName"] as? String ?? .empty
            positionX = data["PositionX"] as? Float ?? .zero
            positionY = data["PositionY"] as? Float ?? .zero
            positionZ = data["PositionZ"] as? Float ?? .zero
            if let idx = data["Element"] as? Int64, idx != .empty {
                element = cache.findOrCreate(idx)
            }
        }
    }

    @Model
    public final class Camera: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<Camera> {
            #Predicate<Camera> { $0.index == index }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .veryHigh

        @Attribute(.unique)
        public var index: Int64
        public var farDistance: Float
        public var targetDistance: Float
        public var horizontalExtent: Float
        public var verticalExtent: Float
        public var rightOffset: Float
        public var upOffset: Float
        public var isPerspective: Bool

        /// Initializer.
        public required init() {
            index = .empty
            farDistance = .zero
            targetDistance = .zero
            horizontalExtent = .zero
            verticalExtent = .zero
            rightOffset = .zero
            upOffset = .zero
            isPerspective = true
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            farDistance = (data["FarDistance"] as? Double ?? .zero).singlePrecision
            targetDistance = (data["TargetDistance"] as? Double ?? .zero).singlePrecision
            horizontalExtent = (data["HorizontalExtent"] as? Double ?? .zero).singlePrecision
            verticalExtent = (data["VerticalExtent"] as? Double ?? .zero).singlePrecision
            rightOffset = (data["RightOffset"] as? Double ?? .zero).singlePrecision
            upOffset = (data["UpOffset"] as? Double ?? .zero).singlePrecision
            isPerspective = data["IsPerspective"] as? Bool ?? true
        }
    }

    @Model
    public final class Category: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<Category> {
            #Predicate<Category> { $0.index == index }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .normal

        @Attribute(.unique)
        public var index: Int64
        public var parent: Category?
        public var name: String
        public var type: String?
        public var builtInCategory: String?
        public var material: Material?

        /// Initializer.
        public required init() {
            index = .empty
            name = .empty
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            name = data["Name"] as? String ?? .empty
            type = data["CategoryType"] as? String
            builtInCategory = data["BuiltInCategory"] as? String
            if let idx = data["Parent"] as? Int64, idx != .empty {
                parent = cache.findOrCreate(idx)
            }
            if let idx = data["Material"] as? Int64, idx != .empty {
                material = cache.findOrCreate(idx)
            }
        }
    }

    @Model
    public final class CompoundStructure: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<CompoundStructure> {
            #Predicate<CompoundStructure> { $0.index == index }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .normal

        @Attribute(.unique)
        public var index: Int64
        public var width: Double
        public var layer: CompoundStructureLayer?

        /// Initializer.
        public required init() {
            index = .empty
            width = .zero
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            width = data["Width"] as? Double ?? .zero
            if let idx = data["StructuralLayer"] as? Int64, idx != .empty {
                layer = cache.findOrCreate(idx)
            }
        }
    }

    @Model
    public final class CompoundStructureLayer: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<CompoundStructureLayer> {
            #Predicate<CompoundStructureLayer> { $0.index == index }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .veryHigh

        @Attribute(.unique)
        public var index: Int64
        public var width: Double
        public var orderIndex: Int

        /// Initializer.
        public required init() {
            index = .empty
            width = .zero
            orderIndex = .zero
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            width = data["Width"] as? Double ?? .zero
            orderIndex = data["OrderIndex"] as? Int ?? .zero
        }
    }

    @Model
    public final class DesignOption: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<DesignOption> {
            #Predicate<DesignOption> { $0.index == index }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .normal

        @Attribute(.unique)
        public var index: Int64
        public var isPrimary: Bool
        public var element: Element?

        /// Initializer.
        public required init() {
            index = .empty
            isPrimary = false
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            isPrimary = data["IsPrimary"] as? Bool ?? false
            if let idx = data["Element"] as? Int64, idx != .empty {
                element = cache.findOrCreate(idx)
            }
        }
    }

    @Model
    public final class DisplayUnit: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<DisplayUnit> {
            #Predicate<DisplayUnit> { $0.index == index }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .veryHigh

        @Attribute(.unique)
        public var index: Int64
        public var label: String

        /// Initializer.
        public required init() {
            index = .empty
            label = .empty
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            label = data["Label"] as? String ?? .empty
        }
    }

    @Model
    public final class Element: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<Element> {
            #Predicate<Element> { $0.index == index }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .high

        @Attribute(.unique)
        public var index: Int64
        public var elementId: Int64
        public var uniqueId: String?
        public var name: String?
        public var type: String?
        public var familyName: String?
        public var category: Category?
        public var level: Level?
        public var room: Room?
        public var group: Group?
        public var workset: Workset?

        /// Returns the elements instance type
        public var instanceType: Element? {
            guard let name, let type else { return nil }
            let predicate = #Predicate<Database.Element>{ $0.name == name && $0.type != type }
            let fetchDescriptor = FetchDescriptor<Database.Element>(predicate: predicate)
            guard let results = try? modelContext?.fetch(fetchDescriptor), results.isNotEmpty else {
                return nil
            }
            return results[0]
        }

        /// Initializer.
        public required init() {
            index = .empty
            elementId = .empty
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            elementId = data["Id"] as? Int64 ?? .empty
            uniqueId = data["UniqueId"] as? String ?? .empty
            name = data["Name"] as? String
            type = data["Type"] as? String
            familyName = data["FamilyName"] as? String
            if let idx = data["Category"] as? Int64, idx != .empty {
                category = cache.findOrCreate(idx)
            }
            if let idx = data["Level"] as? Int64, idx != .empty {
                level = cache.findOrCreate(idx)
            }
            if let idx = data["Room"] as? Int64, idx != .empty {
                room = cache.findOrCreate(idx)
            }
            if let idx = data["Group"] as? Int64, idx != .empty {
                group = cache.findOrCreate(idx)
            }
            if let idx = data["Workset"] as? Int64, idx != .empty {
                workset = cache.findOrCreate(idx)
            }
        }
    }

    @Model
    public final class Family: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<Family> {
            #Predicate<Family> { $0.index == index }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .normal

        @Attribute(.unique)
        public var index: Int64
        public var isSystemFamily: Bool
        public var isInPlace: Bool
        public var category: Category?
        public var element: Element?

        /// Initializer.
        public required init() {
            index = .empty
            isSystemFamily = false
            isInPlace = false
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            isSystemFamily = data["IsSystemFamily"] as? Bool ?? false
            isInPlace = data["IsInPlace"] as? Bool ?? false
            if let idx = data["FamilyCategory"] as? Int64, idx != .empty {
                category = cache.findOrCreate(idx)
            }
            if let idx = data["Element"] as? Int64, idx != .empty {
                element = cache.findOrCreate(idx)
            }
        }
    }

    @Model
    public final class FamilyInstance: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<FamilyInstance> {
            #Predicate<FamilyInstance> { $0.index == index }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .normal

        @Attribute(.unique)
        public var index: Int64
        public var familyType: FamilyType?
        public var element: Element?
        public var host: Element?

        /// Initializer.
        public required init() {
            index = .empty
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            if let idx = data["FamilyType"] as? Int64, idx != .empty {
                familyType = cache.findOrCreate(idx)
            }
            if let idx = data["Element"] as? Int64, idx != .empty {
                element = cache.findOrCreate(idx)
            }
            if let idx = data["Host"] as? Int64, idx != .empty {
                host = cache.findOrCreate(idx)
            }
        }
    }

    @Model
    public final class FamilyType: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<FamilyType> {
            #Predicate<FamilyType> { $0.index == index }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .normal

        @Attribute(.unique)
        public var index: Int64
        public var isSystemFamilyType: Bool
        public var element: Element?
        public var compoundStructure: CompoundStructure?

        /// Initializer.
        public required init() {
            index = .empty
            isSystemFamilyType = false
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            isSystemFamilyType = data["IsSystemFamilyType"] as? Bool ?? false
            if let idx = data["CompoundStructure"] as? Int64, idx != .empty {
                compoundStructure = cache.findOrCreate(idx)
            }
            if let idx = data["Element"] as? Int64, idx != .empty {
                element = cache.findOrCreate(idx)
            }
        }
    }

    @Model
    public final class Group: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<Group> {
            #Predicate<Group> { $0.index == index }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .normal

        @Attribute(.unique)
        public var index: Int64
        public var type: String
        public var element: Element?

        var positionX: Float
        var positionY: Float
        var positionZ: Float

        public var position: SIMD3<Float> {
            [positionX, positionY, positionZ]
        }

        /// Initializer.
        public required init() {
            index = .empty
            type = .empty
            positionX = .zero
            positionY = .zero
            positionZ = .zero
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            type = data["GroupType"] as? String ?? .empty
            positionX = data["PositionX"] as? Float ?? .zero
            positionY = data["PositionY"] as? Float ?? .zero
            positionZ = data["PositionZ"] as? Float ?? .zero
            if let idx = data["Element"] as? Int64, idx != .empty {
                element = cache.findOrCreate(idx)
            }
        }
    }

    @Model
    public final class Level: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<Level> {
            #Predicate<Level> { $0.index == index }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .normal

        @Attribute(.unique)
        public var index: Int64
        public var elevation: Double
        public var element: Element?

        /// Initializer.
        public required init() {
            index = .empty
            elevation = .zero
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            elevation = data["Elevation"] as? Double ?? .zero
            if let idx = data["Element"] as? Int64, idx != .empty {
                element = cache.findOrCreate(idx)
            }
        }
    }

    @Model
    public final class Material: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<Material> {
            #Predicate<Material> { $0.index == index }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .normal

        @Attribute(.unique)
        public var index: Int64
        public var name: String?
        public var category: String?
        public var colorTextureFile: Asset?
        public var normalTextureFile: Asset?
        public var element: Element?

        /// Initializer.
        public required init() {
            index = .empty
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            name = data["Name"] as? String ?? .empty
            category = data["MaterialCategory"] as? String ?? .empty
            if let idx = data["ColorTextureFile"] as? Int64, idx != .empty {
                colorTextureFile = cache.findOrCreate(idx)
            }
            if let idx = data["NormalTextureFile"] as? Int64, idx != .empty {
                normalTextureFile = cache.findOrCreate(idx)
            }
            if let idx = data["Element"] as? Int64, idx != .empty {
                element = cache.findOrCreate(idx)
            }
        }
    }

    @Model
    public final class MaterialInElement: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<MaterialInElement> {
            #Predicate<MaterialInElement> { $0.index == index }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .normal

        @Attribute(.unique)
        public var index: Int64
        public var isPaint: Bool
        public var area: Double
        public var volume: Double
        public var material: Material?
        public var element: Element?

        /// Initializer.
        public required init() {
            index = .empty
            isPaint = false
            area = .zero
            volume = .zero
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            isPaint = data["IsPaint"] as? Bool ?? false
            area = data["Area"] as? Double ?? .zero
            volume = data["Volume"] as? Double ?? .zero
            if let idx = data["Material"] as? Int64, idx != .empty {
                material = cache.findOrCreate(idx)
            }
            if let idx = data["Element"] as? Int64, idx != .empty {
                element = cache.findOrCreate(idx)
            }
        }
    }

    @Model
    public final class Node: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<Node> {
            #Predicate<Node> { $0.index == index }
        }

        public static func predicate(nodes: [Int]) -> Predicate<Node> {
            let indices = nodes.map{ Int64($0)}
            return #Predicate<Database.Node> { node in
                indices.contains(node.index)
            }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .normal

        @Attribute(.unique)
        public var index: Int64
        public var element: Element?

        /// Initializer.
        public required init() {
            index = .empty
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            if let idx = data["Element"] as? Int64, idx != .empty {
                element = cache.findOrCreate(idx)
            }
        }
    }

    @Model
    public final class Parameter: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<Parameter> {
            #Predicate<Parameter> { $0.index == index }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .veryHigh

        @Attribute(.unique)
        public var index: Int64
        public var value: String
        public var descriptor: ParameterDescriptor?
        public var element: Int64

        /// Provides a convenience formatted value if the value is pipe delimited.
        @Transient
        public var formattedValue: String {
            value.contains("|") ? String(value.split(separator: "|").last!) : value
        }

        /// Initializer.
        public required init() {
            index = .empty
            value = .empty
            element = .empty
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            if let idx = data["ParameterDescriptor"] as? Int64, idx != .empty {
                descriptor = cache.findOrCreate(idx)
            }
            value = data["Value"] as? String ?? .empty
            if let idx = data["Element"] as? Int64, idx != .empty {
                element = idx
            }
        }
    }

    @Model
    public final class ParameterDescriptor: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<ParameterDescriptor> {
            #Predicate<ParameterDescriptor> { $0.index == index }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .veryHigh

        @Attribute(.unique)
        public var index: Int64
        public var name: String
        public var group: String
        public var type: String
        public var isInstance: Bool
        public var isShared: Bool
        public var isReadOnly: Bool
        public var displayUnit: DisplayUnit?

        /// Initializer.
        public required init() {
            index = .empty
            name = .empty
            type = .empty
            group = .empty
            isInstance = false
            isShared = false
            isReadOnly = false
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            name = data["Name"] as? String ?? .empty
            group = data["Group"] as? String ?? .empty
            type = data["ParameterType"] as? String ?? .empty
            isInstance = data["IsIntance"] as? Bool ?? false
            isShared = data["IsShared"] as? Bool ?? false
            isReadOnly = data["IsReadOnly"] as? Bool ?? false
            if let idx = data["DisplayUnit"] as? Int64, idx != .empty {
                displayUnit = cache.findOrCreate(idx)
            }
        }
    }

    @Model
    public final class Room: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<Room> {
            #Predicate<Room> { $0.index == index }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .normal

        @Attribute(.unique)
        public var index: Int64
        public var area: Double
        public var perimeter: Double
        public var volume: Double
        public var unboundedHeight: Double
        public var number: String
        public var element: Element?

        /// Initializer.
        public required init() {
            index = .empty
            area = .zero
            perimeter = .zero
            volume = .zero
            unboundedHeight = .zero
            number = .empty
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            area = data["Area"] as? Double ?? .zero
            perimeter = data["Perimeter"] as? Double ?? .zero
            volume = data["Volume"] as? Double ?? .zero
            unboundedHeight = data["UnboundedHeight"] as? Double ?? .zero
            number = data["Number"] as? String ?? .empty
            if let idx = data["Element"] as? Int64, idx != .empty {
                element = cache.findOrCreate(idx)
            }
        }
    }

    @Model
    public final class View: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<View> {
            #Predicate<View> { $0.index == index }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .high

        @Attribute(.unique)
        public var index: Int64
        var originX: Float
        var originY: Float
        var originZ: Float
        public var origin: SIMD3<Float> {
            [originX, originY, originZ]
        }

        var directionX: Float
        var directionY: Float
        var directionZ: Float
        public var direction: SIMD3<Float> {
            [directionX, directionY, directionZ]
        }

        var positionX: Float
        var positionY: Float
        var positionZ: Float
        public var position: SIMD3<Float> {
            [positionX, positionY, positionZ]
        }

        var upX: Float
        var upY: Float
        var upZ: Float
        public var up: SIMD3<Float> {
            [upX, upY, upZ]
        }

        var rightX: Float
        var rightY: Float
        var rightZ: Float
        public var right: SIMD3<Float> {
            [rightX, rightY, rightZ]
        }

        public var scale: Float
        public var camera: Camera?
        public var element: Element?

        /// Initializer.
        public required init() {
            index = .empty
            originX = .zero
            originY = .zero
            originZ = .zero
            directionX = .zero
            directionY = .zero
            directionZ = .zero
            positionX = .zero
            positionY = .zero
            positionZ = .zero
            upX = .zero
            upY = .zero
            upZ = .zero
            rightX = .zero
            rightY = .zero
            rightZ = .zero
            scale = .zero
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            originX = (data["OriginX"] as? Double ?? .zero).singlePrecision
            originY = (data["OriginY"] as? Double ?? .zero).singlePrecision
            originZ = (data["OriginZ"] as? Double ?? .zero).singlePrecision
            directionX = (data["ViewDirectionX"] as? Double ?? .zero).singlePrecision
            directionY = (data["ViewDirectionY"] as? Double ?? .zero).singlePrecision
            directionZ = (data["ViewDirectionZ"] as? Double ?? .zero).singlePrecision
            positionX = (data["ViewPositionX"] as? Double ?? .zero).singlePrecision
            positionY = (data["ViewPositionY"] as? Double ?? .zero).singlePrecision
            positionZ = (data["ViewPositionZ"] as? Double ?? .zero).singlePrecision
            upX = (data["UpX"] as? Double ?? .zero).singlePrecision
            upY = (data["UpY"] as? Double ?? .zero).singlePrecision
            upZ = (data["UpZ"] as? Double ?? .zero).singlePrecision
            rightX = (data["RightX"] as? Double ?? .zero).singlePrecision
            rightY = (data["RightY"] as? Double ?? .zero).singlePrecision
            rightZ = (data["RightZ"] as? Double ?? .zero).singlePrecision
            scale = (data["Scale"] as? Double ?? .zero).singlePrecision

            if let idx = data["Camera"] as? Int64, idx != .empty {
                camera = cache.findOrCreate(idx)
            }
            if let idx = data["Element"] as? Int64, idx != .empty {
                element = cache.findOrCreate(idx)
            }
        }
    }

    @Model
    public final class Workset: IndexedPersistentModel {

        public static func predicate(_ index: Int64) -> Predicate<Workset> {
            #Predicate<Workset> { $0.index == index }
        }

        @Transient
        public static let importPriority: ModelImportPriority = .veryHigh

        @Attribute(.unique)
        public var index: Int64
        public var isEditable: Bool
        public var isOpen: Bool
        public var kind: String
        public var name: String

        /// Initializer.
        public required init() {
            index = .empty
            isEditable = false
            isOpen = false
            kind = .empty
            name = .empty
        }

        public func update(from data: [String: AnyHashable], cache: ImportCache) {
            isEditable = data["IsEditable"] as? Bool ?? false
            isOpen = data["IsOpen"] as? Bool ?? false
            kind = data["Kind"] as? String ?? .empty
            name = data["Name"] as? String ?? .empty
        }
    }
}
