# frozen_string_literal: true

module Subscriptions
  class TerminateService < BaseService
    Result = BaseResult[:subscription]

    def initialize(subscription:, async: true, rotation: false, on_termination_credit_note: subscription&.on_termination_credit_note, on_termination_invoice: subscription&.on_termination_invoice)
      @subscription = subscription
      @async = async
      @rotation = rotation
      @on_termination_credit_note = on_termination_credit_note.blank? ? :credit : on_termination_credit_note.to_sym
      @on_termination_invoice = on_termination_invoice.blank? ? :generate : on_termination_invoice.to_sym

      super
    end

    def call
      return result.not_found_failure!(resource: "subscription") if subscription.blank?
      return result.not_allowed_failure!(code: "subscription_incomplete") if subscription.incomplete?

      ActiveRecord::Base.transaction do
        if subscription.pending?
          previous = subscription.previous_subscription
          subscription.mark_as_canceled!

          if previous
            SendWebhookJob.perform_after_commit("subscription.updated", previous)
            Utils::ActivityLog.produce_after_commit(previous, "subscription.updated")
          end
        elsif !subscription.terminated?
          subscription.mark_as_terminated!
          update_on_termination_actions!

          if subscription.should_sync_hubspot_subscription?
            Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob.perform_after_commit(subscription:)
          end

          if generate_credit_note_for_unconsumed_subscription?
            # NOTE: As subscription was payed in advance and terminated before the end of the period,
            #       we have to create a credit note for the days that were not consumed.
            #       Depending on the termination behaviour, we will optionally refund the portion of the unconsumed
            #       subscription that was already paid.

            if blocked_by_pending_taxes?
              result.not_allowed_failure!(code: "cannot_terminate_with_pending_taxes")
              result.raise_if_error!
            end

            CreditNotes::CreateFromTermination.call!(
              subscription:,
              reason: "order_cancellation",
              rotation: rotation,
              on_termination: on_termination_credit_note
            )
          end

          # NOTE: We should bill subscription and generate invoice for all cases except for a plan rotation
          #       (upgrade/downgrade). For a rotation we will create only one invoice for termination charges
          #       and for in advance charges. It is handled in subscriptions/create_service.rb
          bill_subscription unless rotation
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

      activation_result = Subscriptions::ActivateService.call!(
        subscription: next_subscription,
        timestamp: Time.zone.at(timestamp)
      )

      result.subscription = activation_result.subscription
      result
    end

    private

    attr_reader :subscription, :async, :rotation, :on_termination_credit_note, :on_termination_invoice

    def cancel_next_subscription
      # NOTE: Rotation path (upgrade/downgrade): next_subscription is the new subscription we just
      #       persisted, not a stale scheduled change
      return if rotation

      next_subscription = subscription.next_subscription
      return if next_subscription.nil?

      next_subscription.mark_as_canceled!
    end

    def bill_subscription
      if bill_in_arrears_fees?
        if async
          BillSubscriptionJob.perform_after_commit(
            [subscription],
            subscription.terminated_at,
            invoicing_reason: :subscription_terminating
          )
        else
          BillSubscriptionJob.perform_now(
            [subscription],
            subscription.terminated_at,
            invoicing_reason: :subscription_terminating
          )
        end
      end

      # We always bill pay-in-advance non-invoiceable charges unless it's an upgrade.
      if async
        BillNonInvoiceableFeesJob.perform_after_commit([subscription], subscription.terminated_at)
      else
        BillNonInvoiceableFeesJob.perform_now([subscription], subscription.terminated_at)
      end
    end

    # NOTE: If subscription is terminated automatically by setting ending_at, there is a chance that this service will
    #       be called before invoice for the period has been generated.
    #       In that case we do not want to issue a credit note.
    def pay_in_advance_invoice_issued?
      PayInAdvanceInvoiceIssuedService.call(subscription:, timestamp: subscription.terminated_at).issued
    end

    def generate_credit_note_for_unconsumed_subscription?
      pay_in_advance? &&
        pay_in_advance_invoice_issued? &&
        on_termination_credit_note.in?(%i[credit refund offset])
    end

    def pay_in_advance?
      subscription.plan.pay_in_advance?
    end

    def pay_in_arrears?
      !pay_in_advance?
    end

    def bill_in_arrears_fees?
      on_termination_invoice == :generate
    end

    def update_on_termination_actions!
      params = {}
      params[:on_termination_credit_note] = on_termination_credit_note if pay_in_advance? && subscription.on_termination_credit_note != on_termination_credit_note
      params[:on_termination_invoice] = on_termination_invoice if subscription.on_termination_invoice != on_termination_invoice
      return if params.empty?

      Subscriptions::UpdateService.call!(subscription:, params:)
    end

    def blocked_by_pending_taxes?
      subscription.last_subscription_fee&.invoice&.tax_pending? || false
    end
  end
end
