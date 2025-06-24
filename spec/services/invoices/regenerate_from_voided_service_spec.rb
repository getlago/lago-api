# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::RegenerateFromVoidedService, type: :service do
  subject(:regenerate_service) { described_class.new(voided_invoice:, fees:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:voided_invoice) { create(:invoice, :voided, organization:, customer:) }
  let(:fee) { create(:fee, invoice: voided_invoice, organization:) }
  let(:fees) { [fee.id] }

  describe "#call" do
    context "when voided_invoice is nil" do
      let(:voided_invoice) { nil }
      let(:fees) { [] }

      it "returns a not found failure" do
        result = regenerate_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.resource).to eq("invoice")
        end
      end
    end

    context "when voided_invoice is not voided" do
      let(:voided_invoice) { create(:invoice, organization:, customer:) }

      it "returns a not allowed failure" do
        result = regenerate_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          expect(result.error.code).to eq("not_voided")
        end
      end
    end

    context "when voided_invoice is valid" do
      before do
        allow(Fees::ApplyTaxesService).to receive(:call).and_return(BaseResult.new)
        allow(Invoices::ComputeAmountsFromFees).to receive(:call).and_return(BaseResult.new)
      end

      it "creates a new invoice" do
        result = regenerate_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.invoice).to be_present
          expect(result.invoice).to be_a(Invoice)
          expect(result.invoice).not_to eq(voided_invoice)
        end
      end

      it "sets the new invoice to draft status" do
        result = regenerate_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.invoice.status).to eq("draft")
        end
      end

      it "copies the customer from the voided invoice" do
        result = regenerate_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.invoice.customer).to eq(voided_invoice.customer)
        end
      end

      it "copies the invoice_type from the voided invoice" do
        result = regenerate_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.invoice.invoice_type).to eq(voided_invoice.invoice_type)
        end
      end

      it "copies the currency from the voided invoice" do
        result = regenerate_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.invoice.currency).to eq(voided_invoice.currency)
        end
      end

      it "duplicates all specified fees" do
        result = regenerate_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.invoice.fees.count).to eq(fees.count)
          expect(result.invoice.fees.first.amount_cents).to eq(fee.amount_cents)
        end
      end

      it "sets fee attributes correctly for the new invoice" do
        result = regenerate_service.call

        new_fee = result.invoice.fees.first

        aggregate_failures do
          expect(result).to be_success
          expect(new_fee.invoice).to eq(result.invoice)
          expect(new_fee.organization_id).to eq(result.invoice.organization_id)
          expect(new_fee.billing_entity_id).to eq(result.invoice.billing_entity_id)
          expect(new_fee.amount_currency).to eq(result.invoice.currency)
          expect(new_fee.payment_status).to eq("pending")
          expect(new_fee.taxes_amount_cents).to eq(0)
          expect(new_fee.taxes_precise_amount_cents).to eq(0.to_d)
        end
      end

      it "copies important attributes from the original fee" do
        result = regenerate_service.call

        new_fee = result.invoice.fees.first

        aggregate_failures do
          expect(result).to be_success
          expect(new_fee.amount_cents).to eq(fee.amount_cents)
          expect(new_fee.precise_amount_cents).to eq(fee.precise_amount_cents)
          expect(new_fee.units).to eq(fee.units)
          expect(new_fee.description).to eq(fee.description)
          expect(new_fee.fee_type).to eq(fee.fee_type)
          expect(new_fee.charge_id).to eq(fee.charge_id)
          expect(new_fee.subscription_id).to eq(fee.subscription_id)
          expect(new_fee.add_on_id).to eq(fee.add_on_id)
          expect(new_fee.properties).to eq(fee.properties)
          expect(new_fee.grouped_by).to eq(fee.grouped_by)
          expect(new_fee.amount_details).to eq(fee.amount_details)
          expect(new_fee.events_count).to eq(fee.events_count)
          expect(new_fee.unit_amount_cents).to eq(fee.unit_amount_cents)
          expect(new_fee.precise_unit_amount).to eq(fee.precise_unit_amount)
          expect(new_fee.invoice_display_name).to eq(fee.invoice_display_name)
          expect(new_fee.charge_filter_id).to eq(fee.charge_filter_id)
          expect(new_fee.group_id).to eq(fee.group_id)
          expect(new_fee.true_up_parent_fee_id).to eq(fee.true_up_parent_fee_id)
        end
      end

      it "applies taxes to each fee" do
        regenerate_service.call

        expect(Fees::ApplyTaxesService).to have_received(:call).with(fee: instance_of(Fee)).at_least(fees.count).times
      end

      it "computes amounts from fees" do
        regenerate_service.call

        expect(Invoices::ComputeAmountsFromFees).to have_received(:call).with(invoice: instance_of(Invoice))
      end

      it "returns the new invoice in the result" do
        result = regenerate_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.invoice).to be_present
          expect(result.invoice).to be_a(Invoice)
        end
      end

      it "returns a successful result" do
        result = regenerate_service.call

        expect(result).to be_success
      end

      context "when multiple fees are provided" do
        let(:fee2) { create(:fee, invoice: voided_invoice, organization:) }
        let(:fees) { [fee.id, fee2.id] }

        it "applies taxes to each fee individually" do
          regenerate_service.call

          expect(Fees::ApplyTaxesService).to have_received(:call).with(fee: instance_of(Fee)).at_least(:twice)
        end

        it "duplicates all specified fees" do
          result = regenerate_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(result.invoice.fees.count).to eq(2)
            expect(result.invoice.fees.pluck(:amount_cents)).to match_array([fee.amount_cents, fee2.amount_cents])
          end
        end
      end

      context "when fees are not found in the organization" do
        let(:other_organization) { create(:organization) }
        let(:other_fee) { create(:fee, organization: other_organization) }
        let(:fees) { [fee.id, other_fee.id] }

        it "only processes fees from the correct organization" do
          result = regenerate_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(result.invoice.fees.count).to eq(1)
            expect(result.invoice.fees.first.amount_cents).to eq(fee.amount_cents)
          end
        end
      end

      context "when voided_invoice has different invoice types" do
        context "when invoice_type is subscription" do
          let(:voided_invoice) { create(:invoice, :voided, :subscription, organization:, customer:) }

          it "creates a new invoice with subscription type" do
            fee = create(:fee, invoice: voided_invoice, organization: organization)
            service = described_class.new(voided_invoice: voided_invoice, fees: [fee.id])
            result = service.call

            aggregate_failures do
              expect(result).to be_success
              expect(result.invoice).to be_present
              expect(result.invoice.invoice_type).to eq("subscription")
              expect(result.invoice).not_to eq(voided_invoice)
            end
          end
        end

        context "when invoice_type is one_off" do
          let(:voided_invoice) { create(:invoice, :voided, :one_off, organization:, customer:) }

          it "creates a new invoice with one_off type" do
            fee = create(:fee, invoice: voided_invoice, organization: organization)
            service = described_class.new(voided_invoice: voided_invoice, fees: [fee.id])
            result = service.call

            aggregate_failures do
              expect(result).to be_success
              expect(result.invoice).to be_present
              expect(result.invoice.invoice_type).to eq("one_off")
              expect(result.invoice).not_to eq(voided_invoice)
            end
          end
        end

        context "when invoice_type is credit" do
          let(:voided_invoice) { create(:invoice, :voided, :credit, organization:, customer:) }

          it "creates a new invoice with credit type" do
            fee = create(:fee, invoice: voided_invoice, organization: organization)
            service = described_class.new(voided_invoice: voided_invoice, fees: [fee.id])
            result = service.call

            aggregate_failures do
              expect(result).to be_success
              expect(result.invoice).to be_present
              expect(result.invoice.invoice_type).to eq("credit")
              expect(result.invoice).not_to eq(voided_invoice)
            end
          end
        end
      end

      context "when Invoices::ComputeAmountsFromFees fails" do
        before do
          failed_result = BaseResult.new
          failed_result.fail_with_error!(BaseService::ServiceFailure.new(failed_result, code: "compute_error", error_message: "Compute error"))
          allow(Invoices::ComputeAmountsFromFees).to receive(:call).and_return(failed_result)
        end

        it "raises the error and rolls back the transaction" do
          result = regenerate_service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ServiceFailure)
            expect(result.error.message).to eq("compute_error: Compute error")
          end
        end
      end

      context "when Fees::ApplyTaxesService fails" do
        before do
          failed_result = BaseResult.new
          failed_result.fail_with_error!(BaseService::ServiceFailure.new(failed_result, code: "fee_error", error_message: "Fee error"))
          allow(Fees::ApplyTaxesService).to receive(:call).and_return(failed_result)
        end

        it "raises the error and rolls back the transaction" do
          result = regenerate_service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ServiceFailure)
            expect(result.error.message).to eq("fee_error: Fee error")
          end
        end
      end

      context "when Invoices::CreateGeneratingService fails" do
        before do
          failed_result = BaseResult.new
          failed_result.fail_with_error!(BaseService::ServiceFailure.new(failed_result, code: "generation_error", error_message: "Generation error"))
          allow(Invoices::CreateGeneratingService).to receive(:call).and_return(failed_result)
        end

        it "raises the error and rolls back the transaction" do
          result = regenerate_service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ServiceFailure)
            expect(result.error.message).to eq("generation_error: Generation error")
          end
        end
      end
    end
  end

  describe "activity logging" do
    before do
      allow(Utils::ActivityLog).to receive(:produce)
    end

    it "produces an activity log with invoice.regenerated_from_voided action and uses voided_invoice as record" do
      fee = create(:fee, invoice: voided_invoice, organization: organization)
      described_class.call(voided_invoice: voided_invoice, fees: [fee.id])

      expect(Utils::ActivityLog).to have_received(:produce).with(voided_invoice, "invoice.regenerated_from_voided")
    end
  end
end
