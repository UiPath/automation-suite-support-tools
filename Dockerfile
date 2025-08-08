#build stage
FROM golang:1.24-alpine3.22 AS builder
RUN apk add --no-cache git
WORKDIR /go/src/app
COPY . .
RUN go mod tidy
RUN go build -o /go/bin/app -v ./

#final stage
FROM alpine:3.22
RUN apk --no-cache add ca-certificates
COPY --from=builder /go/bin/app /app
ENTRYPOINT /app
LABEL Name=go Version=1.24.4
EXPOSE 9443
