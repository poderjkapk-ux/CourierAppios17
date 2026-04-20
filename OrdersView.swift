import SwiftUI
import CoreLocation

// MARK: - Дизайн-система (Кольори)
struct AppColors {
    static let primary = Color(red: 30/255, green: 41/255, blue: 59/255) // 1E293B
    static let secondary = Color(red: 16/255, green: 185/255, blue: 129/255) // 10B981
    static let background = Color(red: 248/255, green: 250/255, blue: 252/255) // F8FAFC
    static let error = Color.red
    static let warning = Color.orange
    static let textSecondary = Color.gray
    static let info = Color.blue
    static let surface = Color.white
}

struct OrdersView: View {
    @AppStorage("cookie") var savedCookie: String = ""
    @StateObject private var networkManager = NetworkManager.shared
    @StateObject private var locationManager = LocationManager()
    
    @State private var orders: [OpenOrder] = []
    @State private var announcements: [Announcement] = []
    @State private var isOnline: Bool = false
    @State private var isLoading = false
    
    // Стан для персонального замовлення (Direct Offer)
    @State private var directOffer: OpenOrder? = nil
    @State private var isActionLoading = false
    
    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // MARK: - TopBar
                HStack {
                    Text("Доступні")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(AppColors.primary)
                    
                    Spacer()
                    
                    // Годинник
                    CurrentTimeView()
                        .padding(.trailing, 8)
                    
                    // Кнопка статусу
                    Button(action: toggleStatus) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isOnline ? AppColors.secondary : AppColors.textSecondary)
                                .frame(width: 10, height: 10)
                            Text(isOnline ? "Онлайн" : "Офлайн")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(isOnline ? AppColors.secondary : AppColors.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background((isOnline ? AppColors.secondary : AppColors.textSecondary).opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
                
                // MARK: - Основний список
                ScrollView {
                    LazyVStack(spacing: 16) {
                        
                        // Попередження про вимкнений GPS
                        if !locationManager.isTracking {
                            GPSWarningBanner()
                        }
                        
                        // Блок оголошень від системи
                        ForEach(announcements) { ann in
                            AnnouncementCardView(announcement: ann) { id in
                                dismissAnnouncement(id)
                            }
                        }
                        
                        if orders.isEmpty && !isLoading {
                            VStack(spacing: 20) {
                                Image(systemName: "checkmark.circle.fill")
                                    .resizable()
                                    .frame(width: 80, height: 80)
                                    .foregroundColor(Color.gray.opacity(0.3))
                                Text("Зараз немає замовлень")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundColor(.gray)
                            }
                            .padding(.top, 100)
                        } else {
                            // Список замовлень
                            ForEach(orders) { order in
                                OrderCardView(order: order) { jobId in
                                    acceptOrder(jobId: jobId)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .refreshable { await refreshData() }
            }
            
            // Діалог персонального замовлення (Direct Offer Overlay)
            if let offer = directOffer {
                DirectOfferOverlay(
                    offer: offer,
                    isLoading: isActionLoading,
                    onAccept: { acceptDirectOffer(offer.id) },
                    onDecline: { declineDirectOffer(offer.id) }
                )
            }
        }
        .onAppear {
            locationManager.requestPermissions()
            locationManager.startTracking()
            
            // ДОДАНО: Підключення WebSocket для миттєвого отримання замовлень
            if !savedCookie.isEmpty {
                networkManager.connectWebSocket(cookie: savedCookie)
            }
            
            Task { await refreshData() }
        }
        .onReceive(networkManager.wsEventPublisher) { event in
            handleWSEvent(event)
        }
    }
    
    // MARK: - Логіка
    
    private func handleWSEvent(_ event: WSEvent) {
        switch event {
        case .newOrder:
            Task { await fetchOrders() }
        case .directOffer:
            Task { await fetchDirectOffers() }
        default: break
        }
    }
    
    private func refreshData() async {
        await fetchOrders()
        await fetchAnnouncements()
        await fetchProfileStatus()
        await fetchDirectOffers()
    }
    
    private func fetchOrders() async {
        isLoading = true
        let lat = locationManager.userLocation?.coordinate.latitude ?? 0.0
        let lon = locationManager.userLocation?.coordinate.longitude ?? 0.0
        
        do {
            orders = try await networkManager.getOpenOrders(cookie: savedCookie, lat: lat, lon: lon)
        } catch { print("Error fetching orders: \(error)") }
        isLoading = false
    }
    
    private func fetchAnnouncements() async {
        do {
            announcements = try await networkManager.getAnnouncements(cookie: savedCookie)
        } catch { print("Error fetching announcements: \(error)") }
    }
    
    private func fetchDirectOffers() async {
        do {
            let offers = try await networkManager.getDirectOffers(cookie: savedCookie)
            if let first = offers.first {
                withAnimation { self.directOffer = first }
            }
        } catch { print("Error fetching direct offers: \(error)") }
    }
    
    private func fetchProfileStatus() async {
        do {
            let profile = try await networkManager.getProfile(cookie: savedCookie)
            isOnline = profile.isOnline
        } catch { print("Error fetching profile: \(error)") }
    }
    
    private func toggleStatus() {
        Task {
            do {
                let response = try await networkManager.toggleStatus(cookie: savedCookie)
                isOnline = response.isOnline
            } catch { print("Error toggling status: \(error)") }
        }
    }
    
    private func acceptOrder(jobId: Int) {
        Task {
            do {
                let response = try await networkManager.acceptOrder(cookie: savedCookie, jobId: jobId)
                if response.status == "ok" {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    await fetchOrders()
                }
            } catch { print("Error accepting order: \(error)") }
        }
    }
    
    private func acceptDirectOffer(_ id: Int) {
        isActionLoading = true
        Task {
            do {
                let res = try await networkManager.acceptOrder(cookie: savedCookie, jobId: id)
                if res.status == "ok" {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    directOffer = nil
                    // Після прийняття замовлення воно зникне зі списку доступних автоматично
                }
            } catch { print("Error accepting direct offer: \(error)") }
            isActionLoading = false
        }
    }
    
    private func declineDirectOffer(_ id: Int) {
        isActionLoading = true
        Task {
            do {
                _ = try await networkManager.declineDirectOrder(cookie: savedCookie, jobId: id)
                directOffer = nil
            } catch { print("Error declining direct offer: \(error)") }
            isActionLoading = false
        }
    }
    
    private func dismissAnnouncement(_ id: Int) {
        withAnimation { announcements.removeAll { $0.id == id } }
        Task { try? await networkManager.dismissAnnouncement(cookie: savedCookie, annId: id) }
    }
}

// MARK: - Допоміжні компоненти

struct CurrentTimeView: View {
    @State private var currentTime = ""
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        Text(currentTime)
            .font(.system(size: 16, weight: .heavy))
            .foregroundColor(AppColors.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppColors.primary.opacity(0.08))
            .cornerRadius(12)
            .onReceive(timer) { _ in updateTime() }
            .onAppear { updateTime() }
    }
    
    private func updateTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        currentTime = formatter.string(from: Date())
    }
}

struct GPSWarningBanner: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "location.slash.fill")
                .foregroundColor(AppColors.warning)
                .font(.title)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Геолокацію вимкнено")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(AppColors.primary)
                Text("Увімкніть GPS, щоб бачити реальну відстань до замовлень 🙌")
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            
            Button("Увімкнути") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppColors.warning)
            .cornerRadius(8)
        }
        .padding()
        .background(AppColors.warning.opacity(0.15))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.warning, lineWidth: 1))
        .cornerRadius(16)
    }
}

struct ReadinessTimerView: View {
    let readyAtIso: String?
    
    @State private var timeText = ""
    @State private var isLate = false
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 6) {
            Text(isLate ? "🚨" : "🕰️")
            Text(timeText)
                .font(.caption)
                .fontWeight(.bold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background((isLate ? Color.red : AppColors.primary).opacity(0.1))
        .foregroundColor(isLate ? .red : AppColors.primary)
        .cornerRadius(8)
        .onReceive(timer) { _ in updateTimer() }
        .onAppear { updateTimer() }
    }
    
    // ДОДАНО: Безпечний парсер дати, який розуміє мілісекунди і формат БД
    private func parseDateSafe(_ dateStr: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let d = formatter.date(from: dateStr) { return d }
        
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: dateStr) { return d }
        
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df.date(from: dateStr)
    }
    
    private func updateTimer() {
        guard let iso = readyAtIso, let readyDate = parseDateSafe(iso) else { return } // ВИКОРИСТОВУЄМО parseDateSafe
        let diff = Int(readyDate.timeIntervalSinceNow)
        isLate = diff < 0
        let absDiff = abs(diff)
        let m = absDiff / 60
        let s = absDiff % 60
        timeText = String(format: "%@ %02d:%02d", isLate ? "Запізнення" : "Готується", m, s)
    }
}

struct AnnouncementCardView: View {
    let announcement: Announcement
    let onDismiss: (Int) -> Void
    
    var body: some View {
        let (color, icon) = getStyle()
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(announcement.title).font(.headline).fontWeight(.bold)
                Text(announcement.message).font(.subheadline).foregroundColor(.primary.opacity(0.8))
            }
            Spacer()
            Button(action: { onDismiss(announcement.id) }) {
                Image(systemName: "xmark").foregroundColor(.gray)
            }
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.3), lineWidth: 1))
    }
    
    private func getStyle() -> (Color, String) {
        switch announcement.style {
        case "danger": return (.red, "exclamationmark.triangle.fill")
        case "warning": return (.orange, "exclamationmark.circle.fill")
        case "success": return (.green, "checkmark.seal.fill")
        default: return (.blue, "info.circle.fill")
        }
    }
}

struct DirectOfferOverlay: View {
    let offer: OpenOrder
    let isLoading: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 20) {
                HStack {
                    Image(systemName: "flame.fill").foregroundColor(.orange)
                    Text("Ексклюзив!").font(.title3).fontWeight(.black)
                }
                Text("Заклад пропонує вам ще одне замовлення попутно.").font(.subheadline).multilineTextAlignment(.center)
                
                VStack(alignment: .leading, spacing: 10) {
                    Text(offer.restaurantName).fontWeight(.bold)
                    Text(offer.dropoffAddress).font(.caption).foregroundColor(.gray)
                    Divider()
                    HStack {
                        Text("Ваш дохід:")
                        Spacer()
                        Text("+\(Int(offer.fee)) ₴").fontWeight(.black).foregroundColor(.green)
                    }
                }
                .padding().background(Color.gray.opacity(0.1)).cornerRadius(12)
                
                Button(action: onAccept) {
                    if isLoading { ProgressView().tint(.white) }
                    else { Text("🔥 Прийняти").fontWeight(.bold) }
                }
                .frame(maxWidth: .infinity).padding().background(Color.green).foregroundColor(.white).cornerRadius(12).disabled(isLoading)
                
                Button("Відмовитись", action: onDecline).foregroundColor(.red).disabled(isLoading)
            }
            .padding(24).background(Color.white).cornerRadius(24).padding(30)
        }
    }
}

struct OrderCardView: View {
    let order: OpenOrder
    let onAccept: (Int) -> Void
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(order.restaurantName).font(.title3).fontWeight(.heavy).foregroundColor(AppColors.primary)
                        if !isExpanded { Text(order.restaurantAddress).font(.subheadline).foregroundColor(AppColors.textSecondary).lineLimit(1) }
                    }
                    Spacer()
                    Text("\(Int(order.fee)) ₴").font(.title3).fontWeight(.black).foregroundColor(AppColors.secondary).padding(.horizontal, 12).padding(.vertical, 6).background(AppColors.secondary.opacity(0.1)).cornerRadius(12)
                }
                
                HStack(spacing: 8) {
                    Text(order.paymentType == "prepaid" ? "✨ Оплачено" : "💸 Готівка")
                        .font(.caption).fontWeight(.bold).foregroundColor(order.paymentType == "prepaid" ? AppColors.secondary : AppColors.warning)
                        .padding(.horizontal, 10).padding(.vertical, 6).background((order.paymentType == "prepaid" ? AppColors.secondary : AppColors.warning).opacity(0.15)).cornerRadius(8)
                    
                    if let readyAt = order.readyAt { ReadinessTimerView(readyAtIso: readyAt) }
                    
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down").foregroundColor(.gray)
                }
            }
            .padding(20).background(Color.white)
            .onTapGesture { withAnimation(.spring()) { isExpanded.toggle() } }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()
                    
                    if order.paymentType == "buyout" {
                        Text("Увага: Заберіть \(Int(order.price)) ₴ у клієнта. Повертатися в заклад не потрібно (викуп за власні кошти).")
                            .font(.footnote)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.error)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppColors.error.opacity(0.1))
                            .cornerRadius(12)
                    }
                    
                    AddressRowView(icon: "mappin.and.ellipse", text: order.restaurantAddress, label: "Забрати")
                    
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 2, height: 20)
                        .padding(.leading, 11)
                        .padding(.vertical, -10)
                    
                    AddressRowView(icon: "house.fill", text: order.dropoffAddress, label: "Доставити")
                    
                    if let comment = order.comment, !comment.isEmpty {
                        Text("📝 Коментар: \(comment)")
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(12)
                    }
                    
                    if let trip = order.distTrip {
                        Text("🧭 Маршрут: ~\(trip) км")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.textSecondary)
                    }
                    
                    SwipeToAcceptButton(text: "Свайпніть, щоб прийняти >>>") { onAccept(order.id) }.padding(.top, 8)
                }
                .padding(.horizontal, 20).padding(.bottom, 20).background(Color.white)
            }
        }
        .cornerRadius(24).shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}

struct AddressRowView: View {
    let icon: String
    let text: String
    let label: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(AppColors.primary.opacity(0.08)).frame(width: 36, height: 36)
                Image(systemName: icon).font(.system(size: 16)).foregroundColor(AppColors.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).fontWeight(.medium).foregroundColor(AppColors.textSecondary)
                Text(text).font(.callout).fontWeight(.medium).foregroundColor(AppColors.primary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SwipeToAcceptButton: View {
    let text: String
    let onAccept: () -> Void
    @State private var offset: CGFloat = 0
    let buttonHeight: CGFloat = 56
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 16).fill(AppColors.primary.opacity(0.15))
                Text(text).font(.subheadline).fontWeight(.heavy).foregroundColor(AppColors.primary).frame(maxWidth: .infinity).padding(.leading, buttonHeight)
                RoundedRectangle(cornerRadius: 14).fill(AppColors.primary).frame(width: buttonHeight, height: buttonHeight).padding(4)
                    .overlay(Image(systemName: "arrow.right").font(.system(size: 20, weight: .bold)).foregroundColor(.white))
                    .offset(x: offset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let maxDrag = geometry.size.width - buttonHeight - 8
                                if value.translation.width > 0 && value.translation.width < maxDrag { offset = value.translation.width }
                            }
                            .onEnded { value in
                                let maxDrag = geometry.size.width - buttonHeight - 8
                                if offset > maxDrag * 0.7 {
                                    withAnimation(.spring()) { offset = maxDrag }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        onAccept()
                                        withAnimation(.spring()) { offset = 0 }
                                    }
                                } else {
                                    withAnimation(.spring()) { offset = 0 }
                                }
                            }
                    )
            }
        }
        .frame(height: buttonHeight + 8)
    }
}
