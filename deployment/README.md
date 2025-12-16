# How to Deploy

1. Clone the repo

```
git clone https://github.com/Antervel/coldplay
```

2. Go to the `deployment` folder
 ```
cd coldplay/deployment
```

3. Create and edit the `.env` file
```
 cp .env.sample .env
```

4. Customize `docker-compose.yml` file if needed.

5. Start the containers
```
 docker compose up -d
```

