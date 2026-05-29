FROM python:3.12-alpine

WORKDIR /app
COPY server.py .

RUN mkdir -p /app/apks

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://localhost:8080/health || exit 1

CMD ["python", "server.py"]
