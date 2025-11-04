#build stage
FROM golang:1.24-alpine3.22 AS builder
RUN apk add --no-cache git
WORKDIR /go/src/migmutatingwebhook
COPY . .
RUN go mod tidy
RUN go build -o /go/bin/migmutatingwebhook -v ./

#final stage
FROM alpine:3.22
RUN apk --no-cache add ca-certificates
COPY --from=builder /go/bin/migmutatingwebhook /app/migmutatingwebhook
ENTRYPOINT /app/migmutatingwebhook
LABEL Name=go Version=1.24.4
EXPOSE 9443
