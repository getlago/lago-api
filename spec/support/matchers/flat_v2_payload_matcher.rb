# frozen_string_literal: true

# A v2 record without embedded records, lists or counts, as rendered without `expand`.
# The listed values define the record itself, so they stay inline. The counts are named
# one by one: `billing_interval_count` and `billing_interval_cycle_count` are fields.
# It takes one record and fails on anything else, so a list goes through `all(...)`.
RSpec::Matchers.define :be_a_flat_v2_payload do
  inline_keys = %w[rate_properties values rate_override]
  count_keys = %w[
    rates_count filters_count products_count applied_rate_cards_count rate_phases_count
    add_ons_count customers_count plans_count charges_count commitments_count
  ]

  match do |payload|
    next false unless payload.is_a?(Hash)

    @offending_keys = payload.filter_map do |key, value|
      key = key.to_s
      key if count_keys.include?(key) || (!inline_keys.include?(key) && (value.is_a?(Hash) || value.is_a?(Array)))
    end

    @offending_keys.empty?
  end

  failure_message do |payload|
    if payload.is_a?(Hash)
      "expected a flat v2 payload, but #{@offending_keys.inspect} are nested records, lists or counts in #{payload.inspect}"
    else
      "expected a flat v2 payload, but got #{payload.inspect}, which is not one record"
    end
  end
end
