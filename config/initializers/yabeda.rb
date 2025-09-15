# frozen_string_literal: true

require "yabeda"

Yabeda.configure do
  default_tag :service, ENV["OTEL_SERVICE_NAME"] || "lago-api"
  default_tag :environment, Rails.env
  default_tag :version, ENV["LAGO_VERSION"] || "unknown"

  Yabeda::Rails.config.ignore_actions = ["ApplicationController#health"]
end
