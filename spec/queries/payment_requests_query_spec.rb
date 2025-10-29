# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequestsQuery do
  subject(:result) do
    described_class.call(organization:, pagination:, filters:)
  end

  let(:returned_ids) { result.payment_requests.pluck(:id) }

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

  it "returns all payment requests" do
    expect(result).to be_success
    expect(result.payment_requests.pluck(:id)).to contain_exactly(
      payment_request_first.id,
      payment_request_second.id
    )
  end

  context "when payment requests have the same values for the ordering criteria" do
    let(:payment_request_second) do
      create(
        :payment_request,
        organization:,
        customer:,
        id: "00000000-0000-0000-0000-000000000000",
        created_at: payment_request_first.created_at
      )
    end

    it "returns a consistent list" do
      expect(result).to be_success
      expect(returned_ids.count).to eq(2)
      expect(returned_ids).to include(payment_request_first.id)
      expect(returned_ids).to include(payment_request_second.id)
      expect(returned_ids.index(payment_request_first.id)).to be > returned_ids.index(payment_request_second.id)
    end
  end

  context "with pagination" do
    let(:pagination) { {page: 2, limit: 1} }

    it "applies the pagination" do
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

    it "returns all payment_requests of the customer" do
      expect(result).to be_success
      expect(result.payment_requests.pluck(:id)).to contain_exactly(
        payment_request_second.id
      )
    end
  end

  context "when filtering by payment_status" do
    context "when pending status" do
      let(:filters) { {payment_status: :pending} }

      it "returns all payment_requests with status pending" do
        expect(result).to be_success
        expect(result.payment_requests.count).to eq(2)
        expect(result.payment_requests.pluck(:id)).to contain_exactly(
          payment_request_first.id,
          payment_request_second.id
        )
      end
    end

    context "when succeeded status" do
      let(:filters) { {payment_status: :succeeded} }

      before { payment_request_second.payment_succeeded! }

      it "returns all payment_requests with status pending" do
        expect(result).to be_success
        expect(result.payment_requests.count).to eq(1)
        expect(result.payment_requests.pluck(:id)).to contain_exactly(
          payment_request_second.id
        )
      end
    end
  end
end
