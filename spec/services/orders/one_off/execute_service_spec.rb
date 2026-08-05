# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orders::OneOff::ExecuteService do
  subject(:execute_service) { described_class.new(order:) }

  let(:organization) { create(:organization) }
  let(:billing_entity) { create(:billing_entity, organization:) }
  let(:customer) { create(:customer, organization:, billing_entity:, currency: "EUR") }
  let(:add_on) { create(:add_on, organization:, amount_cents: 10_000) }
  let(:add_on_item) do
    {
      "id" => add_on.id,
      "localId" => "3d08b2df-4e4c-4d58-b415-a525c1663735",
      "payload" => {
        "code" => add_on.code,
        "units" => 2,
        "unitAmountCents" => 5_000,
        "totalAmountCents" => 10_000,
        "invoiceDisplayName" => "Catalog setup"
      },
      "overrides" => overrides
    }.compact
  end
  let(:overrides) { {"unitAmountCents" => 6_000} }
  let(:billing_items) { {"addOns" => [add_on_item]} }
  let(:quote) { create(:quote, organization:, customer:, order_type: :one_off) }
  let(:quote_version) { create(:quote_version, :approved, quote:, organization:, currency: "EUR", billing_items:) }
  let(:order_form) { create(:order_form, :signed, organization:, customer:, quote_version:) }
  let(:order) { create(:order, organization:, customer:, order_form:, execution_mode:) }
  let(:execution_mode) { :execute_in_lago }

  # Add-ons are resolved by id only outside api context, and CurrentContext
  # leaks across spec files (no global reset), so pin it.
  before { CurrentContext.source = nil }

  describe "#call" do
    context "with execute_in_lago mode" do
      it "creates a one-off invoice and marks the order executed" do
        result = nil
        expect { result = execute_service.call }.to change(Invoice, :count).by(1)

        expect(result).to be_success

        invoice = customer.invoices.sole
        expect(invoice.invoice_type).to eq("one_off")
        expect(invoice.currency).to eq("EUR")

        order.reload
        expect(order.executed?).to eq(true)
        expect(order.executed_at).to be_present
        expect(order.execution_record["executed_at"]).to be_present
        expect(order.execution_record["execution_mode"]).to eq("execute_in_lago")
        expect(order.execution_record["invoice_id"]).to eq(invoice.id)
        expect(order.execution_record["errors"]).to eq([])
      end

      it "bills the payload values" do
        execute_service.call

        fee = customer.invoices.sole.fees.sole
        expect(fee.add_on_id).to eq(add_on.id)
        expect(fee.units).to eq(2)
        expect(fee.invoice_display_name).to eq("Catalog setup")
        expect(fee.description).to eq(add_on.description)
      end

      context "with overrides" do
        let(:overrides) do
          {
            "units" => 3,
            "unitAmountCents" => 6_000,
            "invoiceDisplayName" => "Negotiated setup",
            "description" => "Negotiated onboarding"
          }
        end

        it "bills the overridden values" do
          execute_service.call

          fee = customer.invoices.sole.fees.sole
          expect(fee.units).to eq(3)
          expect(fee.unit_amount_cents).to eq(6_000)
          expect(fee.invoice_display_name).to eq("Negotiated setup")
          expect(fee.description).to eq("Negotiated onboarding")
        end
      end

      context "without overrides" do
        let(:overrides) { nil }

        it "bills the payload unit amount" do
          execute_service.call

          fee = customer.invoices.sole.fees.sole
          expect(fee.unit_amount_cents).to eq(5_000)
          expect(fee.units).to eq(2)
        end
      end

      context "when the description is carried by the payload" do
        let(:overrides) { nil }

        before { add_on_item["payload"]["description"] = "Snapshotted onboarding" }

        it "bills the payload description" do
          execute_service.call

          expect(customer.invoices.sole.fees.sole.description).to eq("Snapshotted onboarding")
        end
      end

      context "when the add-on is discarded" do
        before { add_on.discard! }

        it "still bills it" do
          result = nil
          expect { result = execute_service.call }.to change(Invoice, :count).by(1)

          expect(result).to be_success
          expect(customer.invoices.sole.fees.sole.add_on_id).to eq(add_on.id)
        end
      end

      context "when the invoice creation fails" do
        let(:failed_result) do
          Invoices::CreateOneOffService::Result.new.tap do |failed|
            failed.single_validation_failure!(field: :currency, error_code: "currencies_does_not_match")
          end
        end

        before do
          allow(Invoices::CreateOneOffService).to receive(:call!).and_raise(failed_result.error)
        end

        it "records the failure and marks the order failed" do
          result = execute_service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)

          order.reload
          expect(order.failed?).to eq(true)
          expect(order.execution_record["executed_at"]).to be_nil
          expect(order.execution_record["invoice_id"]).to be_nil
          expect(order.execution_record["errors"]).to eq(["currencies_does_not_match"])
        end
      end

      context "when the invoice creation fails with a coded service failure" do
        let(:failed_result) do
          Invoices::CreateOneOffService::Result.new.tap do |failed|
            failed.service_failure!(code: "provider_error", message: "boom")
          end
        end

        before do
          allow(Invoices::CreateOneOffService).to receive(:call!).and_raise(failed_result.error)
        end

        it "records the error code and marks the order failed" do
          result = execute_service.call

          expect(result).not_to be_success

          order.reload
          expect(order.failed?).to eq(true)
          expect(order.execution_record["errors"]).to eq(["provider_error"])
        end
      end

      context "when the invoice creation fails with a resource-not-found failure" do
        let(:failed_result) do
          Invoices::CreateOneOffService::Result.new.tap do |failed|
            failed.not_found_failure!(resource: "add_on")
          end
        end

        before do
          allow(Invoices::CreateOneOffService).to receive(:call!).and_raise(failed_result.error)
        end

        it "records the failure message and marks the order failed" do
          result = execute_service.call

          expect(result).not_to be_success

          order.reload
          expect(order.failed?).to eq(true)
          expect(order.execution_record["errors"]).to eq(["add_on_not_found"])
        end
      end

      context "when taxes are deferred to a provider" do
        let(:deferred_invoice) { create(:invoice, organization:, customer:, status: :pending) }
        let(:deferred_result) do
          Invoices::CreateOneOffService::Result.new.tap { |deferred| deferred.invoice = deferred_invoice }
        end

        before do
          allow(Invoices::CreateOneOffService).to receive(:call!).and_return(deferred_result)
        end

        it "marks the order executed optimistically with the invoice id" do
          execute_service.call

          order.reload
          expect(order.executed?).to eq(true)
          expect(order.execution_record["invoice_id"]).to eq(deferred_invoice.id)
        end
      end
    end

    context "with order_only mode" do
      let(:execution_mode) { :order_only }

      it "marks the order executed without billing" do
        result = nil
        expect { result = execute_service.call }.not_to change(Invoice, :count)

        expect(result).to be_success

        order.reload
        expect(order.executed?).to eq(true)
        expect(order.execution_record["execution_mode"]).to eq("order_only")
        expect(order.execution_record["invoice_id"]).to be_nil
        expect(order.execution_record["errors"]).to eq([])
      end
    end

    context "when the order is already executed" do
      let(:order) { create(:order, :executed_in_lago, organization:, customer:, order_form:) }

      it "is idempotent and does nothing" do
        result = nil
        expect { result = execute_service.call }.not_to change(Invoice, :count)

        expect(result).to be_success
        expect(result.order).to eq(order)
      end
    end

    context "when execution raises a record validation error" do
      let(:invalid_record) do
        build(:add_on).tap { |record| record.errors.add(:base, "some_validation_error") }
      end

      before do
        allow(Invoices::CreateOneOffService).to receive(:call!).and_raise(ActiveRecord::RecordInvalid.new(invalid_record))
      end

      it "records the failure and marks the order failed" do
        result = execute_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)

        order.reload
        expect(order.failed?).to eq(true)
        expect(order.execution_record["executed_at"]).to be_nil
        expect(order.execution_record["errors"]).to eq(["some_validation_error"])
      end
    end

    context "when the order has no execution_mode" do
      let(:order) { create(:order, organization:, customer:, order_form:, execution_mode: nil) }

      it "returns a validation failure without touching the order" do
        result = nil
        expect { result = execute_service.call }.not_to change(Invoice, :count)

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:execution_mode]).to eq(["value_is_mandatory"])

        order.reload
        expect(order.executed?).to eq(false)
        expect(order.execution_record).to eq({})
      end
    end
  end
end
