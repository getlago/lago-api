# frozen_string_literal: true

module LagoUtils
  class License
    def initialize(url)
      @url = url
      @premium = false
    end

    def verify
      true
    end

    def premium?
      premium
    end

    private

    attr_reader :url, :premium
  end
end
