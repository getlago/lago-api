# frozen_string_literal: true

require "lago_http_client"

module Analytics
  class BaseService < BaseService
    def initialize(organization, **filters)
      @organization = organization
      @filters = filters

      super()
    end

    private

    attr_reader :organization, :filters, :records

    def http_client
      LagoHttpClient::Client.new(endpoint_url)
    end

    def headers
      {
        "Authorization" => "Bearer #{ENV["LAGO_DATA_API_BEARER_TOKEN"]}"
      }
    end

    def endpoint_url
      "#{ENV["LAGO_DATA_API_URL"]}/#{action_path}"
    end

    def action_path
      raise NotImplementedError
    end
  end
end
