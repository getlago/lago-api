# frozen_string_literal: true

class BackfillPayablePaymentStatus < ActiveRecord::Migration[7.1]
  def change
    # clean all duplicate data
    # Find `payable_id`s with duplicate_statuses payments

    # Define statuses to clean up duplicates
    duplicate_statuses = %w[
      processing
      requires_capture
      requires_action
      requires_confirmation
      requires_payment_method
      pending_customer_approval
      pending_submission
      submitted
      confirmed
      AuthorisedPending
      Received
    ]

    duplicate_payables = Payment.where(status: duplicate_statuses)
      .group(:payable_id)
      .having("COUNT(id) > 1")
      .pluck(:payable_id)

    # clean the duplicates
    duplicate_payables.each do |payable_id|
      # Find the most recent with duplicate_statuses
      latest_pending_payment = Payment.where(status: duplicate_statuses, payable_id: payable_id)
        .order(created_at: :desc)
        .first

      # Update all other duplicate_statuses payments for this `payable_id` to "failed"
      Payment.where(status: duplicate_statuses, payable_id: payable_id)
        .where.not(id: latest_pending_payment.id)
        .update_all(status: "failed") # rubocop:disable Rails/SkipsModelValidations
    end

    provider_types = PaymentProviders::BaseProvider.distinct.pluck(:type)
    provider_types.each do |provider_type|
      provider_class = provider_type.constantize

      payments = Payment.joins(:payment_provider)
        .where(payment_providers: {type: provider_type}, status: provider_class::PROCESSING_STATUSES)
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
