FROM golang:1.20.4 AS build

WORKDIR /usr/src/app

ADD go.mod main.go /usr/src/app/

RUN go build

FROM debian:bullseye-20230502-slim

COPY --from=build /usr/src/app/main /usr/local/bin/main

CMD ["/usr/local/bin/main"]
