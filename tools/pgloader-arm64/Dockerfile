# Native ARM fallback for Apple Silicon. Linux x86 uses the official Mattermost image.
FROM golang:1.27.1@sha256:3680233e3204827fbdc66088528ae6d4b3d034f51d03a99d454f6de034888244
RUN apt-get update && apt-get install -y --no-install-recommends pgloader ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /home/migration
