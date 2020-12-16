//
//  ViewControllerEx.swift
//  avFoundation
//
//  Created by 池田和浩 on 2020/12/15.
//
import UIKit

extension ViewController {
    // 画面回転なしにする設定
    override var shouldAutorotate: Bool { return true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { return .portrait }
}
