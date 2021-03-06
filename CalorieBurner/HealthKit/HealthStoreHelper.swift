//
//  HealthStoreHelper.swift
//  CalorieBurner
//
//  Created by Dino Srdoč on 30/04/2018.
//  Copyright © 2018 Dino Srdoč. All rights reserved.
//

import HealthKit
import CoreData

protocol DailyModelConvertible {
    associatedtype Data
    
    func convert(data: Data, context: NSManagedObjectContext) -> Daily
    func convertAll(in context: NSManagedObjectContext) -> [Daily]
}

class HealthStoreHelper {
    
    struct SampleTypes {
        static let mass = HKObjectType.quantityType(forIdentifier: .bodyMass)!
        static let energy = HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!
        static let height = HKObjectType.quantityType(forIdentifier: .height)!
        static let steps = HKObjectType.quantityType(forIdentifier: .stepCount)!
    }
    
    struct CharacteristicTypes {
        static let sex = HKObjectType.characteristicType(forIdentifier: .biologicalSex)!
        static let dateOfBirthComponents = HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
    }
    
    // this should only ever be a single instance across the entire app, according to Apple
    private let store: HKHealthStore

    private let typesToRead: Set<HKObjectType>
    private let typesToWrite: Set<HKSampleType>
    
    // this is necessary for stopping the appropriate queries if it didn't fetch any results
    private var didExecuteAnchoredQuery = false
    private var didExecuteStatisticsQuery = false
    
    // anchor query uses this so it doesn't have to fetch everything all over again
    private var anchor: HKQueryAnchor?
    
    // the queries' completion handlers assign their values to these variables when they fetch the appropriate data
    private var energyResults = [Date : HKQuantity]()
    private var massResults = [Date : HKQuantitySample]()
    
    private lazy var statisticsQuery = makeEnergyStatisticsQuery()
    private lazy var anchoredQuery = makeAnchoredMassQuery()
    
    private static let defaultReadingTypes: Set = [SampleTypes.mass, SampleTypes.energy, SampleTypes.steps, SampleTypes.height, CharacteristicTypes.sex, CharacteristicTypes.dateOfBirthComponents]
    private static let defaultWritingTypes: Set = [SampleTypes.mass]
    
    // we need a singleton health store, as they are long lived objects
    static let storeSingleton = HKHealthStore()
    
    static let shared = HealthStoreHelper(store: storeSingleton, readingTypes: defaultReadingTypes, writingTypes: defaultWritingTypes)
    
    init(store: HKHealthStore,
         readingTypes: Set<HKObjectType> = defaultReadingTypes,
         writingTypes: Set<HKSampleType> = defaultWritingTypes)
    {
        self.store = store
        typesToRead = readingTypes
        typesToWrite = writingTypes
    }
    
    func requestAuthorization(_ completion: @escaping (Bool, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false, HKError(.errorHealthDataUnavailable))
            return
        }
        
        store.requestAuthorization(toShare: typesToWrite, read: typesToRead) { (success, error) in
            completion(success, error)
        }
    }
    
    func writeData(sample: HKQuantitySample, _ completion: @escaping (Bool, Error?) -> Void) {
        store.save(sample, withCompletion: completion)
    }
    
    // TODO: don't use a mock
    func fetchUserProfile() -> UserRepresentable {
        let ageComponents = try? store.dateOfBirthComponents()
        let sexComponent = try? store.biologicalSex().biologicalSex
        
        let age: Int? = ageComponents.flatMap {
            let todayDateComponents = Calendar.current.dateComponents(in: Calendar.current.timeZone, from: Date())
            let difference = Calendar.current.dateComponents([.year], from: $0, to: todayDateComponents)
            return difference.year
        }
        let sex = sexComponent.flatMap(Sex.init)
        
        print("hi. sex: ", sex)
        return MockUser(activityLevel: .extreme, age: 12, height: 12, weight: 12, sex: .male)
    }
    
    // set up observer queries for both mass and energy
    func enableBackgroundDelivery() {
        let massQuery = HKObserverQuery(sampleType: SampleTypes.mass,
                                        predicate: nil)
        { [unowned self] (query, completion, error) in
            guard error == nil else { fatalError("mass observer completion handler failed. \(error!.localizedDescription)") }
            
            if !self.didExecuteAnchoredQuery {
                // remove deleted objects, then merge the results back into the massResults
                self.anchoredQuery = self.makeAnchoredMassQuery(completion: completion) { results, deletions in
                    self.massResults = self.massResults.filter { item in
                        return !deletions.contains(where: { $0.uuid == item.value.uuid })
                    }
                    self.massResults.merge(results) { (first, second) in return first }
                }
                self.store.execute(self.anchoredQuery)
                self.didExecuteAnchoredQuery = true
            } else {
                self.store.stop(self.anchoredQuery)
                self.anchoredQuery = self.makeAnchoredMassQuery(completion: completion) { results, deletions in
                    self.massResults = results
                }
                self.store.execute(self.anchoredQuery)
            }
        }
        
        let energyQuery = HKObserverQuery(sampleType: SampleTypes.energy,
                                          predicate: nil)
        { [unowned self] (query, completion, error) in
            guard error == nil else { fatalError("energy observer completion handler failed. \(error!.localizedDescription)") }
            
            if !self.didExecuteStatisticsQuery {
                self.store.execute(self.statisticsQuery)
                self.didExecuteStatisticsQuery = true
            } else {
                self.store.stop(self.statisticsQuery)
                self.statisticsQuery = self.makeEnergyStatisticsQuery(completion: completion) { results in
                    self.energyResults = results
                }
                self.store.execute(self.statisticsQuery)
            }
        }
        
        store.execute(massQuery)
        store.execute(energyQuery)
        
        func completion(success: Bool, error: Error?) {
            guard success else {
                print("** error occured during background delivery setup completion handler **")
                print(error!.localizedDescription)
                abort()
            }
        }
        
        store.enableBackgroundDelivery(for: SampleTypes.mass,
                                       frequency: .immediate,
                                       withCompletion: completion)
        
        store.enableBackgroundDelivery(for: SampleTypes.energy,
                                       frequency: .immediate,
                                       withCompletion: completion)
    }
    
    private func makeEnergyStatisticsQuery(completion: (() -> Void)? = nil,
                                           didProcessValues valueProcessing: (([Date : HKQuantity]) -> Void)? = nil)
        -> HKStatisticsCollectionQuery
    {
        let query = HKStatisticsCollectionQuery(quantityType: SampleTypes.energy,
                                                quantitySamplePredicate: nil,
                                                options: .cumulativeSum,
                                                anchorDate: Date(timeIntervalSinceReferenceDate: 0),
                                                intervalComponents: DateComponents(day: 1))
        
        query.initialResultsHandler = { (query, results, error) in
            guard let results = results,                // no results. fail silently
                  !results.statistics().isEmpty         // results are empty
            else { return }
            
            let endDate = Date()
            let startDate = Calendar.current.date(byAdding: .month, value: -3, to: endDate)!
            
            var caloriesPerDate = [Date : HKQuantity]()
            
            results.enumerateStatistics(from: startDate, to: endDate) { (statistics, stop) in
                if let quantity = statistics.sumQuantity() {
                    let date = statistics.startDate.startOfDay
                    caloriesPerDate[date] = quantity
                }
            }
            
            valueProcessing?(caloriesPerDate)
            completion?()
        }
        
        return query
    }
    
    private func makeAnchoredMassQuery(completion: (() -> Void)? = nil,
                                       didProcessValues valueProcessing: (([Date : HKQuantitySample], [HKDeletedObject]) -> Void)? = nil)
        -> HKAnchoredObjectQuery
    {
        func anchorUpdateHandler(query: HKAnchoredObjectQuery, samples: [HKSample]?, deletions: [HKDeletedObject]?, newAnchor: HKQueryAnchor?, error: Error?) {
            guard let samples = samples, let deletions = deletions else { print("error initial"); return }
            
            anchor = newAnchor

            var values = [Date : HKQuantitySample]()
            for sample in samples {
                values[sample.startDate.startOfDay] = sample as? HKQuantitySample
            }
            
            valueProcessing?(values, deletions)
            
            completion?()
        }
        
        let query = HKAnchoredObjectQuery(type: HKObjectType.quantityType(forIdentifier: .bodyMass)!,
                                          predicate: nil,
                                          anchor: anchor,
                                          limit: HKObjectQueryNoLimit,
                                          resultsHandler: anchorUpdateHandler)
        query.updateHandler = anchorUpdateHandler
        
        return query
    }
}

extension HealthStoreHelper {
    func totalStepCount(startingFrom startDate: Date, to endDate: Date, completionHandler: ((Int?) -> Void)?) {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let query = HKStatisticsQuery(quantityType: SampleTypes.steps,
                                      quantitySamplePredicate: predicate,
                                      options: HKStatisticsOptions.cumulativeSum)
        { (query, statistics, error) in
            guard error == nil else {
                print("error fetching step count: ", error!)
                return
            }
            
            let totalStepCount = (statistics?.sumQuantity()?.doubleValue(for: HKUnit.count())).map(Int.init)
            completionHandler?(totalStepCount)
        }
        
        store.execute(query)
    }
    
    /// Fetches the total step count in the last 6 months
    func totalStepCount(completionHandler: ((Int?) -> Void)? = nil) {
        let currentDate = Date()
        let startDate = Calendar.current.date(byAdding: .month, value: -6, to: currentDate)!
        
        totalStepCount(startingFrom: startDate, to: currentDate, completionHandler: completionHandler)
    }
    
    /// User's average weight in kilograms, or nil if there are no values
    func averageWeight(startingFrom startDate: Date, to endDate: Date, completionHandler: ((Double?) -> Void)? = nil) {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let query = HKStatisticsQuery(quantityType: SampleTypes.mass,
                                      quantitySamplePredicate: predicate,
                                      options: .discreteAverage)
        { (query, statistics, error) in
            guard error == nil else {
                print("error occured fetching average weight: ", error!.localizedDescription)
                return
            }
            
            let averageWeight = statistics?.averageQuantity()?.doubleValue(for: HKUnit.gramUnit(with: .kilo))
            completionHandler?(averageWeight)
        }
        
        store.execute(query)
    }
    
    func averageWeight(_ completionHandler: ((Double?) -> Void)? = nil) {
        let currentDate = Date()
        let startDate = Calendar.current.date(byAdding: .month, value: -6, to: currentDate)!
        
        averageWeight(startingFrom: startDate, to: currentDate, completionHandler: completionHandler)
    }
    
    func averageHeight(startingFrom startDate: Date, to endDate: Date, completionHandler: ((Double?) -> Void)? = nil) {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let query = HKStatisticsQuery(quantityType: SampleTypes.height,
                                      quantitySamplePredicate: predicate,
                                      options: .discreteAverage)
        { (query, statistics, error) in
            guard error == nil else {
                print("error occured fetching average height: ", error!.localizedDescription)
                return
            }
            
            let averageHeight = statistics?.averageQuantity()?.doubleValue(for: HKUnit.meterUnit(with: .centi))
            completionHandler?(averageHeight)
        }
        
        store.execute(query)
    }
    
    func averageHeight(_ completionHandler: ((Double?) -> Void)? = nil) {
        let currentDate = Date()
        let startDate = Calendar.current.date(byAdding: .month, value: -6, to: currentDate)!
        
        averageHeight(startingFrom: startDate, to: currentDate, completionHandler: completionHandler)
    }
}

extension HealthStoreHelper: DailyModelConvertible {
    typealias Data = (date: Date, mass: Double?, energy: Double?)
    
    func convert(data: Data, context: NSManagedObjectContext) -> Daily {
        let (date, mass, energy) = data
        let daily = Daily(context: context, date: date)
        daily.updateValues(mass: mass, energy: energy)
        
        return daily
    }
    
    func convertAll(in context: NSManagedObjectContext) -> [Daily] {
        let dates = Set(energyResults.keys).union(Set(massResults.keys))
        return dates
            .sorted()
            .map { date in
                let massValue = massResults[date]?.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
                let energyValue = energyResults[date]?.doubleValue(for: HKUnit.kilocalorie())
                return convert(data: (date, massValue, energyValue), context: context)
            }
    }

}
