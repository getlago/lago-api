# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Integrations
  module Aggregator
    class BadGatewayError < LagoHttpClient::HttpError
      def initialize(body, uri)
        super(502, body, uri)
      end
    end
  end
end
