# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChargeFilters::MatchingAndIgnoredService do
  subject(:service) { described_class.call(filter: filter1) }

  let(:payment_method) do
    create(:billable_metric_filter, key: 'payment_method', values: %i[card virtual_card transfer])
  end
  let(:card_location) { create(:billable_metric_filter, key: 'card_location', values: %i[domestic]) }
  let(:scheme) { create(:billable_metric_filter, key: 'scheme', values: %i[visa mastercard]) }
  let(:card_type) { create(:billable_metric_filter, key: 'card_type', values: %i[credit debit]) }

  let(:filter1) { create(:charge_filter) }
  let(:filter1_values) do
    [
      create(:charge_filter_value, values: ['card'], billable_metric_filter: payment_method, charge_filter: filter1),
      create(:charge_filter_value, values: ['domestic'], billable_metric_filter: card_location, charge_filter: filter1),
      create(
        :charge_filter_value,
        values: %w[visa mastercard],
        billable_metric_filter: scheme,
        charge_filter: filter1,
      ),
    ]
  end

  let(:filter2) { create(:charge_filter, charge: filter1.charge) }
  let(:filter2_values) do
    [
      create(:charge_filter_value, values: ['card'], billable_metric_filter: payment_method, charge_filter: filter2),
      create(:charge_filter_value, values: ['domestic'], billable_metric_filter: card_location, charge_filter: filter2),
      create(
        :charge_filter_value,
        values: %w[visa mastercard],
        billable_metric_filter: scheme,
        charge_filter: filter2,
      ),
      create(:charge_filter_value, values: ['credit'], billable_metric_filter: card_type, charge_filter: filter2),
    ]
  end

  before do
    filter1_values
    filter2_values
  end

  it 'returns a formatted hash', :aggregate_failures do
    expect(service.matching_filters).to eq(
      {
        'payment_method' => ['card'],
        'card_location' => ['domestic'],
        'scheme' => %w[visa mastercard],
      },
    )

    expect(service.ignored_filters).to eq(
      [{ 'card_type' => ['credit'] }],
    )
  end

  context 'when filter does not have children' do
    subject(:service) { described_class.call(filter: filter2) }

    it 'returns a formatted hash', :aggregate_failures do
      expect(service.matching_filters).to eq(
        {
          'payment_method' => ['card'],
          'card_location' => ['domestic'],
          'scheme' => %w[visa mastercard],
          'card_type' => ['credit'],
        },
      )

      expect(service.ignored_filters).to eq([])
    end
  end

  context 'when provided filter is empty' do
    subject(:service) { described_class.call(filter: ChargeFilter.new(charge: filter1.charge)) }

    it 'returns all filter values as ignored filters' do
      expect(service.matching_filters).to eq({})
      expect(service.ignored_filters).to eq(
        [
          {
            'payment_method' => ['card'],
            'card_location' => ['domestic'],
            'scheme' => %w[visa mastercard],
          },
          {
            'payment_method' => ['card'],
            'card_location' => ['domestic'],
            'scheme' => %w[visa mastercard],
            'card_type' => ['credit'],
          },
        ],
      )
    end
  end

  context 'when filter has children that only match part of the values' do
    let(:filter1_values) do
      [
        create(
          :charge_filter_value,
          values: %w[card virtual_card],
          billable_metric_filter: payment_method,
          charge_filter: filter1,
        ),
      ]
    end

    let(:filter2_values) do
      [
        create(
          :charge_filter_value,
          values: %w[card],
          billable_metric_filter: payment_method,
          charge_filter: filter2,
        ),
        create(
          :charge_filter_value,
          values: %w[visa],
          billable_metric_filter: scheme,
          charge_filter: filter2,
        ),
      ]
    end

    it 'returns a formatted hash', :aggregate_failures do
      expect(service.matching_filters).to eq(
        {
          'payment_method' => %w[card virtual_card],
        },
      )

      expect(service.ignored_filters).to eq(
        [
          {
            'payment_method' => ['card'],
            'scheme' => ['visa'],
          },
        ],
      )
    end
  end
end
