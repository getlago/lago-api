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

  retry_on BaseLockService::FailedToAcquireLock, ActiveRecord::StaleObjectError, attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay
  retry_on Sequenced::SequenceError, ActiveJob::DeserializationError, wait: :polynomially_longer, attempts: 15, jitter: 0.75

  def perform(subscriptions, timestamp, invoicing_reason:, invoice: nil, skip_charges: false)
    Rails.logger.info("BillSubscriptionJob[Invoice ID: #{invoice&.id}] - Started")

    # NOTE: A payment term can change between job enqueue and execution, making the group mixed.
    #       Re-resolve here: mixed groups are split into one job per term instead of failing.
    #       Retries always carry `invoice:` whose snapshot is frozen, so they never split.
    resolutions = invoice.nil? ? resolve_payment_terms(subscriptions) : []

    if mixed_payment_terms?(resolutions)
      term_groups = subscriptions.zip(resolutions).group_by { |_, resolution| resolution.payment_term.to_h }.values
      Rails.logger.info("BillSubscriptionJob - Mixed payment terms, splitting into #{term_groups.size} groups")

      term_groups.each do |pairs|
        self.class.perform_later(pairs.map(&:first), timestamp, invoicing_reason:, skip_charges:)
      end

      return
    end

    sources = resolutions.map(&:source).uniq

    result = Invoices::SubscriptionService.call(
      subscriptions:,
      timestamp:,
      invoicing_reason:,
      invoice:,
      skip_charges:,
      payment_term: resolutions.first&.payment_term,
      payment_term_source: sources.many? ? "mixed" : sources.first
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

  # Each hour, we check for each customer whether they need to be billed today. If it is the case and there's not
  # invoice for today in the DB, we will schedule the BillSubscriptionJob with timestamp of the current time. So it
  # could occur that we schedule a second job while the first one (from one hour ago) hasn't been processed yet due to a
  # high number of jobs. As the timestamp won't be the same, the lock key would be different and both jobs could be
  # processed concurrently, causing unnecessary jobs. Note that even if the job is schduled twice, we'll still prevent
  # duplicate invoices.
  #
  # To avoid this, we normalize the timestamp in the customer's timezone and use the date as the lock key argument.
  def lock_key_arguments
    arguments = self.arguments.dup

    # if there is no subscription, we don't need to normalize anything
    return arguments if arguments[0].empty?
    timestamp = arguments[1]
    subscriptions = arguments[0]

    # BillSubscriptionJob subscriptions will always contain subscriptions for the same customer
    customer = subscriptions.first.customer
    date = Time.zone.at(timestamp).in_time_zone(customer.applicable_timezone).to_date
    arguments[1] = date
    arguments
  end

  private

  def resolve_payment_terms(subscriptions)
    subscriptions.map { |sub| PaymentTerms::ResolveService.call!(customer: sub.customer, subscription: sub) }
  end

  def mixed_payment_terms?(resolutions)
    resolutions.map { |resolution| resolution.payment_term.to_h }.uniq.many?
  end
end
