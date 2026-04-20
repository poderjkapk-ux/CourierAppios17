import SwiftUI
import MapKit

// ДОБАВЛЕНО: Глобальная функция для безопасного парсинга любых форматов дат от сервера
func parseDateSafe(_ dateStr: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    if let d = formatter.date(from: dateStr) { return d }
    
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = formatter.date(from: dateStr) { return d }
    
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd HH:mm:ss" // Для стандартных ответов БД
    return df.date(from: dateStr)
}

struct ActiveOrderView: View {
    @AppStorage("cookie") var savedCookie: String = ""
    @StateObject private var networkManager = NetworkManager.shared
    
    // Стан даних
    @State private var activeJobs: [ActiveJobSummary] = []
    @State private var currentJob: ActiveJobDetail? = nil
    @State private var isLoading = false
    
    // UI стан
    @State private var selectedJobId: Int? = nil
    @State private var selectedTab = 0 // 0 - Деталі, 1 - Чат
    
    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            
            if isLoading && currentJob == nil {
                ProgressView("Завантаження...")
            } else if let job = currentJob {
                VStack(spacing: 0) {
                    // MARK: - Верхня панель (Header)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Замовлення #\(job.id)")
                                    .font(.title2)
                                    .fontWeight(.heavy)
                                    .foregroundColor(AppColors.primary)
                                
                                Text(getStatusText(status: job.serverStatus, isReady: job.isReady))
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(getStatusColor(status: job.serverStatus, isReady: job.isReady))
                            }
                            Spacer()
                            
                            Button(action: { Task { await fetchActiveJobs() } }) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(AppColors.primary)
                                    .padding(10)
                                    .background(AppColors.primary.opacity(0.1))
                                    .clipShape(Circle())
                            }
                        }
                        
                        // Якщо є декілька активних замовлень (Мульти-замовлення)
                        if activeJobs.count > 1 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(activeJobs) { summary in
                                        Button(action: {
                                            selectedJobId = summary.id
                                            Task { await fetchJobDetail(id: summary.id) }
                                        }) {
                                            Text("📦 #\(summary.id) \(summary.partnerName)")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(selectedJobId == summary.id ? AppColors.primary : Color.white)
                                                .foregroundColor(selectedJobId == summary.id ? .white : AppColors.primary)
                                                .cornerRadius(16)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 16)
                                                        .stroke(selectedJobId == summary.id ? AppColors.primary : Color.gray.opacity(0.3), lineWidth: 1)
                                                )
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        
                        // Перемикач вкладок
                        Picker("Вкладки", selection: $selectedTab) {
                            Text("Деталі").tag(0)
                            Text("Чат").tag(1)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.top, 8)
                    }
                    .padding()
                    .background(Color.white)
                    .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 5)
                    
                    // MARK: - Вміст (Деталі або Чат)
                    if selectedTab == 0 {
                        OrderDetailsTab(job: job, onStatusUpdate: { newStatus in
                            updateStatus(jobId: job.id, status: newStatus)
                        })
                    } else {
                        ChatTab(jobId: job.id, cookie: savedCookie)
                    }
                }
            } else {
                // Немає активних замовлень
                VStack(spacing: 20) {
                    Image(systemName: "bag.fill")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundColor(Color.gray.opacity(0.3))
                    Text("Немає активних замовлень")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.gray)
                }
            }
        }
        .onAppear {
            // ДОБАВЛЕНО: Подключение WebSocket для моментального обновления чата и статусов
            if !savedCookie.isEmpty {
                networkManager.connectWebSocket(cookie: savedCookie)
            }
            Task { await fetchActiveJobs() }
        }
        .onReceive(networkManager.wsEventPublisher) { event in
            // Оновлюємо екран, якщо прийшла подія по вебсокету
            if case .jobUpdate = event { Task { await fetchActiveJobs() } }
            if case .jobReady = event { Task { await fetchActiveJobs() } }
        }
    }
    
    // MARK: - Мережеві запити
    private func fetchActiveJobs() async {
        isLoading = true
        do {
            let response = try await networkManager.getActiveJobs(cookie: savedCookie)
            activeJobs = response.jobs
            
            if let firstJob = response.jobs.first {
                if selectedJobId == nil || !response.jobs.contains(where: { $0.id == selectedJobId }) {
                    selectedJobId = firstJob.id
                }
                await fetchJobDetail(id: selectedJobId!)
            } else {
                currentJob = nil
                selectedJobId = nil
            }
        } catch {
            print("Помилка завантаження активних замовлень: \(error)")
        }
        isLoading = false
    }
    
    private func fetchJobDetail(id: Int) async {
        do {
            let response = try await networkManager.getActiveJob(cookie: savedCookie, jobId: id)
            currentJob = response.job
        } catch {
            print("Помилка завантаження деталей замовлення: \(error)")
        }
    }
    
    private func updateStatus(jobId: Int, status: String) {
        Task {
            do {
                if status == "arrived_pickup" {
                    _ = try await networkManager.arrivedAtPickup(cookie: savedCookie, jobId: jobId)
                } else {
                    _ = try await networkManager.updateJobStatus(cookie: savedCookie, jobId: jobId, status: status)
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                await fetchJobDetail(id: jobId)
            } catch {
                print("Помилка оновлення статусу: \(error)")
            }
        }
    }
    
    // MARK: - Хелпери
    private func getStatusText(status: String, isReady: Bool) -> String {
        if isReady { return "Замовлення готове! Можна забирати." }
        switch status {
        case "assigned": return "Прямуйте до закладу"
        case "arrived_pickup": return "Очікуйте видачі"
        case "ready": return "Замовлення готове! Можна забирати."
        case "picked_up": return "Прямуйте до клієнта"
        case "returning": return "Повернення коштів у заклад"
        default: return status
        }
    }
    
    private func getStatusColor(status: String, isReady: Bool) -> Color {
        if isReady { return AppColors.secondary }
        switch status {
        case "assigned", "picked_up": return AppColors.primary
        case "ready": return AppColors.secondary
        case "returning": return AppColors.warning
        default: return AppColors.textSecondary
        }
    }
}

// MARK: - Вкладка Деталей
struct OrderDetailsTab: View {
    let job: ActiveJobDetail
    let onStatusUpdate: (String) -> Void
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // Повідомлення про готовність АБО Великий Таймер Готовності
                    if job.isReady || job.serverStatus == "ready" {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                            VStack(alignment: .leading) {
                                Text("ЗАМОВЛЕННЯ ГОТОВЕ!")
                                    .font(.headline)
                                    .fontWeight(.black)
                                    .foregroundColor(.white)
                                Text("Можете забирати пакунок у закладі.")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            Spacer()
                        }
                        .padding()
                        .background(
                            LinearGradient(gradient: Gradient(colors: [AppColors.secondary, Color(red: 5/255, green: 150/255, blue: 105/255)]), startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(20)
                    } else if ["assigned", "arrived_pickup"].contains(job.serverStatus), let readyAt = job.readyAt {
                        LargeReadinessTimerView(readyAtIso: readyAt)
                    }
                    
                    // Фінанси (Дохід та Сума)
                    FinancesCard(job: job)
                    
                    // Крок 1: Заклад
                    StepCard(
                        title: "КРОК 1: ЗАКЛАД",
                        isActive: ["assigned", "arrived_pickup", "ready"].contains(job.serverStatus),
                        name: job.partnerName,
                        address: job.partnerAddress,
                        phone: job.partnerPhone,
                        icon: "mappin.and.ellipse",
                        startTimeIso: job.assignedAt,
                        endTimeIso: job.pickedUpAt
                    )
                    
                    // Крок 2: Клієнт
                    StepCard(
                        title: "КРОК 2: КЛІЄНТ",
                        isActive: job.serverStatus == "picked_up",
                        name: job.customerName ?? "Ім'я не вказано",
                        address: job.customerAddress,
                        phone: job.customerPhone,
                        icon: "house.fill",
                        lat: job.customerLat,
                        lon: job.customerLon,
                        startTimeIso: job.pickedUpAt,
                        endTimeIso: job.deliveredAt
                    )
                    
                    // Крок 3: Повернення (Якщо потрібно)
                    if job.isReturnRequired && ["delivered", "returning", "completed"].contains(job.serverStatus) {
                        StepCard(
                            title: "КРОК 3: ПОВЕРНЕННЯ КОШТІВ",
                            isActive: job.serverStatus == "returning",
                            name: "Поверніть гроші в заклад",
                            address: job.partnerAddress,
                            phone: nil,
                            icon: "arrow.turn.up.left",
                            isWarning: true,
                            startTimeIso: job.deliveredAt,
                            endTimeIso: job.completedAt
                        )
                    }
                    
                    // Відступ для кнопки знизу
                    Spacer().frame(height: 100)
                }
                .padding()
            }
            
            // Фіксована кнопка дії (Слайдер) знизу
            VStack {
                Spacer()
                VStack {
                    if job.serverStatus == "assigned" {
                        ActionSwipeButton(text: "Свайп: Я в закладі >>>", color: AppColors.primary) {
                            onStatusUpdate("arrived_pickup")
                        }
                    } else if job.serverStatus == "arrived_pickup" || job.serverStatus == "ready" {
                        ActionSwipeButton(text: "Свайп: Забрав пакунок >>>", color: AppColors.secondary) {
                            onStatusUpdate("picked_up")
                        }
                    } else if job.serverStatus == "picked_up" {
                        ActionSwipeButton(text: job.isReturnRequired ? "Свайп: Везу гроші назад >>>" : "Свайп: Успішно доставлено >>>", color: AppColors.secondary) {
                            onStatusUpdate("delivered")
                        }
                    } else if job.serverStatus == "returning" {
                        Text("Чекайте підтвердження від закладу. Заклад має натиснути кнопку у себе в кабінеті.")
                            .font(.footnote)
                            .foregroundColor(AppColors.warning)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                }
                .padding()
                .background(Color.white.shadow(color: .black.opacity(0.1), radius: 10, y: -5))
            }
        }
    }
}

// MARK: - Вспомогательные Таймеры

struct LargeReadinessTimerView: View {
    let readyAtIso: String
    
    @State private var timeText = "00:00"
    @State private var isLate = false
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack {
            Image(systemName: isLate ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.white)
                .padding(12)
                .background(Color.white.opacity(0.2))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(isLate ? "ЗАКЛАД ЗАТРИМУЄ ВИДАЧУ" : "ОЧІКУВАНИЙ ЧАС ВИДАЧІ")
                    .font(.caption)
                    .fontWeight(.black)
                    .foregroundColor(.white)
                    .tracking(0.5)
                
                Text(isLate ? "Замовлення вже мало бути готовим" : "Ресторан ще готує страви")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.9))
            }
            Spacer()
            
            Text(timeText)
                .font(.system(size: 28, weight: .black))
                .foregroundColor(.white)
        }
        .padding(20)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [isLate ? AppColors.error : AppColors.primary, (isLate ? AppColors.error : AppColors.primary).opacity(0.8)]),
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(20)
        .shadow(color: (isLate ? AppColors.error : AppColors.primary).opacity(0.4), radius: 12, x: 0, y: 5)
        .onReceive(timer) { _ in updateTimer() }
        .onAppear { updateTimer() }
    }
    
    // ИСПРАВЛЕНО: Используем parseDateSafe
    private func updateTimer() {
        guard let readyDate = parseDateSafe(readyAtIso) else { return }
        let diff = Int(readyDate.timeIntervalSinceNow)
        isLate = diff < 0
        let absDiff = abs(diff)
        timeText = String(format: "%@%02d:%02d", isLate ? "-" : "", absDiff / 60, absDiff % 60)
    }
}

struct StepTimerView: View {
    let startTimeIso: String?
    let endTimeIso: String?
    let isActive: Bool
    
    @State private var timeText = "00:00"
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        let isDone = endTimeIso != nil
        let bgColor = isDone ? AppColors.secondary.opacity(0.15) : (isActive ? AppColors.primary.opacity(0.15) : Color.gray.opacity(0.2))
        let textColor = isDone ? AppColors.secondary : (isActive ? AppColors.primary : AppColors.textSecondary)
        
        Text("⏳ \(timeText)")
            .font(.system(size: 12, weight: .black))
            .foregroundColor(textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(bgColor)
            .cornerRadius(8)
            .onReceive(timer) { _ in updateTimer() }
            .onAppear { updateTimer() }
    }
    
    // ИСПРАВЛЕНО: Используем parseDateSafe
    private func updateTimer() {
        guard let startIso = startTimeIso, let startDate = parseDateSafe(startIso) else { return }
        
        let endDate: Date
        if let endIso = endTimeIso, let parsedEnd = parseDateSafe(endIso) {
            endDate = parsedEnd // Зафиксированное время (шаг пройден)
        } else if isActive {
            endDate = Date() // Тикающее время (шаг активен)
        } else {
            return
        }
        
        let diff = Int(endDate.timeIntervalSince(startDate))
        if diff >= 0 {
            let m = diff / 60
            let s = diff % 60
            let h = m / 60
            if h > 0 {
                timeText = String(format: "%02d:%02d:%02d", h, m % 60, s)
            } else {
                timeText = String(format: "%02d:%02d", m, s)
            }
        }
    }
}

// MARK: - Картка Фінансів
struct FinancesCard: View {
    let job: ActiveJobDetail
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("ВАШ ДОХІД")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(AppColors.textSecondary)
                    Text("\(Int(job.deliveryFee)) ₴")
                        .font(.title)
                        .fontWeight(.black)
                        .foregroundColor(AppColors.secondary)
                }
                Spacer()
                Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1, height: 40)
                Spacer()
                VStack(alignment: .trailing) {
                    Text("СУМА ЗАМОВЛЕННЯ")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(AppColors.textSecondary)
                    Text("\(Int(job.orderPrice)) ₴")
                        .font(.title2)
                        .fontWeight(.heavy)
                        .foregroundColor(AppColors.primary)
                }
            }
            .padding(24)
            
            let paymentText = getPaymentText()
            Text(paymentText.0)
                .font(.subheadline)
                .fontWeight(.heavy)
                .foregroundColor(paymentText.1)
                .frame(maxWidth: .infinity)
                .padding()
                .background(paymentText.1.opacity(0.12))
            
            if let comment = job.comment, !comment.isEmpty {
                Text("📝 Коментар: \(comment)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(Color.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.orange.opacity(0.1))
            }
        }
        .background(Color.white)
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 5)
    }
    
    private func getPaymentText() -> (String, Color) {
        switch job.paymentType {
        case "prepaid": return ("✨ ОПЛАЧЕНО (Гроші не беремо)", AppColors.secondary)
        case "buyout_paid": return ("✨ ОПЛАЧЕНО В ЗАКЛАДі (Свої гроші: \(Int(job.orderPrice)) ₴)", AppColors.secondary)
        case "cash": return ("💸 ГОТІВКА (Взяти \(Int(job.orderPrice)) ₴)", AppColors.warning)
        case "buyout": return ("💳 ЗАБЕРІТЬ У КЛІЄНТА: \(Int(job.orderPrice)) ₴ (Свої гроші)", AppColors.error)
        default: return ("Оплата: \(job.paymentType)", AppColors.primary)
        }
    }
}

// MARK: - Картка Кроку (Заклад/Клієнт)
struct StepCard: View {
    let title: String
    let isActive: Bool
    let name: String
    let address: String
    let phone: String?
    let icon: String
    var isWarning: Bool = false
    var lat: Double? = nil
    var lon: Double? = nil
    
    var startTimeIso: String? = nil
    var endTimeIso: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.black)
                    .foregroundColor(isActive ? (isWarning ? AppColors.warning : AppColors.primary) : AppColors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((isActive ? (isWarning ? AppColors.warning : AppColors.primary) : Color.gray).opacity(0.1))
                    .cornerRadius(6)
                
                Spacer()
                
                if startTimeIso != nil {
                    StepTimerView(startTimeIso: startTimeIso, endTimeIso: endTimeIso, isActive: isActive)
                }
            }
            
            Text(name)
                .font(.title3)
                .fontWeight(.heavy)
                .foregroundColor(AppColors.primary)
            
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(AppColors.primary)
                    .frame(width: 30, height: 30)
                    .background(AppColors.primary.opacity(0.08))
                    .clipShape(Circle())
                
                Text(address)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.primary)
            }
            
            HStack(spacing: 12) {
                Button(action: openMaps) {
                    HStack {
                        Image(systemName: "location.fill")
                        Text("Маршрут")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .foregroundColor(isWarning ? AppColors.warning : AppColors.primary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isWarning ? AppColors.warning : AppColors.primary, lineWidth: 2)
                    )
                }
                
                if let phoneString = phone, !phoneString.isEmpty {
                    Button(action: { callPhone(phoneString) }) {
                        Image(systemName: "phone.fill")
                            .font(.title2)
                            .foregroundColor(AppColors.primary)
                            .frame(width: 50, height: 50)
                            .background(AppColors.primary.opacity(0.1))
                            .cornerRadius(16)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(24)
        .opacity(isActive ? 1.0 : 0.5)
        .shadow(color: (isActive ? (isWarning ? AppColors.warning : AppColors.primary) : Color.black).opacity(isActive ? 0.2 : 0.05), radius: isActive ? 12 : 2, y: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(isActive ? (isWarning ? AppColors.warning : AppColors.primary) : Color.gray.opacity(0.3), lineWidth: isActive ? 2 : 1)
        )
    }
    
    private func openMaps() {
        if let lat = lat, let lon = lon, lat != 0, lon != 0 {
            let coordinate = CLLocationCoordinate2DMake(lat, lon)
            let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate, addressDictionary:nil))
            mapItem.name = name
            mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey : MKLaunchOptionsDirectionsModeDriving])
        } else {
            let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "maps://?q=\(encodedAddress)") {
                UIApplication.shared.open(url)
            }
        }
    }
    
    private func callPhone(_ phone: String) {
        let cleaned = phone.replacingOccurrences(of: "+", with: "")
        let formatted = cleaned.hasPrefix("380") ? String(cleaned.dropFirst(2)) : cleaned
        if let url = URL(string: "tel://\(formatted)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Слайдер дії (для статусів)
struct ActionSwipeButton: View {
    let text: String
    let color: Color
    let onAccept: () -> Void
    
    @State private var offset: CGFloat = 0
    let buttonHeight: CGFloat = 56
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 16).fill(color.opacity(0.15))
                
                Text(text).font(.subheadline).fontWeight(.heavy).foregroundColor(color).frame(maxWidth: .infinity).padding(.leading, buttonHeight)
                
                RoundedRectangle(cornerRadius: 14).fill(color).frame(width: buttonHeight, height: buttonHeight).padding(4)
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
                                        offset = 0
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

// MARK: - Вкладка Чату (ОБНОВЛЕНО С WEBSOCKET)
struct ChatTab: View {
    let jobId: Int
    let cookie: String
    @StateObject private var networkManager = NetworkManager.shared
    
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isSending = false
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { index, msg in
                            let isMe = msg.role == "courier"
                            HStack {
                                if isMe { Spacer() }
                                
                                VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                                    Text(msg.text)
                                        .font(.body)
                                        .foregroundColor(isMe ? .white : AppColors.primary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(isMe ? AppColors.primary : Color.white)
                                        .cornerRadius(20)
                                    
                                    Text(msg.time)
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: 280, alignment: isMe ? .trailing : .leading)
                                
                                if !isMe { Spacer() }
                            }
                            .id(index)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    if !messages.isEmpty {
                        withAnimation { proxy.scrollTo(messages.count - 1, anchor: .bottom) }
                    }
                }
            }
            
            // Поле вводу
            HStack(spacing: 12) {
                TextField("Повідомлення...", text: $inputText)
                    .padding(12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(24)
                
                Button(action: sendMessage) {
                    if isSending {
                        ProgressView().frame(width: 44, height: 44).background(AppColors.primary).clipShape(Circle())
                    } else {
                        Image(systemName: "paperplane.fill").foregroundColor(.white).frame(width: 44, height: 44)
                            .background(inputText.isEmpty ? Color.gray : AppColors.primary).clipShape(Circle())
                    }
                }
                .disabled(inputText.isEmpty || isSending)
            }
            .padding()
            .background(Color.white.shadow(color: .black.opacity(0.1), radius: 5, y: -2))
        }
        .onAppear { Task { await loadHistory() } }
        .onReceive(networkManager.wsEventPublisher) { event in
            if case let .chatMessage(incomingJobId, newMessage) = event {
                if incomingJobId == jobId {
                    withAnimation(.easeOut(duration: 0.3)) { messages.append(newMessage) }
                }
            }
        }
    }
    
    private func loadHistory() async {
        do { messages = try await networkManager.getChatMessages(cookie: cookie, jobId: jobId) }
        catch { print("Помилка завантаження чату: \(error)") }
    }
    
    private func sendMessage() {
        let textToSend = inputText
        inputText = ""
        isSending = true
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let localMsg = ChatMessage(role: "courier", text: textToSend, time: formatter.string(from: Date()))
        withAnimation { messages.append(localMsg) }
        
        Task {
            do {
                _ = try await networkManager.sendChatMessage(cookie: cookie, jobId: jobId, message: textToSend)
            } catch { print("Помилка відправки: \(error)") }
            isSending = false
        }
    }
}
