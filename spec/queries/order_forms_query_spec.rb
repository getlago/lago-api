# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrderFormsQuery do
  subject(:result) do
    described_class.call(organization:, pagination:, filters:, search_term:)
  end

  let(:returned_ids) { result.order_forms.pluck(:id) }
  let(:pagination) { nil }
  let(:filters) { nil }
  let(:search_term) { nil }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:) }
  let(:order_form_one) { create(:order_form, organization:, customer:, quote:) }
  let(:order_form_two) { create(:order_form, organization:, customer:, quote:) }

  before do
    order_form_one
    order_form_two
  end

  it "returns all order forms for the organization" do
    expect(result).to be_success
    expect(returned_ids).to match_array([order_form_one.id, order_form_two.id])
  end

  context "with pagination" do
    let(:pagination) { {page: 2, limit: 1} }

    it "applies the pagination" do
      expect(result).to be_success
      expect(result.order_forms.count).to eq(1)
      expect(result.order_forms.current_page).to eq(2)
      expect(result.order_forms.total_pages).to eq(2)
      expect(result.order_forms.total_count).to eq(2)
    end
  end

  context "when filtering by status" do
    let(:order_form_two) { create(:order_form, :signed, organization:, customer:, quote:) }
    let(:filters) { {status: "generated"} }

    it "returns only order forms with the specified status" do
      expect(result).to be_success
      expect(returned_ids).to eq([order_form_one.id])
    end
  end

  context "when filtering by external_customer_id" do
    let(:other_customer) { create(:customer, organization:) }
    let(:other_quote) { create(:quote, organization:, customer: other_customer) }
    let(:order_form_two) { create(:order_form, organization:, customer: other_customer, quote: other_quote) }
    let(:filters) { {external_customer_id: customer.external_id} }

    it "returns only order forms for the specified customer" do
      expect(result).to be_success
      expect(returned_ids).to eq([order_form_one.id])
    end
  end

  context "with search_term on number" do
    let(:search_term) { order_form_one.number }

    it "returns matching order forms" do
      expect(result).to be_success
      expect(returned_ids).to eq([order_form_one.id])
    end
  end

  context "when no order forms exist" do
    before { OrderForm.delete_all }

    it "returns an empty result set" do
      expect(result).to be_success
      expect(returned_ids).to be_empty
    end
  end
end
