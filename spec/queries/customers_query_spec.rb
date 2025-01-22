# frozen_string_literal: true

require "rails_helper"

RSpec.describe CustomersQuery, type: :query do
  subject(:result) do
    described_class.call(organization:, search_term:, pagination:, filters:)
  end

  let(:returned_ids) { result.customers.pluck(:id) }
  let(:pagination) { nil }
  let(:search_term) { nil }
  let(:filters) { {} }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:customer_first) do
    create(:customer, organization:, name: "defgh", firstname: "John", lastname: "Doe", legal_name: "Legalname", external_id: "11", email: "1@example.com")
  end
  let(:customer_second) do
    create(:customer, organization:, name: "abcde", firstname: "Jane", lastname: "Smith", legal_name: "other name", external_id: "22", email: "2@example.com")
  end
  let(:customer_third) do
    create(
      :customer,
      organization:,
      account_type: "partner",
      email: "3@example.com",
      external_id: "33",
      firstname: "Mary",
      lastname: "Johnson",
      legal_name: "Company name",
      name: "presuv"
    )
  end

  before do
    customer_first
    customer_second
    customer_third
  end

  it "returns all customers" do
    expect(result).to be_success
    expect(returned_ids.count).to eq(3)
    expect(returned_ids).to include(customer_first.id)
    expect(returned_ids).to include(customer_second.id)
    expect(returned_ids).to include(customer_third.id)
  end

  context "when filtering by partner account_type" do
    let(:filters) { {account_type: %w[partner]} }

    it "returns partner accounts" do
      expect(returned_ids.count).to eq(1)
      expect(returned_ids).to eq [customer_third.id]
    end
  end

  context "when filtering by customer account_type" do
    let(:filters) { {account_type: %w[customer]} }

    it "returns customer accounts" do
      expect(returned_ids.count).to eq(2)
      expect(returned_ids).to include customer_first.id
      expect(returned_ids).to include customer_second.id
    end
  end

  context "when customers have the same values for the ordering criteria" do
    let(:customer_second) do
      create(
        :customer,
        organization:,
        name: "abcde",
        firstname: "Jane",
        lastname: "Smith",
        legal_name: "other name",
        external_id: "22",
        email: "2@example.com",
        created_at: customer_first.created_at
      ).tap do |customer|
        customer.update! id: "00000000-0000-0000-0000-000000000000"
      end
    end

    it "returns a consistent list" do
      expect(result).to be_success
      expect(returned_ids.count).to eq(3)
      expect(returned_ids).to include(customer_first.id)
      expect(returned_ids).to include(customer_second.id)
      expect(returned_ids.index(customer_first.id)).to be > returned_ids.index(customer_second.id)
    end
  end

  context "with pagination" do
    let(:pagination) { {page: 2, limit: 2} }

    it "applies the pagination" do
      expect(result).to be_success
      expect(result.customers.count).to eq(1)
      expect(result.customers.current_page).to eq(2)
      expect(result.customers.prev_page).to eq(1)
      expect(result.customers.next_page).to be_nil
      expect(result.customers.total_pages).to eq(2)
      expect(result.customers.total_count).to eq(3)
    end
  end

  context "when searching for /de/ term" do
    let(:search_term) { "de" }

    it "returns only two customers" do
      expect(returned_ids.count).to eq(2)
      expect(returned_ids).to include(customer_first.id)
      expect(returned_ids).to include(customer_second.id)
      expect(returned_ids).not_to include(customer_third.id)
    end
  end

  context "when searching for firstname 'Jane'" do
    let(:search_term) { "Jane" }

    it "returns only one customer" do
      expect(returned_ids.count).to eq(1)
      expect(returned_ids).to include(customer_second.id)
      expect(returned_ids).not_to include(customer_first.id)
      expect(returned_ids).not_to include(customer_third.id)
    end
  end

  context "when searching for lastname 'Johnson'" do
    let(:search_term) { "Johnson" }

    it "returns only one customer" do
      expect(returned_ids.count).to eq(1)
      expect(returned_ids).not_to include(customer_first.id)
      expect(returned_ids).not_to include(customer_second.id)
      expect(returned_ids).to include(customer_third.id)
    end
  end

  context "when searching for legalname 'Company'" do
    let(:search_term) { "Company" }

    it "returns only one customer" do
      expect(returned_ids.count).to eq(1)
      expect(returned_ids).not_to include(customer_first.id)
      expect(returned_ids).not_to include(customer_second.id)
      expect(returned_ids).to include(customer_third.id)
    end
  end

  context "when filters validation fails" do
    let(:filters) { {account_type: %w[random]} }

    it "captures all validation errors" do
      expect(result).not_to be_success
      expect(result.error.messages[:filters][:account_type]).to eq({0 => ["must be one of: customer, partner"]})
    end
  end
end
