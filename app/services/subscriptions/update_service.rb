# frozen_string_literal: true

module Subscriptions
  class UpdateService < BaseService
    Result = BaseResult[:subscription, :payment_method]

    def initialize(subscription:, params:)
      @subscription = subscription
      @params = params
      super
    end

    activity_loggable(
      action: "subscription.updated",
      record: -> { subscription },
      condition: -> { !subscription&.starting_in_the_future? },
      after_commit: true
    )

    def call
      return result.not_found_failure!(resource: "subscription") unless subscription

      unless valid?(
        customer: subscription.customer,
        plan: subscription.plan,
        subscription_at: params.key?(:subscription_at) ? params[:subscription_at] : subscription.subscription_at,
        ending_at: params[:ending_at],
        on_termination_credit_note: params[:on_termination_credit_note],
        on_termination_invoice: params[:on_termination_invoice],
        payment_method: params[:payment_method]
      )
        return result
      end

      return result.forbidden_failure! if !License.premium? && params.key?(:plan_overrides)

      ActiveRecord::Base.transaction do
        subscription.name = params[:name] if params.key?(:name)
        subscription.ending_at = params[:ending_at] if params.key?(:ending_at)

        if pay_in_advance? && params.key?(:on_termination_credit_note)
          subscription.on_termination_credit_note = params[:on_termination_credit_note]
        end

        if params.key?(:on_termination_invoice)
          subscription.on_termination_invoice = params[:on_termination_invoice]
        end

        if params.key?(:payment_method)
          subscription.payment_method_type = params[:payment_method][:payment_method_type] if params[:payment_method].key?(:payment_method_type)
          subscription.payment_method_id = params[:payment_method][:payment_method_id] if params[:payment_method].key?(:payment_method_id)
        end

        if params.key?(:activation_rules)
          if subscription.activating?
            if params[:activation_rules].present?
              return result.single_validation_failure!(
                field: :activation_rules,
                error_code: "cannot_be_modified_while_activating"
              )
            end

            handle_activation_rules_removal
            result.subscription = subscription
            return result
          else
            subscription.activation_rules = params[:activation_rules]
          end
        end

        subscription.plan = handle_plan_override.plan if params.key?(:plan_overrides)

        if subscription.starting_in_the_future? && params.key?(:subscription_at)
          subscription.subscription_at = params[:subscription_at]

          process_subscription_at_change(subscription)
        else
          subscription.save!

          if subscription.active? && subscription.fixed_charges.pay_in_advance.any? && subscription.plan_id_previously_changed?
            Invoices::CreatePayInAdvanceFixedChargesJob.perform_after_commit(subscription, Time.current.to_i)
          end

          SendWebhookJob.perform_after_commit("subscription.updated", subscription)

          if subscription.should_sync_hubspot_subscription?
            Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob.perform_after_commit(subscription:)
          end
        end

        InvoiceCustomSections::AttachToResourceService.call(resource: subscription, params:)
      end

      result.subscription = subscription
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :subscription, :params

    def pay_in_advance?
      subscription.plan.pay_in_advance?
    end

    def process_subscription_at_change(subscription)
      if subscription.subscription_at <= Time.current
        subscription.mark_as_active!(subscription.subscription_at)

        EmitFixedChargeEventsService.call!(
          subscriptions: [subscription],
          timestamp: subscription.started_at + 1.second
        )

        if subscription.subscription_at.today?
          if subscription.plan.pay_in_advance?
            BillSubscriptionJob.perform_after_commit([subscription], Time.current.to_i, invoicing_reason: :subscription_starting)
          elsif subscription.fixed_charges.pay_in_advance.any?
            Invoices::CreatePayInAdvanceFixedChargesJob.perform_after_commit(subscription, subscription.started_at + 1.second)
          end
        end
      else
        subscription.save!
      end
    end

    def handle_plan_override
      current_plan = subscription.plan

      if current_plan.parent_id
        Plans::UpdateService.call!(
          plan: current_plan,
          params: params[:plan_overrides].to_h.with_indifferent_access
        )
      else
        Plans::OverrideService.call!(
          plan: current_plan,
          params: params[:plan_overrides].to_h.with_indifferent_access,
          subscription:
        )
      end
    end

    def valid?(args)
      result.payment_method = payment_method

      Subscriptions::ValidateService.new(result, **args).valid?
    end

    def payment_method
      return @payment_method if defined? @payment_method
      return nil if params[:payment_method].blank? || params[:payment_method][:payment_method_id].blank?

      @payment_method = PaymentMethod.find_by(id: params[:payment_method][:payment_method_id], organization_id: subscription.organization_id)
    end

    def handle_activation_rules_removal
      invoice = subscription.invoices.order(created_at: :desc).first

      subscription.activation_rules = nil
      subscription.activating_at = nil
      subscription.active!

      if invoice
        finalize_activation_invoice(invoice)

        after_commit do
          Subscriptions::Payments::CancelService.call(invoice:)

          SendWebhookJob.perform_later("invoice.created", invoice)
          Utils::ActivityLog.produce(invoice, "invoice.created")
          Invoices::GenerateDocumentsJob.perform_later(invoice:, notify: should_deliver_finalized_email?)
          Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:) if invoice.should_sync_invoice?
          Integrations::Aggregator::Invoices::Hubspot::CreateJob.perform_later(invoice:) if invoice.should_sync_hubspot_invoice?
          Invoices::Payments::CreateService.call_async(invoice:)
          Utils::SegmentTrack.invoice_created(invoice)
        end
      end

      if subscription.previous_subscription.present?
        Subscriptions::TerminateService.call(
          subscription: subscription.previous_subscription,
          upgrade: true
        )
      end

      after_commit do
        SendWebhookJob.perform_later("subscription.started", subscription)
        Utils::ActivityLog.produce(subscription, "subscription.started")
      end
    end

    def finalize_activation_invoice(invoice)
      invoice.issuing_date = Time.current.in_time_zone(subscription.customer.applicable_timezone).to_date
      invoice.payment_due_date = invoice.issuing_date + invoice.net_payment_term.days
      Invoices::FinalizeService.call!(invoice:)
    end

    def should_deliver_finalized_email?
      License.premium? && subscription.customer.billing_entity.email_settings.include?("invoice.finalized")
    end
  end
end
