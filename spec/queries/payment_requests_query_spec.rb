# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentRequestsQuery, type: :query do
  subject(:result) do
    described_class.call(organization:, pagination:, filters:)
  end

  let(:pagination) { nil }
  let(:filters) { {} }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:payment_request_first) { create(:payment_request, organization:) }
  let(:payment_request_second) { create(:payment_request, organization:, customer:) }

  before do
    payment_request_first
    payment_request_second
  end

  it "returns all payment requests", :aggregate_failures do
    expect(result).to be_success
    expect(result.payment_requests.pluck(:id)).to contain_exactly(
      payment_request_first.id,
      payment_request_second.id
    )
  end

  context "with pagination" do
    let(:pagination) { {page: 2, limit: 1} }

    it "applies the pagination", :aggregate_failures do
      expect(result).to be_success
      expect(result.payment_requests.count).to eq(1)
      expect(result.payment_requests.current_page).to eq(2)
      expect(result.payment_requests.prev_page).to eq(1)
      expect(result.payment_requests.next_page).to be_nil
      expect(result.payment_requests.total_pages).to eq(2)
      expect(result.payment_requests.total_count).to eq(2)
    end
  end

  context "when filtering by customer_id" do
    let(:filters) { {external_customer_id: customer.external_id} }

    it "returns all payment_requests of the customer", :aggregate_failures do
      expect(result).to be_success
      expect(result.payment_requests.pluck(:id)).to contain_exactly(
        payment_request_second.id
      )
    end
  end
end
