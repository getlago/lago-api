# frozen_string_literal: true

module Charges
  module CascadeUpdatable
    extend ActiveSupport::Concern

    private

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
        code: charge.code,
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

    def capture_old_filters_attrs
      charge.filters.map { |f| {id: f.id, properties: f.properties} }
    end

    def capture_old_applied_pricing_unit_attrs
      charge.applied_pricing_unit&.attributes
    end
  end
end
