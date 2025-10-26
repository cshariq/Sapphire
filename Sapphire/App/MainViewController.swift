//
//  MainViewController.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-23

import AppKit

class MainViewController: NSViewController {

    var client = XPCClient()

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let auth = Util.askAuthorization() else {
            fatalError("Authorization not acquired.")
        }

        Util.blessHelper(label: Constant.helperMachLabel, authorization: auth)

        client.start()
    }
}