# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Queries::PlanQuery, type: :service do
  subject(:plan_query) do
    described_class.new(organization: organization)
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan_first) { create(:plan, organization: organization, name: 'defgh') }
  let(:plan_second) { create(:plan, organization: organization, name: 'abcde') }
  let(:plan_third) { create(:plan, organization: organization, name: 'presuv') }

  before do
    plan_first
    plan_second
    plan_third
  end

  it 'returns all plans' do
    result = plan_query.call(
      search_term: nil,
      page: 1,
      limit: 10,
    )

    returned_ids = result.plans.pluck(:id)

    aggregate_failures do
      expect(result.plans.count).to eq(3)
      expect(returned_ids).to include(plan_first.id)
      expect(returned_ids).to include(plan_second.id)
      expect(returned_ids).to include(plan_third.id)
    end
  end

  context 'when searching for /de/ term' do
    it 'returns only two plans' do
      result = plan_query.call(
        search_term: 'de',
        page: 1,
        limit: 10,
      )

      returned_ids = result.plans.pluck(:id)

      aggregate_failures do
        expect(result.plans.count).to eq(2)
        expect(returned_ids).to include(plan_first.id)
        expect(returned_ids).to include(plan_second.id)
        expect(returned_ids).not_to include(plan_third.id)
      end
    end
  end

  context 'when searching for /de/ term and filtering by id' do
    it 'returns only one plan' do
      result = plan_query.call(
        search_term: 'de',
        page: 1,
        limit: 10,
        filters: {
          ids: [plan_second.id],
        },
      )

      returned_ids = result.plans.pluck(:id)

      aggregate_failures do
        expect(result.plans.count).to eq(1)
        expect(returned_ids).not_to include(plan_first.id)
        expect(returned_ids).to include(plan_second.id)
        expect(returned_ids).not_to include(plan_third.id)
      end
    end
  end
end
