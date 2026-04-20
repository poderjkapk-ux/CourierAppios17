import SwiftUI

struct MainTabView: View {
    // Стан для вибору активної вкладки
    @State private var selectedTab = 0
    
    // Підключаємо NetworkManager для відстеження подій
    @ObservedObject private var networkManager = NetworkManager.shared
    
    var body: some View {
        TabView(selection: $selectedTab) {
            
            // Вкладка 1: Список доступних замовлень
            NavigationView {
                OrdersView()
            }
            .tabItem {
                Label("Замовлення", systemImage: "list.bullet")
            }
            .tag(0)
            
            // Вкладка 2: Активні замовлення в роботі
            NavigationView {
                ActiveOrderView()
            }
            .tabItem {
                Label("Активні", systemImage: "bag.fill")
            }
            .tag(1)
            
            // Вкладка 3: Історія замовлень (ДОДАНО)
            NavigationView {
                HistoryView()
            }
            .tabItem {
                Label("Історія", systemImage: "clock.fill")
            }
            .tag(2)
            
            // Вкладка 4: Профіль кур'єра та статистика
            NavigationView {
                ProfileView()
            }
            .tabItem {
                Label("Профіль", systemImage: "person.fill")
            }
            .tag(3)
        }
        // Встановлюємо акцентний колір для активної вкладки
        .accentColor(.blue)
        .onReceive(networkManager.wsEventPublisher) { event in
            handleGlobalEvents(event)
        }
    }
    
    /// Обробка глобальних повідомлень, що впливають на навігацію
    private func handleGlobalEvents(_ event: WSEvent) {
        switch event {
        case .newOrder:
            // Якщо прийшло нове замовлення
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            
        case .directOffer:
            // Для персональних оферів перемикаємо на вкладку замовлень
            selectedTab = 0
            
        default:
            break
        }
    }
}
