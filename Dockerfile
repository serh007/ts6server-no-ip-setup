# Офіційний базовий образ TeamSpeak 6 Server Beta
FROM teamspeaksystems/teamspeak6-server:latest

LABEL maintainer="TeamSpeak 6 Server Setup"
LABEL description="TeamSpeak 6 Server Beta with Portwarp reverse tunnel integration"

# Базові змінні середовища за замовчуванням
ENV TSSERVER_LICENSE_ACCEPTED=accept \
    TSSERVER_DEFAULT_PORT=9987 \
    TSSERVER_VOICE_IP=0.0.0.0 \
    TSSERVER_FILE_TRANSFER_PORT=30033 \
    TSSERVER_FILE_TRANSFER_IP=0.0.0.0

# Порти TeamSpeak:
# 9987/udp  - Голосовий зв'язок (Voice port)
# 30033/tcp - Передача файлів (File transfer)
# 10080/tcp - WebQuery інтерфейс
# 10022/tcp - ServerQuery SSH
EXPOSE 9987/udp
EXPOSE 30033/tcp
EXPOSE 10080/tcp
EXPOSE 10022/tcp

# Директорія для постійного зберігання бази даних та конфігурації
VOLUME ["/var/tsserver"]

WORKDIR /var/tsserver

CMD ["tsserver"]
