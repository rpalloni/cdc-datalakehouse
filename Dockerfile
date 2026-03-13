FROM apache/kafka:4.1.0

WORKDIR /opt/kafka

EXPOSE 8083

RUN mkdir -p /opt/kafka/plugins
RUN cp /opt/kafka/libs/connect-file-*.jar /opt/kafka/plugins/

ENV CONNECT_PLUGIN_PATH=/opt/kafka/plugins

COPY scripts/connect-entrypoint.sh /connect-entrypoint.sh

ENTRYPOINT ["sh","/connect-entrypoint.sh"]