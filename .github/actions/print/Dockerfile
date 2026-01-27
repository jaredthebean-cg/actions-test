FROM alpine:latest
RUN apk add --no-cache bash git
WORKDIR /app
COPY run.sh run.sh
WORKDIR /github/workspace
ENTRYPOINT [ "/app/run.sh" ]
