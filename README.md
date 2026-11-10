# Практика 4 — миграция Mattermost
Шведов Андрей Александрович, БСБО-13-25.

## Состав
Legacy: Mattermost 9.5.0 + MySQL 8.0. Production: Mattermost 12.0.1 + PostgreSQL 15. В обоих стеках один именованный том файлов mm_data. Порт 8065 доступен только на localhost; порты БД не публикуются.

## Подготовка
Нужны Docker, Compose и self-hosted runner Linux x86_64 для GitHub Actions. На Apple Silicon локальный стенд использует эмуляцию Mattermost x86_64 и нативный pgloader ARM.
```sh
cp .env.example .env
# Установить три разных тестовых пароля из букв, цифр, _ и -.
set -a; . ./.env; set +a
docker compose -p shvedov-mm -f legacy/docker-compose.yml up -d
```
Откройте localhost:8065, создайте тестового администратора, команду, приватный канал и 3–5 сообщений. Используйте вымышленные данные.

## Миграция на Linux x86_64
```sh
docker build -t shvedov-migration-tools:1.0 tools/migration
bash scripts/migrate.sh
bash scripts/migrate.sh
```

## Apple Silicon
```sh
docker build -t shvedov-pgloader:arm64 tools/pgloader-arm64
docker build --build-arg PGLOADER_BASE=shvedov-pgloader:arm64 -t shvedov-migration-tools:1.0 tools/migration
PGLOADER_PLATFORM=linux/arm64 bash scripts/migrate.sh
```

## Этапы
1. Проверка флага и блокировка параллельного запуска.
2. Остановка записи в исходный Mattermost и резервное копирование MySQL.
3. Сохранение всех ID и текстов сообщений для сравнения.
4. Запуск PostgreSQL и пересоздание ТОЛЬКО целевой схемы при незавершённой миграции.
5. Создание родной PostgreSQL-схемы командой db migrate в образе Mattermost 9.5.0.
6. Генерация data-only конфигурации официальным migration-assist и запуск pgloader. Служебные db_migrations/db_lock не копируются из MySQL. Восстанавливаются полнотекстовые индексы.
7. Сравнение всех сообщений до/после. При различиях скрипт останавливается.
8. Обновление Mattermost до 12.0.1 с --remove-orphans. MySQL-контейнер удаляется, исходный том сохраняется.
9. Проверка API и веб-страницы, затем установка .migration_completed.
10. Повторный запуск пропускает backup и перенос, проверяет работающий стек.

## Отличие от шаблона задания
Прямой pgloader с include drop был фактически проверен: он переносит таблицы, но запуск Mattermost завершается ошибкой db_migrations, затем channel_type. Поэтому рабочая реализация создаёт схему PostgreSQL средствами Mattermost и использует официальный data-only перенос. Устойчивость к частичному переносу обеспечивается пересозданием целевой схемы перед повтором. Это осознанное отклонение от буквального требования include drop, которое следует объяснить преподавателю. Служебная схема MySQL и PostgreSQL различается.

Официальный процесс: https://docs.mattermost.com/administration-guide/manage/admin/postgres-migration-assist-tool
Исходники утилиты: https://github.com/mattermost/migration-assist
Источник Dockerfile pgloader: https://github.com/mattermost/mattermost-pgloader-docker

## GitHub Actions
Ветка migration. Добавить DB_MYSQL_ROOT_PASSWORD, DB_MYSQL_PASSWORD, DB_POSTGRES_PASSWORD в GitHub Secrets. Runner должен использовать тот же Docker daemon, где подготовлен legacy-стенд. Workflow запрещает параллельные миграции. STATE_DIR находится вне checkout, поэтому сохраняется между запусками на том же runner. Локальная миграция не является подтверждением запуска Actions.

## Восстановление
Не удалять MySQL volume shvedov_mm_mysql и backups. Если проверка не прошла, флаг не устанавливается. После исправления повторить скрипт: источник сохраняется, незавершённая целевая схема пересоздаётся. Для реальной эксплуатации нужна отдельная проверка плагинов и резервная копия всех томов; учебный стенд содержит только тестовые сообщения.

Локальные .env, state, backups и LOCAL_ACCESS.txt не включать в Git или сдаваемый архив.
