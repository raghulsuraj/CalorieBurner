//
//  DailyInputViewController.swift
//  CalorieBurner
//
//  Created by Dino Srdoč on 17/05/2018.
//  Copyright © 2018 Dino Srdoč. All rights reserved.
//

import UIKit

protocol DailyInputViewControllerDelegate: AnyObject {
    func didSaveDaily()
}

class DailyInputViewController: UIViewController {
    @IBOutlet weak var dailyInputView: DailyInputView!
    
    var date: Date?
    weak var delegate: DailyInputViewControllerDelegate?
    
    private func shouldSaveDaily() {
        guard let date = date else { return }
        // TODO: - don't `try?`, `DO`
        try? CoreDataStack.shared.updateOrCreate(at: date,
                                                 mass: dailyInputView.mass ?? dailyInputView.massBuffer,
                                                 energy: dailyInputView.energy ?? dailyInputView.energyBuffer,
                                                 mood: dailyInputView.mood)
    }
    
    @IBAction func doneButtonWasPressed(_ sender: Any) {
        shouldSaveDaily()
        delegate?.didSaveDaily()
        dismiss(animated: true, completion: nil)
    }
    
    @IBAction func cancelButtonWasPressed(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }
}
