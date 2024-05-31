# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AddOnsQuery, type: :query do
  subject(:add_ons_query) do
    described_class.new(organization:)
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:add_on_first) { create(:add_on, organization:, name: 'defgh', code: '11') }
  let(:add_on_second) { create(:add_on, organization:, name: 'abcde', code: '22') }
  let(:add_on_third) { create(:add_on, organization:, name: 'presuv', code: '33') }

  before do
    add_on_first
    add_on_second
    add_on_third
  end

  it 'returns all add_ons' do
    result = add_ons_query.call(
      search_term: nil,
      page: 1,
      limit: 10
    )

    returned_ids = result.add_ons.pluck(:id)

    aggregate_failures do
      expect(result.add_ons.count).to eq(3)
      expect(returned_ids).to include(add_on_first.id)
      expect(returned_ids).to include(add_on_second.id)
      expect(returned_ids).to include(add_on_third.id)
    end
  end

  context 'when searching for /de/ term' do
    it 'returns only two add_ons' do
      result = add_ons_query.call(
        search_term: 'de',
        page: 1,
        limit: 10
      )

      returned_ids = result.add_ons.pluck(:id)

      aggregate_failures do
        expect(result.add_ons.count).to eq(2)
        expect(returned_ids).to include(add_on_first.id)
        expect(returned_ids).to include(add_on_second.id)
        expect(returned_ids).not_to include(add_on_third.id)
      end
    end
  end

  context 'when searching for /de/ term and filtering by id' do
    it 'returns only one add_on' do
      result = add_ons_query.call(
        search_term: 'de',
        page: 1,
        limit: 10,
        filters: {
          ids: [add_on_second.id]
        }
      )

      returned_ids = result.add_ons.pluck(:id)

      aggregate_failures do
        expect(result.add_ons.count).to eq(1)
        expect(returned_ids).not_to include(add_on_first.id)
        expect(returned_ids).to include(add_on_second.id)
        expect(returned_ids).not_to include(add_on_third.id)
      end
    end
  end

  context 'when searching for /1/ term' do
    it 'returns only two add_ons' do
      result = add_ons_query.call(
        search_term: '1',
        page: 1,
        limit: 10
      )

      returned_ids = result.add_ons.pluck(:id)

      aggregate_failures do
        expect(result.add_ons.count).to eq(1)
        expect(returned_ids).to include(add_on_first.id)
        expect(returned_ids).not_to include(add_on_second.id)
        expect(returned_ids).not_to include(add_on_third.id)
      end
    end
  end
end
