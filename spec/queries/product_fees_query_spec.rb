# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductFeesQuery do
  subject(:result) { described_class.call(organization:, pagination: nil, filters:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }
  let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card) }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:filters) { {} }

  let(:fee_attributes) do
    {
      invoice:,
      subscription: nil,
      fee_type: :product,
      invoiceable: contract_rate_card.rate_card.product,
      contract:,
      contract_rate_card:,
      rate_card_rate:
    }
  end
  let(:fee) { create(:fee, fee_attributes) }

  let(:other_contract) { create(:contract, organization:) }
  let(:other_contract_rate_card) { create(:contract_rate_card, organization:, contract: other_contract) }
  let(:other_rate_card_rate) { create(:rate_card_rate, organization:, rate_card: other_contract_rate_card.rate_card) }
  let(:other_fee) do
    create(
      :fee,
      fee_attributes.merge(
        invoice: create(:invoice, organization:, customer: other_contract.customer),
        invoiceable: other_contract_rate_card.rate_card.product,
        contract: other_contract,
        contract_rate_card: other_contract_rate_card,
        rate_card_rate: other_rate_card_rate,
        amount_currency: "USD",
        pay_in_advance_event_transaction_id: "tx_other"
      )
    )
  end

  before do
    fee
    other_fee
    create(:fee, invoice:)
    create(:fee, fee_attributes.merge(deleted_at: Time.current))
    create(:fee, fee_attributes.merge(invoice: create(:invoice), contract: nil, contract_rate_card: nil))
  end

  it "returns the kept product fees of the organization only" do
    expect(result).to be_success
    expect(result.fees).to contain_exactly(fee, other_fee)
  end

  context "when filtering by payment_status" do
    let(:filters) { {payment_status: "succeeded"} }
    let(:fee) { create(:fee, :succeeded, fee_attributes) }

    it "returns the fees in that status" do
      expect(result.fees).to contain_exactly(fee)
    end

    context "with an unknown status" do
      let(:filters) { {payment_status: "foo_bar"} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:payment_status]).to eq(["value_is_invalid"])
      end
    end

    context "with a status that is not a string" do
      let(:filters) { {payment_status: true} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:payment_status]).to eq(["value_is_invalid"])
      end
    end
  end

  context "when filtering by external_customer_id" do
    let(:filters) { {external_customer_id: customer.external_id} }

    it "returns the fees of the customer's contracts" do
      expect(result.fees).to contain_exactly(fee)
    end

    context "with a fee billed on an event and not invoiced yet" do
      let(:fee) do
        create(
          :fee,
          fee_attributes.merge(
            invoice: nil,
            organization:,
            billing_entity: customer.billing_entity,
            pay_in_advance_event_transaction_id: "tx_123"
          )
        )
      end

      it "finds it through the contract" do
        expect(result.fees).to contain_exactly(fee)
      end
    end

    context "when the customer was deleted" do
      before { customer.discard! }

      it "still returns its fees" do
        expect(result.fees).to contain_exactly(fee)
      end
    end

    context "with product fees billed before contracts" do
      let(:invoiced_fee) { create(:fee, fee_attributes.merge(contract: nil, contract_rate_card: nil)) }
      let(:subscription_fee) do
        create(
          :fee,
          fee_attributes.merge(
            invoice: nil,
            organization:,
            billing_entity: customer.billing_entity,
            contract: nil,
            contract_rate_card: nil,
            subscription: create(:subscription, organization:, customer:)
          )
        )
      end

      before do
        invoiced_fee
        subscription_fee
      end

      it "finds them through their invoice or subscription" do
        expect(result.fees).to contain_exactly(fee, invoiced_fee, subscription_fee)
      end
    end
  end

  context "when filtering by lago_invoice_id" do
    let(:filters) { {lago_invoice_id: invoice.id} }

    it "returns the product fees of that invoice" do
      expect(result.fees).to contain_exactly(fee)
    end

    context "with a value that is not an id" do
      let(:filters) { {lago_invoice_id: "not-an-id"} }

      before { create(:fee, fee_attributes.merge(invoice: nil, organization:, billing_entity: customer.billing_entity)) }

      it "returns a validation failure instead of the fees not invoiced yet" do
        expect(result).not_to be_success
        expect(result.error.messages[:lago_invoice_id]).to eq(["value_is_invalid"])
      end
    end
  end

  context "when filtering by product_code" do
    let(:filters) { {product_code: other_contract_rate_card.rate_card.product.code} }

    it "returns the fees of that product" do
      expect(result.fees).to contain_exactly(other_fee)
    end

    context "when the product was deleted after billing" do
      before { other_contract_rate_card.rate_card.product.discard! }

      it "still returns its fees" do
        expect(result.fees).to contain_exactly(other_fee)
      end
    end
  end

  context "when filtering by rate_card_code" do
    let(:filters) { {rate_card_code: other_contract_rate_card.rate_card.code} }

    it "returns the fees of that rate card" do
      expect(result.fees).to contain_exactly(other_fee)
    end

    context "with a product fee billed before contracts" do
      let(:legacy_fee) do
        create(
          :fee,
          fee_attributes.merge(
            contract: nil,
            contract_rate_card: nil,
            rate_card_rate: other_rate_card_rate
          )
        )
      end

      before { legacy_fee }

      it "finds it through its rate" do
        expect(result.fees).to contain_exactly(other_fee, legacy_fee)
      end
    end
  end

  context "when filtering by external_contract_id" do
    let(:filters) { {external_contract_id: other_contract.external_id} }

    it "returns the fees of that contract" do
      expect(result.fees).to contain_exactly(other_fee)
    end
  end

  context "when filtering by currency" do
    let(:filters) { {currency: "usd"} }

    it "matches the currency regardless of case" do
      expect(result.fees).to contain_exactly(other_fee)
    end

    context "with a currency that is not a string" do
      let(:filters) { {currency: true} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:currency]).to eq(["value_is_invalid"])
      end
    end
  end

  context "when filtering by event_transaction_id" do
    let(:filters) { {event_transaction_id: "tx_other"} }

    it "returns the fee billed on that event" do
      expect(result.fees).to contain_exactly(other_fee)
    end
  end

  context "when filtering by created_at" do
    let(:fee) { create(:fee, fee_attributes.merge(created_at: Time.zone.parse("2026-01-10T10:00:00Z"))) }
    let(:filters) { {created_at_from: "2026-01-01T00:00:00Z", created_at_to: "2026-01-31T23:59:59Z"} }

    it "returns the fees created in the range" do
      expect(result.fees).to contain_exactly(fee)
    end

    context "with an open-ended range" do
      let(:filters) { {created_at_from: "2026-02-01"} }

      it "returns the fees created after the bound" do
        expect(result.fees).to contain_exactly(other_fee)
      end
    end

    context "with an invalid date" do
      let(:filters) { {created_at_from: "not-a-date"} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:created_at_from]).to eq(["invalid_date"])
      end
    end
  end

  context "when filtering by succeeded_at" do
    let(:fee) { create(:fee, fee_attributes.merge(payment_status: :succeeded, succeeded_at: Time.zone.parse("2026-01-10T10:00:00Z"))) }
    let(:filters) { {succeeded_at_from: "2026-01-01T00:00:00Z", succeeded_at_to: "2026-01-31T23:59:59Z"} }

    it "returns the fees that succeeded in the range" do
      expect(result.fees).to contain_exactly(fee)
    end
  end

  context "when filtering by failed_at" do
    let(:fee) { create(:fee, fee_attributes.merge(payment_status: :failed, failed_at: Time.zone.parse("2026-01-10T10:00:00Z"))) }
    let(:filters) { {failed_at_to: "2026-01-31T23:59:59Z"} }

    it "returns the fees that failed before the bound" do
      expect(result.fees).to contain_exactly(fee)
    end
  end

  context "when filtering by refunded_at" do
    let(:fee) { create(:fee, fee_attributes.merge(payment_status: :refunded, refunded_at: Time.zone.parse("2026-01-10T10:00:00Z"))) }
    let(:filters) { {refunded_at_from: "2026-01-01T00:00:00Z", refunded_at_to: "invalid"} }

    it "rejects the invalid bound" do
      expect(result).not_to be_success
      expect(result.error.messages[:refunded_at_to]).to eq(["invalid_date"])
    end
  end

  context "with cursor pagination" do
    subject(:result) { described_class.call(organization:, pagination: cursor, filters:) }

    let(:cursor) { CursorPagination::Cursor.new(table: "fees", limit: 1) }
    let(:filters) { {currency: "USD"} }

    it "paginates after filtering" do
      page = CursorPagination::Page.new(records: result.fees, cursor:)

      expect(page.records).to eq([other_fee])
      expect(page.meta).to eq(next_cursor: nil, prev_cursor: nil)
    end
  end
end
