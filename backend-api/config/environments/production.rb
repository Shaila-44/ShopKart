require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Do not reload code between requests
  config.enable_reloading = false

  # Eager load code on boot
  config.eager_load = true

  # Disable full error reports
  config.consider_all_requests_local = false

  # Cache public files for 1 year
  config.public_file_server.headers = {
    "cache-control" => "public, max-age=#{1.year.to_i}",
  }

  # Active Storage service
  config.active_storage.service = :local

  # Logging
  config.log_tags = [:request_id]
  config.logger = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Log level
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Silence health check logs
  config.silence_healthcheck_path = "/up"

  # Disable deprecation logging
  config.active_support.report_deprecations = false

  # Outgoing email: configured entirely through environment variables (no credentials in code).
  if ENV["SMTP_ADDRESS"].present?
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = {
      address: ENV["SMTP_ADDRESS"],
      port: ENV.fetch("SMTP_PORT", 587).to_i,
      user_name: ENV["SMTP_USERNAME"],
      password: ENV["SMTP_PASSWORD"],
      authentication: ENV["SMTP_USERNAME"].present? ? :plain : nil,
      enable_starttls_auto: true,
    }.compact
  end
  config.action_mailer.raise_delivery_errors = true
  config.client_url = ENV.fetch("CLIENT_URL", "https://zilvo.ddns.net")

  # Mailer URL configuration
  config.action_mailer.default_url_options = {
    host: "zilvo.ddns.net",
    protocol: "https",
  }

  # URL helpers (important for ActiveStorage / serializers / Blueprinter)
  Rails.application.routes.default_url_options = {
    host: "zilvo.ddns.net",
    protocol: "https",
  }

  # I18n fallback
  config.i18n.fallbacks = true

  # Do not dump schema after migrations
  config.active_record.dump_schema_after_migration = false

  # Limit attributes shown in inspect
  config.active_record.attributes_for_inspect = [:id]
end
