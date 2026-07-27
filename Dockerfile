FROM jaseci/jaclang:0.34.7

WORKDIR /app

COPY jac.toml ./
RUN jac install --no-dev --no-npm

COPY . .
RUN chmod +x scripts/start_prod.sh

EXPOSE 8000

# The Jac base image launches `jac` as its entrypoint. Override it so Railway
# executes our production bootstrap script instead of treating the script path
# as a Jac subcommand.
ENTRYPOINT ["/app/scripts/start_prod.sh"]
