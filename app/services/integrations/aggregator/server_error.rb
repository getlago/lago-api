# frozen_string_literal: true

module Integrations
  module Aggregator
    # NOTE: Raised on a 500, 503 or 504 answer of the draft tax request. Not a LagoHttpClient::HttpError,
    #       so no generic rescue swallows it.
    class ServerError < StandardError
    end
  end
end
