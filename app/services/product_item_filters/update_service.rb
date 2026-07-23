# frozen_string_literal: true

module ProductItemFilters
  class UpdateService < BaseService
    Result = BaseResult[:product_item_filter]

    def initialize(product_item_filter:, params:)
      @product_item_filter = product_item_filter
      @params = params.to_h.with_indifferent_access
      super
    end

    activity_loggable(
      action: "product_item_filter.updated",
      record: -> { product_item_filter }
    )

    def call
      return result.not_found_failure!(resource: "product_item_filter") unless product_item_filter

      if params.key?(:values)
        return resolved_values unless resolved_values.success?
      end

      # NOTE: the code freezes as soon as the item is in a plan or subscription
      #       (it is the filter's identity); the values only freeze once a
      #       subscription bills through a card scoped to this filter. Clients
      #       typically resend the whole payload on edit, so only an actual
      #       change counts as a structural edit.
      if product_item_filter.attached_to_plan_or_subscription? &&
          params.key?(:code) && params[:code] != product_item_filter.code
        return result.single_validation_failure!(field: :code, error_code: "attached_to_plan_or_subscription")
      end

      if product_item_filter.attached_to_subscriptions? && params.key?(:values) && values_changed?
        return result.single_validation_failure!(field: :values, error_code: "attached_to_subscriptions")
      end

      if params.key?(:values)
        values_validation = ProductItemFilters::ValidateValuesService.call(
          product_item: product_item_filter.product_item,
          values_params: resolved_values.values_params
        )
        return values_validation unless values_validation.success?
      end

      ActiveRecord::Base.transaction do
        product_item_filter.name = params[:name] if params.key?(:name)
        product_item_filter.description = params[:description] if params.key?(:description)
        product_item_filter.invoice_display_name = params[:invoice_display_name] if params.key?(:invoice_display_name)
        product_item_filter.code = params[:code] if params.key?(:code)
        product_item_filter.save!

        replace_values if params.key?(:values) && values_changed?

        result.product_item_filter = product_item_filter
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      if e.record.is_a?(ProductItemFilterValue)
        errors = e.record.errors.messages.transform_keys { |key| :"values.#{key}" }
        result.validation_failure!(errors:)
      else
        result.record_validation_failure!(record: e.record)
      end
    end

    private

    attr_reader :product_item_filter, :params

    def values_changed?
      current = product_item_filter.values.map { |value| [value.billable_metric_filter_id, value.value] }.sort
      submitted = resolved_values.values_params.map { |value| [value[:billable_metric_filter_id], value[:value]] }.sort

      current != submitted
    end

    def resolved_values
      @resolved_values ||= ProductItemFilters::ResolveValuesService.call(
        product_item: product_item_filter.product_item,
        values_params: params[:values]
      )
    end

    def replace_values
      product_item_filter.values.discard_all!

      resolved_values.values_params.each do |value_params|
        product_item_filter.values.create!(
          organization_id: product_item_filter.organization_id,
          billable_metric_filter_id: value_params[:billable_metric_filter_id],
          value: value_params[:value]
        )
      end
    end
  end
end
