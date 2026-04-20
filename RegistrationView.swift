import SwiftUI
import PhotosUI

// MARK: - Модели для верификации (если их еще нет в NetworkManager)
extension NetworkManager {
    struct VerificationInitResponse: Codable {
        let token: String
        let link: String
    }
    
    struct VerificationCheckResponse: Codable {
        let status: String
        let phone: String?
    }
    
    func initVerification() async throws -> VerificationInitResponse {
        guard let url = URL(string: "https://restify.site/api/auth/init_verification") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(EmptyRequest())
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(VerificationInitResponse.self, from: data)
    }
    
    func checkVerification(token: String) async throws -> VerificationCheckResponse {
        guard let url = URL(string: "https://restify.site/api/auth/check_verification/\(token)") else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(VerificationCheckResponse.self, from: data)
    }
}

// MARK: - Registration View
struct RegistrationView: View {
    @Environment(\.presentationMode) var presentationMode
    
    // Данные формы
    @State private var name = ""
    @State private var password = ""
    
    // Фотографии
    @State private var documentPhotoItem: PhotosPickerItem?
    @State private var selfiePhotoItem: PhotosPickerItem?
    @State private var documentImage: UIImage?
    @State private var selfieImage: UIImage?
    
    // Верификация номера (Telegram)
    @State private var verificationToken: String?
    @State private var verificationLink: String?
    @State private var isPhoneVerified = false
    
    // Состояния UI и процессов
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccessAlert = false
    
    // Ссылка на задачу поллинга, чтобы её можно было убить при выходе!
    @State private var pollingTask: Task<Void, Never>?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                // 1. Верификация номера телефона
                VStack(alignment: .leading, spacing: 10) {
                    Text("1. Підтвердження номеру")
                        .font(.headline)
                    
                    if isPhoneVerified {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Номер успішно підтверджено")
                                .foregroundColor(.green)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(10)
                    } else {
                        Button(action: {
                            Task { await startVerificationProcess() }
                        }) {
                            HStack {
                                if isLoading && verificationLink == nil {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                    Text("Підтвердити через Telegram")
                                        .fontWeight(.bold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(isLoading)
                        
                        if let link = verificationLink {
                            VStack(spacing: 8) {
                                Text("Очікуємо підтвердження в боті...")
                                    .font(.footnote)
                                    .foregroundColor(.gray)
                                
                                Button("Відкрити Telegram ще раз") {
                                    openTelegramApp(link: link)
                                }
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(.horizontal)
                
                Divider()
                
                // 2. Особисті дані (доступні тільки після верификации)
                VStack(alignment: .leading, spacing: 15) {
                    Text("2. Особисті дані")
                        .font(.headline)
                    
                    TextField("ПІБ", text: $name)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disabled(!isPhoneVerified)
                    
                    SecureField("Пароль", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disabled(!isPhoneVerified)
                }
                .padding(.horizontal)
                .opacity(isPhoneVerified ? 1.0 : 0.5)
                
                Divider()
                
                // 3. Документи
                VStack(alignment: .leading, spacing: 15) {
                    Text("3. Фотографії")
                        .font(.headline)
                    
                    // Фото документа
                    HStack {
                        Text("Фото паспорта/прав:")
                        Spacer()
                        PhotosPicker(selection: $documentPhotoItem, matching: .images) {
                            if let docImg = documentImage {
                                Image(uiImage: docImg)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                Image(systemName: "camera.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                    .frame(width: 60, height: 60)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .onChange(of: documentPhotoItem) { newItem in
                        loadPhoto(from: newItem, isDocument: true)
                    }
                    
                    // Селфи
                    HStack {
                        Text("Ваше селфі:")
                        Spacer()
                        PhotosPicker(selection: $selfiePhotoItem, matching: .images) {
                            if let selfie = selfieImage {
                                Image(uiImage: selfie)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                    .frame(width: 60, height: 60)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .onChange(of: selfiePhotoItem) { newItem in
                        loadPhoto(from: newItem, isDocument: false)
                    }
                }
                .padding(.horizontal)
                .opacity(isPhoneVerified ? 1.0 : 0.5)
                .disabled(!isPhoneVerified)
                
                // Ошибки
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Кнопка регистрации
                Button(action: {
                    Task { await register() }
                }) {
                    HStack {
                        if isLoading && isPhoneVerified {
                            ProgressView().tint(.white)
                        } else {
                            Text("Зареєструватися")
                                .fontWeight(.bold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isFormValid ? Color.green : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(!isFormValid || isLoading)
                .padding()
            }
            .padding(.vertical)
        }
        .navigationTitle("Реєстрація")
        .navigationBarTitleDisplayMode(.inline)
        .alert(isPresented: $showSuccessAlert) {
            Alert(
                title: Text("Успіх!"),
                message: Text("Ваша заявка успішно відправлена. Зачекайте на підтвердження адміністратором."),
                dismissButton: .default(Text("OK")) {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
        .onDisappear {
            pollingTask?.cancel()
        }
    }
    
    // MARK: - Логика
    
    private var isFormValid: Bool {
        isPhoneVerified && !name.isEmpty && password.count >= 6 && documentImage != nil && selfieImage != nil
    }
    
    private func loadPhoto(from item: PhotosPickerItem?, isDocument: Bool) {
        Task {
            if let data = try? await item?.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                DispatchQueue.main.async {
                    if isDocument {
                        self.documentImage = image
                    } else {
                        self.selfieImage = image
                    }
                }
            }
        }
    }
    
    private func startVerificationProcess() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await NetworkManager.shared.initVerification()
            verificationToken = response.token
            verificationLink = response.link
            
            // Вызываем умное открытие Telegram
            openTelegramApp(link: response.link)
            
            // Запускаем безопасный поллинг
            startSafePolling(token: response.token)
            
        } catch {
            errorMessage = "Помилка зв'язку з сервером. Спробуйте ще раз."
        }
        
        isLoading = false
    }
    
    // <-- ДОБАВЛЕНО: Умное конвертирование ссылки для iOS
    private func openTelegramApp(link: String) {
        DispatchQueue.main.async {
            // Пробуем создать нативный Deep Link (tg://resolve?domain=botname&start=token)
            if link.contains("t.me/") {
                var tgLink = link.replacingOccurrences(of: "https://t.me/", with: "tg://resolve?domain=")
                tgLink = tgLink.replacingOccurrences(of: "?start=", with: "&start=")
                
                if let tgUrl = URL(string: tgLink), UIApplication.shared.canOpenURL(tgUrl) {
                    UIApplication.shared.open(tgUrl)
                    return
                }
            }
            
            // Если tg:// не сработал (например, Telegram не установлен), открываем обычную ссылку в браузере
            if let webUrl = URL(string: link) {
                UIApplication.shared.open(webUrl)
            }
        }
    }
    
    private func startSafePolling(token: String) {
        pollingTask?.cancel()
        
        pollingTask = Task {
            var attempts = 0
            let maxAttempts = 100 // 5 минут (100 итераций по 3 секунды)
            
            while !isPhoneVerified && attempts < maxAttempts {
                if Task.isCancelled { break }
                
                do {
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                    
                    let response = try await NetworkManager.shared.checkVerification(token: token)
                    if response.status == "verified" {
                        DispatchQueue.main.async {
                            self.isPhoneVerified = true
                            self.verificationLink = nil
                        }
                        break
                    }
                } catch {
                    print("Polling error: \(error.localizedDescription)")
                }
                attempts += 1
            }
            
            if !Task.isCancelled && !isPhoneVerified {
                DispatchQueue.main.async {
                    self.errorMessage = "Час очікування підтвердження вичерпано."
                    self.verificationLink = nil
                }
            }
        }
    }
    
    private func register() async {
        guard let token = verificationToken, let doc = documentImage, let selfie = selfieImage else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let success = try await NetworkManager.shared.registerCourier(
                name: name,
                pass: password,
                token: token,
                docImage: doc,
                selfieImage: selfie
            )
            
            if success {
                showSuccessAlert = true
            } else {
                errorMessage = "Помилка при реєстрації. Можливо, такий користувач вже існує."
            }
        } catch {
            errorMessage = "Помилка мережі при відправці даних."
        }
        
        isLoading = false
    }
}
