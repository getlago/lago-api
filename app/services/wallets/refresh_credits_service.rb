# frozen_string_literal: true

module Wallets
  class RefreshCreditsService < BaseService
    def initialize(wallet:)
      @wallet = wallet
      super
    end

    def call
      # TODO
    end
  end
end
