# frozen_string_literal: true

module LagoUtils
  class License
    def initialize(url)
      @url = url
      @premium = false
    end

    def verify
      return if ENV["LAGO_LICENSE"].blank?

      # Runs at boot: a transient failure must not crash the process.
      http_client = LagoHttpClient::Client.new("#{url}/verify/#{ENV["LAGO_LICENSE"]}", retry_on_transient_errors: true)
      response = http_client.get

      @premium = response["valid"]
    end

    def premium?
      premium
    end

    private

    attr_reader :url, :premium
  end
end
