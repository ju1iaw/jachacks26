FROM jaseci/jaclang:0.34.7

WORKDIR /app

COPY jac.toml ./
RUN jac install --no-dev --no-npm

COPY . .
RUN chmod +x scripts/start_prod.sh

EXPOSE 8000

CMD ["./scripts/start_prod.sh"]
