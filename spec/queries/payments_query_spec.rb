# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentsQuery do
  subject(:result) do
    described_class.call(organization:, pagination:, filters:, search_term:)
  end

  let(:returned_ids) { result.payments.pluck(:id) }
  let(:invoice) { create(:invoice, organization:) }
  let(:invoice2) { create(:invoice, organization:) }
  let(:payment_request) { create(:payment_request, organization:) }
  let(:payment_one) { create(:payment, payable: invoice) }
  let(:payment_two) { create(:payment, payable: invoice2) }
  let(:payment_three) { create(:payment, payable: payment_request) }
  let(:pagination) { nil }
  let(:filters) { nil }
  let(:search_term) { nil }

  let_it_be(:membership) { create(:membership) }
  let_it_be(:organization) { create_default(:organization) }

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

  context "with search_term" do
    let_it_be(:customer) { create(:customer, organization:, firstname: "first", lastname: "last", external_id: "external_c_id", email: "email@example.com", name: "The name") }
    let_it_be(:invoice) { create(:invoice, :finalized, organization:, customer:, number: "number-test-123") }
    let_it_be(:invoice3) { create(:invoice, :finalized, organization:, customer:) }
    let(:payment_one) { create(:payment, payable: invoice) }
    let(:payment_two) { create(:payment, payable: invoice3) }
    let(:payment_three) { create(:payment, payable: invoice2) }
    let(:payment_four) { create(:payment, payable: payment_request) }

    before do
      payment_one
      payment_two
      payment_three
      payment_four
    end

    context "when search_term is an id" do
      let(:search_term) { payment_one.id }

      it "returns only payments for the specified id" do
        expect(result).to be_success
        expect(returned_ids.count).to eq(1)
        expect(returned_ids).to contain_exactly(payment_one.id)
      end
    end

    context "when search_term is a partial id" do
      let(:search_term) { payment_one.id.first(13) }

      it "does not match payments on a partial id" do
        expect(result).to be_success
        expect(returned_ids).not_to include(payment_one.id)
      end
    end

    context "when search_term is a uuid matching no payment" do
      let(:search_term) { "00000000-0000-0000-0000-000000000000" }

      it "returns an empty result set" do
        expect(result).to be_success
        expect(returned_ids).to be_empty
      end
    end

    context "when search_term is an invoice number" do
      let(:search_term) { invoice.number }

      it "returns only payments for the specified invoice number" do
        expect(result).to be_success
        expect(returned_ids.count).to eq(1)
        expect(returned_ids).to contain_exactly(payment_one.id)
      end
    end

    context "when search_term is a customer name" do
      let(:search_term) { customer.name }

      it "returns only payments for the specified customer name" do
        expect(result).to be_success
        expect(returned_ids.count).to eq(2)
        expect(returned_ids).to contain_exactly(payment_one.id, payment_two.id)
      end
    end

    context "when search_term is a customer email" do
      let(:search_term) { customer.email }

      it "returns only payments for the specified customer email" do
        expect(result).to be_success
        expect(returned_ids.count).to eq(2)
        expect(returned_ids).to contain_exactly(payment_one.id, payment_two.id)
      end
    end

    context "when search_term is a customer external id" do
      let(:search_term) { customer.external_id }

      it "returns only payments for the specified customer external id" do
        expect(result).to be_success
        expect(returned_ids.count).to eq(2)
        expect(returned_ids).to contain_exactly(payment_one.id, payment_two.id)
      end
    end

    context "when search_term is a customer firstname" do
      let(:search_term) { customer.firstname }

      it "returns only payments for the specified customer firstname" do
        expect(result).to be_success
        expect(returned_ids.count).to eq(2)
        expect(returned_ids).to contain_exactly(payment_one.id, payment_two.id)
      end
    end

    context "when search_term is a customer lastname" do
      let(:search_term) { customer.lastname }

      it "returns only payments for the specified customer lastname" do
        expect(result).to be_success
        expect(returned_ids.count).to eq(2)
        expect(returned_ids).to contain_exactly(payment_one.id, payment_two.id)
      end
    end
  end

  context "when filtering by invoice_id" do
    let(:filters) { {invoice_id: invoice.id} }

    it "returns only payments for the specified invoice" do
      expect(result).to be_success
      expect(returned_ids.count).to eq(1)
      expect(returned_ids).to include(payment_one.id)
      expect(returned_ids).not_to include(payment_two.id)
      expect(returned_ids).not_to include(payment_three.id)
    end

    # A LEFT JOIN on invoices_payment_requests with an OR across both tables
    # prevents Postgres from using the payable indexes, which makes the query
    # scan every payment of the organization. The ids are selected through a
    # UNION of two indexed branches instead.
    it "filters on a union of payment ids instead of a left join with an OR" do
      sql = result.payments.to_sql

      expect(sql).to match(/"payments"\."id" IN \(SELECT .+ UNION .+\)/)
      expect(sql).not_to include("LEFT JOIN invoices_payment_requests")
      expect(sql).not_to include("OR invoices_payment_requests.invoice_id")
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

  context "when filtering by invoice_id paid directly and through a payment request" do
    let(:filters) { {invoice_id: invoice.id} }
    let(:other_payment_request) { create(:payment_request, organization:) }

    before do
      create(:payment_request_applied_invoice, invoice:, payment_request:)
      create(:payment_request_applied_invoice, invoice: invoice2, payment_request:)
      create(:payment_request_applied_invoice, invoice: invoice2, payment_request: other_payment_request)
      create(:payment, payable: other_payment_request)
    end

    it "returns the direct payment and the payment of the payment request" do
      expect(result).to be_success
      expect(returned_ids).to contain_exactly(payment_one.id, payment_three.id)
    end

    context "with a currency matching one of the payments" do
      let(:filters) { {invoice_id: invoice.id, currency: "USD"} }
      let(:payment_three) { create(:payment, payable: payment_request, amount_currency: "USD") }

      it "returns only the payment with that currency" do
        expect(result).to be_success
        expect(returned_ids).to contain_exactly(payment_three.id)
      end
    end

    context "with the external_customer_id of the invoice customer" do
      let(:filters) { {invoice_id: invoice.id, external_customer_id: invoice_customer.external_id} }
      let(:invoice_customer) { create(:customer, organization:) }
      let(:invoice) { create(:invoice, organization:, customer: invoice_customer) }

      it "returns only the payment of that customer" do
        expect(result).to be_success
        expect(returned_ids).to contain_exactly(payment_one.id)
      end
    end

    context "with a search_term matching one of the payments" do
      let(:search_term) { "pr-payment-reference" }
      let(:payment_three) { create(:payment, payable: payment_request, provider_payment_id: "pr-payment-reference") }

      it "returns only the payment matching the search_term" do
        expect(result).to be_success
        expect(returned_ids).to contain_exactly(payment_three.id)
      end
    end

    context "with pagination" do
      let(:pagination) { {page: 1, limit: 1} }
      let(:second_page_ids) do
        described_class.call(organization:, pagination: {page: 2, limit: 1}, filters:, search_term:).payments.pluck(:id)
      end

      it "paginates the matching payments without duplicates" do
        expect(result).to be_success
        expect(result.payments.total_count).to eq(2)
        expect(returned_ids + second_page_ids).to contain_exactly(payment_one.id, payment_three.id)
      end
    end

    context "with distinct creation dates" do
      let(:payment_one) { create(:payment, payable: invoice, created_at: 2.days.ago) }
      let(:payment_three) { create(:payment, payable: payment_request, created_at: 1.day.ago) }
      let(:page_ids) do
        [1, 2].flat_map do |page|
          described_class.call(organization:, pagination: {page:, limit: 1}, filters:, search_term:).payments.pluck(:id)
        end
      end

      it "returns the payments in the consistent order" do
        expect(result).to be_success
        expect(returned_ids).to eq([payment_three.id, payment_one.id])
        expect(page_ids).to eq([payment_three.id, payment_one.id])
      end
    end

    context "when the invoice is not visible" do
      let(:invoice) { create(:invoice, organization:, status: :generating) }

      it "excludes the direct payment of the invoice" do
        expect(result).to be_success
        expect(returned_ids).to contain_exactly(payment_three.id)
      end
    end
  end

  context "when filtering by the invoice_id of another organization" do
    let(:filters) { {invoice_id: other_invoice.id} }
    let(:other_organization) { create(:organization) }
    let(:other_customer) { create(:customer, organization: other_organization) }
    let(:other_invoice) { create(:invoice, organization: other_organization, customer: other_customer) }

    before { create(:payment, payable: other_invoice) }

    it "returns an empty result set" do
      expect(result).to be_success
      expect(returned_ids).to be_empty
    end

    context "with a payment request of another organization" do
      let(:other_payment_request) { create(:payment_request, organization: other_organization, customer: other_customer) }

      before do
        create(:payment_request_applied_invoice, invoice: other_invoice, payment_request: other_payment_request)
        create(:payment, payable: other_payment_request, organization: other_organization, customer: other_customer)
      end

      it "does not return payments of a payment request of another organization" do
        expect(result).to be_success
        expect(returned_ids).to be_empty
      end
    end
  end

  context "when filtering by invoice_id with a payment request payment in another organization" do
    let(:filters) { {invoice_id: invoice.id} }
    let(:other_organization) { create(:organization) }
    let(:other_customer) { create(:customer, organization: other_organization) }
    let(:other_payment_request) { create(:payment_request, organization: other_organization, customer: other_customer) }

    before do
      create(:payment_request_applied_invoice, invoice:, payment_request: other_payment_request)
      create(:payment, payable: other_payment_request, organization: other_organization, customer: other_customer)
    end

    it "excludes the payment of the other organization" do
      expect(result).to be_success
      expect(returned_ids).to contain_exactly(payment_one.id)
    end
  end

  context "when filtering by external_customer_id" do
    let(:filters) { {external_customer_id: customer.external_id} }
    let(:new_payment) { create(:payment, payable: new_invoice) }
    let(:customer) { create_default(:customer) }
    let(:invoice) { create(:invoice, organization:) }

    let(:new_invoice) { create(:invoice, organization:, customer:) }

    before do
      new_payment
    end

    it "returns only payments for the specified external_customer_id" do
      expect(result).to be_success
      expect(returned_ids.count).to eq(1)
      expect(returned_ids).to include(new_payment.id)
    end
  end

  context "when filtering by an invalid external_customer_id" do
    let(:filters) { {external_customer_id: "invalid-external-id"} }

    it "returns an empty result set" do
      expect(result).to be_success
      expect(returned_ids).to be_empty
    end
  end

  context "when filtering by currency" do
    let(:filters) { {currency: "USD"} }
    let(:usd_invoice) { create(:invoice, organization:, currency: "USD") }
    let!(:usd_payment) { create(:payment, payable: usd_invoice, amount_currency: "USD") }

    it "returns only payments matching the currency" do
      expect(result).to be_success
      expect(returned_ids).to contain_exactly(usd_payment.id)
    end
  end

  context "when filtering by a currency that matches no payments" do
    let(:filters) { {currency: "GBP"} }

    it "returns an empty result set" do
      expect(result).to be_success
      expect(returned_ids).to be_empty
    end
  end

  context "when filtering with an invalid invoice_id" do
    let(:filters) { {invoice_id: "invalid-uuid"} }

    it "returns a validation error" do
      expect(result).not_to be_success
      expect(result.error.messages[:invoice_id]).to include("is in invalid format")
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
