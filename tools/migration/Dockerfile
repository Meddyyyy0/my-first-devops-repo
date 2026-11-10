ARG PGLOADER_BASE=mattermost/mattermost-pgloader:latest
FROM ${PGLOADER_BASE}
RUN go install github.com/mattermost/migration-assist/cmd/migration-assist@v0.0.2 && cp /go/bin/migration-assist /usr/local/bin/migration-assist
