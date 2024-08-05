# frozen_string_literal: true

Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new
  config.colorize_logging = false

  config.lograge.custom_options = lambda do |event|
    # If ENV[OTEL_EXPORTER] is not set, the span context will have all zero values.
    span = OpenTelemetry::Trace.current_span

    {
      ddsource: 'ruby',
      params: event.payload[:params].reject { |k| %w[controller action].include?(k) },
      organization_id: event.payload[:organization_id],
      trace_id: span.context.hex_trace_id,
      span_id: span.context.hex_span_id
    }
  end
end
