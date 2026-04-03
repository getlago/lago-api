# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrdersQuery do
  subject(:result) do
    described_class.call(organization:, pagination:, filters:, search_term:)
  end

  let(:returned_ids) { result.orders.pluck(:id) }
  let(:pagination) { nil }
  let(:filters) { nil }
  let(:search_term) { nil }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:) }
  let(:order_form) { create(:order_form, :signed, organization:, customer:, quote:) }
  let(:order_one) { create(:order, organization:, customer:, order_form:) }
  let(:order_form_two) { create(:order_form, :signed, organization:, customer:, quote:) }
  let(:order_two) { create(:order, organization:, customer:, order_form: order_form_two, order_type: :one_off) }

  before do
    order_one
    order_two
  end

  it "returns all orders for the organization" do
    expect(result).to be_success
    expect(returned_ids).to match_array([order_one.id, order_two.id])
  end

  context "with pagination" do
    let(:pagination) { {page: 2, limit: 1} }

    it "applies the pagination" do
      expect(result).to be_success
      expect(result.orders.count).to eq(1)
      expect(result.orders.current_page).to eq(2)
      expect(result.orders.total_pages).to eq(2)
      expect(result.orders.total_count).to eq(2)
    end
  end

  context "when filtering by status" do
    let(:filters) { {status: "created"} }

    it "returns only orders with the specified status" do
      expect(result).to be_success
      expect(returned_ids).to match_array([order_one.id, order_two.id])
    end
  end

  context "when filtering by order_type" do
    let(:filters) { {order_type: "one_off"} }

    it "returns only orders with the specified order type" do
      expect(result).to be_success
      expect(returned_ids).to eq([order_two.id])
    end
  end

  context "when filtering by external_customer_id" do
    let(:other_customer) { create(:customer, organization:) }
    let(:other_quote) { create(:quote, organization:, customer: other_customer) }
    let(:other_order_form) { create(:order_form, :signed, organization:, customer: other_customer, quote: other_quote) }
    let(:order_two) { create(:order, organization:, customer: other_customer, order_form: other_order_form) }
    let(:filters) { {external_customer_id: customer.external_id} }

    it "returns only orders for the specified customer" do
      expect(result).to be_success
      expect(returned_ids).to eq([order_one.id])
    end
  end

  context "with search_term on number" do
    let(:search_term) { order_one.number }

    it "returns matching orders" do
      expect(result).to be_success
      expect(returned_ids).to eq([order_one.id])
    end
  end

  context "when no orders exist" do
    before { Order.delete_all }

    it "returns an empty result set" do
      expect(result).to be_success
      expect(returned_ids).to be_empty
    end
  end
end
