# frozen_string_literal: true

module Subscriptions
  class TerminateService < BaseService
    def initialize(subscription:, async: true, upgrade: false)
      @subscription = subscription
      @async = async
      @upgrade = upgrade

      super
    end

    def call
      return result.not_found_failure!(resource: "subscription") if subscription.blank?

      ActiveRecord::Base.transaction do
        if subscription.pending?
          subscription.mark_as_canceled!
        elsif !subscription.terminated?
          subscription.mark_as_terminated!

          if subscription.should_sync_hubspot_subscription?
            Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob.perform_after_commit(subscription:)
          end

          if subscription.plan.pay_in_advance? && pay_in_advance_invoice_issued?
            # NOTE: As subscription was payed in advance and terminated before the end of the period,
            #       we have to create a credit note for the days that were not consumed
            CreditNotes::CreateFromTermination.call!(
              subscription:,
              reason: "order_cancellation",
              upgrade:
            )
          end

          # NOTE: We should bill subscription and generate invoice for all cases except for the upgrade
          #       For upgrade we will create only one invoice for termination charges and for in advance charges
          #       It is handled in subscriptions/create_service.rb
          bill_subscription unless upgrade
        end

        cancel_next_subscription
      end

      SendWebhookJob.perform_after_commit("subscription.terminated", subscription)
      Utils::ActivityLog.produce_after_commit(subscription, "subscription.terminated")

      result.subscription = subscription
      result
    rescue BaseService::FailedResult => e
      e.result
    end

    # NOTE: Called to terminate a downgraded subscription
    def terminate_and_start_next(timestamp:)
      next_subscription = subscription.next_subscription
      return result unless next_subscription
      return result unless next_subscription.pending?

      rotation_date = Time.zone.at(timestamp)

      ActiveRecord::Base.transaction do
        subscription.mark_as_terminated!(rotation_date)

        if subscription.should_sync_hubspot_subscription?
          Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob.perform_later(subscription:)
        end

        next_subscription.mark_as_active!(rotation_date)
        if next_subscription.should_sync_hubspot_subscription?
          Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob.perform_later(next_subscription)
        end
      end

      # NOTE: Create an invoice for the terminated subscription
      #       if it has not been billed yet
      #       or only for the charges if subscription was billed in advance
      #       Also, add new pay in advance plan inside if applicable
      billable_subscriptions = if next_subscription.plan.pay_in_advance?
        [subscription, next_subscription]
      else
        [subscription]
      end
      BillSubscriptionJob.perform_later(billable_subscriptions, timestamp, invoicing_reason: :upgrading)
      BillNonInvoiceableFeesJob.perform_later([subscription], rotation_date) # Ignore next subscription since there can't be events

      SendWebhookJob.perform_later("subscription.terminated", subscription)
      Utils::ActivityLog.produce(subscription, "subscription.terminated")
      SendWebhookJob.perform_later("subscription.started", next_subscription)
      Utils::ActivityLog.produce(next_subscription, "subscription.started")

      result.subscription = next_subscription

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :subscription, :async, :upgrade

    def cancel_next_subscription
      next_subscription = subscription.next_subscription
      return if next_subscription.nil?

      next_subscription.mark_as_canceled!

      if next_subscription.should_sync_hubspot_subscription?
        Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob.perform_after_commit(subscription: next_subscription)
      end
    end

    def bill_subscription
      if async
        BillSubscriptionJob.perform_after_commit(
          [subscription],
          subscription.terminated_at,
          invoicing_reason: :subscription_terminating
        )
        BillNonInvoiceableFeesJob.perform_after_commit([subscription], subscription.terminated_at)
      else
        BillSubscriptionJob.perform_now(
          [subscription],
          subscription.terminated_at,
          invoicing_reason: :subscription_terminating
        )
        BillNonInvoiceableFeesJob.perform_now(
          [subscription],
          subscription.terminated_at
        )
      end
    end

    # NOTE: If subscription is terminated automatically by setting ending_at, there is a chance that this service will
    #       be called before invoice for the period has been generated.
    #       In that case we do not want to issue a credit note.
    def pay_in_advance_invoice_issued?
      # Subscription duplicate is used in this logic so that special cases used for terminated subscription
      # can be avoided in boundaries calculation
      duplicate = subscription.dup.tap { |s| s.status = :active }
      beginning_of_period = beginning_of_period(duplicate)

      # If this is first period, pay in advance invoice is issued with creating subscription
      return true if beginning_of_period < duplicate.started_at

      dates_service = Subscriptions::DatesService.new_instance(
        duplicate,
        beginning_of_period,
        current_usage: false
      )

      boundaries = {
        from_datetime: dates_service.from_datetime,
        to_datetime: dates_service.to_datetime,
        charges_from_datetime: dates_service.charges_from_datetime,
        charges_to_datetime: dates_service.charges_to_datetime,
        charges_duration: dates_service.charges_duration_in_days
      }

      InvoiceSubscription.matching?(subscription, boundaries, recurring: false)
    end

    def beginning_of_period(subscription_dup)
      dates_service = Subscriptions::DatesService.new_instance(
        subscription_dup,
        subscription.terminated_at,
        current_usage: false
      )

      dates_service.previous_beginning_of_period(current_period: true).to_datetime
    end
  end
end
