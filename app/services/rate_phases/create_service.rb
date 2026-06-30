# frozen_string_literal: true

module RatePhases
  class CreateService < BaseService
    Result = BaseResult[:rate_phase]

    def initialize(plan_product_item: nil, subscription_product_item: nil, params: {})
      @plan_product_item = plan_product_item
      @subscription_product_item = subscription_product_item
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      parent = plan_product_item || subscription_product_item
      return result.not_found_failure!(resource: "rate_phaseable") unless parent

      rate_phase = RatePhase.create!(
        organization: parent.organization,
        plan_product_item:,
        subscription_product_item:,
        position: params[:position],
        billing_interval_cycle_count: params[:billing_interval_cycle_count],
        name: params[:name]
      )

      result.rate_phase = rate_phase
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :plan_product_item, :subscription_product_item, :params
  end
end
