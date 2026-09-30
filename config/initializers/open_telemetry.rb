# frozen_string_literal: true

require "opentelemetry/sdk"
require "opentelemetry/instrumentation/all"

# Set OTEL log level to ERROR in console, unless OTEL_LOG_LEVEL is set
if defined?(Rails::Console) && ENV["OTEL_LOG_LEVEL"].blank?
  OpenTelemetry.logger = Logger.new($stdout, level: Logger::ERROR)
end

OpenTelemetry::SDK.configure(&:use_all) if ENV["OTEL_EXPORTER"].present?

LagoTracer = OpenTelemetry.tracer_provider.tracer("lago")
