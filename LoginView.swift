import SwiftUI
import FirebaseMessaging

struct LoginView: View {
    @State private var phone = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    // Аналог SharedPreferences: сохраняем куки для автоматического входа
    @AppStorage("cookie") var savedCookie: String = ""
    
    var body: some View {
        VStack(spacing: 25) {
            Spacer()
            
            // Блок логотипа (аналог restify_logo из Android)
            VStack(spacing: 12) {
                Image(systemName: "box.truck.fill") // Можно заменить на ваш ассет restify_logo
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.blue)
                
                Text("Restify")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Доставка для кур'єрів")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 30)
            
            // Поля ввода (аналог OutlinedTextField из Compose)
            VStack(spacing: 15) {
                HStack {
                    Image(systemName: "phone")
                        .foregroundColor(.gray)
                    TextField("Номер телефону", text: $phone)
                        .keyboardType(.phonePad)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                HStack {
                    Image(systemName: "lock")
                        .foregroundColor(.gray)
                    SecureField("Пароль", text: $password)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .padding(.horizontal)
            
            // Вывод ошибок
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // Кнопка входа
            Button(action: {
                // Прячем клавиатуру перед запросом
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                Task {
                    await performLogin()
                }
            }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            // Фикс ошибки NaN: жестко задаем размер колесика
                            .frame(width: 24, height: 24)
                    } else {
                        Text("Увійти")
                            .fontWeight(.bold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(phone.isEmpty || password.isEmpty ? Color.blue.opacity(0.5) : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isLoading || phone.isEmpty || password.isEmpty)
            .padding(.horizontal)
            
            Button("Забули пароль?") {
                // В будущем здесь вызовем resetCourierPassword из NetworkManager
            }
            .font(.footnote)
            .foregroundColor(.blue)
            
            Spacer()
            
            Text("v1.0.0")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    @MainActor
    private func performLogin() async {
        isLoading = true
        errorMessage = nil
        
        // 1. Полная очистка, включая удаление плюса (как было изначально)
        let cleanPhone = phone
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            
        var finalPhone = cleanPhone
        if finalPhone.hasPrefix("0") && finalPhone.count == 10 {
            finalPhone = "38" + finalPhone
        }
        
        do {
            // 2. Отправляем правильный номер
            if let cookie = try await NetworkManager.shared.login(phone: finalPhone, password: password) {
                let cleanCookie = cookie.trimmingCharacters(in: .whitespaces)
                self.savedCookie = cleanCookie
                
                // --- ОБНОВЛЕНИЕ ТОКЕНА ДЛЯ ПУШЕЙ ---
                // Принудительно обновляем FCM токен на бэкенде после логина
                Messaging.messaging().token { token, error in
                    if let fcmToken = token {
                        Task {
                            _ = try? await NetworkManager.shared.sendFcmToken(cookie: cleanCookie, token: fcmToken)
                        }
                    }
                }
                // -----------------------------------
                
                self.isLoading = false
            } else {
                errorMessage = "Невірний логін або пароль."
                isLoading = false
            }
        } catch {
            errorMessage = "Помилка сервера: \(error.localizedDescription)"
            isLoading = false
        }
    }
}
