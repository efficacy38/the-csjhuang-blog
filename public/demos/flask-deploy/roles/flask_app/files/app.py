from flask import Flask, jsonify
import psycopg2
import os

app = Flask(__name__)


def get_db_connection():
    return psycopg2.connect(
        host=os.environ.get('DB_HOST', 'localhost'),
        port=os.environ.get('DB_PORT', '5432'),
        database=os.environ.get('DB_NAME', 'flask_demo'),
        user=os.environ.get('DB_USER', 'flask_app'),
        password=os.environ.get('DB_PASSWORD', '')
    )


@app.route('/health')
def health():
    return jsonify({"status": "ok"})


@app.route('/db-health')
def db_health():
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute('SELECT 1')
        cur.close()
        conn.close()
        return jsonify({"status": "ok", "database": "connected"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
