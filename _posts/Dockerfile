# docker build -t onbuild . --progress plain --no-cache
FROM ubuntu AS base

WORKDIR /app

COPY compile.sh .
RUN chmod +x compile.sh

RUN apt-get update && apt-get install -y cowsay && rm -rf /var/lib/apt/lists/*
ENV PATH="${PATH}:/usr/games"

ONBUILD WORKDIR /app
ONBUILD COPY ./Docker* .
ONBUILD RUN ls -la
ONBUILD RUN ./compile.sh
