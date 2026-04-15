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

    context "with multiple external_customer_ids" do
      let(:filters) { {external_customer_id: [customer.external_id, other_customer.external_id]} }

      it "returns order forms for all specified customers" do
        expect(result).to be_success
        expect(returned_ids).to match_array([order_form_one.id, order_form_two.id])
      end
    end
  end

  context "when filtering by number" do
    let(:filters) { {number: [order_form_one.number]} }

    it "returns only order forms with the specified numbers" do
      expect(result).to be_success
      expect(returned_ids).to eq([order_form_one.id])
    end
  end

  context "when filtering by customer_id" do
    let(:other_customer) { create(:customer, organization:) }
    let(:other_quote) { create(:quote, organization:, customer: other_customer) }
    let(:order_form_two) { create(:order_form, organization:, customer: other_customer, quote: other_quote) }
    let(:filters) { {customer_id: [customer.id]} }

    it "returns only order forms for the specified customer ids" do
      expect(result).to be_success
      expect(returned_ids).to eq([order_form_one.id])
    end
  end

  context "when filtering by owner_id" do
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }
    let(:other_quote) { create(:quote, organization:, customer:) }
    let(:order_form_two) { create(:order_form, organization:, customer:, quote: other_quote) }

    before do
      QuoteOwner.create!(quote:, user:, organization_id: organization.id)
      QuoteOwner.create!(quote: other_quote, user: other_user, organization_id: organization.id)
    end

    let(:filters) { {owner_id: [user.id]} }

    it "returns only order forms owned by the specified user" do
      expect(result).to be_success
      expect(returned_ids).to eq([order_form_one.id])
    end
  end

  context "when filtering by quote_number" do
    let(:other_customer) { create(:customer, organization:) }
    let(:other_quote) { create(:quote, organization:, customer: other_customer) }
    let(:order_form_two) { create(:order_form, organization:, customer: other_customer, quote: other_quote) }
    let(:filters) { {quote_number: [quote.number]} }

    it "returns only order forms for the specified quote numbers" do
      expect(result).to be_success
      expect(returned_ids).to eq([order_form_one.id])
    end
  end

  context "when filtering by order_form_date_from" do
    let(:order_form_one) { create(:order_form, organization:, customer:, quote:, created_at: 3.days.ago) }
    let(:order_form_two) { create(:order_form, organization:, customer:, quote:, created_at: 1.day.ago) }
    let(:filters) { {order_form_date_from: 2.days.ago.iso8601} }

    it "returns only order forms created on or after the date" do
      expect(result).to be_success
      expect(returned_ids).to eq([order_form_two.id])
    end
  end

  context "when filtering by order_form_date_to" do
    let(:order_form_one) { create(:order_form, organization:, customer:, quote:, created_at: 3.days.ago) }
    let(:order_form_two) { create(:order_form, organization:, customer:, quote:, created_at: 1.day.ago) }
    let(:filters) { {order_form_date_to: 2.days.ago.iso8601} }

    it "returns only order forms created on or before the date" do
      expect(result).to be_success
      expect(returned_ids).to eq([order_form_one.id])
    end
  end

  context "when filtering by expiry_date_from" do
    let(:order_form_one) { create(:order_form, organization:, customer:, quote:, expires_at: 1.day.from_now) }
    let(:order_form_two) { create(:order_form, organization:, customer:, quote:, expires_at: 5.days.from_now) }
    let(:filters) { {expiry_date_from: 3.days.from_now.iso8601} }

    it "returns only order forms expiring on or after the date" do
      expect(result).to be_success
      expect(returned_ids).to eq([order_form_two.id])
    end
  end

  context "when filtering by expiry_date_to" do
    let(:order_form_one) { create(:order_form, organization:, customer:, quote:, expires_at: 1.day.from_now) }
    let(:order_form_two) { create(:order_form, organization:, customer:, quote:, expires_at: 5.days.from_now) }
    let(:filters) { {expiry_date_to: 3.days.from_now.iso8601} }

    it "returns only order forms expiring on or before the date" do
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
