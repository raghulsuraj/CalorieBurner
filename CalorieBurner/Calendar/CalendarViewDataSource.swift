//
//  CalendarViewDataSource.swift
//  CalorieBurner
//
//  Created by Dino Srdoč on 08/05/2018.
//  Copyright © 2018 Dino Srdoč. All rights reserved.
//

import JTAppleCalendar

/// Preconfigured Calendar Data Source equipped for dealing with weekly/monthly Calendar Views. 
class CalendarViewDataSource: JTAppleCalendarViewDataSource, DateBoundaries {
    enum Configuration { case weekly, monthly }
    
    let dateFormatter = DateFormatter()
    var configuration: Configuration
    var firstDayOfWeek: DaysOfWeek = .monday
    
    lazy var startDate: Date = {
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.date(from: "2000-01-01")!
    }()
    
    lazy var endDate: Date = {
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.date(from: "2030-12-31")!
    }()
    
    init(configuration: Configuration) {
        self.configuration = configuration
    }
    
    /// A weekly configuration displays only a single row with no overlapping dates. A monthly configuration displays as many rows as it needs — mostly 5-6
    func configureCalendar(_ calendar: JTAppleCalendarView) -> ConfigurationParameters {
        if configuration == .weekly {
            return ConfigurationParameters(startDate: startDate,
                                           endDate: endDate,
                                           numberOfRows: 1,
                                           generateInDates: .forFirstMonthOnly,
                                           generateOutDates: .off,
                                           firstDayOfWeek: firstDayOfWeek,
                                           hasStrictBoundaries: false)
        } else {
            return ConfigurationParameters(startDate: startDate,
                                           endDate: endDate,
                                           generateOutDates: .tillEndOfRow,
                                           firstDayOfWeek: firstDayOfWeek,
                                           hasStrictBoundaries: false)
        }
    }
}
