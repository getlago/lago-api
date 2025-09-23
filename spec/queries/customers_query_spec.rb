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
  let(:organization) { create(:organization) }
  let(:billing_entity1) { organization.default_billing_entity }
  let(:billing_entity2) { create(:billing_entity, organization:) }

  let(:customer_first) do
    create(
      :customer,
      organization:,
      name: "defgh",
      firstname: "John",
      lastname: "Doe",
      legal_name: "Legalname",
      external_id: "11",
      email: "1@example.com",
      country: "US",
      state: "CA",
      zipcode: "90001",
      billing_entity: billing_entity1
    )
  end
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
      country: "FR",
      state: "Paris",
      zipcode: "75001",
      billing_entity: billing_entity1
    )
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
      name: "presuv",
      country: "DE",
      state: "Berlin",
      zipcode: "10115",
      billing_entity: billing_entity2
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

  context "when filtering by billing_entity_id" do
    let(:filters) { {billing_entity_ids: [billing_entity2.id]} }

    it "returns customers for the specified billing entity" do
      expect(returned_ids.count).to eq(1)
      expect(returned_ids).to include(customer_third.id)
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

  context "with search_term" do
    context "when searching for name 'de'" do
      let(:search_term) { "de" }

      it "returns only two customers" do
        expect(returned_ids).to match_array([customer_first.id, customer_second.id])
      end
    end

    context "when searching for firstname 'Jane'" do
      let(:search_term) { "Jane" }

      it "returns only one customer" do
        expect(returned_ids).to eq([customer_second.id])
      end
    end

    context "when searching for lastname 'Johnson'" do
      let(:search_term) { "Johnson" }

      it "returns only one customer" do
        expect(returned_ids).to eq([customer_third.id])
      end
    end

    context "when searching for legalname 'Company'" do
      let(:search_term) { "Company" }

      it "returns only one customer" do
        expect(returned_ids).to eq([customer_third.id])
      end
    end

    context "when searching for external_id '11'" do
      let(:search_term) { "11" }

      it "returns only one customer" do
        expect(returned_ids).to eq([customer_first.id])
      end
    end

    context "when searching for email '1@e'" do
      let(:search_term) { "1@e" }

      it "returns only one customer" do
        expect(returned_ids).to eq([customer_first.id])
      end
    end
  end

  context "when filtering by countries" do
    let(:filters) { {countries: ["US", "FR"]} }

    it "returns only two customers" do
      expect(returned_ids).to match_array([customer_first.id, customer_second.id])
    end
  end

  context "when filtering by states" do
    let(:filters) { {states: ["CA", "Paris"]} }

    it "returns only two customers" do
      expect(returned_ids).to match_array([customer_first.id, customer_second.id])
    end
  end

  context "when filtering by zipcodes" do
    let(:filters) { {zipcodes: ["10115", "75001"]} }

    it "returns only two customers" do
      expect(returned_ids).to match_array([customer_third.id, customer_second.id])
    end
  end

  context "when searching for active subscriptions" do
    let(:filters) do
      {active_subscriptions_count_from: from, active_subscriptions_count_to: to}
    end
    let(:subscriptionless_customer) do
      create(:customer, organization:, billing_entity: billing_entity1)
    end

    before do
      subscriptionless_customer
      create(:subscription, customer: customer_first)
      2.times do
        create(:subscription, customer: customer_second)
      end
      3.times do
        create(:subscription, customer: customer_third)
      end
    end

    context "without subscriptions" do
      let(:from) { 0 }
      let(:to) { 0 }

      it "returns customers" do
        expect(returned_ids.count).to eq(1)
        expect(returned_ids).to eq([subscriptionless_customer.id])
      end
    end

    context "with exact subscriptions count" do
      let(:from) { 2 }
      let(:to) { 2 }

      it "returns customers" do
        expect(returned_ids.count).to eq(1)
        expect(returned_ids).to eq([customer_second.id])
      end
    end

    context "with subscriptions count more than a number" do
      let(:from) { 1 }
      let(:to) { nil }

      it "returns customers" do
        expect(returned_ids.count).to eq(2)
        expect(returned_ids).to include(customer_second.id)
        expect(returned_ids).to include(customer_third.id)
      end
    end

    context "with subscriptions count in a range" do
      let(:from) { 1 }
      let(:to) { 2 }

      it "returns customers" do
        expect(returned_ids.count).to eq(2)
        expect(returned_ids).to include(customer_first.id)
        expect(returned_ids).to include(customer_second.id)
      end
    end

    context "with subscriptions count less than a number" do
      let(:from) { nil }
      let(:to) { 2 }

      it "returns customers" do
        expect(returned_ids.count).to eq(2)
        expect(returned_ids).to include(customer_first.id)
        expect(returned_ids).to include(subscriptionless_customer.id)
      end
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
