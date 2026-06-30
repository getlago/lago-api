# frozen_string_literal: true

module PlanProductItems
  class CreateService < BaseService
    Result = BaseResult[:plan_product_item]

    def initialize(plan:, params:)
      @plan = plan
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "plan") unless plan

      product_item = organization.product_items.find_by(id: params[:product_item_id])
      return result.not_found_failure!(resource: "product_item") unless product_item

      rate_card = organization.rate_cards.find_by(id: params[:rate_card_id])
      return result.not_found_failure!(resource: "rate_card") unless rate_card

      if rate_card.product_item_id != product_item.id
        return result.single_validation_failure!(field: :rate_card_id, error_code: "does_not_match_product_item")
      end

      ActiveRecord::Base.transaction do
        plan_product_item = plan.plan_product_items.create!(
          organization:,
          product_item:,
          rate_card:,
          units: params[:units]
        )

        RatePhases::CreateService.call!(plan_product_item:, params: {position: 1})

        result.plan_product_item = plan_product_item
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :plan, :params

    def organization
      plan.organization
    end
  end
end
