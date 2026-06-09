# frozen_string_literal: true

module Plans
  module WebhookPayload
    PLAN_INCLUDES = %i[
      charges
      fixed_charges
      usage_thresholds
      taxes
      minimum_commitment
      entitlements
    ].freeze

    PLAN_ATTRIBUTES = %w[
      name
      invoice_display_name
      code
      interval
      description
      amount_cents
      amount_currency
      trial_period
      pay_in_advance
      bill_charges_monthly
      bill_fixed_charges_monthly
      parent_id
      pending_deletion
    ].freeze

    COMMON_IGNORED_KEYS = %w[created_at updated_at].freeze
    IDENTIFIER_KEYS = %w[lago_id code billable_metric_code add_on_code].freeze

    module_function

    def snapshot(plan)
      ::V1::PlanSerializer.new(
        plan.reload,
        includes: PLAN_INCLUDES
      ).serialize.deep_stringify_keys
    end

    def changes(previous:, current:)
      previous = (previous || {}).deep_stringify_keys
      current = (current || {}).deep_stringify_keys

      payload = {}
      append_if_present(payload, "plan", plan_changes(previous, current))
      append_if_present(
        payload,
        "charges",
        collection_changes(previous["charges"], current["charges"], identifier: "lago_id")
      )
      append_if_present(
        payload,
        "fixed_charges",
        collection_changes(previous["fixed_charges"], current["fixed_charges"], identifier: "lago_id")
      )
      append_if_present(
        payload,
        "taxes",
        collection_changes(previous["taxes"], current["taxes"], identifier: "lago_id")
      )
      append_if_present(
        payload,
        "usage_thresholds",
        collection_changes(previous["usage_thresholds"], current["usage_thresholds"], identifier: "lago_id")
      )
      append_if_present(
        payload,
        "minimum_commitment",
        single_resource_changes(previous["minimum_commitment"], current["minimum_commitment"])
      )
      append_if_present(payload, "metadata", metadata_changes(previous["metadata"], current["metadata"]))
      append_if_present(
        payload,
        "entitlements",
        entitlements_changes(previous["entitlements"], current["entitlements"])
      )
      payload
    end

    def updated_details_options(previous:, current_plan:)
      {
        changes: changes(
          previous: previous,
          current: snapshot(current_plan)
        )
      }
    end

    def plan_changes(previous, current)
      field_changes(previous.slice(*PLAN_ATTRIBUTES), current.slice(*PLAN_ATTRIBUTES))
    end

    def collection_changes(previous_items, current_items, identifier:)
      previous_items ||= []
      current_items ||= []

      previous_by_id = previous_items.index_by { |item| item.fetch(identifier).to_s }
      current_by_id = current_items.index_by { |item| item.fetch(identifier).to_s }

      payload = {}
      created_ids = current_by_id.keys - previous_by_id.keys
      deleted_ids = previous_by_id.keys - current_by_id.keys
      common_ids = previous_by_id.keys & current_by_id.keys

      created = created_ids.map { |id| resource_value(current_by_id[id], "current_value") }
      deleted = deleted_ids.map { |id| resource_value(previous_by_id[id], "previous_value") }
      updated = common_ids.filter_map do |id|
        item_changes = field_changes(previous_by_id[id], current_by_id[id], ignored_keys: COMMON_IGNORED_KEYS)
        next if item_changes.blank?

        resource_identifier(current_by_id[id]).merge("changes" => item_changes)
      end

      append_if_present(payload, "created", created)
      append_if_present(payload, "updated", updated)
      append_if_present(payload, "deleted", deleted)
      payload
    end

    def single_resource_changes(previous, current)
      if previous.blank? && current.blank?
        {}
      elsif previous.blank?
        {"created" => resource_value(current, "current_value")}
      elsif current.blank?
        {"deleted" => resource_value(previous, "previous_value")}
      else
        changes = field_changes(previous, current, ignored_keys: COMMON_IGNORED_KEYS)
        if changes.present?
          {"updated" => resource_identifier(current).merge("changes" => changes)}
        else
          {}
        end
      end
    end

    def metadata_changes(previous, current)
      field_changes(previous || {}, current || {})
    end

    def entitlements_changes(previous_items, current_items)
      previous_items ||= []
      current_items ||= []

      previous_by_code = previous_items.index_by { |item| item.fetch("code").to_s }
      current_by_code = current_items.index_by { |item| item.fetch("code").to_s }

      payload = {}
      created_codes = current_by_code.keys - previous_by_code.keys
      deleted_codes = previous_by_code.keys - current_by_code.keys
      common_codes = previous_by_code.keys & current_by_code.keys

      created = created_codes.map { |code| resource_value(current_by_code[code], "current_value") }
      deleted = deleted_codes.map { |code| resource_value(previous_by_code[code], "previous_value") }
      updated = common_codes.filter_map do |code|
        changes = entitlement_resource_changes(previous_by_code[code], current_by_code[code])
        next if changes.blank?

        {"code" => code, "changes" => changes}
      end

      append_if_present(payload, "created", created)
      append_if_present(payload, "updated", updated)
      append_if_present(payload, "deleted", deleted)
      payload
    end

    def entitlement_resource_changes(previous, current)
      changes = field_changes(
        previous.except("privileges"),
        current.except("privileges")
      )
      privileges = collection_changes(previous["privileges"], current["privileges"], identifier: "code")
      append_if_present(changes, "privileges", privileges)
      changes
    end

    def field_changes(previous, current, ignored_keys: [])
      previous = previous.deep_stringify_keys
      current = current.deep_stringify_keys
      ignored_keys = ignored_keys.map(&:to_s)

      ((previous.keys | current.keys) - ignored_keys).each_with_object({}) do |key, payload|
        before = previous[key]
        after = current[key]
        next if same_value?(before, after)

        payload[key] = {
          "previous_value" => before,
          "current_value" => after
        }
      end
    end

    def same_value?(previous, current)
      comparable_value(previous) == comparable_value(current)
    end

    def comparable_value(value)
      case value
      when Hash
        value.deep_stringify_keys.transform_values { |v| comparable_value(v) }
      when Array
        value.map { |v| comparable_value(v) }
      when BigDecimal
        value.to_s("F")
      else
        value
      end
    end

    def resource_value(resource, value_key)
      resource_identifier(resource).merge(value_key => resource)
    end

    def resource_identifier(resource)
      IDENTIFIER_KEYS.each_with_object({}) do |key, payload|
        payload[key] = resource[key] if resource.key?(key)
      end
    end

    def append_if_present(payload, key, value)
      payload[key] = value if value.present?
    end
  end
end
