# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlansQuery, type: :query do
  subject(:result) do
    described_class.call(organization:, pagination:, search_term:, filters:)
  end

  let(:pagination) { nil }
  let(:search_term) { nil }
  let(:filters) { nil }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan_first) { create(:plan, organization:, name: 'defgh', code: '11') }
  let(:plan_second) { create(:plan, organization:, name: 'abcde', code: '22') }
  let(:plan_third) { create(:plan, organization:, name: 'presuv', code: '33') }

  before do
    plan_first
    plan_second
    plan_third
  end

  it 'returns all plans' do
    returned_ids = result.plans.pluck(:id)

    aggregate_failures do
      expect(result).to be_success
      expect(returned_ids.count).to eq(3)
      expect(returned_ids).to include(plan_first.id)
      expect(returned_ids).to include(plan_second.id)
      expect(returned_ids).to include(plan_third.id)
    end
  end

  context 'with pagination' do
    let(:pagination) { {page: 2, limit: 2} }

    it 'applies the pagination' do
      aggregate_failures do
        expect(result).to be_success
        expect(result.plans.count).to eq(1)
        expect(result.plans.current_page).to eq(2)
        expect(result.plans.prev_page).to eq(1)
        expect(result.plans.next_page).to be_nil
        expect(result.plans.total_pages).to eq(2)
        expect(result.plans.total_count).to eq(3)
      end
    end
  end

  context 'when searching for /de/ term' do
    let(:search_term) { 'de' }

    it 'returns only two plans' do
      returned_ids = result.plans.pluck(:id)

      aggregate_failures do
        expect(returned_ids.count).to eq(2)
        expect(returned_ids).to include(plan_first.id)
        expect(returned_ids).to include(plan_second.id)
        expect(returned_ids).not_to include(plan_third.id)
      end
    end
  end
end
