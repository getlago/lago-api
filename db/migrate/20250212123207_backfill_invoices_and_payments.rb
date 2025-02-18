# frozen_string_literal: true

class BackfillInvoicesAndPayments < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    update_invoices
    update_payments
  end

  def down
  end

  private

  def update_invoices
    Invoice.where(payment_status: 1).update_all("total_paid_amount_cents = total_amount_cents") # rubocop:disable Rails/SkipsModelValidations
  end

  def update_payments
    PaymentProviders::BaseProvider.distinct.pluck(:type).each do |provider_type|
      provider_class = provider_type.constantize

      update_payment_status(provider_type, provider_class::PROCESSING_STATUSES, :processing)
      update_payment_status(provider_type, provider_class::SUCCESS_STATUSES, :succeeded)
      update_payment_status(provider_type, provider_class::FAILED_STATUSES, :failed)
    end
  end

  def update_payment_status(provider_type, statuses, new_status)
    # some payments providers are already deleted but we still need to change the payment
    Payment.left_joins(:payment_provider)
      .where("payment_providers.type = ? OR payment_providers.id IS NULL", provider_type)
      .where(payable_payment_status: nil, status: statuses)
      .update_all(payable_payment_status: new_status) # rubocop:disable Rails/SkipsModelValidations
  end
end
