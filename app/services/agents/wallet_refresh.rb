# frozen_string_literal: true

module Agents
  module WalletRefresh
    def self.available?
      ENV["LAGO_REDIS_CACHE_URL"].present? && ENV["LAGO_DISABLE_WALLET_REFRESH"] != "true"
    end
  end
end
