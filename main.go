package main

import (
	"html/template"
	"log"
	"net/http"
	"os"

	"github.com/joho/godotenv"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Структура для передачи в index.html
type PageData struct {
	EmailUser   string
	EmailDomain string
}

// tmpl парсится один раз при старте
var tmpl = template.Must(template.ParseFiles("templates/index.html"))

// Middleware для добавления заголовков безопасности
func securityHeadersMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Security-Policy", "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline';")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		next.ServeHTTP(w, r)
	})
}

func homeHandler(w http.ResponseWriter, r *http.Request) {
	data := PageData{
		EmailUser:   os.Getenv("EMAIL_USER"),
		EmailDomain: os.Getenv("EMAIL_DOMAIN"),
	}

	if err := tmpl.Execute(w, data); err != nil {
		log.Printf("Ошибка выполнения шаблона: %v\n", err)
	}
}

func main() {
	if err := godotenv.Load(); err != nil {
		log.Println("Предупреждение: файл .env не найден, берутся системные переменные")
	}

	// 1. НАСТРОЙКА ОСНОВНОГО СЕРВЕРА (Резюме)
	mux := http.NewServeMux()

	fs := http.FileServer(http.Dir("./static"))
	mux.Handle("/static/", http.StripPrefix("/static/", fs))
	mux.HandleFunc("/", homeHandler)

	secureMux := securityHeadersMiddleware(mux)

	port := os.Getenv("SERVER_PORT")
	if port == "" {
		port = "8080"
	}

	// 2. НАСТРОЙКА СЕРВЕРА МЕТРИК (Prometheus) на приватном порту 8081
	metricMux := http.NewServeMux()
	metricMux.Handle("/metrics", promhttp.Handler())

	// Запускаем сервер метрик в горутине — он не блокирует основной сервер
	go func() {
		log.Println("Сервер метрик Prometheus запущен на http://localhost:8081/metrics")
		if err := http.ListenAndServe(":8081", metricMux); err != nil {
			log.Fatalf("Ошибка запуска сервера метрик: %v\n", err)
		}
	}()

	// Запуск основного сервера (блокирующий вызов)
	log.Printf("Основной сервер запущен на http://localhost:%s\n", port)
	if err := http.ListenAndServe(":"+port, secureMux); err != nil {
		log.Fatal(err)
	}
}
