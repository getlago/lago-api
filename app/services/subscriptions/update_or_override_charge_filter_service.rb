# frozen_string_literal: true

module Subscriptions
  class UpdateOrOverrideChargeFilterService < BaseService
    Result = BaseResult[:charge_filter]

    def initialize(subscription:, charge:, charge_filter:, params:)
      @subscription = subscription
      @charge = charge
      @charge_filter = charge_filter
      @params = params

      super
    end

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "subscription") unless subscription
      return result.not_found_failure!(resource: "charge") unless charge
      return result.not_found_failure!(resource: "charge_filter") unless charge_filter

      ActiveRecord::Base.transaction do
        target_plan = ensure_plan_override
        target_charge = find_or_create_charge_override(target_plan)
        target_filter = find_or_create_filter_override(target_charge)

        result.charge_filter = target_filter
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :subscription, :charge, :charge_filter, :params

    def ensure_plan_override
      current_plan = subscription.plan

      if current_plan.parent_id
        current_plan
      else
        override_result = Plans::OverrideService.call!(
          plan: current_plan,
          params: {},
          subscription:
        )
        subscription.update!(plan: override_result.plan)
        override_result.plan
      end
    end

    def find_or_create_charge_override(target_plan)
      parent_charge = find_parent_charge
      existing_override = target_plan.charges.find_by(parent_id: parent_charge.id)

      if existing_override
        existing_override
      else
        override_result = Charges::OverrideService.call!(
          charge: parent_charge,
          params: {plan_id: target_plan.id}
        )
        override_result.charge
      end
    end

    def find_parent_charge
      if charge.parent_id
        charge.parent
      else
        charge
      end
    end

    def find_or_create_filter_override(target_charge)
      filter_values_hash = charge_filter.to_h
      existing_filter = find_filter_by_values(target_charge, filter_values_hash)

      if existing_filter
        update_filter(existing_filter)
      else
        create_filter_override(target_charge, filter_values_hash)
      end
    end

    def find_filter_by_values(target_charge, filter_values_hash)
      target_charge.filters.find { |f| f.to_h.sort == filter_values_hash.sort }
    end

    def create_filter_override(target_charge, filter_values_hash)
      create_result = ChargeFilters::CreateService.call!(
        charge: target_charge,
        params: {
          values: filter_values_hash,
          properties: params[:properties] || charge_filter.properties,
          invoice_display_name: params[:invoice_display_name] || charge_filter.invoice_display_name
        }
      )
      create_result.charge_filter
    end

    def update_filter(existing_filter)
      existing_filter.properties = filtered_properties if params.key?(:properties)
      existing_filter.invoice_display_name = params[:invoice_display_name] if params.key?(:invoice_display_name)
      existing_filter.save!

      existing_filter.reload
    end

    def filtered_properties
      ChargeModels::FilterPropertiesService.call(
        chargeable: charge,
        properties: params[:properties]
      ).properties
    end
  end
end
