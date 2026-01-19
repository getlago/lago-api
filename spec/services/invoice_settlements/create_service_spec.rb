# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvoiceSettlements::CreateService do
  subject(:service_call) do
    described_class.call(
      invoice:,
      amount_cents:,
      amount_currency:,
      source_credit_note:,
      source_payment:
    )
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      currency: "EUR",
      total_amount_cents: 1000,
      total_paid_amount_cents: 0
    )
  end
  let(:amount_cents) { 500 }
  let(:amount_currency) { "EUR" }
  let(:source_credit_note) { nil }
  let(:source_payment) { nil }

  describe ".call" do
    context "with source_credit_note" do
      let(:credit_note) do
        create(
          :credit_note,
          invoice:,
          customer:,
          offset_amount_cents: 500,
          total_amount_cents: 500,
          status: :finalized
        )
      end
      let(:source_credit_note) { credit_note }

      it "creates an invoice settlement" do
        expect { service_call }.to change(InvoiceSettlement, :count).by(1)
      end

      it "returns a successful result" do
        result = service_call

        expect(result).to be_success
        expect(result.invoice_settlement).to be_a(InvoiceSettlement)
      end

      it "creates settlement with correct attributes" do
        result = service_call
        settlement = result.invoice_settlement

        aggregate_failures do
          expect(settlement.organization_id).to eq(organization.id)
          expect(settlement.billing_entity_id).to eq(invoice.billing_entity_id)
          expect(settlement.target_invoice).to eq(invoice)
          expect(settlement.source_credit_note).to eq(credit_note)
          expect(settlement.source_payment).to be_nil
          expect(settlement.settlement_type).to eq("credit_note")
          expect(settlement.amount_cents).to eq(500)
          expect(settlement.amount_currency).to eq("EUR")
        end
      end

      it "does not mark invoice as paid when not fully settled" do
        service_call

        expect(invoice.reload.payment_status).not_to eq("succeeded")
      end

      context "when invoice is fully settled" do
        let(:amount_cents) { 1000 }
        let(:credit_note) do
          create(
            :credit_note,
            invoice:,
            customer:,
            offset_amount_cents: 1000,
            total_amount_cents: 1000,
            status: :finalized
          )
        end

        it "marks invoice as paid" do
          service_call

          expect(invoice.reload.payment_status).to eq("succeeded")
        end
      end

      context "when invoice is partially paid and offset completes payment" do
        let(:invoice) do
          create(
            :invoice,
            organization:,
            customer:,
            currency: "EUR",
            total_amount_cents: 1000,
            total_paid_amount_cents: 600
          )
        end
        let(:amount_cents) { 400 }
        let(:credit_note) do
          create(
            :credit_note,
            invoice:,
            customer:,
            offset_amount_cents: 400,
            total_amount_cents: 400,
            status: :finalized
          )
        end

        it "marks invoice as paid" do
          service_call

          expect(invoice.reload.payment_status).to eq("succeeded")
        end
      end
    end

    context "with source_payment" do
      let(:payment) { create(:payment, payable: invoice) }
      let(:source_payment) { payment }

      it "creates an invoice settlement" do
        expect { service_call }.to change(InvoiceSettlement, :count).by(1)
      end

      it "returns a successful result" do
        result = service_call

        expect(result).to be_success
        expect(result.invoice_settlement).to be_a(InvoiceSettlement)
      end

      it "creates settlement with correct attributes" do
        result = service_call
        settlement = result.invoice_settlement

        aggregate_failures do
          expect(settlement.organization_id).to eq(organization.id)
          expect(settlement.target_invoice).to eq(invoice)
          expect(settlement.source_payment).to eq(payment)
          expect(settlement.source_credit_note).to be_nil
          expect(settlement.settlement_type).to eq("payment")
          expect(settlement.amount_cents).to eq(500)
          expect(settlement.amount_currency).to eq("EUR")
        end
      end
    end

    context "without source" do
      it "raises an ArgumentError" do
        expect { service_call }.to raise_error(ArgumentError, "Must provide either source_credit_note or source_payment")
      end
    end

    context "with both source_credit_note and source_payment" do
      let(:credit_note) { create(:credit_note, invoice:, customer:) }
      let(:payment) { create(:payment, payable: invoice) }
      let(:source_credit_note) { credit_note }
      let(:source_payment) { payment }

      it "raises an ArgumentError" do
        expect { service_call }.to raise_error(ArgumentError, "Cannot provide both source_credit_note and source_payment")
      end
    end

    context "when multiple settlements fully settle invoice" do
      let(:invoice) do
        create(
          :invoice,
          organization:,
          customer:,
          currency: "EUR",
          total_amount_cents: 1000,
          total_paid_amount_cents: 0
        )
      end
      let(:credit_note1) do
        create(
          :credit_note,
          invoice:,
          customer:,
          offset_amount_cents: 600,
          total_amount_cents: 600,
          status: :finalized
        )
      end
      let(:credit_note2) do
        create(
          :credit_note,
          invoice:,
          customer:,
          offset_amount_cents: 400,
          total_amount_cents: 400,
          status: :finalized
        )
      end

      before do
        # First settlement
        described_class.call(
          invoice:,
          amount_cents: 600,
          amount_currency: "EUR",
          source_credit_note: credit_note1
        )
      end

      it "marks invoice as paid after second settlement" do
        # Second settlement that completes the payment
        described_class.call(
          invoice:,
          amount_cents: 400,
          amount_currency: "EUR",
          source_credit_note: credit_note2
        )

        expect(invoice.reload.payment_status).to eq("succeeded")
      end
    end

    context "with different currency" do
      let(:amount_currency) { "USD" }
      let(:credit_note) do
        create(
          :credit_note,
          invoice:,
          customer:,
          offset_amount_cents: 500,
          offset_amount_currency: "USD",
          total_amount_cents: 500,
          status: :finalized
        )
      end
      let(:source_credit_note) { credit_note }

      it "creates settlement with specified currency" do
        result = service_call
        settlement = result.invoice_settlement

        expect(settlement.amount_currency).to eq("USD")
      end
    end

    context "when invoice total_due_amount_cents is exactly zero" do
      let(:invoice) do
        create(
          :invoice,
          organization:,
          customer:,
          currency: "EUR",
          total_amount_cents: 500,
          total_paid_amount_cents: 0
        )
      end
      let(:amount_cents) { 500 }
      let(:credit_note) do
        create(
          :credit_note,
          invoice:,
          customer:,
          offset_amount_cents: 500,
          total_amount_cents: 500,
          status: :finalized
        )
      end
      let(:source_credit_note) { credit_note }

      it "marks invoice as paid" do
        service_call

        expect(invoice.reload.payment_status).to eq("succeeded")
      end
    end

    context "when offset slightly exceeds due amount (rounding)" do
      let(:invoice) do
        create(
          :invoice,
          organization:,
          customer:,
          currency: "EUR",
          total_amount_cents: 1000,
          total_paid_amount_cents: 999
        )
      end
      let(:amount_cents) { 2 }
      let(:credit_note) do
        create(
          :credit_note,
          invoice:,
          customer:,
          offset_amount_cents: 2,
          total_amount_cents: 2,
          status: :finalized
        )
      end
      let(:source_credit_note) { credit_note }

      it "marks invoice as paid" do
        service_call

        expect(invoice.reload.payment_status).to eq("succeeded")
      end
    end
  end
end
