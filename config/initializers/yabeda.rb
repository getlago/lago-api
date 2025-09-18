# frozen_string_literal: true

require "yabeda"

# https://github.com/yabeda-rb/yabeda-prometheus?tab=readme-ov-file#multi-process-server-support
Prometheus::Client.config.data_store = Prometheus::Client::DataStores::DirectFileStore.new(
  dir: "/tmp/prometheus/"
)

Yabeda.configure do
  default_tag :service, ENV["OTEL_SERVICE_NAME"] || "lago-api"
  default_tag :environment, Rails.env
  default_tag :version, ENV["LAGO_VERSION"] || "unknown"

  Yabeda::Rails.config.ignore_actions = ["ApplicationController#health"]
end
