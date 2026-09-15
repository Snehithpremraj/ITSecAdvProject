FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Keep the SQLite DB and JSONL logs inside the container's copy of
# prompt_inj_ch1/, same layout main.py already assumes on WSL2.
ENV ACME_DB_PATH=/app/prompt_inj_ch1/acme.db \
    ACME_TOOL_LOG=/app/prompt_inj_ch1/tool_calls.jsonl \
    ACME_NOTIFY_LOG=/app/prompt_inj_ch1/notify_calls.jsonl

RUN chmod +x entrypoint.sh

EXPOSE 8000

CMD ["./entrypoint.sh"]
