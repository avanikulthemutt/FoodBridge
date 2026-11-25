from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    app_name: str = "FoodBridge API"
    environment: str = "development"
    database_url: str
    jwt_secret: str
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 60
    frontend_origin: str = "http://127.0.0.1:5500"
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

settings = Settings()
