# frozen_string_literal: true

module WalletTransactions
  class CreateService < BaseService
    def initialize(wallet_id:, paid_credits:, granted_credits:)
      super(nil)

      @current_wallet = Wallet.find_by(id: wallet_id)
      @paid_credits = paid_credits
      @granted_credits = granted_credits
    end

    def create
      return result.fail!(code: 'not_found') unless current_wallet

      handle_paid_credits(current_wallet, paid_credits) if paid_credits
      handle_granted_credits(current_wallet, granted_credts) if granted_credits
    end

    private

    attr_reader :current_wallet, :paid_credits, :granted_credits

    def handle_paid_credits
      # TODO
    end

    def handle_granted_credits
      # TODO
    end
  end
end
