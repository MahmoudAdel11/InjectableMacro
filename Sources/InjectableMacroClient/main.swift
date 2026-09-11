import InjectableMacro

@Injectable
class TripBookingViewModel {
    let repository: String
    let geocoder: String

    init(repository: String, geocoder: String) {
        self.repository = repository
        self.geocoder = geocoder
    }
}
