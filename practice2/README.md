# Практика 2 — Docker и Docker Compose
Шведов Андрей Александрович, БСБО-13-25.

## Запуск
```sh
cp .env.example .env
# Задайте локальный пароль в .env.
docker compose config -q
docker compose up -d --build
docker compose ps
curl --fail http://localhost:8080/api/items
```
Откройте http://localhost:8080. Ожидаются first item и second item.

## Проверка
```sh
docker image inspect shvedov-devops2:1.0 --format '{{.Size}} {{.Config.User}}'
docker compose logs app
docker compose exec db psql -U app -d appdb -c "SELECT * FROM items;"
docker compose down
```
`down` сохраняет именованный том; повторный запуск сохраняет данные. Не используйте `down -v`, если данные нужны.

## Для защиты
Сборка создаёт образ, запуск создаёт контейнер. Первый этап Dockerfile содержит Go; второй — только бинарник и distroless. go.mod/go.sum копируются раньше исходников для кэширования зависимостей. USER 65532 исключает запуск от root. EXPOSE документирует порт; ports публикует его только на loopback хоста. PostgreSQL не публикуется наружу. Compose DNS разрешает имя db. Healthcheck и depends_on ожидают готовности БД. Фронтенд подключён как read-only bind mount; данные БД живут в именованном томе. Пароль хранится в игнорируемом .env.
