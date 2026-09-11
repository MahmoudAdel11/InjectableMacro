import InjectableMacro

@Injectable
class TripBookingViewModel {
    let repository: String
    let geocoder: String
    var bookingCount: Int = 0
    var lastStatus: String = "idle" {
        didSet {
            print("status changed to \(lastStatus)")
        }
    }
    var summary: String {
        "\(repository) - \(geocoder)"
    }
}
