package main

import (
	"html/template"
	"log"
	"net/http"
	"time"
)

// Данные, которые мы будем передавать в HTML
type PageData struct {
	Title   string
	Message string
	Time    string
}

func homeHandler(w http.ResponseWriter, r *http.Request) {
	// 1. Подготавливаем данные
	data := PageData{
		Title:   "Моя домашняя страница",
		Message: "Добро пожаловать в мой пет-проект на Go!",
		Time:    time.Now().Format("15:04:05"),
	}

	// 2. Парсим файл шаблона (создадим его ниже)
	tmpl, err := template.ParseFiles("templates/index.html")
	if err != nil {
		http.Error(w, "Ошибка загрузки шаблона", http.StatusInternalServerError)
		return
	}

	// 3. Объединяем шаблон и данные (рендеринг)
	tmpl.Execute(w, data)
}

func main() {
	// Раздача статических файлов (CSS, изображения) из папки "static"
	fs := http.FileServer(http.Dir("./static"))
	http.Handle("/static/", http.StripPrefix("/static/", fs))

	http.HandleFunc("/", homeHandler)

	log.Println("Сервер запущен на http://localhost:8080")
	if err := http.ListenAndServe(":8080", nil); err != nil {
		log.Fatal(err)
	}
}
