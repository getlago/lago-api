# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentsQuery do
  subject(:result) do
    described_class.call(organization:, pagination:, filters:, search_term:)
  end

  let(:returned_ids) { result.payments.pluck(:id) }
  let(:pagination) { nil }
  let(:filters) { nil }
  let(:search_term) { nil }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:invoice) { create(:invoice, organization:) }
  let(:invoice2) { create(:invoice, organization:) }
  let(:payment_request) { create(:payment_request, organization:) }
  let(:payment_one) { create(:payment, payable: invoice) }
  let(:payment_two) { create(:payment, payable: invoice2) }
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

  context "with search_term" do
    let(:customer) { create(:customer, organization:, firstname: "first", lastname: "last", external_id: "external_c_id", email: "email@example.com", name: "The name") }
    let(:invoice) { create(:invoice, :finalized, organization:, customer:, number: "number-test-123") }
    let(:invoice3) { create(:invoice, :finalized, organization:, customer:) }
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

  context "when filtering by external_customer_id" do
    let(:filters) { {external_customer_id: customer.external_id} }
    let(:customer) { create(:customer, organization:) }
    let(:new_invoice) { create(:invoice, organization:, customer:) }
    let(:new_payment) { create(:payment, payable: new_invoice) }

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

  context "with payment status filters" do
    before do
      payment_one.update!(payable_payment_status: "processing")
      payment_two.update!(payable_payment_status: "failed")
      payment_three.update!(payable_payment_status: "succeeded")
    end

    context "with one status" do
      let(:filters) { {payment_status: "processing"} }

      it "matches the payment status, including processing" do
        expect(returned_ids).to eq([payment_one.id])
      end
    end

    context "with several statuses" do
      let(:filters) { {payment_status: %w[succeeded failed]} }

      it "combines statuses with OR" do
        expect(returned_ids).to match_array([payment_two.id, payment_three.id])
      end
    end
  end

  context "with amount filters" do
    before do
      payment_one.update!(amount_cents: 0)
      payment_two.update!(amount_cents: 1000)
      payment_three.update!(amount_cents: 5000)
    end

    [
      [{amount_from: "1000"}, %i[payment_two payment_three]],
      [{amount_to: 1000}, %i[payment_one payment_two]],
      [{amount_from: 1000, amount_to: 5000}, %i[payment_two payment_three]],
      [{amount_from: 0, amount_to: 0}, %i[payment_one]],
      [{amount_from: 1001, amount_to: 4999}, []]
    ].each do |amount_filters, expected|
      context "with #{amount_filters}" do
        let(:filters) { amount_filters }

        it "uses inclusive integer bounds" do
          expect(returned_ids).to match_array(expected.map { |name| public_send(name).id })
        end
      end
    end

    context "with amounts above the JavaScript safe integer limit" do
      let(:filters) { {amount_from: "9007199254740993", amount_to: "9223372036854775807"} }

      before do
        payment_one.update!(amount_cents: 9_007_199_254_740_992)
        payment_two.update!(amount_cents: 9_007_199_254_740_993)
        payment_three.update!(amount_cents: 9_223_372_036_854_775_807)
      end

      it "distinguishes adjacent amounts without rounding" do
        expect(returned_ids).to match_array([payment_two.id, payment_three.id])
      end
    end
  end

  context "with receipt number" do
    let(:filters) { {receipt_number: "rcpt-2026-0001"} }

    before { create(:payment_receipt, organization:, payment: payment_one, number: "RCPT-2026-0001") }

    it "matches exactly without case sensitivity and excludes missing receipts" do
      expect(returned_ids).to eq([payment_one.id])
    end

    context "with a partial number" do
      let(:filters) { {receipt_number: "RCPT-2026"} }

      it "does not match a prefix" do
        expect(returned_ids).to be_empty
      end
    end

    context "with receipt number as search only" do
      let(:filters) { {} }
      let(:search_term) { "RCPT-2026-0001" }

      it "does not add receipts to free-text search" do
        expect(returned_ids).to be_empty
      end
    end
  end

  context "with created date range" do
    let(:filters) { {created_at_from: "2026-11-01", created_at_to: Date.new(2026, 11, 1)} }
    let(:zone) { ActiveSupport::TimeZone["America/Los_Angeles"] }

    before do
      organization.default_billing_entity.update!(timezone: zone.name)
      payment_one.update!(created_at: zone.local(2026, 11, 1))
      payment_two.update!(created_at: zone.local(2026, 11, 1).end_of_day)
      payment_three.update!(created_at: zone.local(2026, 11, 2))
      create(:payment, payable: create(:invoice, organization:), created_at: zone.local(2026, 11, 1) - Rational(1, 1_000_000))
    end

    it "includes both boundary instants across a 25-hour DST day" do
      expect(returned_ids).to match_array([payment_one.id, payment_two.id])
    end

    context "with only a lower bound" do
      let(:filters) { {created_at_from: "2026-11-02"} }

      it "includes subsequent payments" do
        expect(returned_ids).to eq([payment_three.id])
      end
    end

    context "with only an upper bound" do
      let(:filters) { {created_at_to: "2026-11-01"} }

      it "includes earlier days" do
        expect(returned_ids.size).to eq(3)
      end
    end
  end

  context "with payment provider type" do
    let(:filters) { {payment_provider_type: ["gocardless"]} }

    before do
      payment_one.update!(payment_provider: create(:gocardless_provider, organization:))
      payment_two.update!(payment_provider: nil)
      payment_three.update!(payment_provider: create(:stripe_provider, organization:))
    end

    it "maps API names to provider STI types" do
      expect(returned_ids).to eq([payment_one.id])
    end

    context "with multiple provider types" do
      let(:filters) { {payment_provider_type: %w[gocardless stripe]} }

      it "matches either provider and excludes payments without a provider" do
        expect(returned_ids).to match_array([payment_one.id, payment_three.id])
      end
    end
  end

  context "with payment method type" do
    let(:filters) { {payment_method_type: %w[card sepa_debit]} }
    let(:method) { create(:payment_method, organization:, provider_method_type: "sepa_debit") }

    before do
      payment_one.update!(provider_payment_method_data: {type: "card"})
      payment_two.update!(provider_payment_method_data: {}, payment_method: method)
      payment_three.update!(provider_payment_method_data: {type: "link"}, payment_method: method)
    end

    it "uses JSON first and falls back to the associated method" do
      expect(returned_ids).to match_array([payment_one.id, payment_two.id])
    end

    [nil, ""].each do |empty_type|
      context "when JSON type is #{empty_type.inspect}" do
        before { payment_two.update!(provider_payment_method_data: {type: empty_type}) }

        it "falls back for an empty JSON type" do
          expect(returned_ids).to match_array([payment_one.id, payment_two.id])
        end
      end
    end

    context "when neither source supplies a method" do
      before { payment_two.update!(payment_method: nil) }

      it "does not match" do
        expect(returned_ids).to eq([payment_one.id])
      end
    end
  end

  context "with invoice number" do
    let(:filters) { {invoice_number: "lag-1234-001-002"} }

    before do
      invoice.update!(number: "LAG-1234-001-002")
      invoice2.update!(number: "LAG-1234-001-002-extra")
      create(:payment_request_applied_invoice, invoice:, payment_request:)
      create(:payment_request_applied_invoice, invoice: invoice2, payment_request:)
    end

    it "matches both payable paths exactly, without case sensitivity" do
      expect(returned_ids).to match_array([payment_one.id, payment_three.id])
    end

    context "when several invoices have the same number" do
      let(:pagination) { {page: 1, limit: 1} }

      before { invoice2.update!(number: invoice.number) }

      it "counts and paginates each payment once" do
        expect(result.payments.total_count).to eq(3)
        expect(result.payments.size).to eq(1)
        expect(result.payments.to_sql).not_to include("DISTINCT")
      end
    end

    context "with search on the same invoice number" do
      let(:search_term) { "LAG-1234-001-002" }

      it "skips the redundant invoice search branch" do
        expect(returned_ids).to be_empty
      end

      context "when another search branch matches" do
        before { payment_one.update!(provider_payment_id: "pi_LAG-1234-001-002") }

        it "still narrows the exact filter by search" do
          expect(returned_ids).to eq([payment_one.id])
        end
      end
    end
  end

  context "with payment type" do
    let(:filters) { {payment_type: "manual"} }

    before { payment_three.update!(payment_type: "manual", reference: "bank transfer") }

    it "matches manual payments" do
      expect(returned_ids).to eq([payment_three.id])
    end
  end

  context "with payable type" do
    let(:filters) { {payable_type: ["PaymentRequest"]} }

    it "matches payment requests" do
      expect(returned_ids).to eq([payment_three.id])
    end
  end

  context "with every filter set" do
    let(:filters) do
      {
        external_customer_id: payment_one.customer.external_id, currency: "EUR", payment_status: %w[failed pending],
        amount_from: 100, amount_to: 10_000, receipt_number: "RCPT-1", created_at_from: "2026-01-01", created_at_to: "2026-01-31",
        payment_provider_type: %w[stripe], payment_method_type: %w[card], invoice_number: "INV-1",
        payment_type: %w[provider], payable_type: %w[Invoice]
      }
    end
    let(:search_term) { "term" }

    # Tripwire for the shapes that defeat the payments indexes on large organizations.
    # Plan shapes are not asserted (too brittle on a tiny dataset); the SQL text is.
    it "keeps the generated SQL indexable" do
      sql = result.payments.to_sql

      expect(sql).not_to include("DISTINCT")
      # A function around an indexed payments column disables index_payments_by_cursor and any amount index.
      expect(sql).not_to match(/\w+\(\s*"?payments"?\."?(created_at|amount_cents)"?\s*\)/i)
      # Receipts and invoices are resolved through organization-scoped sub-selects, never joined.
      expect(sql).not_to match(/JOIN\s+"?(payment_receipts|invoices|payment_methods|customers)"?/i)
      expect(sql.scan("lower(").count).to eq(sql.scan(/lower\((payment_receipts|invoices)\.number\)/).count * 2)
    end
  end

  context "with composed filters" do
    let(:filters) { {payment_status: ["succeeded"], amount_from: 200, currency: "USD"} }

    before do
      payment_one.update!(payable_payment_status: "succeeded", amount_currency: "USD")
      payment_two.update!(payable_payment_status: "succeeded", amount_currency: "EUR")
      payment_three.update!(payable_payment_status: "failed", amount_currency: "USD")
      create(:payment, payable: create(:invoice, :open, organization:), payable_payment_status: "succeeded", amount_currency: "USD")
      create(:payment, payable_payment_status: "succeeded", amount_currency: "USD")
    end

    it "ANDs filters without exposing invisible invoices or other organizations" do
      expect(returned_ids).to eq([payment_one.id])
    end

    context "when the matching invoice is draft" do
      before { invoice.update!(status: :draft) }

      it "preserves the existing visible status contract" do
        expect(returned_ids).to eq([payment_one.id])
      end
    end
  end
end
