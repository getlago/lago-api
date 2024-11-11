# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetricsQuery, type: :query do
  subject(:result) do
    described_class.call(organization:, search_term:, pagination:, filters:)
  end

  let(:pagination) { nil }
  let(:search_term) { nil }
  let(:filters) { {} }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:billable_metric_first) { create(:billable_metric, organization:, name: 'defgh', code: '11') }
  let(:billable_metric_second) { create(:billable_metric, organization:, name: 'abcde', code: '22') }
  let(:billable_metric_third) { create(:billable_metric, organization:, name: 'presuv', code: '33') }
  let(:billable_metric_fourth) { create(:unique_count_billable_metric, organization:, name: 'qwerty', code: '44') }

  before do
    billable_metric_first
    billable_metric_second
    billable_metric_third
    billable_metric_fourth
  end

  it 'returns all billable metrics' do
    returned_ids = result.billable_metrics.pluck(:id)

    aggregate_failures do
      expect(result).to be_success
      expect(returned_ids.count).to eq(4)
      expect(returned_ids).to include(billable_metric_first.id)
      expect(returned_ids).to include(billable_metric_second.id)
      expect(returned_ids).to include(billable_metric_third.id)
      expect(returned_ids).to include(billable_metric_fourth.id)
    end
  end

  context "when filters validation fails" do
    let(:filters) do
      {
        recurring: "unexpected_value",
        aggregation_types: ["unexpected_value"]
      }
    end

    it "captures all validation errors" do
      expect(result).not_to be_success
      expect(result.error.messages[:filters][:recurring]).to include("must be boolean")
      expect(result.error.messages[:filters][:aggregation_types][0]).to include("must be one of: max_agg, count_agg")
    end
  end

  context 'with pagination' do
    let(:pagination) { {page: 2, limit: 3} }

    it 'applies the pagination' do
      aggregate_failures do
        expect(result).to be_success
        expect(result.billable_metrics.count).to eq(1)
        expect(result.billable_metrics.current_page).to eq(2)
        expect(result.billable_metrics.prev_page).to eq(1)
        expect(result.billable_metrics.next_page).to be_nil
        expect(result.billable_metrics.total_pages).to eq(2)
        expect(result.billable_metrics.total_count).to eq(4)
      end
    end
  end

  context 'when filtering by recurring billable metrics' do
    let(:billable_metric_recurring) do
      create(
        :billable_metric,
        organization:,
        aggregation_type: 'unique_count_agg',
        name: 'defghz',
        code: '55',
        field_name: 'test',
        recurring: true
      )
    end

    let(:filters) { {recurring: true} }

    before { billable_metric_recurring }

    it 'returns 1 billable metric' do
      returned_ids = result.billable_metrics.pluck(:id)

      aggregate_failures do
        expect(returned_ids.count).to eq(1)
        expect(returned_ids).not_to include(billable_metric_first.id)
        expect(returned_ids).not_to include(billable_metric_second.id)
        expect(returned_ids).not_to include(billable_metric_third.id)
        expect(returned_ids).not_to include(billable_metric_fourth.id)
        expect(returned_ids).to include(billable_metric_recurring.id)
      end
    end
  end

  context 'when filtering by count_agg aggregation type' do
    let(:filters) { {aggregation_types: ['count_agg']} }

    it 'returns 3 billable metrics' do
      returned_ids = result.billable_metrics.pluck(:id)

      aggregate_failures do
        expect(returned_ids.count).to eq(3)
        expect(returned_ids).to include(billable_metric_first.id)
        expect(returned_ids).to include(billable_metric_second.id)
        expect(returned_ids).to include(billable_metric_third.id)
        expect(returned_ids).not_to include(billable_metric_fourth.id)
      end
    end
  end

  context 'when filtering by max_agg aggregation type' do
    let(:filters) { {aggregation_types: ['max_agg']} }

    it 'returns 0 billable metrics' do
      returned_ids = result.billable_metrics.pluck(:id)

      aggregate_failures do
        expect(returned_ids.count).to eq(0)
        expect(returned_ids).not_to include(billable_metric_first.id)
        expect(returned_ids).not_to include(billable_metric_second.id)
        expect(returned_ids).not_to include(billable_metric_third.id)
        expect(returned_ids).not_to include(billable_metric_fourth.id)
      end
    end
  end

  context 'when searching for /de/ term' do
    let(:search_term) { 'de' }

    it 'returns only two billable metrics' do
      returned_ids = result.billable_metrics.pluck(:id)

      aggregate_failures do
        expect(returned_ids.count).to eq(2)
        expect(returned_ids).to include(billable_metric_first.id)
        expect(returned_ids).to include(billable_metric_second.id)
        expect(returned_ids).not_to include(billable_metric_third.id)
      end
    end
  end
end
