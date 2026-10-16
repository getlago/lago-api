# frozen_string_literal: true

# Native v2 controllers that render a v1 payload until their v2 serializer exists.
V2_TIMESTAMPS_UNCHECKED_CONTROLLERS = %w[api/v2/invoices].freeze

# Checks the last response of every request spec on a native v2 endpoint, so only the fields the
# specs populate. The /api/v2 routes that fall through to v1 controllers keep the v1 formats.
RSpec.configure do |config|
  config.after(type: :request) do
    controller = request&.path_parameters&.dig(:controller).to_s
    next unless controller.start_with?("api/v2/")
    next if V2_TIMESTAMPS_UNCHECKED_CONTROLLERS.include?(controller)
    next unless response.media_type == "application/json"

    expect(response.parsed_body).to have_normalized_timestamps
  end
end
