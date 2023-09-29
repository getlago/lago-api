# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::ChargeModels::ProratedGraduatedService, type: :service do
  subject(:apply_graduated_service) do
    described_class.apply(
      charge:,
      aggregation_result:,
      properties: charge.properties,
    )
  end

  let(:aggregation_result) { BaseService::Result.new }
  let(:billable_metric) { create(:sum_billable_metric, recurring: true) }
  let(:aggregation) { 5.96667 }
  let(:aggregator) do
    BillableMetrics::ProratedAggregations::SumService.new(billable_metric:, subscription: nil, boundaries: nil)
  end
  let(:per_event_aggregation) do
    BaseService::Result.new.tap do |r|
      r.event_aggregation = [5, 5, 10, -6]
      r.event_prorated_aggregation = [3.5, 2.66667, 2, -2.2]
    end
  end
  let(:charge) do
    create(
      :graduated_charge,
      billable_metric:,
      properties: {
        graduated_ranges: [
          {
            from_value: 0,
            to_value: 5,
            per_unit_amount: '10',
            flat_amount: '100',
          },
          {
            from_value: 6,
            to_value: nil,
            per_unit_amount: '5',
            flat_amount: '50',
          },
        ],
      },
    )
  end

  before do
    aggregation_result.aggregator = aggregator
    aggregation_result.aggregation = aggregation
    aggregation_result.full_units_number = 14
    aggregation_result.current_usage_units = 14

    allow(aggregator).to receive(:per_event_aggregation).and_return(per_event_aggregation)
  end

  it 'calculates the amount correctly' do
    expect(apply_graduated_service.amount.round(2)).to eq(197.33)
  end

  context 'with event that cannot be fully placed into the range' do
    let(:aggregation) { 3.86667 }
    let(:per_event_aggregation) do
      BaseService::Result.new.tap do |r|
        r.event_aggregation = [2, 5, 10, -6]
        r.event_prorated_aggregation = [1.4, 2.66667, 2, -2.2]
      end
    end

    before do
      aggregation_result.aggregation = aggregation
      aggregation_result.full_units_number = 11
      aggregation_result.current_usage_units = 11
    end

    it 'calculates the amount correctly' do
      expect(apply_graduated_service.amount.round(2)).to eq(184.33)
    end
  end

  context 'with three ranges and one overflow' do
    let(:aggregation) { 6.36 }
    let(:per_event_aggregation) do
      BaseService::Result.new.tap do |r|
        r.event_aggregation = [2, 5, -6, 10, 4, 60]
        r.event_prorated_aggregation = [1.4, 2.5, -2.2, 2, 0.667, 2]
      end
    end
    let(:charge) do
      create(
        :graduated_charge,
        billable_metric:,
        properties: {
          graduated_ranges: [
            {
              from_value: 0,
              to_value: 5,
              per_unit_amount: '10',
              flat_amount: '100',
            },
            {
              from_value: 6,
              to_value: 15,
              per_unit_amount: '5',
              flat_amount: '50',
            },
            {
              from_value: 16,
              to_value: nil,
              per_unit_amount: '2',
              flat_amount: '0',
            },
          ],
        },
      )
    end

    before do
      aggregation_result.aggregation = aggregation
      aggregation_result.full_units_number = 75
      aggregation_result.current_usage_units = 75
    end

    it 'calculates the amount correctly' do
      expect(apply_graduated_service.amount.round(2)).to eq(190.33)
    end

    context 'when there ate two overflows' do
      let(:aggregation) { 75 }
      let(:per_event_aggregation) do
        BaseService::Result.new.tap do |r|
          r.event_aggregation = [75]
          r.event_prorated_aggregation = [75]
        end
      end

      before do
        aggregation_result.aggregation = aggregation
        aggregation_result.full_units_number = 75
        aggregation_result.current_usage_units = 75
      end

      it 'calculates the amount correctly' do
        expect(apply_graduated_service.amount.round(2)).to eq(370)
      end
    end
  end
end
