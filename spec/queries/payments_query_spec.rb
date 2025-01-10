# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentsQuery, type: :query do
  subject(:result) do
    described_class.call(organization:, pagination:, filters:)
  end

  let(:returned_ids) { result.payments.pluck(:id) }
  let(:pagination) { nil }
  let(:filters) { nil }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:invoice) { create(:invoice, organization:) }
  let(:payment_request) { create(:payment_request, organization:) }
  let(:payment_one) { create(:payment, payable: invoice) }
  let(:payment_two) { create(:payment, payable: invoice) }
  let(:payment_three) { create(:payment, payable: payment_request) }

  before do
    payment_one
    payment_two
    payment_three
  end

  it "returns all payments for the organization" do
    expect(result).to be_success
    expect(returned_ids.count).to eq(3)
    expect(returned_ids).to include(payment_one.id)
    expect(returned_ids).to include(payment_two.id)
    expect(returned_ids).to include(payment_three.id)
  end

  context "with pagination" do
    let(:pagination) { {page: 2, limit: 2} }

    it "applies the pagination" do
      expect(result).to be_success
      expect(result.payments.count).to eq(1)
      expect(result.payments.current_page).to eq(2)
      expect(result.payments.prev_page).to eq(1)
      expect(result.payments.next_page).to be_nil
      expect(result.payments.total_pages).to eq(2)
      expect(result.payments.total_count).to eq(3)
    end
  end

  context "when filtering by invoice_id" do
    let(:filters) { {invoice_id: invoice.id} }

    it "returns only payments for the specified invoice" do
      expect(result).to be_success
      expect(returned_ids.count).to eq(2)
      expect(returned_ids).to include(payment_one.id)
      expect(returned_ids).to include(payment_two.id)
      expect(returned_ids).not_to include(payment_three.id)
    end
  end

  context "when filtering by invoice_id of a payment request" do
    let(:filters) { {invoice_id: invoice_pr.id} }
    let(:invoice_pr) { create(:invoice, organization:) }

    before do
      create(:payment_request_applied_invoice, invoice: invoice_pr, payment_request:)
    end

    it "returns only payments for the specified invoice" do
      expect(result).to be_success
      expect(returned_ids.count).to eq(1)
      expect(returned_ids).to include(payment_three.id)
    end
  end

  context "when filtering with an invalid invoice_id" do
    let(:filters) { {invoice_id: "invalid-uuid"} }

    it "returns a validation error" do
      expect(result).not_to be_success
      expect(result.error.messages[:filters][:invoice_id]).to include("must be a valid UUID")
    end
  end

  context "when no payments exist" do
    before do
      Payment.delete_all
    end

    it "returns an empty result set" do
      expect(result).to be_success
      expect(returned_ids).to be_empty
    end
  end
end
