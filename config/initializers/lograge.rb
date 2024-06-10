# frozen_string_literal: true

Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new
  config.colorize_logging = false

  config.lograge.custom_options = lambda do |event|
    {
      ddsource: 'ruby',
      params: event.payload[:params].reject { |k| %w[controller action].include?(k) },
      organization_id: event.payload[:organization_id]
    }
  end
end
