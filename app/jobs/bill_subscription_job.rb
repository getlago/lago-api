# frozen_string_literal: true

class BillSubscriptionJob < ApplicationJob
  queue_as do
    if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
      :billing
    else
      :default
    end
  end

  unique :until_executed, on_conflict: :log, lock_ttl: 12.hours

  retry_on Sequenced::SequenceError, ActiveJob::DeserializationError, wait: :polynomially_longer, attempts: 15, jitter: 0.75

  def perform(subscriptions, timestamp, invoicing_reason:, invoice: nil, skip_charges: false)
    Rails.logger.info("BillSubscriptionJob[Invoice ID: #{invoice&.id}] - Started")

    result = Invoices::SubscriptionService.call(
      subscriptions:,
      timestamp:,
      invoicing_reason:,
      invoice:,
      skip_charges:
    )

    if result.success?
      Rails.logger.info("BillSubscriptionJob[Invoice ID: #{invoice&.id}] - Finished [SUCCESS]")
      return
    end

    Rails.logger.info("BillSubscriptionJob[Invoice ID: #{invoice&.id}] - Before reload [#{result.invoice&.inspect}]")
    result.invoice&.reload
    Rails.logger.info("BillSubscriptionJob[Invoice ID: #{invoice&.id}] - After reload [#{result.invoice&.inspect}]")

    # If the invoice was passed as an argument, it means the job was already retried (see end of function)
    if invoice || !result.invoice&.generating?
      Rails.logger.info("BillSubscriptionJob[Invoice ID: #{invoice&.id}] - generating?: #{result.invoice&.generating?}")

      ErrorDetail.create_generation_error_for(invoice: result.invoice, error: result.error)
      Rails.logger.info("BillSubscriptionJob[Invoice ID: #{invoice&.id}] - Raising error: #{result.error.inspect}")
      return result.raise_if_error!
    end

    # On billing day, we'll retry the job further in the future because the system is typically under heavy load
    is_billing_date = invoicing_reason.to_sym == :subscription_periodic

    Rails.logger.info("BillSubscriptionJob[Invoice ID: #{invoice&.id}] - Retrying with invoice")

    self.class.set(wait: is_billing_date ? 5.minutes : 3.seconds).perform_later(
      subscriptions,
      timestamp,
      invoicing_reason:,
      invoice: result.invoice,
      skip_charges:
    )
  end
end
