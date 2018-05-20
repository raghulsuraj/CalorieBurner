//
//  OnboardingViewController.swift
//  CalorieBurner
//
//  Created by Dino Srdoč on 20/05/2018.
//  Copyright © 2018 Dino Srdoč. All rights reserved.
//

import UIKit

class OnboardingViewController: UIPageViewController {
    var pages: [UIViewController]!
    var onDoneButtonTap: (() -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
//        delegate = self
        dataSource = self
        
        let tempPages = [
            storyboard?.instantiateViewController(withIdentifier: "PageOne"),
            storyboard?.instantiateViewController(withIdentifier: "PageTwo"),
            storyboard?.instantiateViewController(withIdentifier: "PageThree")
        ]
        
        pages = tempPages.compactMap { $0 }
        
        (pages.last as? PageThreeViewController)?.onDoneButtonTap = onDoneButtonTap
        
        setViewControllers([pages[0]], direction: .forward, animated: false, completion: nil)
    }
}

extension OnboardingViewController: UIPageViewControllerDataSource {
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let index = pages.index(of: viewController), index != 0 else { return nil }
        
        let previous = abs((index - 1) % pages.count)
        return pages[previous]
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let index = pages.index(of: viewController), index != (pages.count - 1) else { return nil }
        
        let next = abs((index + 1) % pages.count)
        return pages[next]
    }
    
    func presentationIndex(for pageViewController: UIPageViewController) -> Int {
        return pages.count
    }
}

class PageThreeViewController: UIViewController {
    var onDoneButtonTap: (() -> Void)?
    
    @IBAction func didTapOkayButton(_ sender: Any) {
        onDoneButtonTap?()
    }
}