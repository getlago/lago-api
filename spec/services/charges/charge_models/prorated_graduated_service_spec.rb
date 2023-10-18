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

  context 'with negative event that results in changing range' do
    let(:aggregation) { 2.5 }
    let(:per_event_aggregation) do
      BaseService::Result.new.tap do |r|
        r.event_aggregation = [5, -2]
        r.event_prorated_aggregation = [3.5, -1]
      end
    end

    before do
      aggregation_result.aggregation = aggregation
      aggregation_result.full_units_number = 3
      aggregation_result.current_usage_units = 3
    end

    it 'calculates the amount correctly' do
      expect(apply_graduated_service.amount.round(2)).to eq(125)
    end

    context 'with overflow and changing ranges' do
      let(:aggregation) { 3.2 }
      let(:per_event_aggregation) do
        BaseService::Result.new.tap do |r|
          r.event_aggregation = [4, 2, -3]
          r.event_prorated_aggregation = [2.8, 1, -0.6]
        end
      end

      before do
        aggregation_result.aggregation = aggregation
        aggregation_result.full_units_number = 3
        aggregation_result.current_usage_units = 3
      end

      it 'calculates the amount correctly' do
        expect(apply_graduated_service.amount.round(2)).to eq(130.5)
      end
    end

    context 'with multiple overflows in both directions' do
      let(:aggregation) { 4.9 }
      let(:per_event_aggregation) do
        BaseService::Result.new.tap do |r|
          r.event_aggregation = [5, 2, -4, 10]
          r.event_prorated_aggregation = [3.5, 1, -1.6, 2]
        end
      end

      before do
        aggregation_result.aggregation = aggregation
        aggregation_result.full_units_number = 13
        aggregation_result.current_usage_units = 13
      end

      it 'calculates the amount correctly' do
        expect(apply_graduated_service.amount.round(2)).to eq(190)
      end
    end
  end

  context 'with negative event that results in negative total amount' do
    let(:aggregation) { -31.33 }
    let(:per_event_aggregation) do
      BaseService::Result.new.tap do |r|
        r.event_aggregation = [5, -100]
        r.event_prorated_aggregation = [2, -33.33]
      end
    end

    before do
      aggregation_result.aggregation = aggregation
      aggregation_result.full_units_number = -95
      aggregation_result.current_usage_units = -95
    end

    it 'calculates the amount correctly' do
      expect(apply_graduated_service.amount.round(2)).to eq(0)
    end

    context 'with only one range used' do
      let(:aggregation) { -31.73 }
      let(:per_event_aggregation) do
        BaseService::Result.new.tap do |r|
          r.event_aggregation = [4, -100]
          r.event_prorated_aggregation = [1.6, -33.33]
        end
      end

      before do
        aggregation_result.aggregation = aggregation
        aggregation_result.full_units_number = -96
        aggregation_result.current_usage_units = -96
      end

      it 'calculates the amount correctly' do
        expect(apply_graduated_service.amount.round(2)).to eq(0)
      end
    end
  end

  context 'when only one range is used' do
    let(:aggregation) { 0.7 }
    let(:per_event_aggregation) do
      BaseService::Result.new.tap do |r|
        r.event_aggregation = [1]
        r.event_prorated_aggregation = [0.7]
      end
    end

    before do
      aggregation_result.aggregation = aggregation
      aggregation_result.full_units_number = 1
      aggregation_result.current_usage_units = 1
    end

    it 'calculates the amount correctly' do
      expect(apply_graduated_service.amount.round(2)).to eq(107)
    end

    context 'with two ranges where first unit fully covers first range' do
      let(:charge) do
        create(
          :graduated_charge,
          billable_metric:,
          properties: {
            graduated_ranges: [
              {
                from_value: 0,
                to_value: 1,
                per_unit_amount: '10',
                flat_amount: '100',
              },
              {
                from_value: 2,
                to_value: nil,
                per_unit_amount: '5',
                flat_amount: '50',
              },
            ],
          },
        )
      end

      it 'calculates the amount correctly and second flat fee is not applied' do
        expect(apply_graduated_service.amount.round(2)).to eq(107)
      end
    end
  end

  context 'with three ranges and one overflow' do
    let(:aggregation) { 6.36 }
    let(:per_event_aggregation) do
      BaseService::Result.new.tap do |r|
        r.event_aggregation = [2, 5, 10, -6, 4, 60]
        r.event_prorated_aggregation = [1.4, 2.5, 2, -2.2, 0.667, 2]
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
      expect(apply_graduated_service.amount.ceil(2)).to eq(191.34)
    end

    context 'when there are two overflows' do
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
