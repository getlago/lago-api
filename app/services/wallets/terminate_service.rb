# frozen_string_literal: true

module Wallets
  class TerminateService < BaseService
    def self.call(...)
      new(...).call
    end

    def initialize(wallet:)
      @wallet = wallet
      super
    end

    def call
      return result.not_found_failure!(resource: 'wallet') unless wallet

      wallet.mark_as_terminated! if wallet.active?

      result.wallet = wallet
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    def terminate_all_expired
      Wallet.active.expired.find_each(&:mark_as_terminated!)
    end

    private

    attr_reader :wallet
  end
end
