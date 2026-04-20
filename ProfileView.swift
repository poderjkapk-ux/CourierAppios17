import SwiftUI

struct ProfileView: View {
    @AppStorage("cookie") var savedCookie: String = ""
    @StateObject private var networkManager = NetworkManager.shared
    
    @State private var profile: CourierProfile? = nil
    @State private var motivators: [Motivator] = []
    @State private var isLoading = true
    
    // Состояния для формы обратной связи
    @State private var showFeedbackDialog = false
    @State private var feedbackText = ""
    @State private var isFeedbackSending = false
    @State private var showToast = false
    @State private var toastMessage = ""
    
    var body: some View {
        ZStack {
            // Цвета AppColors определены в OrdersView.swift
            AppColors.background.ignoresSafeArea()
            
            if isLoading {
                ProgressView("Завантаження профілю...")
            } else if let profile = profile {
                ScrollView {
                    VStack(spacing: 24) {
                        // Аватарка и базовые данные
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(gradient: Gradient(colors: [AppColors.primary, AppColors.secondary]), startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 100, height: 100)
                                    .shadow(radius: 8)
                                
                                Image(systemName: "person.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.white)
                            }
                            
                            Text(profile.name)
                                .font(.title)
                                .fontWeight(.heavy)
                                .foregroundColor(AppColors.primary)
                            
                            Text(profile.phone)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .padding(.top, 20)
                        
                        // Статистика (Комиссия, Рейтинг, Баланс)
                        HStack {
                            ProfileStatItem(label: "Комісія", value: "\(String(format: "%.1f", profile.commissionRate ?? 0))%", color: AppColors.primary)
                            
                            Divider().frame(height: 40)
                            
                            ProfileStatItem(label: "Рейтинг", value: "\(String(format: "%.1f", profile.rating ?? 5.0))", color: AppColors.warning)
                            
                            Divider().frame(height: 40)
                            
                            ProfileStatItem(label: "Баланс", value: "\(Int(profile.balance ?? 0)) ₴", color: AppColors.secondary)
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(24)
                        .shadow(color: Color.black.opacity(0.05), radius: 8, y: 5)
                        
                        // Мотиваторы (Цели и бонусы)
                        if !motivators.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "trophy.fill")
                                        .foregroundColor(.yellow)
                                    Text("Ваші цілі та бонуси")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(AppColors.primary)
                                }
                                
                                ForEach(motivators) { motivator in
                                    MotivatorCardView(motivator: motivator)
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                        
                        // Статистика отзывов
                        HStack(spacing: 12) {
                            Image(systemName: "star.bubble.fill")
                                .foregroundColor(AppColors.primary)
                                .font(.title3)
                            VStack(alignment: .leading) {
                                Text("Отримано відгуків")
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary)
                                Text("\(profile.ratingCount ?? 0)")
                                    .font(.headline)
                                    .foregroundColor(AppColors.primary)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.05), radius: 5, y: 3)
                        
                        // Кнопка поддержки
                        Button(action: { showFeedbackDialog = true }) {
                            HStack {
                                Image(systemName: "paperplane.fill")
                                Text("Написати в підтримку")
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(red: 99/255, green: 102/255, blue: 241/255)) // Indigo
                            .foregroundColor(.white)
                            .cornerRadius(16)
                        }
                        
                        // Кнопка выхода
                        Button(action: logout) {
                            Text("Вийти з акаунта")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.white)
                                .foregroundColor(AppColors.error)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(AppColors.error, lineWidth: 2)
                                )
                        }
                        .padding(.bottom, 30)
                    }
                    .padding()
                }
            } else {
                VStack {
                    Text("Помилка завантаження")
                        .foregroundColor(AppColors.error)
                    Button("Спробувати ще раз") {
                        Task { await loadData() }
                    }
                    .padding(.top, 10)
                }
            }
            
            // Простой Toast для уведомлений
            if showToast {
                VStack {
                    Spacer()
                    Text(toastMessage)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(20)
                        .padding(.bottom, 20)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut, value: showToast)
            }
        }
        .onAppear {
            Task { await loadData() }
        }
        // Модальное окно обратной связи
        .alert("Служба підтримки", isPresented: $showFeedbackDialog) {
            TextField("Опишіть вашу проблему...", text: $feedbackText)
            Button("Скасувати", role: .cancel) { feedbackText = "" }
            Button("Відправити") { sendFeedback() }
        } message: {
            Text("Ми обов'язково вам допоможемо.")
        }
    }
    
    // MARK: - Методы
    
    // <-- ИСПРАВЛЕНО: Теперь параллельно грузим и профиль, и мотиваторы
    // MARK: - Методы
        
        private func loadData() async {
            isLoading = true
            do {
                async let fetchProfile = networkManager.getProfile(cookie: savedCookie)
                async let fetchMotivators = networkManager.getMotivators(cookie: savedCookie)
                
                let (profileResult, motivatorsResult) = try await (fetchProfile, fetchMotivators)
                self.profile = profileResult
                
                // ФІЛЬТРАЦІЯ МОТИВАТОРІВ
                self.motivators = motivatorsResult.filter { motivator in
                    // 1. Відразу ховаємо прострочені або скасовані системою
                    if motivator.status == "expired" || motivator.status == "cancelled" {
                        return false
                    }
                    
                    // 2. Якщо ціль виконана (комісія вже знижена)
                    if motivator.status == "completed" {
                        // Перевіряємо дату закінчення періоду зниженої комісії
                        guard let endDateStr = motivator.rewardEndDate,
                              let endDate = parseDate(endDateStr) else {
                            // Якщо дата не вказана, але ціль закрита — ховаємо
                            return false
                        }
                        
                        // Залишаємо картку ТІЛЬКИ якщо поточний час менший за дату закінчення знижки
                        return Date() < endDate
                    }
                    
                    // 3. Всі інші (активні цілі, які кур'єр ще виконує) — показуємо
                    return true
                }
                
            } catch {
                print("Помилка завантаження профілю або мотиваторів: \(error)")
            }
            isLoading = false
        }
        
        // Допоміжна функція для надійного парсингу ISO8601 дат з бекенду
        private func parseDate(_ isoString: String) -> Date? {
            let formatter = ISO8601DateFormatter()
            // Спочатку пробуємо розпарсити з мілісекундами
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = formatter.date(from: isoString) { return d }
            
            // Якщо бекенд віддає без мілісекунд
            let fallbackFormatter = ISO8601DateFormatter()
            return fallbackFormatter.date(from: isoString)
        }
    
    // <-- ИСПРАВЛЕНО: Реальная отправка на сервер
    private func sendFeedback() {
        guard !feedbackText.isEmpty, let currentProfile = profile else { return }
        isFeedbackSending = true
        
        Task {
            do {
                let response = try await networkManager.sendFeedback(
                    role: "courier",
                    name: currentProfile.name,
                    phone: currentProfile.phone,
                    message: feedbackText
                )
                
                if response.status == "ok" {
                    feedbackText = ""
                    toastMessage = "✅ Дякуємо! Звернення відправлено."
                    showToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { showToast = false }
                }
            } catch {
                print("Помилка відправки підтримки: \(error)")
                toastMessage = "❌ Помилка з'єднання."
                showToast = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { showToast = false }
            }
            isFeedbackSending = false
        }
    }
    
    private func logout() {
        savedCookie = ""
        networkManager.disconnectWebSocket()
    }
}

// MARK: - Компоненты UI
struct ProfileStatItem: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.black)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// Карточка мотиватора
struct MotivatorCardView: View {
    let motivator: Motivator
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundColor(.yellow)
                Text(motivator.title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            if let desc = motivator.description {
                Text(desc)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
            
            // Прогресс бар
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 10)
                    
                    RoundedRectangle(cornerRadius: 5)
                        .fill(AppColors.secondary)
                        // Защита от деления на ноль или некорректных значений прогресса
                        .frame(width: max(0, geometry.size.width * CGFloat(motivator.progressPercent) / 100), height: 10)
                }
            }
            .frame(height: 10)
            .padding(.vertical, 4)
            
            HStack {
                Text("Прогрес: \(motivator.currentOrders) / \(motivator.targetOrders)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                if let deadline = motivator.deadlineDate {
                    Text("До: \(formatDate(deadline))")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding()
        .background(
            LinearGradient(gradient: Gradient(colors: [AppColors.primary, Color.black]), startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .cornerRadius(16)
        .shadow(radius: 4)
    }
    
    private func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: isoString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "dd.MM.yyyy"
            return displayFormatter.string(from: date)
        }
        return isoString
    }
}
