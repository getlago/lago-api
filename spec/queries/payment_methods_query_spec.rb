# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentMethodsQuery do
  subject(:result) do
    described_class.call(organization:, pagination:, filters:)
  end

  let(:returned_ids) { result.payment_methods.pluck(:id) }

  let(:pagination) { nil }
  let(:filters) { {} }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:payment_method_first) { create(:payment_method, organization:) }
  let(:payment_method_second) { create(:payment_method, organization:, customer:) }

  before do
    payment_method_first
    payment_method_second
  end

  it "returns all payment methods" do
    expect(result).to be_success
    expect(returned_ids).to contain_exactly(payment_method_first.id, payment_method_second.id)
  end

  context "when payment methods have the same values for the ordering criteria" do
    let(:payment_method_second) do
      create(
        :payment_method,
        organization:,
        customer:,
        id: "00000000-0000-0000-0000-000000000000",
        created_at: payment_method_first.created_at
      )
    end

    it "returns a consistent list" do
      expect(result).to be_success
      expect(returned_ids.count).to eq(2)
      expect(returned_ids).to include(payment_method_first.id)
      expect(returned_ids).to include(payment_method_second.id)
      expect(returned_ids.index(payment_method_first.id)).to be > returned_ids.index(payment_method_second.id)
    end
  end

  context "with pagination" do
    let(:pagination) { {page: 2, limit: 1} }

    it "applies the pagination" do
      expect(result).to be_success
      expect(result.payment_methods.count).to eq(1)
      expect(result.payment_methods.current_page).to eq(2)
      expect(result.payment_methods.prev_page).to eq(1)
      expect(result.payment_methods.next_page).to be_nil
      expect(result.payment_methods.total_pages).to eq(2)
      expect(result.payment_methods.total_count).to eq(2)
    end
  end

  context "when filtering by customer_id" do
    let(:filters) { {external_customer_id: customer.external_id} }

    it "returns all payment methods of the customer" do
      expect(result).to be_success
      expect(returned_ids).to contain_exactly(payment_method_second.id)
    end
  end
end
