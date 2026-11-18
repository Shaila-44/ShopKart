require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module BackendApi
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0
    config.active_storage.draw_routes = true

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore, key: "_auth_api_session"
    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # Storefront URL used in emails (links back to the React app) and the shop/sender identity.
    config.client_url = ENV.fetch("CLIENT_URL", "http://localhost:5173")
    config.x.shop_name = ENV.fetch("SHOP_NAME", "Zilvo")
    config.x.mail_from = ENV.fetch("MAIL_FROM", "Zilvo <orders@zilvo.local>")
    # Times shown in customer emails (stored values stay UTC).
    config.time_zone = ENV.fetch("TIME_ZONE", "Asia/Kolkata")

    # Background jobs (order emails) are stored in PostgreSQL via Solid Queue, so they
    # survive restarts and failed jobs can be retried. The test env overrides this with :test.
    config.active_job.queue_adapter = :solid_queue
  end
end
