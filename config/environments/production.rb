require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  Rails.application.routes.default_url_options[:host] = "https://geomatch-web.onrender.com"

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance.
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Caching
  config.action_controller.perform_caching = true
  config.public_file_server.headers = {
    "cache-control" => "public, max-age=#{1.year.to_i}"
  }

  # Active Storage (points to R2)
  config.active_storage.service = :r2

  
  # Logging
  config.log_tags = [:request_id]
  config.logger = ActiveSupport::TaggedLogging.logger(STDOUT)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Healthcheck
  config.silence_healthcheck_path = "/up"

  # No deprecations
  config.active_support.report_deprecations = false

  # Cache store
  config.cache_store = :solid_cache_store

  # Active Job
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Mailer
  config.action_mailer.default_url_options = { host: "example.com" }

  # I18n fallbacks
  config.i18n.fallbacks = true

  # Schema dump
  config.active_record.dump_schema_after_migration = false

  # Only show id on production logs
  config.active_record.attributes_for_inspect = [:id]
end
