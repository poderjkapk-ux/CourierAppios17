import SwiftUI

struct HistoryView: View {
    @AppStorage("cookie") var savedCookie: String = ""
    
    @State private var orders: [HistoryOrder] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    @State private var selectedFilter = "Сьогодні"
    let filters = ["Сьогодні", "Вчора", "Всі"]
    
    var body: some View {
        NavigationView {
            ZStack {
                // Колір фону екрану
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Перемикач фільтрів
                    Picker("Фільтр", selection: $selectedFilter) {
                        ForEach(filters, id: \.self) { filter in
                            Text(filter).tag(filter)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding()
                    
                    if isLoading && orders.isEmpty {
                        Spacer()
                        ProgressView("Завантаження історії...")
                        Spacer()
                    } else if let error = errorMessage {
                        Spacer()
                        VStack(spacing: 15) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                            Text(error)
                                .multilineTextAlignment(.center)
                            Button("Спробувати знову") {
                                Task { await fetchHistory() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(spacing: 16) {
                                // КАРТКА СТАТИСТИКИ (ПІДСУМКИ)
                                SummaryCardView(
                                    count: completedCount,
                                    earned: totalEarned,
                                    commission: totalCommission,
                                    profit: netProfit
                                )
                                .padding(.horizontal)
                                
                                // СПИСОК ЗАМОВЛЕНЬ
                                if filteredOrders.isEmpty {
                                    VStack(spacing: 16) {
                                        Image(systemName: "calendar.badge.exclamationmark")
                                            .font(.system(size: 50))
                                            .foregroundColor(.gray.opacity(0.5))
                                        Text("За цей період замовлень не знайдено")
                                            .foregroundColor(.gray)
                                            .font(.headline)
                                    }
                                    .padding(.top, 40)
                                } else {
                                    LazyVStack(spacing: 16) {
                                        ForEach(filteredOrders, id: \.id) { order in
                                            HistoryOrderCard(order: order)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.bottom, 20)
                        }
                        .refreshable {
                            await fetchHistory()
                        }
                    }
                }
            }
            .navigationTitle("Історія та Доходи")
            .onAppear {
                Task { await fetchHistory() }
            }
        }
    }
    
    // MARK: - Логіка фільтрації та підрахунку
    
    private var filteredOrders: [HistoryOrder] {
        let today = getFormattedDate(Date())
        let yesterday = getFormattedDate(Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        
        switch selectedFilter {
        case "Сьогодні":
            return orders.filter { $0.date.hasPrefix(today) }
        case "Вчора":
            return orders.filter { $0.date.hasPrefix(yesterday) }
        default:
            return orders
        }
    }
    
    // Підрахунок ТІЛЬКИ для доставлених замовлень
    private var deliveredOrders: [HistoryOrder] {
        filteredOrders.filter { $0.status.lowercased() == "delivered" || $0.status.lowercased() == "виконано" }
    }
    
    private var completedCount: Int { deliveredOrders.count }
    
    private var totalEarned: Double { deliveredOrders.reduce(0) { $0 + $1.price } }
    
    private var totalCommission: Double { deliveredOrders.reduce(0) { $0 + ($1.commission ?? 0.0) } }
    
    private var netProfit: Double { totalEarned - totalCommission }
    
    private func getFormattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM" // Формат як в Android
        return formatter.string(from: date)
    }
    
    // MARK: - Мережа
    private func fetchHistory() async {
        if savedCookie.isEmpty {
            self.errorMessage = "Потрібна авторизація"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let fetchedOrders = try await NetworkManager.shared.getHistory(cookie: savedCookie)
            DispatchQueue.main.async {
                self.orders = fetchedOrders.sorted(by: { $0.id > $1.id })
                self.isLoading = false
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Не вдалося завантажити історію."
                self.isLoading = false
            }
        }
    }
}

// MARK: - Компоненти UI

struct SummaryCardView: View {
    let count: Int
    let earned: Double
    let commission: Double
    let profit: Double
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                HStack {
                    Text("Чистий прибуток")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text("\(count) замовлень")
                        .font(.caption)
                        .bold()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(8)
                        .foregroundColor(.white)
                }
                
                HStack {
                    Text("₴ \(String(format: "%.2f", profit))")
                        .font(.system(size: 36, weight: .black))
                        .foregroundColor(.white)
                    Spacer()
                }
                
                Divider().background(Color.white.opacity(0.3))
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Дохід з доставок")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        Text("+ ₴\(String(format: "%.2f", earned))")
                            .font(.headline)
                            .foregroundColor(Color.green)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Комісія сервісу")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        Text("- ₴\(String(format: "%.2f", commission))")
                            .font(.headline)
                            .foregroundColor(Color.red)
                    }
                }
            }
            .padding(20)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color(red: 0.12, green: 0.16, blue: 0.23), Color(red: 0.06, green: 0.09, blue: 0.16)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .cornerRadius(24)
        .shadow(color: Color(red: 0.12, green: 0.16, blue: 0.23).opacity(0.3), radius: 10, x: 0, y: 5)
    }
}

struct HistoryOrderCard: View {
    let order: HistoryOrder
    
    var isDelivered: Bool {
        order.status.lowercased() == "delivered" || order.status.lowercased() == "виконано"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Замовлення #\(order.id)")
                    .font(.headline)
                    .fontWeight(.heavy)
                Spacer()
                Text(order.date)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            HStack(alignment: .top) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundColor(Color(red: 0.12, green: 0.16, blue: 0.23))
                    .padding(.top, 2)
                Text(order.address)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            HStack(alignment: .bottom) {
                // Статус
                Text(isDelivered ? "Виконано" : "Скасовано")
                    .font(.caption)
                    .bold()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isDelivered ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .foregroundColor(isDelivered ? .green : .red)
                    .cornerRadius(8)
                
                Spacer()
                
                // Фінанси
                VStack(alignment: .trailing, spacing: 6) {
                    Text("+\(String(format: "%.2f", order.price)) ₴")
                        .font(.title3)
                        .fontWeight(.black)
                        .foregroundColor(isDelivered ? .green : .gray)
                    
                    if isDelivered, let comm = order.commission, comm > 0 {
                        Text("Комісія: -\(String(format: "%.2f", comm)) ₴")
                            .font(.caption)
                            .bold()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.red.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
            }
        }
        .padding(20)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}
