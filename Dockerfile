FROM golang:1.14-alpine as go

FROM alpine:3.13 as protoc_builder
RUN apk add --no-cache build-base curl automake autoconf libtool git zlib-dev g++ unzip linux-headers go cmake

ENV GRPC_VERSION=1.44.0 \
        GRPC_WEB_VERSION=1.3.1 \
        PROTOBUF_VERSION=3.19.4 \
        PROTOC_GEN_DOC_VERSION=1.5.1 \
        OUTDIR=/out
RUN mkdir -p /protobuf && \
        curl -L https://github.com/protocolbuffers/protobuf/archive/refs/tags/v${PROTOBUF_VERSION}.tar.gz | tar xvz --strip-components=1 -C /protobuf
RUN git clone --depth 1 --recursive -b v${GRPC_VERSION} https://github.com/grpc/grpc.git /grpc && \
        rm -rf grpc/third_party/protobuf && \
        ln -s /protobuf /grpc/third_party/protobuf
RUN mkdir -p /grpc-web && \
        curl -L https://github.com/grpc/grpc-web/archive/${GRPC_WEB_VERSION}.tar.gz | tar xvz --strip-components=1 -C /grpc-web

RUN cd /protobuf && \
        ./autogen.sh && \
        (./configure --prefix=/usr || cat config.log) && \
        make -j2 && make install

RUN cd grpc && \
        make -j2
RUN cd /protobuf && \
        make install DESTDIR=${OUTDIR}

RUN cd /grpc && \
    mkdir -p cmake/build && cd cmake/build && cmake ../.. && make
RUN cd /grpc && cmake --install cmake/build  --prefix ${OUTDIR}/usr

RUN cd /grpc-web && \
        make plugin && \
        make install-plugin PREFIX=${OUTDIR}/usr

RUN find ${OUTDIR} -name "*.a" -delete -or -name "*.la" -delete

ENV GOPATH=/go \
        PATH=/go/bin/:$PATH
RUN go get -u -v -ldflags '-w -s' \
        github.com/golang/protobuf/protoc-gen-go \
        github.com/gogo/protobuf/protoc-gen-gofast \
        github.com/gogo/protobuf/protoc-gen-gogo \
        github.com/gogo/protobuf/protoc-gen-gogofast \
        github.com/gogo/protobuf/protoc-gen-gogofaster \
        github.com/gogo/protobuf/protoc-gen-gogoslick \
        github.com/grpc-ecosystem/grpc-gateway/protoc-gen-grpc-gateway \
        github.com/ckaznocha/protoc-gen-lint \
        github.com/mwitkow/go-proto-validators/protoc-gen-govalidators
RUN install -c ${GOPATH}/bin/protoc-gen* ${OUTDIR}/usr/bin/


FROM alpine:3.13
RUN apk add --no-cache libstdc++
COPY --from=protoc_builder /out/ /

RUN apk add --no-cache curl && \
        mkdir -p /protobuf/google/protobuf && \
        for f in any duration descriptor empty struct timestamp wrappers; do \
        curl -L -o /protobuf/google/protobuf/${f}.proto https://raw.githubusercontent.com/google/protobuf/master/src/google/protobuf/${f}.proto; \
        done && \
        mkdir -p /protobuf/google/api && \
        for f in annotations http; do \
        curl -L -o /protobuf/google/api/${f}.proto https://raw.githubusercontent.com/grpc-ecosystem/grpc-gateway/master/third_party/googleapis/google/api/${f}.proto; \
        done && \
        mkdir -p /protobuf/github.com/gogo/protobuf/gogoproto && \
        curl -L -o /protobuf/github.com/gogo/protobuf/gogoproto/gogo.proto https://raw.githubusercontent.com/gogo/protobuf/master/gogoproto/gogo.proto && \
        mkdir -p /protobuf/github.com/mwitkow/go-proto-validators && \
        curl -L -o /protobuf/github.com/mwitkow/go-proto-validators/validator.proto https://raw.githubusercontent.com/mwitkow/go-proto-validators/master/validator.proto && \
        apk del curl && \
        chmod a+x /usr/bin/protoc

ENTRYPOINT ["/usr/bin/protoc", "-I/protobuf"]

RUN apk update && apk add openssh-client
RUN apk add --update nodejs nodejs-npm
RUN npm config set unsafe-perm true

RUN apk --no-cache add git make musl-dev
ENV GOPATH /go
ENV PATH $GOPATH/bin:/usr/local/go/bin:$PATH

COPY --from=go /go /go
COPY --from=go /usr/local/go /usr/local/go

RUN mkdir -p $GOPATH/src/github.com/envoyproxy \
    && cd $GOPATH/src/github.com/envoyproxy \
    && wget https://github.com/envoyproxy/protoc-gen-validate/archive/refs/tags/v0.5.1.zip \
    && unzip v0.5.1.zip \
    && mv protoc-gen-validate-0.5.1 protoc-gen-validate
RUN cd $GOPATH/src/github.com/envoyproxy/protoc-gen-validate && export GO111MODULE=on && make build
RUN cp -r $GOPATH/src/github.com/envoyproxy/protoc-gen-validate/validate  /protobuf/

RUN mkdir /ts
WORKDIR /ts
RUN npm install ts-protoc-gen
