# frozen_string_literal: true

module WalletTransactions
  class CreateService < BaseService
    def create(**args)
      return result unless valid?(**args)

      handle_paid_credits(args[:wallet_id], args[:paid_credits]) if args[:paid_credits]
      handle_granted_credits(args[:wallet_id], args[:granted_credits]) if args[:granted_credits]
    end

    private

    def handle_paid_credits(wallet_id, paid_credits)
      # TODO
    end

    def handle_granted_credits(wallet_id, granted_credits)
      # TODO
    end

    def valid?(**args)
      WalletTransactions::ValidateService.new(result, **args).valid?
    end
  end
end
