# frozen_string_literal: true

module X402
  module CreditPurchases
    class CreatePaymentJob < ApplicationJob
      queue_as do
        if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PAYMENTS"])
          :payments
        else
          :default
        end
      end

      retry_on ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, wait: :polynomially_longer, attempts: 6

      def perform(invoice, wallet_transaction)
        settlement = X402::Settlement.find_by!(customer_id: invoice.customer_id, wallet_transaction:)
        X402::Payments::CreateService.call!(settlement:, invoice:)
      end
    end
  end
end
