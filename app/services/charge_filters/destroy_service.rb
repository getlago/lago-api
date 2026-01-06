# frozen_string_literal: true

module ChargeFilters
  class DestroyService < BaseService
    Result = BaseResult[:charge_filter]

    def initialize(charge_filter:, cascade_updates: false)
      @charge_filter = charge_filter
      @cascade_updates = cascade_updates

      super
    end

    def call
      return result.not_found_failure!(resource: "charge_filter") unless charge_filter

      old_filters_attrs = charge.filters.map { |f| {id: f.id, properties: f.properties} }

      ActiveRecord::Base.transaction do
        charge_filter.values.update_all(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        charge_filter.discard!

        result.charge_filter = charge_filter
      end

      trigger_cascade(old_filters_attrs)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :charge_filter, :cascade_updates

    delegate :charge, to: :charge_filter

    def trigger_cascade(old_filters_attrs)
      return unless cascade_updates
      return unless charge.children.exists?

      Charges::UpdateChildrenJob.perform_later(
        params: build_cascade_params.deep_stringify_keys,
        old_parent_attrs: charge.attributes,
        old_parent_filters_attrs: old_filters_attrs.map(&:deep_stringify_keys),
        old_parent_applied_pricing_unit_attrs: charge.applied_pricing_unit&.attributes
      )
    end

    def build_cascade_params
      {
        charge_model: charge.charge_model,
        properties: charge.properties,
        filters: charge.filters.reload.map do |f|
          {
            invoice_display_name: f.invoice_display_name,
            properties: f.properties,
            values: f.to_h
          }
        end
      }
    end
  end
end
