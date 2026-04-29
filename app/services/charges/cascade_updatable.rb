# frozen_string_literal: true

module Charges
  module CascadeUpdatable
    extend ActiveSupport::Concern

    private

    def trigger_cascade(old_filters_attrs, old_parent_attrs: nil, old_applied_pricing_unit_attrs: nil)
      return unless cascade_updates
      return unless charge.children.exists?

      # Charge-level cascade only — filters are stripped from `params` and
      # cascaded individually below via per-filter jobs that don't contend
      # for the parent-level advisory lock.
      # TODO: drop `old_parent_filters_attrs:` after Sidekiq drain — dead, filter cascade goes through ChargeFilters::CascadeJob now.
      Charges::UpdateChildrenJob.perform_later(
        params: build_cascade_params.deep_stringify_keys,
        old_parent_attrs: old_parent_attrs || charge.attributes,
        old_parent_filters_attrs: old_filters_attrs.map { |f| f.slice(:id, :properties).deep_stringify_keys },
        old_parent_applied_pricing_unit_attrs: old_applied_pricing_unit_attrs || charge.applied_pricing_unit&.attributes
      )

      cascade_filter_changes(old_filters_attrs)
    end

    def cascade_filter_changes(old_filters_attrs)
      old_by_values = old_filters_attrs.index_by { |f| f[:values] }

      charge.filters.reset
      charge.filters.includes(values: :billable_metric_filter).unscope(:order).find_each do |filter|
        values = filter.to_h
        old = old_by_values.delete(values)

        ChargeFilters::CascadeJob.perform_later(
          charge.id,
          old ? "update" : "create",
          values.deep_stringify_keys,
          old&.dig(:properties)&.deep_stringify_keys,
          filter.properties.deep_stringify_keys,
          filter.invoice_display_name
        )
      end

      old_by_values.each_value do |old|
        ChargeFilters::CascadeJob.perform_later(
          charge.id,
          "destroy",
          old[:values].deep_stringify_keys,
          old[:properties]&.deep_stringify_keys,
          nil,
          old[:invoice_display_name]
        )
      end
    end

    def build_cascade_params
      {
        code: charge.code,
        charge_model: charge.charge_model,
        properties: charge.properties
      }
    end

    def capture_old_filters_attrs
      charge.filters.includes(values: :billable_metric_filter).map do |f|
        {id: f.id, properties: f.properties, invoice_display_name: f.invoice_display_name, values: f.to_h}
      end
    end

    def capture_old_applied_pricing_unit_attrs
      charge.applied_pricing_unit&.attributes
    end
  end
end
