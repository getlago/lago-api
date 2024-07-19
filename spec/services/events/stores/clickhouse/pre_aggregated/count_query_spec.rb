# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Events::Stores::Clickhouse::PreAggregated::CountQuery, type: :service, clickhouse: true do
  subject(:pre_aggregated_query) { described_class.new(subscription:, boundaries:) }

  let(:subscription) { create(:subscription, customer:, plan:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  let(:billable_metric1) { create(:billable_metric, organization:) }
  let(:billable_metric2) { create(:billable_metric, organization:) }

  let(:plan) { create(:plan, organization:) }
  let(:charge1) { create(:standard_charge, billable_metric: billable_metric1, plan:) }
  let(:charge2) { create(:standard_charge, billable_metric: billable_metric2, plan:) }

  let(:boundaries) { {from_datetime:, to_datetime:} }
  let(:from_datetime) { Time.zone.parse('2024-07-01T03:42:00') }
  let(:to_datetime) { Time.zone.parse('2024-07-31T22:47:00') }

  let(:pre_aggregated_events1) do
    [
      create(
        :clickhouse_events_count_agg,
        subscription:,
        organization:,
        billable_metric: billable_metric1,
        charge: charge1,
        value: 3.0,
        timestamp: Time.zone.parse('2024-07-07T00:00:00')
      ),
      create(
        :clickhouse_events_count_agg,
        subscription:,
        organization:,
        billable_metric: billable_metric1,
        charge: charge1,
        value: 2.0,
        timestamp: Time.zone.parse('2024-07-09T00:00:00')
      )
    ]
  end

  let(:pre_aggregated_events2) do
    [
      create(
        :clickhouse_events_count_agg,
        subscription:,
        organization:,
        billable_metric: billable_metric2,
        charge: charge2,
        value: 4.0,
        timestamp: Time.zone.parse('2024-07-04T00:00:00')
      ),
      create(
        :clickhouse_events_count_agg,
        subscription:,
        organization:,
        billable_metric: billable_metric2,
        charge: charge2,
        value: 8.0,
        timestamp: Time.zone.parse('2024-07-10T00:00:00')
      ),
      create(
        :clickhouse_events_count_agg,
        subscription:,
        organization:,
        billable_metric: billable_metric2,
        charge: charge2,
        value: 2.0,
        timestamp: Time.zone.parse('2024-07-16T00:00:00')
      )
    ]
  end

  before do
    pre_aggregated_events1
    pre_aggregated_events2
  end

  describe '.call' do
    it 'returns the aggregated count units', aggregate_failures: true do
      result = pre_aggregated_query.call

      expect(result).to be_success
      expect(result.charges_units.keys).to match_array([charge1.id, charge2.id])
      expect(result.charges_units[charge1.id]).to eq({units: 5.0, filters: {}, grouped_by: {}})
      expect(result.charges_units[charge2.id]).to eq({units: 14.0, filters: {}, grouped_by: {}})
    end

    context 'with enriched events before and after the boundaries' do
      let(:enriched_events1) do
        [
          create(
            :clickhouse_events_enriched,
            subscription:,
            organization:,
            charge: charge1,
            value: 1.0,
            timestamp: Time.zone.parse('2024-07-01T03:45:50')
          ),
          create(
            :clickhouse_events_enriched,
            subscription:,
            organization:,
            charge: charge1,
            value: 1.0,
            timestamp: Time.zone.parse('2024-07-31T22:12:00')
          )
        ]
      end

      let(:enriched_events2) do
        [
          create(
            :clickhouse_events_enriched,
            subscription:,
            organization:,
            charge: charge2,
            value: 1.0,
            # Ignored since it should be taken into account by the pre-aggregated query
            timestamp: Time.zone.parse('2024-07-01T04:10:50')
          ),
          create(
            :clickhouse_events_enriched,
            subscription:,
            organization:,
            charge: charge2,
            value: 1.0,
            # Ignored since it should be taken into account by the pre-aggregated query
            timestamp: Time.zone.parse('2024-07-31T23:10:00')
          )
        ]
      end

      before do
        enriched_events1
        enriched_events2
      end

      it 'returns the aggregated count units', aggregate_failures: true do
        result = pre_aggregated_query.call

        expect(result).to be_success
        expect(result.charges_units.keys).to match_array([charge1.id, charge2.id])
        expect(result.charges_units[charge1.id]).to eq({units: 7.0, filters: {}, grouped_by: {}})
        expect(result.charges_units[charge2.id]).to eq({units: 14.0, filters: {}, grouped_by: {}})
      end
    end

    context 'with grouped_by' do
      let(:charge1) do
        create(
          :charge,
          billable_metric: billable_metric1,
          plan:,
          properties: {amount: 10.to_s, grouped_by: %w[cloud country]}
        )
      end

      let(:pre_aggregated_events1) do
        [
          create(
            :clickhouse_events_count_agg,
            subscription:,
            organization:,
            billable_metric: billable_metric1,
            charge: charge1,
            value: 3.0,
            timestamp: Time.zone.parse('2024-07-07T00:00:00'),
            grouped_by: {cloud: 'aws', country: 'us'}
          ),
          create(
            :clickhouse_events_count_agg,
            subscription:,
            organization:,
            billable_metric: billable_metric1,
            charge: charge1,
            value: 2.0,
            timestamp: Time.zone.parse('2024-07-09T00:00:00'),
            grouped_by: {cloud: 'aws', country: 'us'}
          ),
          create(
            :clickhouse_events_count_agg,
            subscription:,
            organization:,
            billable_metric: billable_metric1,
            charge: charge1,
            value: 2.0,
            timestamp: Time.zone.parse('2024-07-09T00:00:00')
          ),
          create(
            :clickhouse_events_count_agg,
            subscription:,
            organization:,
            billable_metric: billable_metric1,
            charge: charge1,
            value: 2.0,
            timestamp: Time.zone.parse('2024-07-09T00:00:00'),
            grouped_by: {cloud: 'aws', country: 'canada'}
          )
        ]
      end

      it 'returns the aggregated count units', aggregate_failures: true do
        result = pre_aggregated_query.call

        expect(result).to be_success
        expect(result.charges_units.keys).to match_array([charge1.id, charge2.id])
        expect(result.charges_units[charge1.id][:units]).to eq(2.0)
        expect(result.charges_units[charge1.id][:grouped_by]).to eq({
          "{\"cloud\":\"aws\",\"country\":\"canada\"}" => {units: 2.0},
          "{\"cloud\":\"aws\",\"country\":\"us\"}" => {units: 5.0}
        })

        expect(result.charges_units[charge2.id]).to eq({units: 14.0, filters: {}, grouped_by: {}})
      end

      context 'with enriched events before and after the boundaries' do
        let(:enriched_events1) do
          [
            create(
              :clickhouse_events_enriched,
              subscription:,
              organization:,
              charge: charge1,
              value: 1.0,
              timestamp: Time.zone.parse('2024-07-01T03:45:50'),
              grouped_by: {cloud: 'aws', country: 'canada'}
            ),
            create(
              :clickhouse_events_enriched,
              subscription:,
              organization:,
              charge: charge1,
              value: 1.0,
              timestamp: Time.zone.parse('2024-07-31T22:12:00')
            )
          ]
        end

        before do
          enriched_events1
        end

        it 'returns the aggregated count units', aggregate_failures: true do
          result = pre_aggregated_query.call

          expect(result).to be_success
          expect(result.charges_units.keys).to match_array([charge1.id, charge2.id])
          expect(result.charges_units[charge1.id][:units]).to eq(3.0)
          expect(result.charges_units[charge1.id][:grouped_by]).to eq({
            "{\"cloud\":\"aws\",\"country\":\"canada\"}" => {units: 3.0},
            "{\"cloud\":\"aws\",\"country\":\"us\"}" => {units: 5.0}
          })

          expect(result.charges_units[charge2.id]).to eq({units: 14.0, filters: {}, grouped_by: {}})
        end
      end
    end

    context 'with filters' do
      let(:billable_metric_filter11) do
        create(:billable_metric_filter, billable_metric: billable_metric1, key: 'cloud', values: %w[aws gcp azure])
      end
      let(:billable_metric_filter12) do
        create(:billable_metric_filter, billable_metric: billable_metric1, key: 'country', values: %w[us canada france])
      end

      let(:charge_filter1) { create(:charge_filter, charge: charge1, properties: {amount: 10.to_s}) }
      let(:charge_filter1_value1) do
        create(
          :charge_filter_value,
          charge_filter: charge_filter1,
          billable_metric_filter: billable_metric_filter11,
          values: %w[aws]
        )
      end
      let(:charge_filter1_value2) do
        create(
          :charge_filter_value,
          charge_filter: charge_filter1,
          billable_metric_filter: billable_metric_filter12,
          values: %w[us canada]
        )
      end

      let(:charge_filter2) { create(:charge_filter, charge: charge1, properties: {amount: 10.to_s}) }
      let(:charge_filter2_value1) do
        create(
          :charge_filter_value,
          charge_filter: charge_filter1,
          billable_metric_filter: billable_metric_filter12,
          values: %w[france]
        )
      end

      let(:pre_aggregated_events1) do
        [
          create(
            :clickhouse_events_count_agg,
            subscription:,
            organization:,
            billable_metric: billable_metric1,
            charge: charge1,
            value: 3.0,
            timestamp: Time.zone.parse('2024-07-07T00:00:00'),
            filters: {cloud: ['aws'], country: %w[us canada]}
          ),
          create(
            :clickhouse_events_count_agg,
            subscription:,
            organization:,
            billable_metric: billable_metric1,
            charge: charge1,
            value: 2.0,
            timestamp: Time.zone.parse('2024-07-09T00:00:00'),
            filters: {cloud: ['aws'], country: %w[us canada]}
          ),
          create(
            :clickhouse_events_count_agg,
            subscription:,
            organization:,
            billable_metric: billable_metric1,
            charge: charge1,
            value: 2.0,
            timestamp: Time.zone.parse('2024-07-09T00:00:00')
          ),
          create(
            :clickhouse_events_count_agg,
            subscription:,
            organization:,
            billable_metric: billable_metric1,
            charge: charge1,
            value: 2.0,
            timestamp: Time.zone.parse('2024-07-09T00:00:00'),
            filters: {country: %w[france]}
          )
        ]
      end

      it 'returns the aggregated count units', aggregate_failures: true do
        result = pre_aggregated_query.call

        expect(result).to be_success
        expect(result.charges_units.keys).to match_array([charge1.id, charge2.id])
        expect(result.charges_units[charge1.id][:units]).to eq(2.0)
        expect(result.charges_units[charge1.id][:filters]).to eq({
          "{\"cloud\":[\"aws\"],\"country\":[\"us\",\"canada\"]}" => {units: 5.0, grouped_by: {}},
          "{\"country\":[\"france\"]}" => {units: 2.0, grouped_by: {}}
        })

        expect(result.charges_units[charge2.id]).to eq({units: 14.0, filters: {}, grouped_by: {}})
      end

      context 'with enriched events before and after the boundaries' do
        let(:enriched_events1) do
          [
            create(
              :clickhouse_events_enriched,
              subscription:,
              organization:,
              charge: charge1,
              value: 1.0,
              timestamp: Time.zone.parse('2024-07-01T03:45:50'),
              filters: {cloud: ['aws'], country: %w[us canada]}
            ),
            create(
              :clickhouse_events_enriched,
              subscription:,
              organization:,
              charge: charge1,
              value: 1.0,
              timestamp: Time.zone.parse('2024-07-31T22:12:00')
            )
          ]
        end

        before do
          enriched_events1
        end

        it 'returns the aggregated count units', aggregate_failures: true do
          result = pre_aggregated_query.call

          expect(result).to be_success
          expect(result.charges_units.keys).to match_array([charge1.id, charge2.id])
          expect(result.charges_units[charge1.id][:units]).to eq(3.0)
          expect(result.charges_units[charge1.id][:filters]).to eq({
            "{\"cloud\":[\"aws\"],\"country\":[\"us\",\"canada\"]}" => {units: 6.0, grouped_by: {}},
            "{\"country\":[\"france\"]}" => {units: 2.0, grouped_by: {}}
          })

          expect(result.charges_units[charge2.id]).to eq({units: 14.0, filters: {}, grouped_by: {}})
        end
      end

      context 'with grouped_by and filters' do
        let(:charge1) do
          create(
            :charge,
            billable_metric: billable_metric1,
            plan:,
            properties: {amount: 10.to_s, grouped_by: %w[region]}
          )
        end

        let(:pre_aggregated_events1) do
          [
            create(
              :clickhouse_events_count_agg,
              subscription:,
              organization:,
              billable_metric: billable_metric1,
              charge: charge1,
              value: 3.0,
              timestamp: Time.zone.parse('2024-07-07T00:00:00'),
              filters: {cloud: ['aws'], country: %w[us canada]},
              grouped_by: {region: 'us-east-1'}
            ),
            create(
              :clickhouse_events_count_agg,
              subscription:,
              organization:,
              billable_metric: billable_metric1,
              charge: charge1,
              value: 2.0,
              timestamp: Time.zone.parse('2024-07-09T00:00:00'),
              filters: {cloud: ['aws'], country: %w[us canada]},
              grouped_by: {region: 'us-east-1'}
            ),
            create(
              :clickhouse_events_count_agg,
              subscription:,
              organization:,
              billable_metric: billable_metric1,
              charge: charge1,
              value: 2.0,
              timestamp: Time.zone.parse('2024-07-09T00:00:00'),
              grouped_by: {region: 'us-east-1'}
            ),
            create(
              :clickhouse_events_count_agg,
              subscription:,
              organization:,
              billable_metric: billable_metric1,
              charge: charge1,
              value: 2.0,
              timestamp: Time.zone.parse('2024-07-09T00:00:00'),
              filters: {cloud: ['aws'], country: %w[us canada]},
              grouped_by: {region: 'us-east-2'}
            )
          ]
        end

        it 'returns the aggregated count units', aggregate_failures: true do
          result = pre_aggregated_query.call

          expect(result).to be_success
          expect(result.charges_units.keys).to match_array([charge1.id, charge2.id])
          expect(result.charges_units[charge1.id][:units]).to eq(0.0)
          expect(result.charges_units[charge1.id][:grouped_by]).to eq(
            {"{\"region\":\"us-east-1\"}" => {units: 2.0}}
          )

          expect(result.charges_units[charge1.id][:filters]).to eq({
            "{\"cloud\":[\"aws\"],\"country\":[\"us\",\"canada\"]}" => {
              units: 0.0,
              grouped_by: {
                "{\"region\":\"us-east-1\"}" => {units: 5.0},
                "{\"region\":\"us-east-2\"}" => {units: 2.0}
              }
            }
          })

          expect(result.charges_units[charge2.id]).to eq({units: 14.0, filters: {}, grouped_by: {}})
        end
      end
    end
  end
end
