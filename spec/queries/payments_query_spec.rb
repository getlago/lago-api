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

  context "when filtering by invoice_id with a payment request including the invoice" do
    let(:filters) { {invoice_id: invoice.id} }

    before { create(:payment_request_applied_invoice, invoice:, payment_request:) }

    it "returns each payment of the invoice and of its payment request once, not those of another invoice" do
      expect(result).to be_success
      expect(returned_ids.size).to eq(2)
      expect(returned_ids).to match_array([payment_one.id, payment_three.id])
      expect(returned_ids).not_to include(payment_two.id)
    end

    context "with sequential and bitmap scans disabled" do
      before do
        %w[enable_seqscan enable_bitmapscan].each do |setting|
          ActiveRecord::Base.connection.execute("SET LOCAL #{setting} = off")
        end
      end

      # An OR across a join of invoices_payment_requests scans every payment of the organization.
      it "selects the payment ids through the payable and the applied invoice indexes" do
        plan = ActiveRecord::Base.connection.select_rows("EXPLAIN #{result.payments.to_sql}").flatten.join("\n")

        expect(plan).to include("index_payments_on_payable_type_and_payable_id")
        expect(plan).to match(/index_invoices_payment_requests_on_invoice_id|idx_on_invoice_id_payment_request_id_aa550779a4/)
        expect(returned_ids).to match_array([payment_one.id, payment_three.id])
      end
    end
  end

  context "when the invoice belongs to another organization" do
    let(:filters) { {invoice_id: other_invoice.id} }
    let(:other_organization) { create(:organization) }
    let(:other_customer) { create(:customer, organization: other_organization) }
    let(:other_invoice) { create(:invoice, organization: other_organization, customer: other_customer) }
    let(:other_payment_request) { create(:payment_request, organization: other_organization, customer: other_customer) }

    before do
      create(:payment_request_applied_invoice, invoice: other_invoice, payment_request: other_payment_request, organization: other_organization)
      create(:payment, payable: other_invoice, organization: other_organization, customer: other_customer)
      create(:payment, payable: other_payment_request, organization: other_organization, customer: other_customer)
    end

    it "returns no payments" do
      expect(result).to be_success
      expect(returned_ids).to eq([])
    end

    context "when a payment request of this organization is applied to it in the other organization" do
      let(:own_payment_request) { create(:payment_request, organization:) }

      before do
        create(:payment, payable: own_payment_request, organization:)
        create(:payment_request_applied_invoice, invoice: other_invoice, payment_request: own_payment_request, organization: other_organization)
      end

      it "does not return a payment request payment of this organization through another organization applied invoice" do
        expect(result).to be_success
        expect(returned_ids).to eq([])
      end
    end
  end

  context "when the invoice filter is combined with other filters and pagination" do
    let(:filters) do
      {invoice_id: invoice.id, currency: "EUR", external_customer_id: invoice.customer.external_id}
    end
    let(:pagination) { {page: 1, limit: 1} }
    let(:payment_request) { create(:payment_request, organization:, customer: invoice.customer) }
    let(:payment_three) { create(:payment, payable: payment_request, provider_payment_id: "pr-payment-ref") }

    before do
      create(:payment_request_applied_invoice, invoice:, payment_request:)
      # Failed attempts, as only one pending provider payment is allowed per invoice.
      # Excluded by the currency filter.
      create(:payment, payable: invoice, amount_currency: "USD", status: "failed", payable_payment_status: "failed")
      # Excluded by the external_customer_id filter.
      create(:payment, payable: invoice, customer: create(:customer, organization:), status: "failed", payable_payment_status: "failed")
    end

    it "paginates the intersection of the filters" do
      expect(result).to be_success
      expect(result.payments.total_count).to eq(2)
      expect(returned_ids.size).to eq(1)
      expect([payment_one.id, payment_three.id]).to include(returned_ids.first)
    end

    context "with a search_term" do
      let(:search_term) { "pr-payment-ref" }

      it "returns the intersection with the search" do
        expect(result).to be_success
        expect(result.payments.total_count).to eq(1)
        expect(returned_ids).to eq([payment_three.id])
      end
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

  context "when filtering by customer_id" do
    let(:filters) { {customer_id: customer.id} }
    let(:customer) { create(:customer, organization:, external_id: "reused") }
    let(:deleted_customer) { create(:customer, organization:, external_id: "reused", deleted_at: Time.current) }
    let(:customer_payment) { create(:payment, payable: create(:invoice, organization:, customer:)) }

    before do
      create(:payment, payable: create(:invoice, organization:, customer: deleted_customer))
      customer_payment
    end

    it "returns only the payments of that customer, not of a deleted one sharing its external id" do
      expect(result).to be_success
      expect(returned_ids).to eq([customer_payment.id])
    end
  end

  context "when filtering by an invalid customer_id" do
    let(:filters) { {customer_id: "not-a-uuid"} }

    it "returns a validation error" do
      expect(result).not_to be_success
      expect(result.error.messages[:customer_id]).to include("is in invalid format")
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
