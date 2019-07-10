# first, cat goss-entrypoint.sh into whatever directory within which we are building a particular image
COPY goss-entrypoint.sh /

RUN sudo chmod +x /goss-entrypoint.sh || chmod +x /goss-entrypoint.sh

ENTRYPOINT ["/goss-entrypoint.sh"]
