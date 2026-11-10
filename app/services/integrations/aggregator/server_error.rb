# frozen_string_literal: true

module Integrations
  module Aggregator
    # NOTE: Raised on a 500, 503 or 504 answer only for callers that opt in, such as the wallet
    #       refresh job, which retries it. Not a LagoHttpClient::HttpError, so no generic rescue swallows it.
    class ServerError < StandardError
    end
  end
end
