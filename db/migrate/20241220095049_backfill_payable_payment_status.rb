# frozen_string_literal: true

class BackfillPayablePaymentStatus < ActiveRecord::Migration[7.1]
  def change
    provider_types = PaymentProviders::BaseProvider.distinct.pluck(:type)
    provider_types.each do |provider_type|
      provider_class = provider_type.constantize

      payments = Payment.joins(:payment_provider)
        .where(payment_providers: {type: provider_type}, status: provider_class::PENDING_STATUSES)
      payments.update_all(payable_payment_status: :pending) # rubocop:disable Rails/SkipsModelValidations

      payments = Payment.joins(:payment_provider)
        .where(payment_providers: {type: provider_type}, status: provider_class::SUCCESS_STATUSES)
      payments.update_all(payable_payment_status: :succeeded) # rubocop:disable Rails/SkipsModelValidations

      payments = Payment.joins(:payment_provider)
        .where(payment_providers: {type: provider_type}, status: provider_class::FAILED_STATUSES)
      payments.update_all(payable_payment_status: :failed) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
