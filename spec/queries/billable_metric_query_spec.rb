# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetricQuery, type: :query do
  subject(:billable_metric_query) do
    described_class.new(organization:)
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:billable_metric_first) { create(:billable_metric, organization:, name: 'defgh', code: '11') }
  let(:billable_metric_second) { create(:billable_metric, organization:, name: 'abcde', code: '22') }
  let(:billable_metric_third) { create(:billable_metric, organization:, name: 'presuv', code: '33') }

  before do
    billable_metric_first
    billable_metric_second
    billable_metric_third
  end

  it 'returns all billable metrics' do
    result = billable_metric_query.call(
      search_term: nil,
      page: 1,
      limit: 10,
    )

    returned_ids = result.billable_metrics.pluck(:id)

    aggregate_failures do
      expect(result.billable_metrics.count).to eq(3)
      expect(returned_ids).to include(billable_metric_first.id)
      expect(returned_ids).to include(billable_metric_second.id)
      expect(returned_ids).to include(billable_metric_third.id)
    end
  end

  context 'when searching for /de/ term' do
    it 'returns only two billable metrics' do
      result = billable_metric_query.call(
        search_term: 'de',
        page: 1,
        limit: 10,
      )

      returned_ids = result.billable_metrics.pluck(:id)

      aggregate_failures do
        expect(result.billable_metrics.count).to eq(2)
        expect(returned_ids).to include(billable_metric_first.id)
        expect(returned_ids).to include(billable_metric_second.id)
        expect(returned_ids).not_to include(billable_metric_third.id)
      end
    end
  end

  context 'when searching for /de/ term and filtering by id' do
    it 'returns only one billable metric' do
      result = billable_metric_query.call(
        search_term: 'de',
        page: 1,
        limit: 10,
        filters: {
          ids: [billable_metric_second.id],
        },
      )

      returned_ids = result.billable_metrics.pluck(:id)

      aggregate_failures do
        expect(result.billable_metrics.count).to eq(1)
        expect(returned_ids).not_to include(billable_metric_first.id)
        expect(returned_ids).to include(billable_metric_second.id)
        expect(returned_ids).not_to include(billable_metric_third.id)
      end
    end
  end
end
