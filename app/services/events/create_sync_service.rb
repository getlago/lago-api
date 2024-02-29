# frozen_string_literal: true

module Events
  class CreateSyncService < CreateService
    def call
      event = Event.new
      event.organization_id = organization.id
      event.code = params[:code]
      event.transaction_id = params[:transaction_id]
      event.external_customer_id = params[:external_customer_id]
      event.external_subscription_id = params[:external_subscription_id]
      event.properties = params[:properties] || {}
      event.metadata = metadata || {}
      event.timestamp = Time.zone.at(params[:timestamp] ? params[:timestamp].to_f : timestamp)

      if is_charge_group?
        event.current_package_count = current_package_count
      end

      event.save!

      result.event = event

      produce_kafka_event(event)

      post_event_result = Events::PostProcessSyncService.call(event:)
      post_event_result.raise_if_error!
      result.invoices = post_event_result.invoices

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ActiveRecord::RecordNotUnique
      result.single_validation_failure!(field: :transaction_id, error_code: "value_already_exist")
    end

    def subscriptions
      @subscription ||= organization.subscriptions.where(external_id: params[:external_subscription_id])
    end

    def charge
      @charge ||= find_charge
    end
    
    def find_charge
      subscription = Subscription.find_by(external_id: params[:external_subscription_id])
      plan = subscription&.plan
      billable_metric = organization.billable_metrics.find_by(code: params[:code])
      
      Charge.where(plan: plan, billable_metric: billable_metric).first if plan && billable_metric
    end

    def is_charge_group?
      # NOTE: Currently there is only one type of charge group, 
      #       so we can just check if the charge is a package_group
      charge&.charge_model == 'package_group'
    end

    def current_package_count
      charge_group = charge&.charge_group
      subscription = Subscription.find_by(external_id: params[:external_subscription_id])
      
      usage_charge_group = UsageChargeGroup.find_by(charge_group_id: charge_group.id, subscription_id: subscription.id) if charge_group && subscription

      usage_charge_group&.current_package_count || 1
    end
  end
end
