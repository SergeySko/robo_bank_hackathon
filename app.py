import os
from flask import Flask
from flask import Flask, Markup, Response, jsonify, render_template, request, redirect
import requests
import simplejson as json
import sqlalchemy
from sqlalchemy import create_engine,  Table, Column, Integer, String, Boolean, Text, MetaData, ForeignKey, Sequence, inspect, desc, func
from sqlalchemy.sql import select, text
from sqlalchemy.orm import relationship, backref, sessionmaker, object_session
from sqlalchemy.ext.declarative import declarative_base
import requests
from binance.client import Client

app = Flask(__name__)
api_key = "";
api_secret = "";
client = Client(api_key, api_secret)

@app.route('/')
def index():
    debug = ""
    return render_template('index.html', debug=debug)

@app.route('/binance')
def binance():
    return render_template('binance.html')

@app.route('/get_assets')
def get_asset():
    info = client.get_all_tickers()
    return json.dumps(info, sort_keys=True, indent=4); 

if __name__ == '__main__':
    app.run(host=os.getenv('IP', '0.0.0.0'), port=int(os.getenv('PORT', 8080)), debug=True)
