FROM golang:1.26-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o main .

# =========================
# Runtime image
# =========================

FROM alpine:3.20

# Запуск от непривилегированного пользователя — best practice для production
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

COPY --from=builder /app/main .
COPY --from=builder /app/templates ./templates
COPY --from=builder /app/static ./static

# Меняем владельца файлов на appuser
RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE 8080

CMD ["./main"]
