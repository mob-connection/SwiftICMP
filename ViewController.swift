//
//  ViewController.swift
//  SwiftICMP
//
//  Created by Oleksandr Zhurba on 21.05.2024.
//

import UIKit

class ViewController: UIViewController {

	override func viewDidLoad() {
		super.viewDidLoad()

		Task {
			let ping = try await ICMPSender(host: "192.168.0.1", timeval: .init(tv_sec: 1, tv_usec: 0))
			var i: UInt16 = 0
			while i < UInt16.max {
				do {
					let response = try await ping.send(sequence: i)
					print(response)
					print("\n")
				} catch {
					print("error: \(error)")
				}
				i += 1
			}
		}
	}

}
