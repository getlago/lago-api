# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::FilterChargeModelPropertiesService, type: :service do
  subject(:filter_service) { described_class.new(charge:, properties:) }

  let(:charge_model) { nil }
  let(:billable_metric) { build(:billable_metric) }
  let(:charge) { build(:charge, charge_model:, billable_metric:) }

  let(:properties) do
    {
      amount: 100,
      grouped_by: %w[location],
      graduated_ranges: [{from_value: 0, to_value: 100, per_unit_amount: '2', flat_amount: '1'}],
      graduated_percentage_ranges: [{from_value: 0, to_value: 100, percentage: '2'}],
      free_units: 10,
      package_size: 10,
      rate: '0.0555',
      fixed_amount: '2',
      free_units_per_events: 10,
      free_units_per_total_aggregation: 10,
      per_transaction_max_amount: 100,
      per_transaction_min_amount: 10,
      volume_ranges: [{from_value: 0, to_value: 100, per_unit_amount: '2', flat_amount: '1'}],
      custom_properties: {rate: '20'}
    }
  end

  describe '#call' do
    context 'without charge_model' do
      it 'returns empty hash' do
        expect(filter_service.call.properties).to eq({})
      end
    end

    context 'with standard charge_model' do
      let(:charge_model) { 'standard' }

      it { expect(filter_service.call.properties.keys).to include('amount', 'grouped_by') }

      context 'when grouped_by contains empty string' do
        let(:properties) { {amount: 100, grouped_by: ['', '']} }

        it { expect(filter_service.call.properties[:grouped_by]).to be_empty }
      end
    end

    context 'with graduated charge_model' do
      let(:charge_model) { 'graduated' }

      it { expect(filter_service.call.properties.keys).to include('graduated_ranges') }
    end

    context 'with graduated_percentage charge_model' do
      let(:charge_model) { 'graduated_percentage' }

      it { expect(filter_service.call.properties.keys).to include('graduated_percentage_ranges') }
    end

    context 'with package charge_model' do
      let(:charge_model) { 'package' }

      it { expect(filter_service.call.properties.keys).to include('amount', 'free_units', 'package_size') }
    end

    context 'with percentage charge_model' do
      let(:charge_model) { 'percentage' }

      it do
        expect(filter_service.call.properties.keys).to include(
          'rate',
          'fixed_amount',
          'free_units_per_events',
          'free_units_per_total_aggregation',
          'per_transaction_max_amount',
          'per_transaction_min_amount',
        )
      end
    end

    context 'with volume charge_model' do
      let(:charge_model) { 'volume' }

      it { expect(filter_service.call.properties.keys).to include('volume_ranges') }
    end

    context 'with custom billable metric' do
      let(:billable_metric) { build(:custom_billable_metric) }

      it { expect(filter_service.call.properties.keys).to include('custom_properties') }
    end
  end
end
