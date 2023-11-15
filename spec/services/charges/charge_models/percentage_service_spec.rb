# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::ChargeModels::PercentageService, type: :service do
  subject(:apply_percentage_service) do
    described_class.apply(
      charge:,
      aggregation_result:,
      properties: charge.properties,
    )
  end

  before do
    aggregation_result.aggregation = aggregation
    aggregation_result.count = 4
    aggregation_result.options = { running_total: }
  end

  let(:running_total) { [50, 150, 400] }
  let(:aggregation_result) { BaseService::Result.new }
  let(:fixed_amount) { '2.0' }
  let(:aggregation) { 800 }
  let(:free_units_per_events) { 3 }
  let(:free_units_per_total_aggregation) { '250.0' }
  let(:per_transaction_max_amount) { nil }
  let(:per_transaction_min_amount) { nil }

  let(:rate) { '1.3' }
  let(:charge) do
    create(
      :percentage_charge,
      properties: {
        rate:,
        fixed_amount:,
        free_units_per_events:,
        free_units_per_total_aggregation:,
        per_transaction_max_amount:,
        per_transaction_min_amount:,
      },
    )
  end

  context 'when aggregation value is 0' do
    let(:aggregation) { 0 }

    it 'returns expected amount', :aggregate_failures do
      expect(apply_percentage_service.amount).to eq(0)
      expect(apply_percentage_service.unit_amount).to eq(0)
      expect(apply_percentage_service.amount_details).to eq(
        {
          units: 0,
          free_units: 250,
          paid_units: 0,
          free_events: 2,
          percentage_rate_unit_amount: 0,
          percentage_rate_amount: 0,
          paid_events: 2,
          fixed_fee_unit_amount: 2,
          fixed_fee_amount: 0,
          min_max_adjustment_amount: 0,
        },
      )
    end
  end

  context 'when fixed amount value is 0' do
    it 'returns expected amount', :aggregate_failures do
      expect(apply_percentage_service.amount).to eq(11.15)
      expect(apply_percentage_service.unit_amount).to eq(0.0139375) # 11.15 / 800
      expect(apply_percentage_service.amount_details).to eq(
        {
          units: 800,
          free_units: 250,
          paid_units: 550,
          free_events: 2,
          percentage_rate_unit_amount: 0.013,
          percentage_rate_amount: 7.15, # (800 - 250) * (1.3 / 100),
          paid_events: 2,
          fixed_fee_unit_amount: 2,
          fixed_fee_amount: 4, # (4 - 2) * 2.0
          min_max_adjustment_amount: 0,
        },
      )
    end
  end

  context 'when rate is 0' do
    let(:running_total) { [] }
    let(:free_units_per_events) { nil }
    let(:free_units_per_total_aggregation) { nil }
    let(:rate) { '0' }
    let(:expected_fixed_amount) { (4 - 0) * 2.0 }

    it 'returns expected amount', :aggregate_failures do
      expect(apply_percentage_service.amount).to eq(8)
      expect(apply_percentage_service.unit_amount).to eq(0.01)
      expect(apply_percentage_service.amount_details).to eq(
        {
          units: 800,
          free_units: 0,
          paid_units: 800,
          free_events: 0,
          percentage_rate_unit_amount: 0,
          percentage_rate_amount: 0,
          paid_events: 4,
          fixed_fee_unit_amount: 2,
          fixed_fee_amount: 8,
          min_max_adjustment_amount: 0,
        },
      )
    end
  end

  context 'when free_units_per_events is nil' do
    let(:free_units_per_events) { nil }

    it 'returns expected amount', :aggregate_failures do
      expect(apply_percentage_service.amount).to eq(11.15) # (800 - 250) * (1.3 / 100) + (4 - 2) * 2.0
      expect(apply_percentage_service.unit_amount).to eq(0.0139375)
      expect(apply_percentage_service.amount_details).to eq(
        {
          units: 800,
          free_units: 250,
          paid_units: 550,
          free_events: 2,
          percentage_rate_unit_amount: 0.013,
          percentage_rate_amount: 7.15,
          paid_events: 2,
          fixed_fee_unit_amount: 2,
          fixed_fee_amount: 4,
          min_max_adjustment_amount: 0,
        },
      )
    end
  end

  context 'when free_units_per_total_aggregation is nil' do
    let(:free_units_per_total_aggregation) { nil }

    it 'returns expected amount', :aggregate_failures do
      expect(apply_percentage_service.amount).to eq(7.2)
      expect(apply_percentage_service.unit_amount).to eq(0.009)
      expect(apply_percentage_service.amount_details).to eq(
        {
          units: 800,
          free_units: 400,
          paid_units: 400,
          free_events: 3,
          percentage_rate_unit_amount: 0.013000000000000001,
          percentage_rate_amount: 5.2, # (800 - 400) * (1.3 / 100)
          paid_events: 1,
          fixed_fee_unit_amount: 2,
          fixed_fee_amount: 2, # (4 - 3) * 2.0
          min_max_adjustment_amount: 0,
        },
      )
    end
  end

  context 'when free units are not set' do
    let(:free_units_per_total_aggregation) { nil }
    let(:free_units_per_events) { nil }
    let(:running_total) { [] }

    it 'returns expected amount', :aggregate_failures do
      expect(apply_percentage_service.amount).to eq(18.4)
      expect(apply_percentage_service.unit_amount).to eq(0.023)
      expect(apply_percentage_service.amount_details).to eq(
        {
          units: 800,
          free_units: 0,
          paid_units: 800,
          free_events: 0,
          percentage_rate_unit_amount: 0.013000000000000001,
          percentage_rate_amount: 10.4, # 800 * (1.3 / 100)
          paid_events: 4,
          fixed_fee_unit_amount: 2,
          fixed_fee_amount: 8, # 4 * 2.0
          min_max_adjustment_amount: 0,
        },
      )
    end
  end

  context 'when free_units_per_total_aggregation > last running total' do
    let(:free_units_per_total_aggregation) { '500.0' }
    let(:expected_percentage_amount) { (800 - 400) * (1.3 / 100) }
    let(:expected_fixed_amount) { (4 - 3) * 2.0 }

    it 'returns expected amount', :aggregate_failures do
      expect(apply_percentage_service.amount).to eq(7.2)
      expect(apply_percentage_service.unit_amount).to eq(0.009)
      expect(apply_percentage_service.amount_details).to eq(
        {
          units: 800,
          free_units: 400,
          paid_units: 400,
          free_events: 3,
          percentage_rate_unit_amount: 0.013000000000000001,
          percentage_rate_amount: 5.2, # (800 - 400) * (1.3 / 100)
          paid_events: 1,
          fixed_fee_unit_amount: 2,
          fixed_fee_amount: 2, # (4 - 3) * 2.0
          min_max_adjustment_amount: 0,
        },
      )
    end
  end

  context 'when free_units_count > number of events' do
    let(:free_units_per_events) { 5 }
    let(:free_units_per_total_aggregation) { nil }
    let(:aggregation) { 400 }

    it 'returns 0' do
      expect(apply_percentage_service.amount).to eq(0)
    end
  end

  context 'when applying min / max amount per transaction' do
    let(:per_transaction_max_amount) { '12' }
    let(:per_transaction_min_amount) { '1.75' }

    let(:aggregator) do
      BillableMetrics::Aggregations::SumService.new(
        event_store_class:,
        charge: nil,
        subscription: nil,
        boundaries: nil,
      )
    end

    let(:event_store_class) { Events::Stores::PostgresStore }

    let(:aggregation) { 11_100 }

    let(:fixed_amount) { '0' }
    let(:free_units_per_events) { nil }
    let(:free_units_per_total_aggregation) { '0' }
    let(:rate) { '1' }

    let(:per_event_aggregation) { BaseService::Result.new.tap { |r| r.event_aggregation = [100, 1_000, 10_000] } }
    let(:running_total) { [] }

    before do
      aggregation_result.aggregator = aggregator
      aggregation_result.count = 3

      allow(aggregator).to receive(:per_event_aggregation).and_return(per_event_aggregation)
    end

    it 'does not apply max and min if not premium' do
      expect(apply_percentage_service.amount).to eq(111) # (100 + 1000 + 10000) * 0.01
    end

    context 'when premium' do
      around { |test| lago_premium!(&test) }

      it 'applies the min and max per transaction' do
        # 1.75 (min as 100 * 0.01 < 1.75) + 10 + 12 (max as 10000 * 0.01 > 12)
        expect(apply_percentage_service.amount).to eq(23.75)
      end

      context 'with fixed_amount' do
        let(:fixed_amount) { '1.0' }

        it 'applies the min and max per transaction' do
          # 2 + 11 + 12 (max as 10001 * 0.01 > 12)
          expect(apply_percentage_service.amount).to eq(25)
        end
      end

      context 'with free units per events' do
        let(:free_units_per_events) { 2 }

        it 'applies the min and max only on paying transaction' do
          # 10000 * 0.01 > 12
          expect(apply_percentage_service.amount).to eq(12)
        end
      end

      context 'with free units per total aggregation' do
        let(:free_units_per_total_aggregation) { '300' }

        it 'takes the free amount into account' do
          # (100 + 1000 - 300) * 0.01 + 12 (max as 10000 * 0.01 > 12)
          expect(apply_percentage_service.amount).to eq(20)
        end
      end

      context 'when both free units per events and per total aggregation are applied' do
        let(:free_units_per_events) { 3 }
        let(:free_units_per_total_aggregation) { '10000' }

        it 'takes the free amounts into account' do
          # (100 + 1000 + 10000 - 10000) * 0.01 (max as 10000 * 0.01 > 12)
          expect(apply_percentage_service.amount).to eq(11)
        end
      end
    end
  end
end
