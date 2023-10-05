FROM python:3.8-alpine

RUN apk add build-base nodejs npm
RUN pip3 install solc-select && solc-select install 0.8.19 && solc-select use 0.8.19
RUN pip3 install slither-analyzer==0.9.6

WORKDIR /src
COPY package.json /src/package.json
COPY package-lock.json /src/package-lock.json

RUN npm install

COPY . /src

ENTRYPOINT [ "slither"]