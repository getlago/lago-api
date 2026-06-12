# frozen_string_literal: true

module RateCards
  class CreateService < BaseService
    Result = BaseResult[:rate_card]

    def initialize(product_item:, params:)
      @product_item = product_item
      @params = params.to_h.with_indifferent_access
      super
    end

    activity_loggable(
      action: "rate_card.created",
      record: -> { result.rate_card }
    )

    def call
      return result.not_found_failure!(resource: "product_item") unless product_item

      product_item_filter = nil
      if params[:product_item_filter_id].present?
        product_item_filter = product_item.filters.find_by(id: params[:product_item_filter_id])
        return result.not_found_failure!(resource: "product_item_filter") unless product_item_filter
      end

      if params[:wallet_targetable] && !organization.events_targeting_wallets_enabled?
        return result.single_validation_failure!(field: :wallet_targetable, error_code: "feature_unavailable")
      end

      if params[:applied_pricing_unit_code].present? && !organization.pricing_units.exists?(code: params[:applied_pricing_unit_code])
        return result.single_validation_failure!(field: :applied_pricing_unit_code, error_code: "value_is_invalid")
      end

      ActiveRecord::Base.transaction do
        rate_card = product_item.rate_cards.create!(
          organization:,
          product_item_filter:,
          name: params[:name],
          code: params[:code]&.strip,
          description: params[:description],
          currency: params[:currency],
          billing_timing: params[:billing_timing] || "arrears",
          proration: params[:proration] || "full",
          display_on_invoice: params.fetch(:display_on_invoice, true),
          regroup_paid_fees: params[:regroup_paid_fees],
          applied_pricing_unit_code: params[:applied_pricing_unit_code],
          wallet_targetable: params[:wallet_targetable]
        )

        create_rates(rate_card)

        result.rate_card = rate_card
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      # Only the nested rate creations are called with call! here.
      if e.result.error.is_a?(BaseService::ValidationFailure)
        errors = e.result.error.messages.transform_keys { |key| :"rates.#{key}" }
        result.validation_failure!(errors:)
      else
        e.result
      end
    end

    private

    attr_reader :product_item, :params

    def organization
      product_item.organization
    end

    def create_rates(rate_card)
      (params[:rates] || []).each do |rate_params|
        RateCardRates::CreateService.call!(rate_card:, params: rate_params, emit_activity_log: false)
      end
    end
  end
end
