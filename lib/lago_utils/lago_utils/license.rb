# frozen_string_literal: true

module LagoUtils
  class License
    def initialize(url)
      @url = url
      @premium = true
    end

    def verify
      @premium = true
    end

    def premium?
      premium
    end

    private

    attr_reader :url, :premium
  end
end
