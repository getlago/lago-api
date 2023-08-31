# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::PayInAdvanceAggregationService, type: :service do
  subject(:agg_service) do
    described_class.new(charge:, boundaries:, group:, properties:, event:)
  end

  let(:billable_metric) { create(:billable_metric, aggregation_type:, field_name: 'item_id') }
  let(:charge) { create(:standard_charge, billable_metric:) }
  let(:group) { create(:group) }
  let(:aggregation_type) { 'count_agg' }
  let(:event) { create(:event, subscription:) }
  let(:properties) { {} }

  let(:subscription) do
    create(:subscription, started_at: DateTime.parse('2023-03-15'))
  end

  let(:boundaries) do
    {
      charges_from_datetime: subscription.started_at.beginning_of_day,
      charges_to_datetime: subscription.started_at.end_of_month.end_of_day,
    }
  end

  let(:agg_result) { BaseService::Result.new }

  describe '#call' do
    describe 'when count aggregation' do
      let(:count_service) { instance_double(BillableMetrics::Aggregations::CountService, aggregate: agg_result) }

      it 'delegates to the count aggregation service' do
        allow(BillableMetrics::Aggregations::CountService).to receive(:new).and_return(count_service)

        agg_service.call

        expect(BillableMetrics::Aggregations::CountService).to have_received(:new)
          .with(
            billable_metric:,
            subscription:,
            group:,
            event:,
            boundaries: {
              from_datetime: boundaries[:charges_from_datetime],
              to_datetime: boundaries[:charges_to_datetime],
            },
          )

        expect(count_service).to have_received(:aggregate).with(
          options: { free_units_per_events: 0, free_units_per_total_aggregation: 0 },
        )
      end
    end

    describe 'when sum aggregation' do
      let(:aggregation_type) { 'sum_agg' }
      let(:sum_service) { instance_double(BillableMetrics::Aggregations::SumService, aggregate: agg_result) }
      let(:properties) do
        { 'free_units_per_events' => '3', 'free_units_per_total_aggregation' => '50' }
      end

      it 'delegates to the sum aggregation service' do
        allow(BillableMetrics::Aggregations::SumService).to receive(:new).and_return(sum_service)

        agg_service.call

        expect(BillableMetrics::Aggregations::SumService).to have_received(:new)
          .with(
            billable_metric:,
            subscription:,
            group:,
            event:,
            boundaries: {
              from_datetime: boundaries[:charges_from_datetime],
              to_datetime: boundaries[:charges_to_datetime],
            },
          )

        expect(sum_service).to have_received(:aggregate).with(
          options: { free_units_per_events: 3, free_units_per_total_aggregation: 50 },
        )
      end
    end

    describe 'when unique_count aggregation' do
      let(:aggregation_type) { 'unique_count_agg' }
      let(:unique_count_service) do
        instance_double(BillableMetrics::Aggregations::UniqueCountService, aggregate: agg_result)
      end

      it 'delegates to the sum aggregation service' do
        allow(BillableMetrics::Aggregations::UniqueCountService).to receive(:new).and_return(unique_count_service)

        agg_service.call

        expect(BillableMetrics::Aggregations::UniqueCountService).to have_received(:new)
          .with(
            billable_metric:,
            subscription:,
            group:,
            event:,
            boundaries: {
              from_datetime: boundaries[:charges_from_datetime],
              to_datetime: boundaries[:charges_to_datetime],
            },
          )

        expect(unique_count_service).to have_received(:aggregate).with(
          options: { free_units_per_events: 0, free_units_per_total_aggregation: 0 },
        )
      end
    end

    describe 'when unknown aggregation' do
      let(:aggregation_type) { 'max_agg' }

      it 'raises a NotImplementedError' do
        expect { agg_service.call }.to raise_error(NotImplementedError)
      end
    end
  end
end
