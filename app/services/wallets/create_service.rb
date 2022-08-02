# frozen_string_literal: true

module Wallets
  class CreateService < BaseService
    def create(**args)
      current_customer = Customer.find_by(
        id: args[:customer_id],
        organization_id: args[:organization_id],
      )

      return result.fail!(code: 'missing_argument', message: 'unable to find customer') unless current_customer

      if current_customer.wallets.active.any?
        return result.fail!(code: 'wallet_already_exists', message: 'a wallet already exists for this customer')
      end

      unless current_customer.subscriptions.active.any?
        return result.fail!(code: 'no_active_subscription', message: 'customer does not have any active subscription')
      end

      wallet = current_customer.wallets.create!(
        name: args[:name],
        rate_amount: args[:rate_amount],
        expiration_date: args[:expiration_date],
        currency: default_currency(current_customer),
        status: :active,
      )

      result.wallet = wallet
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    private

    def default_currency(customer)
      customer.active_subscription&.plan&.amount_currency
    end
  end
end
