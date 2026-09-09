# frozen_string_literal: true

RSpec.shared_examples "a payment index endpoint" do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  let(:params) { {} }

  include_examples "requires API permission", "payment", "read"

  it "returns customer's payments" do
    invoice = create(:invoice, organization:, customer:)
    invoice2 = create(:invoice, organization:, customer:)
    payment_request = create(:payment_request, organization:, customer:)
    first_payment = create(:payment, payable: invoice, customer:)
    second_payment = create(:payment, payable: invoice2, customer:)
    third_payment = create(:payment, payable: payment_request, customer:)

    subject

    expect(response).to have_http_status(:success)
    expect(json[:payments].count).to eq(3)
    expect(json[:payments].map { |r| r[:lago_id] }).to contain_exactly(
      first_payment.id,
      second_payment.id,
      third_payment.id
    )
  end

  context "with invoice_id filter" do
    let(:invoice) { create(:invoice, organization:, customer:) }
    let(:params) { {invoice_id: invoice.id} }
    let(:first_payment) { create(:payment, payable: invoice, customer:) }

    before do
      first_payment
      create(:payment)
    end

    it "returns invoice's payments" do
      subject
      expect(response).to have_http_status(:success)
      expect(json[:payments].map { |r| r[:lago_id] }).to contain_exactly(first_payment.id)
      expect(json[:payments].first[:invoice_ids].first).to eq(invoice.id)
    end
  end

  context "with list filters" do
    let(:invoice) { create(:invoice, organization:, customer:, number: "QA-INVOICE") }
    let(:payment_request) { create(:payment_request, organization:, customer:, invoices: [invoice]) }
    let(:provider) { create(:stripe_provider, organization:) }
    let(:matching_payment) do
      create(:payment, payable: payment_request, customer:, payment_type: "manual", reference: "QA transfer",
        payment_provider: provider, amount_cents: 5_000_000_000, amount_currency: "USD",
        payable_payment_status: "processing", provider_payment_method_data: {type: "card"},
        created_at: Time.utc(2026, 9, 4, 12))
    end
    let(:other_payment) do
      create(:payment, payable: create(:invoice, organization:, customer:), customer:,
        payment_provider: create(:gocardless_provider, organization:), amount_cents: 200,
        amount_currency: "EUR", payable_payment_status: "pending", created_at: Time.utc(2026, 8, 31))
    end

    before do
      matching_payment
      other_payment
      create(:payment_receipt, organization:, payment: matching_payment, number: "RCPT-2026-0001")
    end

    [
      {payment_status: "processing"},
      {payment_status: %w[processing failed]},
      {payment_statuses: %w[processing succeeded]},
      {amount_from: "5000000000"},
      {amount_from: "5000000000", amount_to: "5000000000"},
      {receipt_number: "rcpt-2026-0001"},
      {created_at_from: "2026-09-01"},
      {created_at_from: "2026-09-01", created_at_to: "2026-09-07"},
      {payment_provider_type: "stripe"},
      {payment_provider_type: ["stripe"]},
      {currency: "USD"},
      {invoice_number: "qa-invoice"},
      {payment_type: "manual"},
      {payment_type: ["manual"]},
      {payable_type: "PaymentRequest"},
      {payable_type: ["PaymentRequest"]},
      {search_term: "QA transfer"},
      {payment_status: "processing", currency: "USD", amount_from: "1000", search_term: "QA transfer"}
    ].each do |filter_params|
      context "with #{filter_params}" do
        let(:params) { filter_params }

        it "filters the response and its pagination metadata" do
          subject

          expect(response).to have_http_status(:ok)
          expect(json[:payments].map { |payment| payment[:lago_id] }).to eq([matching_payment.id])
          expect(json[:meta][:total_count]).to eq(1)
        end
      end
    end

    [{amount_to: "200"}, {created_at_to: "2026-08-31"}].each do |filter_params|
      context "with #{filter_params}" do
        let(:params) { filter_params }

        it "applies an inclusive upper bound" do
          subject

          expect(response).to have_http_status(:ok)
          expect(json[:payments].map { |payment| payment[:lago_id] }).to eq([other_payment.id])
          expect(json[:meta][:total_count]).to eq(1)
        end
      end
    end

    context "with invoice_id through a payment request" do
      let(:params) { {invoice_id: invoice.id} }

      it "preserves the existing invoice filter" do
        subject
        expect(json[:payments].map { |payment| payment[:lago_id] }).to eq([matching_payment.id])
      end
    end

    context "with invalid dates" do
      let(:params) { {created_at_from: "2026-02-30", created_at_to: "invalid"} }

      it "ignores them without rejecting the request" do
        subject
        expect(response).to have_http_status(:ok)
        expect(json[:meta][:total_count]).to eq(2)
      end
    end

    context "with bigint bounds above JavaScript precision" do
      let(:params) { {amount_from: "9007199254740993", amount_to: "9007199254740993"} }

      before do
        matching_payment.update!(amount_cents: 9_007_199_254_740_993)
        other_payment.update!(amount_cents: 9_007_199_254_740_992)
      end

      it "preserves every digit" do
        subject
        expect(response).to have_http_status(:ok)
        expect(json[:payments].map { |payment| payment[:lago_id] }).to eq([matching_payment.id])
      end
    end

    [
      {payment_status: "bogus"}, {payment_statuses: ["bogus"]},
      {payment_provider_type: ["bogus"]},
      {payment_type: "bogus"}, {payable_type: "bogus"}, {currency: "XYZ"},
      {amount_from: "-1"}, {amount_to: "-1"}, {amount_from: "1.5"},
      {amount_from: "9223372036854775808"}, {amount_from: "500", amount_to: "100"},
      {invoice_id: "not-a-uuid"}, {invoice_number: "x" * 256}, {receipt_number: "x" * 256}
    ].each do |invalid_params|
      context "with invalid #{invalid_params.keys.join(", ")}" do
        let(:params) { invalid_params }

        it "returns the standard validation error" do
          subject

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:code]).to eq("validation_errors")
          expect(json[:error_details]).to be_present
        end
      end
    end

    context "when advancing a filtered page" do
      let(:params) { {payment_status: ["processing"], currency: "USD", amount_from: "100", per_page: 1} }

      before do
        create(:payment, payable: payment_request, customer:, payment_type: "manual", reference: "Second transfer",
          amount_cents: 1000, amount_currency: "USD", payable_payment_status: "processing")
      end

      it "keeps the filtered count and predicates on subsequent pages" do
        subject
        first_ids = json[:payments].map { |payment| payment[:lago_id] }
        expect(json[:meta][:total_count]).to eq(2)
        expect(json[:meta][:next_page]).to eq(2)

        params[:page] = json[:meta][:next_page]
        # The API returns a page number, not a next-page URL.
        get_with_token(organization, request.path, params)

        expect(response).to have_http_status(:ok)
        expect(json[:meta][:current_page]).to eq(2)
        expect(json[:meta][:total_count]).to eq(2)
        expect(json[:payments].map { |payment| payment[:lago_id] } & first_ids).to be_empty
        expect(json[:payments].map { |payment| payment[:payment_status] }).to eq(["processing"])
        expect(json[:payments].map { |payment| payment[:amount_currency] }).to eq(["USD"])
      end
    end
  end
end
