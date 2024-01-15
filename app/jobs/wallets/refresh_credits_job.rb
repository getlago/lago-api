# frozen_string_literal: true

module Wallets
  class RefreshCreditsJob < ApplicationJob
    queue_as 'wallets'

    def perform(wallet)
      Wallets::RefreshCreditsService.call(wallet:)
    end
  end
end
