# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNotes::EstimateService, :premium do
  subject(:estimate_service) { described_class.new(invoice: invoice&.reload, items:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:) }

  let_it_be(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      currency: "EUR",
      fees_amount_cents: 20,
      coupons_amount_cents: 10,
      taxes_amount_cents: 2,
      sub_total_including_taxes_amount_cents: 12,
      total_amount_cents: 12,
      payment_status: :succeeded,
      taxes_rate: 20,
      version_number: 3
    )
  end
  let(:tax) { create(:tax, organization:, rate: 20) }
  let(:invoice_applied_tax) { create(:invoice_applied_tax, tax:, invoice:) }

  let(:params) { {invoice_id: invoice&.id, amount_cents: 9, reference: "ref1"} }

  context "when invoice is subscription" do
    let(:fee1) do
      create(:fee, invoice:, amount_cents: 10, taxes_amount_cents: 1, taxes_rate: 20, precise_coupons_amount_cents: 5)
    end

    let(:fee2) do
      create(:fee, invoice:, amount_cents: 10, taxes_amount_cents: 1, taxes_rate: 20, precise_coupons_amount_cents: 5)
    end

    let(:items) do
      [
        {
          fee_id: fee1.id,
          amount_cents: 10
        },
        {
          fee_id: fee2.id,
          amount_cents: 5
        }
      ]
    end

    before do
      create(:fee_applied_tax, tax:, fee: fee1)
      create(:fee_applied_tax, tax:, fee: fee2) if fee2
      invoice_applied_tax if invoice
      Payments::ManualCreateService.call(organization:, params:)
    end

    it "estimates the credit and refund amount" do
      result = estimate_service.call

      expect(result).to be_success

      credit_note = result.credit_note
      expect(credit_note).to have_attributes(
        invoice:,
        customer:,
        currency: invoice.currency,
        sub_total_excluding_taxes_amount_cents: 8,
        credit_amount_cents: 9,
        refund_amount_cents: 9,
        coupons_adjustment_amount_cents: 8,
        taxes_amount_cents: 1,
        total_amount_cents: 9,
        taxes_rate: 20
      )

      expect(credit_note.applied_taxes.size).to eq(1)

      expect(credit_note.items.size).to eq(2)

      item1 = credit_note.items.first
      expect(item1).to have_attributes(
        fee: fee1,
        amount_cents: 10,
        amount_currency: invoice.currency
      )

      item2 = credit_note.items.last
      expect(item2).to have_attributes(
        fee: fee2,
        amount_cents: 5,
        amount_currency: invoice.currency
      )
    end

    context "with invalid items" do
      let(:items) do
        [
          {
            fee_id: fee1.id,
            amount_cents: 10
          },
          {
            fee_id: fee2.id,
            amount_cents: 15
          }
        ]
      end

      it "returns a failed result" do
        result = estimate_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages.keys).to include(:amount_cents)
        expect(result.error.messages[:amount_cents]).to eq(
          %w[
            higher_than_remaining_fee_amount
          ]
        )
      end
    end

    context "when a fee tax has no matching invoice tax" do
      let(:invoice_applied_tax) { nil }

      it "returns the apply taxes failure" do
        result = estimate_service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("invoice_applied_tax_not_found")
      end
    end

    context "with missing items" do
      let(:items) {}

      it "returns a failed result" do
        result = estimate_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages.keys).to include(:items)
        expect(result.error.messages[:items]).to eq(
          %w[
            must_be_an_array
          ]
        )
      end
    end

    context "when invoice is legacy" do
      let(:invoice) do
        create(
          :invoice,
          currency: "EUR",
          sub_total_excluding_taxes_amount_cents: 20,
          total_amount_cents: 24,
          payment_status: :succeeded,
          taxes_rate: 20,
          version_number: 1
        )
      end

      it "returns a failure" do
        result = estimate_service.call

        expect(result).not_to be_success

        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("invalid_type_or_status")
      end
    end

    context "with rounding adjustment" do
      let(:tax) { create(:tax, organization:, rate: 25) }

      let(:invoice) do
        create(
          :invoice,
          total_amount_cents: 25000,
          taxes_amount_cents: 5000,
          sub_total_including_taxes_amount_cents: 25000,
          fees_amount_cents: 20000,
          total_paid_amount_cents: 25000,
          taxes_rate: 25,
          payment_status: :succeeded
        )
      end

      let(:fee1) do
        create(
          :fee,
          invoice:,
          amount_cents: 20000,
          taxes_rate: 25,
          taxes_amount_cents: 5000,
          taxes_precise_amount_cents: 5000
        )
      end

      let(:fee2) { nil }

      let(:items) do
        [
          {
            fee_id: fee1.id,
            amount_cents: 19333
          }
        ]
      end

      let(:params) { {invoice_id: invoice&.id, amount_cents: 25000, reference: "ref1"} }

      it "estimates the credit note" do
        result = estimate_service.call

        expect(result).to be_success

        credit_note = result.credit_note
        expect(credit_note).to have_attributes(
          currency: invoice.currency,
          sub_total_excluding_taxes_amount_cents: 19333,
          credit_amount_cents: 24166,
          refund_amount_cents: 24166,
          coupons_adjustment_amount_cents: 0,
          taxes_amount_cents: 4833,
          taxes_rate: 25
        )
      end
    end
  end

  context "when invoice is not found" do
    let(:invoice) { nil }
    let(:items) { [] }

    it "returns a failure" do
      result = estimate_service.call

      expect(result).not_to be_success

      expect(result.error).to be_a(BaseService::NotFoundFailure)
      expect(result.error.message).to eq("invoice_not_found")
    end
  end

  context "when estimating a contract product fee" do
    before { Organization.find(invoice.organization_id).enable_feature_flag!(:product_catalog) }

    let(:invoice) do
      create(:invoice, organization:, customer:, currency: "EUR", fees_amount_cents: 100, status: :finalized,
        total_amount_cents: 100, total_paid_amount_cents: 100, taxes_amount_cents: 0,
        payment_status: :succeeded, version_number: 3)
    end
    let(:contract) { create(:contract, organization:, customer:) }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }
    let(:rate_card_rate) { create(:rate_card_rate, organization: contract_rate_card.organization, rate_card: contract_rate_card.rate_card) }
    let(:fee) do
      create(:fee, invoice:, subscription: nil, fee_type: :product, amount_cents: 100, precise_amount_cents: 100, taxes_rate: 0,
        invoiceable: contract_rate_card.rate_card.product, contract:, contract_rate_card:, rate_card_rate:, taxes_amount_cents: 0,
        taxes_precise_amount_cents: 0)
    end
    let(:items) { [{fee_id: fee.id, amount_cents: 40}] }

    context "when the product catalog flag is disabled" do
      before { Organization.find(invoice.organization_id).disable_feature_flag!(:product_catalog) }

      it "rejects estimates for product fees" do
        result = estimate_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("feature_unavailable")
      end
    end

    it "estimates a partial credit without assuming a subscription" do
      result = estimate_service.call

      expect(result).to be_success
      expect(result.credit_note).to have_attributes(invoice:, total_amount_cents: 40)
      expect(fee.subscription_id).to be_nil
      expect(result.credit_note.items.sole).to have_attributes(fee:, amount_cents: 40)
      expect(invoice.reload).to have_attributes(status: "finalized", total_amount_cents: 100)
    end

    context "when the fee belongs to another organization" do
      let(:other_organization) { create(:organization) }
      let(:other_customer) { create(:customer, organization: other_organization) }
      let(:other_invoice) { create(:invoice, organization: other_organization, customer: other_customer, version_number: 3) }
      let(:contract) { create(:contract, organization: other_organization, customer: other_customer) }
      let(:contract_rate_card) { create(:contract_rate_card, organization: other_organization, contract:) }
      let(:fee) do
        create(:fee, invoice: other_invoice, subscription: nil, fee_type: :product, amount_cents: 100, precise_amount_cents: 100,
          invoiceable: contract_rate_card.rate_card.product, contract:, contract_rate_card:, rate_card_rate:, taxes_amount_cents: 0,
          taxes_precise_amount_cents: 0)
      end

      it "rejects the foreign fee" do
        result = estimate_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
      end
    end
  end

  context "when invoice is a prepaid credit invoice" do
    let_it_be(:invoice) do
      create(
        :invoice,
        invoice_type: :credit,
        organization:,
        customer:,
        currency: "EUR",
        fees_amount_cents: 200,
        total_amount_cents: 200,
        total_paid_amount_cents: 200,
        payment_status: :succeeded,
        version_number: 3
      )
    end
    let(:wallet) { create(:wallet, customer:, balance_cents: 100) }
    let(:wallet_transaction) { create(:wallet_transaction, wallet:) }
    let(:credit_fee) { create(:credit_fee, invoice:, invoiceable: wallet_transaction) }
    let(:params) { {invoice_id: invoice.id, amount_cents: 12, reference: "ref2"} }

    let(:items) do
      [
        {
          fee_id: credit_fee.id,
          amount_cents: 50
        }
      ]
    end

    before do
      credit_fee
      Payments::ManualCreateService.call(organization:, params:)
    end

    context "when wallet for the credits is active" do
      it "estimates the credit and refund amount not higher than wallet.balance_cents" do
        result = estimate_service.call

        expect(result).to be_success

        credit_note = result.credit_note
        expect(credit_note).to have_attributes(
          currency: invoice.currency,
          sub_total_excluding_taxes_amount_cents: 50,
          credit_amount_cents: 0,
          refund_amount_cents: 50,
          coupons_adjustment_amount_cents: 0,
          taxes_amount_cents: 0,
          taxes_rate: 0
        )
      end

      context "when estimating with amount higher than in the active wallet" do
        let(:items) do
          [
            {
              fee_id: credit_fee.id,
              amount_cents: 150
            }
          ]
        end

        it "returns a failure" do
          result = estimate_service.call

          expect(result).not_to be_success

          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to include(:amount_cents)
          expect(result.error.messages[:amount_cents]).to eq(
            %w[
              higher_than_wallet_balance
            ]
          )
        end
      end
    end

    context "when wallet for the credits is not active" do
      let(:wallet) { create(:wallet, customer:, balance_cents: 10, status: :terminated) }

      it "estimates the credit and refund amount hot higher than wallet.balance_amount_cents" do
        result = estimate_service.call

        expect(result).not_to be_success

        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
      end
    end
  end
end
