//

import UIKit
import CoreBluetooth
import AVFoundation

let heartRateServiceCBUUID = CBUUID(string: "0x180D") // для определения только мониторов СерРитма
// служба измерения пульса имеет две характеристики частота сердца "2A37" и положение датчика "2A38"
// каждая характиристика имеет свойства
let heartRateMeasurementCharacteristicCBUUID = CBUUID(string: "2A37")
let bodySensorLocationCharacteristicCBUUID = CBUUID(string: "2A38")


class HRMViewController: UIViewController {

  @IBOutlet weak var heartRateLabel: UILabel!
  @IBOutlet weak var bodySensorLocationLabel: UILabel!

  var centralManager: CBCentralManager!
  var heartRatePeripheral: CBPeripheral!
  
  private var soundTimer: Timer? //добавил
  private var heartRate: Int = 0  // добавил
  private var countedInterval: Int = 0 //добавил
    
  private lazy var player: AVAudioPlayer? = {
    guard let url = Bundle.main.url(forResource: "Edited short", withExtension: "m4a"),
      let player = try? AVAudioPlayer(contentsOf: url)
      else {
      assertionFailure("Failed to setup player")
      return nil
    }
    return player
  }()
  
  override func viewDidLoad() {
    super.viewDidLoad()
    heartRate = 170
    print("view loaded")

    soundTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true, block: { _ in
      print("timer triggered \(self.countedInterval), calculation \(self.countedInterval > 60 / self.heartRate * 100)")
      self.countedInterval += 1
      if self.countedInterval > 60 / self.heartRate * 100 && self.heartRate > 0 {
        print("beeped")
        self.countedInterval = 0
        self.playSound()
      }
    })

    heartRateLabel.font = UIFont.monospacedDigitSystemFont(ofSize: heartRateLabel.font!.pointSize, weight: .regular)
    centralManager = CBCentralManager(delegate: self, queue: nil) //инициализация переменной
    
  }

  // выходной метод
  func onHeartRateReceived(_ heartRate: Int) {
    heartRateLabel.text = String(heartRate)
    print("BPM: \(heartRate)")
    self.heartRate = heartRate
    //playSound()
     //!!! если фукциия playSound активна звук идет примерно один раз в секунду, если эта функция закомитена то звука совсем нет
  }
}

extension HRMViewController: CBCentralManagerDelegate {
  
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    
    switch central.state {
    case .unknown:
    print("central.state is .unknown")
    case .resetting:
      print("central.state is .resetting")
    case .unsupported:
      print("central.state is .unsuppoted")
    case .unauthorized:
      print("central.state is .unauthorized")
    case .poweredOff:
      print("central.state is .poweredOff ---")
    case .poweredOn:
      print("central.state is .poweredON +++")
      centralManager.scanForPeripherals(withServices: nil) // сканирование периферийных устройств
    
    }
  }
  func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
    print(peripheral)
    // функция обнаружения устройств
    heartRatePeripheral = peripheral
    heartRatePeripheral.delegate = self
    centralManager.stopScan() // остановка сканирования
    centralManager.connect (heartRatePeripheral) // подключение к переф устройству
  
  }
  
  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    print("Поключено")
    heartRatePeripheral.discoverServices ([heartRateServiceCBUUID]) // обращение к перефирийному устр чтоб узнать какие службы есть было: (nil)
  }
}
extension HRMViewController: CBPeripheralDelegate {
  
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    
    guard let services = peripheral.services else { return }
    
    for service in services {
      print(services)
      peripheral.discoverCharacteristics(nil, for: service)
     
    }
  }
  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    guard let characteristics = service.characteristics else { return }
    
    for characteristic in characteristics {
      print("\(characteristic.properties) роу свойства")
      
      if characteristic.properties.contains(.read) {
        print("\(characteristic.uuid): properties contains .read")
        peripheral.readValue(for: characteristic)
      }
      if characteristic.properties.contains(.notify) {
        print("\(characteristic.uuid): properties contains .notify")
       peripheral.setNotifyValue(true, for: characteristic)
      }
    }
  }
  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                  error: Error?) {
    
    switch characteristic.uuid {
    
    case bodySensorLocationCharacteristicCBUUID:
        print(characteristic.value ?? "no value /////")
        let bodySensorLocation = bodyLocation(from: characteristic)
        bodySensorLocationLabel.text = bodySensorLocation
    
    case heartRateMeasurementCharacteristicCBUUID: // последнее значение
      let bpm = heartRate(from: characteristic)
      onHeartRateReceived(bpm)
      
     
      
    default:
        print("Unhandled Characteristic UUID: \(characteristic.uuid)")
    }
  }

  private func bodyLocation(from characteristic: CBCharacteristic) -> String {
    guard let characteristicData = characteristic.value,
      let byte = characteristicData.first else { return "Error" }

    switch byte {
      case 0: return "Other"
      case 1: return "Chest"
      case 2: return "Wrist"
      case 3: return "Finger"
      case 4: return "Hand"
      case 5: return "Ear Lobe"
      case 6: return "Foot"
      default:
        return "Reserved for future use"
    }
  }
  private func heartRate(from characteristic: CBCharacteristic) -> Int {
    guard let characteristicData = characteristic.value else { return -1 }
    let byteArray = [UInt8](characteristicData)
    
    let firstBitValue = byteArray[0] & 0x01
    if firstBitValue == 0 {
      // Heart Rate Value Format is in the 2nd byte
      return Int(byteArray[1])
    
    } else {
      // Heart Rate Value Format is in the 2nd and 3rd bytes
      return (Int(byteArray[1]) << 8) + Int(byteArray[2])
    
    }
   
  }
  // моя функция
  func playSound() {
      player?.play() // У тебя был раньше let player = try! Не используй ! (force unwrapping) в коде который будет выпускаться, это один из самых легких способом получить вылетание приложения. В тестах ок, в production code нет. Могут быть редкие исключения но пока о них можно не париться. Если optional то if let = или guard let = (как я в декларации player сделал) или как тут player?
  }

}


