# Build the manager binary
FROM golang:1.24 as builder

# Build arguments for cross-compilation
ARG TARGETOS=linux
ARG TARGETARCH=amd64

WORKDIR /workspace
# Copy the Go Modules manifests
COPY go.mod go.mod
COPY go.sum go.sum

# Copy the go source
COPY main.go main.go
COPY webhook/ webhook/
COPY sample/certs/ certs/

# Build using target architecture
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 GO111MODULE=on go build -a -o rewriter main.go

FROM --platform=linux/amd64 uipathsec.azurecr.io/uipath/parent/ubi9-v2/base:1.0

WORKDIR /
COPY --from=builder /workspace/rewriter .
COPY --from=builder /workspace/certs ./certs

ENTRYPOINT ["/rewriter"]