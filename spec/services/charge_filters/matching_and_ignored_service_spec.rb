# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChargeFilters::MatchingAndIgnoredService do
  subject(:service) { described_class.call(filter: filter1) }

  let(:payment_method) { create(:billable_metric_filter, key: 'payment_method', values: %i[card transfer]) }
  let(:card_location) { create(:billable_metric_filter, key: 'card_location', values: %i[domestic]) }
  let(:scheme) { create(:billable_metric_filter, key: 'scheme', values: %i[visa mastercard]) }
  let(:card_type) { create(:billable_metric_filter, key: 'card_type', values: %i[credit debit]) }

  let(:filter1) { create(:charge_filter) }
  let(:filter1_values) do
    [
      create(:charge_filter_value, value: 'card', billable_metric_filter: payment_method, charge_filter: filter1),
      create(:charge_filter_value, value: 'domestic', billable_metric_filter: card_location, charge_filter: filter1),
      create(:charge_filter_value, value: 'visa', billable_metric_filter: scheme, charge_filter: filter1),
    ]
  end

  let(:filter2) { create(:charge_filter, charge: filter1.charge) }
  let(:filter2_values) do
    [
      create(:charge_filter_value, value: 'card', billable_metric_filter: payment_method, charge_filter: filter2),
      create(:charge_filter_value, value: 'domestic', billable_metric_filter: card_location, charge_filter: filter2),
      create(:charge_filter_value, value: 'visa', billable_metric_filter: scheme, charge_filter: filter2),
      create(:charge_filter_value, value: 'credit', billable_metric_filter: card_type, charge_filter: filter2),
    ]
  end

  before do
    filter1_values
    filter2_values
  end

  it 'returns a formatted hash', :aggregate_failures do
    expect(service.matching_filters).to eq(
      {
        'payment_method' => 'card',
        'card_location' => 'domestic',
        'scheme' => 'visa',
      },
    )

    expect(service.ignored_filters).to eq(
      { 'card_type' => 'credit' },
    )
  end
end
