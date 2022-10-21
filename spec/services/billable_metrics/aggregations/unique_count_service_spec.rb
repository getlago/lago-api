# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::Aggregations::UniqueCountService, type: :service do
  subject(:count_service) do
    described_class.new(billable_metric: billable_metric, subscription: subscription)
  end

  let(:subscription) { create(:subscription) }
  let(:organization) { subscription.organization }
  let(:customer) { subscription.customer }

  let(:billable_metric) do
    create(
      :billable_metric,
      organization: organization,
      aggregation_type: 'unique_count_agg',
      field_name: 'anonymous_id',
    )
  end

  let(:from_date) { Time.zone.today - 1.month }
  let(:to_date) { Time.zone.today }

  before do
    create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'europe')
    create(:group, billable_metric_id: billable_metric.id, key: 'region', value: 'usa')
    create(:group, billable_metric_id: billable_metric.id, key: 'country', value: 'france')

    create_list(
      :event,
      3,
      code: billable_metric.code,
      customer: customer,
      subscription: subscription,
      timestamp: Time.zone.now,
      properties: {
        anonymous_id: 'foo_bar',
        region: 'europe',
      },
    )

    create(
      :event,
      code: billable_metric.code,
      customer: customer,
      subscription: subscription,
      timestamp: Time.zone.now,
      properties: {
        anonymous_id: 'foo_bar',
        region: 'usa',
      },
    )

    create(
      :event,
      code: billable_metric.code,
      customer: customer,
      subscription: subscription,
      timestamp: Time.zone.now,
      properties: {
        anonymous_id: 'foo_bar',
        region: 'africa',
      },
    )

    create(
      :event,
      code: billable_metric.code,
      customer: customer,
      subscription: subscription,
      timestamp: Time.zone.now,
      properties: {
        anonymous_id: 'foo_bar',
        country: 'france',
      },
    )
  end

  it 'aggregates the events' do
    result = count_service.aggregate(from_date: from_date, to_date: to_date)

    expect(result.aggregation).to eq(1)
    expect(result.aggregation_per_group).to eq(
      [
        [{ 'africa' => 1 }, { 'europe' => 1 }, { 'usa' => 1 }],
        [{ 'france' => 1 }],
      ],
    )
    expect(result.count).to eq(6)
  end

  context 'when events are out of bounds' do
    let(:to_date) { Time.zone.now - 2.days }

    it 'does not take events into account' do
      result = count_service.aggregate(from_date: from_date, to_date: to_date)

      expect(result.aggregation).to eq(0)
      expect(result.aggregation_per_group).to eq([[], []])
      expect(result.count).to eq(0)
    end
  end

  context 'when properties is not found on events' do
    before do
      billable_metric.update!(field_name: 'foo_bar')
    end

    it 'counts as zero' do
      result = count_service.aggregate(from_date: from_date, to_date: to_date)

      expect(result.aggregation).to eq(0)
      expect(result.aggregation_per_group).to eq([[], []])
      expect(result.count).to eq(0)
    end
  end
end
