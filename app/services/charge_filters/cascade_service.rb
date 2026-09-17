# frozen_string_literal: true

module ChargeFilters
  class CascadeService < BaseService
    Result = BaseResult

    # An update with nothing to identify the filter by would leave the override on the old
    # price with nobody the wiser, so it fails instead of guessing at the predicate.
    class MissingParentCode < StandardError; end

    # Two filters on one predicate leave nothing to choose between them, and adopting the plan's
    # code into one picked by row order would settle which of the two bills from then on.
    class DuplicatePredicate < StandardError; end

    def initialize(charge:, action:, filter_values:, old_properties: nil, new_properties: nil, invoice_display_name: nil, parent_code: nil)
      @charge = charge
      @action = action
      @filter_values = filter_values
      @old_properties = old_properties
      @new_properties = new_properties
      @invoice_display_name = invoice_display_name
      @parent_code = parent_code

      super
    end

    BATCH_SIZE = 1_000

    def call
      # Before the check below, so that a charge with nothing to cascade to stays quiet rather
      # than reporting a filter whose missing code is costing nothing
      return result if child_ids.empty?

      raise MissingParentCode, "charge #{charge.id} filter #{filter_values} has no code" if action == "update" && parent_code.blank?

      # NOTE: The cascade runs one job per changed filter
      # Each job has a single target (filter_values), so the matching child filter
      # is resolved for a whole batch of children in one query rather than loading
      # every child's full filter set, which keeps each job lightweight.
      child_ids.each_slice(BATCH_SIZE) do |ids|
        child_filters = child_filters_by_charge(ids)

        Charge.where(id: ids).includes(:billable_metric).find_each do |child_charge|
          Charge.no_touching do
            Plan.no_touching do
              child_filter = child_filters[child_charge.id]

              case action
              when "update" then update_child_filter(child_charge, child_filter)
              when "create" then create_child_filter(child_charge, child_filter)
              when "destroy" then destroy_child_filter(child_filter)
              end
            end
          end
        end
      end

      result
    end

    private

    attr_reader :charge, :action, :filter_values, :old_properties, :new_properties, :invoice_display_name, :parent_code

    def child_ids
      @child_ids ||= charge.children
        .joins(plan: :subscriptions)
        .where(subscriptions: {status: %w[active pending]})
        .distinct.pluck(:id)
    end

    # The code says which filter this is. The predicate is only a guess at it, and the
    # legacy path until every filter has a code — so it is asked about the children the
    # code could not reach, and about none once they all have one.
    def child_filters_by_charge(batch_child_ids)
      by_code = child_filters_holding_parent_code(batch_child_ids)

      # Only a create still guesses, and it has to: anything already sitting on the predicate
      # means there is nothing to add, and missing it would leave a duplicate. An update or a
      # destroy acts on one filter, where acting on the wrong one is worse than not acting.
      return by_code unless action == "create"

      remaining = batch_child_ids.reject { by_code.key?(it) }
      by_predicate = matching_child_filters(remaining)

      by_code.merge(by_predicate)
    end

    # Resolve the child filter matching filter_values for an entire batch of
    # children in two bounded queries: narrow candidates by a shared value via the
    # database, then confirm the exact match in Ruby. This avoids both loading each
    # child's full filter set (memory) and querying once per child (N+1).
    def matching_child_filters(batch_child_ids)
      return {} if batch_child_ids.empty?

      _key, values = filter_values.first
      return {} if values.blank?

      candidate_ids = ChargeFilter
        .where(charge_id: batch_child_ids)
        .joins(:values)
        .where("charge_filter_values.values && ARRAY[?]::varchar[]", values)
        .unscope(:order)
        .distinct
        .pluck(:id)
      return {} if candidate_ids.empty?

      matched = ChargeFilter
        .where(id: candidate_ids)
        .includes(values: :billable_metric_filter)
        .select { |filter| filter.to_h == filter_values }
        .group_by(&:charge_id)

      duplicated = matched.select { |_charge_id, filters| filters.many? }
      if duplicated.any?
        raise DuplicatePredicate, "charges #{duplicated.keys.join(", ")} hold #{filter_values} more than once"
      end

      matched.transform_values(&:first)
    end

    def child_filters_holding_parent_code(batch_child_ids)
      return {} if parent_code.blank?

      ChargeFilter
        .where(charge_id: batch_child_ids, code: parent_code)
        .index_by(&:charge_id)
    end

    def update_child_filter(child_charge, child_filter)
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

    def create_child_filter(child_charge, existing_filter)
      if existing_filter
        adopt_parent_code(existing_filter)
        return
      end

      # NOTE: Resolve against the current state of the billable metric filters
      # to avoid any changes that may have occurred since the job was enqueued
      return if resolved_filter_values.empty?

      ActiveRecord::Base.transaction do
        child_filter = child_charge.filters.new(
          organization_id: child_charge.organization_id,
          code: parent_code,
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

    # A filter already sitting on the predicate when the plan gains one is that filter's copy,
    # and this is the only moment we can say so. Left unlinked it is unreachable for good: an
    # update would raise and a destroy would pass it by, both for want of the code.
    #
    # A code of its own means the opposite — it was created on the override and is not a copy
    # of anything, so it keeps it.
    def adopt_parent_code(existing_filter)
      return if parent_code.blank? || existing_filter.code.present?

      existing_filter.update!(code: parent_code)
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

    def destroy_child_filter(child_filter)
      return unless child_filter

      child_filter.values.update_all(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      child_filter.discard!
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
