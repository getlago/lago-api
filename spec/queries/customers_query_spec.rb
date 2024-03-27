# frozen_string_literal: true

require "rails_helper"

RSpec.describe CustomersQuery, type: :query do
  subject(:customer_query) do
    described_class.new(organization:)
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:customer_first) do
    create(:customer, organization:, name: "defgh", external_id: "11", email: "1@example.com")
  end
  let(:customer_second) do
    create(:customer, organization:, name: "abcde", external_id: "22", email: "2@example.com")
  end
  let(:customer_third) do
    create(:customer, organization:, name: "presuv", external_id: "33", email: "3@example.com")
  end

  before do
    customer_first
    customer_second
    customer_third
  end

  it "returns all customers" do
    result = customer_query.call(
      search_term: nil,
      page: 1,
      limit: 10
    )

    returned_ids = result.customers.pluck(:id)

    aggregate_failures do
      expect(result.customers.count).to eq(3)
      expect(returned_ids).to include(customer_first.id)
      expect(returned_ids).to include(customer_second.id)
      expect(returned_ids).to include(customer_third.id)
    end
  end

  context "when searching for /de/ term" do
    it "returns only two customers" do
      result = customer_query.call(
        search_term: "de",
        page: 1,
        limit: 10
      )

      returned_ids = result.customers.pluck(:id)

      aggregate_failures do
        expect(result.customers.count).to eq(2)
        expect(returned_ids).to include(customer_first.id)
        expect(returned_ids).to include(customer_second.id)
        expect(returned_ids).not_to include(customer_third.id)
      end
    end
  end

  context "when searching for /de/ term and filtering by id" do
    it "returns only one customer" do
      result = customer_query.call(
        search_term: "de",
        page: 1,
        limit: 10,
        filters: {
          ids: [customer_second.id]
        }
      )

      returned_ids = result.customers.pluck(:id)

      aggregate_failures do
        expect(result.customers.count).to eq(1)
        expect(returned_ids).not_to include(customer_first.id)
        expect(returned_ids).to include(customer_second.id)
        expect(returned_ids).not_to include(customer_third.id)
      end
    end
  end
end
