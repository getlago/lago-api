# frozen_string_literal: true

module ProductFilters
  class UpdateService < BaseService
    Result = BaseResult[:product_filter]

    def initialize(product_filter:, params:)
      @product_filter = product_filter
      @params = params.to_h.with_indifferent_access
      super
    end

    activity_loggable(
      action: "product_filter.updated",
      record: -> { product_filter }
    )

    def call
      return result.not_found_failure!(resource: "product_filter") unless product_filter

      if params.key?(:values)
        return resolved_values unless resolved_values.success?
      end

      # NOTE: the code freezes as soon as the item is in a plan or subscription
      #       (it is the filter's identity); the values only freeze once a
      #       subscription bills through a card scoped to this filter. Clients
      #       typically resend the whole payload on edit, so only an actual
      #       change counts as a structural edit.
      if product_filter.attached_to_plan_or_subscription? &&
          params.key?(:code) && params[:code] != product_filter.code
        return result.single_validation_failure!(field: :code, error_code: "attached_to_plan_or_subscription")
      end

      if product_filter.attached_to_subscriptions? && params.key?(:values) && values_changed?
        return result.single_validation_failure!(field: :values, error_code: "attached_to_subscriptions")
      end

      if params.key?(:values)
        values_validation = ProductFilters::ValidateValuesService.call(
          product: product_filter.product,
          values_params: resolved_values.values_params,
          product_filter:
        )
        return values_validation unless values_validation.success?
      end

      ActiveRecord::Base.transaction do
        product_filter.name = params[:name] if params.key?(:name)
        product_filter.description = params[:description] if params.key?(:description)
        product_filter.invoice_display_name = params[:invoice_display_name] if params.key?(:invoice_display_name)
        product_filter.code = params[:code] if params.key?(:code)
        product_filter.save!

        replace_values if params.key?(:values) && values_changed?

        result.product_filter = product_filter
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      if e.record.is_a?(ProductFilterValue)
        errors = e.record.errors.messages.transform_keys { |key| :"values.#{key}" }
        result.validation_failure!(errors:)
      else
        result.record_validation_failure!(record: e.record)
      end
    end

    private

    attr_reader :product_filter, :params

    # value.to_s keeps key-only entries (nil) sortable next to valued entries
    # for the same key — nil <=> String raises. It cannot conflate distinct
    # entries: an empty-string value is invalid, so "" only ever means nil.
    def values_changed?
      current = product_filter.values.map { |value| [value.billable_metric_filter_id.to_s, value.value.to_s] }.sort
      submitted = resolved_values.values_params.map { |value| [value[:billable_metric_filter_id].to_s, value[:value].to_s] }.sort

      current != submitted
    end

    def resolved_values
      @resolved_values ||= ProductFilters::ResolveValuesService.call(
        product: product_filter.product,
        values_params: params[:values]
      )
    end

    def replace_values
      product_filter.values.discard_all!

      resolved_values.values_params.each do |value_params|
        product_filter.values.create!(
          organization_id: product_filter.organization_id,
          billable_metric_filter_id: value_params[:billable_metric_filter_id],
          value: value_params[:value]
        )
      end
    end
  end
end
