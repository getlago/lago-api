# frozen_string_literal: true

module ChargeFilters
  class CascadeService < BaseService
    Result = BaseResult

    def initialize(charge:, action:, filter_values:, old_properties: nil, new_properties: nil, invoice_display_name: nil)
      @charge = charge
      @action = action
      @filter_values = filter_values
      @old_properties = old_properties
      @new_properties = new_properties
      @invoice_display_name = invoice_display_name

      super
    end

    def call
      charge.children
        .joins(plan: :subscriptions)
        .where(subscriptions: {status: %w[active pending]})
        .distinct.find_each do |child_charge|
          Charge.no_touching do
            Plan.no_touching do
              case action
              when "update" then update_child_filter(child_charge)
              when "create" then create_child_filter(child_charge)
              when "destroy" then destroy_child_filter(child_charge)
              end
            end
          end
        end

      result
    end

    private

    attr_reader :charge, :action, :filter_values, :old_properties, :new_properties, :invoice_display_name

    def update_child_filter(child_charge)
      child_filter = find_child_filter(child_charge)
      return unless child_filter

      if filter_customized?(child_filter)
        cascade_group_keys(child_filter)
        child_filter.save! if child_filter.changed?
        return
      end

      child_filter.properties = ChargeModels::FilterPropertiesService.call(
        chargeable: child_charge,
        properties: new_properties
      ).properties
      child_filter.invoice_display_name = invoice_display_name
      child_filter.save!
    end

    def create_child_filter(child_charge)
      return if find_child_filter(child_charge)

      # NOTE: Resolve against the current state of the billable metric filters
      # to avoid any changes that may have occurred since the job was enqueued
      return if resolved_filter_values.empty?

      ActiveRecord::Base.transaction do
        child_filter = child_charge.filters.new(
          organization_id: child_charge.organization_id,
          invoice_display_name:,
          properties: ChargeModels::FilterPropertiesService.call(
            chargeable: child_charge,
            properties: new_properties
          ).properties
        )
        child_filter.save!

        resolved_filter_values.each do |billable_metric_filter, values|
          child_filter.values.create!(
            billable_metric_filter_id: billable_metric_filter.id,
            organization_id: child_charge.organization_id,
            values:
          )
        end
      end
    end

    def resolved_filter_values
      @resolved_filter_values ||= filter_values.filter_map do |key, values|
        billable_metric_filter = billable_metric_filters_by_key[key]
        next if billable_metric_filter.nil?

        valid_values = values & billable_metric_filter.values
        next if valid_values.empty?

        [billable_metric_filter, valid_values]
      end
    end

    def billable_metric_filters_by_key
      @billable_metric_filters_by_key ||= charge.billable_metric.filters
        .where(key: filter_values.keys)
        .index_by(&:key)
    end

    def destroy_child_filter(child_charge)
      child_filter = find_child_filter(child_charge)
      return unless child_filter

      child_filter.values.update_all(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      child_filter.discard!
    end

    def find_child_filter(child_charge)
      child_charge.filters.includes(values: :billable_metric_filter).find do |f|
        f.to_h == filter_values
      end
    end

    def filter_customized?(child_filter)
      return false unless old_properties

      normalize_properties(old_properties) != normalize_properties(child_filter.properties)
    end

    # Cascade group keys even for customized filters — group keys are structural
    # (they affect how events are bucketed), not pricing overrides.
    def cascade_group_keys(child_filter)
      pricing_group_keys = new_properties&.dig("pricing_group_keys") || new_properties&.dig("grouped_by")
      if pricing_group_keys
        child_filter.properties["pricing_group_keys"] = pricing_group_keys
        child_filter.properties.delete("grouped_by")
      elsif child_filter.pricing_group_keys.present?
        child_filter.properties.delete("pricing_group_keys")
        child_filter.properties.delete("grouped_by")
      end
    end

    def normalize_properties(props)
      return props unless props.is_a?(Hash)

      props.transform_values do |v|
        (v.is_a?(String) && v.match?(/\A-?\d+(\.\d+)?\z/)) ? v.to_f : v
      end
    end
  end
end
