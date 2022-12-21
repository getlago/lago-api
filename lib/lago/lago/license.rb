# frozen_string_literal: true

module Lago
  class License
    def initialize(url)
      @url = url
    end

    def verify
      return @premium = false unless ENV['LAGO_LICENSE']

      http_client = LagoHttpClient.new("#{url}/verify/#{ENV['LAGO_LICENSE']}")
      response = http_client.post

      @premium = response['valid']
    end

    def premium?
      premium
    end

    private

    attr_reader :url, :premium
  end
end
