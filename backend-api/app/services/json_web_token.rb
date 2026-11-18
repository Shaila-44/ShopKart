# app/services/json_web_token.rb
class JsonWebToken
  # Never fall back to a guessable constant: use the app's secret_key_base if no dedicated key is set.
  SECRET_KEY = ENV["JWT_SECRET_KEY"].presence || Rails.application.secret_key_base

  def self.encode(payload, exp = 24.hours.from_now)
    payload[:exp] = exp.to_i
    JWT.encode(payload, SECRET_KEY)
  end

  def self.decode(token)
    decoded = JWT.decode(token, SECRET_KEY)[0]
    ActiveSupport::HashWithIndifferentAccess.new(decoded)
  rescue JWT::DecodeError, JWT::ExpiredSignature
    nil
  end

  def self.decode_for_refresh(token)
    decoded = JWT.decode(token, SECRET_KEY, false, { verify_expiration: false })[0]
    ActiveSupport::HashWithIndifferentAccess.new(decoded)
  rescue JWT::DecodeError
    nil
  end
end
