# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::Aggregations::MaxService, type: :service do
  subject(:max_service) do
    described_class.new(billable_metric: billable_metric, subscription: subscription)
  end

  let(:subscription) { create(:subscription) }
  let(:organization) { subscription.organization }
  let(:customer) { subscription.customer }

  let(:billable_metric) do
    create(
      :billable_metric,
      organization: organization,
      aggregation_type: 'max_agg',
      field_name: 'total_count',
    )
  end

  let(:from_date) { Time.zone.today - 1.month }
  let(:to_date) { Time.zone.today }

  before do
    create_list(
      :event,
      4,
      code: billable_metric.code,
      customer: customer,
      subscription: subscription,
      timestamp: Time.zone.now,
      properties: {
        total_count: rand(10),
      },
    )

    create(
      :event,
      code: billable_metric.code,
      customer: customer,
      subscription: subscription,
      timestamp: Time.zone.now,
      properties: {
        total_count: 12,
      },
    )
  end

  it 'aggregates the events' do
    result = max_service.aggregate(from_date: from_date, to_date: to_date)

    expect(result.aggregation).to eq(12)
  end

  context 'when events are out of bounds' do
    let(:to_date) { Time.zone.now - 2.days }

    it 'does not take events into account' do
      result = max_service.aggregate(from_date: from_date, to_date: to_date)

      expect(result.aggregation).to eq(0)
    end
  end

  context 'when properties is not found on events' do
    before do
      billable_metric.update!(field_name: 'foo_bar')
    end

    it 'counts as zero' do
      result = max_service.aggregate(from_date: from_date, to_date: to_date)

      expect(result.aggregation).to eq(0)
    end
  end

  context 'when properties is a float' do
    before do
      create(
        :event,
        code: billable_metric.code,
        customer: customer,
        subscription: subscription,
        timestamp: Time.zone.now,
        properties: {
          total_count: 14.2,
        },
      )
    end

    it 'aggregates the events' do
      result = max_service.aggregate(from_date: from_date, to_date: to_date)

      expect(result.aggregation).to eq(14.2)
    end
  end

  context 'when properties is not a number' do
    before do
      create(
        :event,
        code: billable_metric.code,
        customer: customer,
        subscription: subscription,
        timestamp: Time.zone.now,
        properties: {
          total_count: 'foo_bar',
        },
      )
    end

    it 'returns a failed result' do
      result = max_service.aggregate(from_date: from_date, to_date: to_date)

      expect(result).not_to be_success
      expect(result.error_code).to eq('aggregation_failure')
    end
  end

  context 'when properties is missing' do
    before do
      create(
        :event,
        code: billable_metric.code,
        customer: customer,
        subscription: subscription,
        timestamp: Time.zone.now,
      )
    end

    it 'ignore the event' do
      result = max_service.aggregate(from_date: from_date, to_date: to_date)

      expect(result).to be_success
      expect(result.aggregation).to eq(12)
    end
  end
end
