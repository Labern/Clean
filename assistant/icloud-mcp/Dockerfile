FROM python:3.12-slim
WORKDIR /app
COPY pyproject.toml ./
COPY icloud_mcp ./icloud_mcp
RUN pip install --no-cache-dir .
ENV PORT=8000
EXPOSE 8000
CMD ["icloud-mcp", "--http"]
