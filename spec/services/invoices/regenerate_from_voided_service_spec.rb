# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::RegenerateFromVoidedService, type: :service do
  subject(:regenerate_service) { described_class.new(voided_invoice:, fees:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:voided_invoice) { create(:invoice, :voided, organization:, customer:) }
  let(:fee) { create(:fee, invoice: voided_invoice, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:fees) do
    [{
      id: fee.id,
      add_on_id: nil,
      description: "Updated description",
      invoice_display_name: "Updated display name",
      units: 5.0,
      unit_amount_cents: 1000
    }]
  end

  def new_fee_config(description: "New fee", units: 2.0, amount_cents: 500, unit_amount_cents: 1000)
    {
      organization_id: organization.id,
      billing_entity_id: voided_invoice.billing_entity_id,
      description:,
      units:,
      amount_cents:,
      unit_amount_cents:,
      taxes_amount_cents: 0,
      amount_currency: "EUR",
      subscription_id: subscription.id,
      invoiceable_type: "Subscription",
      invoiceable_id: subscription.id
    }
  end

  describe "#call" do
    describe "successful scenarios" do
      before do
        allow(Fees::ApplyTaxesService).to receive(:call).and_return(BaseResult.new)
        allow(Invoices::ComputeAmountsFromFees).to receive(:call).and_return(BaseResult.new)
      end

      let(:subscription) { create(:subscription, organization:, customer:) }
      let(:charge) { create(:standard_charge, organization:) }

      context "when regenerating a basic invoice" do
        it "creates a new invoice" do
          result = regenerate_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(result.invoice).to be_present
            expect(result.invoice).to be_a(Invoice)
            expect(result.invoice).not_to eq(voided_invoice)
          end
        end

        it "sets the new invoice to finalized status when no grace period" do
          result = regenerate_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(result.invoice.status).to eq("finalized")
          end
        end

        it "does not create invoice with generating status" do
          result = regenerate_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(result.invoice.status).not_to eq("generating")
            expect(result.invoice).to be_visible
          end
        end

        it "sets the voided_invoice_id on the new invoice" do
          result = regenerate_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(result.invoice.voided_invoice_id).to eq(voided_invoice.id)
          end
        end
      end

      context "when copying invoice attributes" do
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
      end

      context "when handling existing fees" do
        it "copies existing fees from the voided invoice" do
          result = regenerate_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(result.invoice.fees.count).to eq(1)
            new_fee = result.invoice.fees.first
            expect(new_fee.description).to eq("Updated description")
            expect(new_fee.invoice_display_name).to eq("Updated display name")
            expect(new_fee.units).to eq(5.0)
            expect(new_fee.unit_amount_cents).to eq(1000)
          end
        end

        it "applies fee input attributes when provided" do
          custom_fee_input = {
            id: fee.id,
            charge_id: charge.id,
            subscription_id: subscription.id,
            invoice_display_name: "Custom Display Name"
          }

          service = described_class.new(voided_invoice:, fees: [custom_fee_input])
          result = service.call

          new_fee = result.invoice.fees.first

          aggregate_failures do
            expect(result).to be_success
            expect(new_fee.charge_id).to eq(custom_fee_input[:charge_id])
            expect(new_fee.subscription_id).to eq(custom_fee_input[:subscription_id])
            expect(new_fee.invoice_display_name).to eq("Custom Display Name")
          end
        end

        it "copies other important attributes from the original fee" do
          result = regenerate_service.call

          new_fee = result.invoice.fees.first

          aggregate_failures do
            expect(result).to be_success
            expect(new_fee.precise_amount_cents).to eq(fee.precise_amount_cents)
            expect(new_fee.fee_type).to eq(fee.fee_type)
            expect(new_fee.charge_id).to eq(fee.charge_id)
            expect(new_fee.subscription_id).to eq(fee.subscription_id)
            expect(new_fee.add_on_id).to eq(fee.add_on_id)
            expect(new_fee.properties).to eq(fee.properties)
            expect(new_fee.grouped_by).to eq(fee.grouped_by)
            expect(new_fee.amount_details).to eq(fee.amount_details)
            expect(new_fee.events_count).to eq(fee.events_count)
            expect(new_fee.precise_unit_amount).to eq(fee.precise_unit_amount)
            expect(new_fee.charge_filter_id).to eq(fee.charge_filter_id)
            expect(new_fee.group_id).to eq(fee.group_id)
            expect(new_fee.true_up_parent_fee_id).to eq(fee.true_up_parent_fee_id)
          end
        end

        it "resets payment status to pending for copied fees" do
          result = regenerate_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(result.invoice.fees.first.payment_status).to eq("pending")
          end
        end

        it "resets taxes amount to zero for copied fees" do
          result = regenerate_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(result.invoice.fees.first.taxes_amount_cents).to eq(0)
          end
        end
      end

      context "when creating new fees" do
        context "when a new fee is provided (id omitted)" do
          let(:charge_fee_attrs) { new_fee_config.merge(total_aggregated_units: 2.0, description: "Charge fee") }
          let(:add_on_fee_attrs) { new_fee_config(description: "Add-on fee", units: 1.0, amount_cents: 200).merge(add_on_id: add_on.id) }
          let(:fees) do
            [
              charge_fee_attrs,
              add_on_fee_attrs
            ]
          end

          it "creates new fees on the regenerated invoice (charge and add_on)" do
            result = regenerate_service.call
            expect(result).to be_success
            expect(result.invoice.fees.count).to eq(2)

            charge_fee = result.invoice.fees.find { |f| f.description == "Charge fee" }
            add_on_fee = result.invoice.fees.find { |f| f.description == "Add-on fee" }

            expect(charge_fee.total_aggregated_units).to eq(2.0)
            expect(add_on_fee.total_aggregated_units).to be_nil
          end
        end

        context "when mixing existing and new fees" do
          let(:charge_fee_attrs) { new_fee_config.merge(total_aggregated_units: 2.0, description: "Charge fee") }
          let(:add_on_fee_attrs) { new_fee_config(description: "Add-on fee", units: 1.0, amount_cents: 200).merge(add_on_id: add_on.id) }
          let(:fees) do
            [
              {id: fee.id},
              charge_fee_attrs,
              add_on_fee_attrs
            ]
          end

          it "processes both existing and new fees correctly" do
            result = regenerate_service.call

            aggregate_failures do
              expect(result).to be_success
              expect(result.invoice.fees.count).to eq(3)
              expect(result.invoice.fees.map(&:description)).to include(fee.description, "Charge fee", "Add-on fee")

              charge_fee = result.invoice.fees.find { |f| f.description == "Charge fee" }
              add_on_fee = result.invoice.fees.find { |f| f.description == "Add-on fee" }

              expect(charge_fee.total_aggregated_units).to eq(2.0)
              expect(add_on_fee.total_aggregated_units).to be_nil
            end
          end
        end
      end
    end

    describe "failure scenarios" do
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

      context "when voided_invoice has already been regenerated" do
        let(:regenerated_invoice) { create(:invoice, organization:, customer:, voided_invoice_id: voided_invoice.id) }

        before do
          regenerated_invoice
        end

        it "returns a not allowed failure" do
          result = regenerate_service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
            expect(result.error.code).to eq("already_regenerated")
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
    end

    describe "specific scenarios" do
      before do
        allow(Fees::ApplyTaxesService).to receive(:call).and_return(BaseResult.new)
        allow(Invoices::ComputeAmountsFromFees).to receive(:call).and_return(BaseResult.new)
      end

      context "when voided_invoice has different invoice types" do
        context "when invoice_type is subscription" do
          let(:voided_invoice) { create(:invoice, :voided, :subscription, organization:, customer:) }

          it "creates a new invoice with subscription type" do
            service = described_class.new(voided_invoice:, fees: [{id: fee.id}])
            result = service.call

            aggregate_failures do
              expect(result).to be_success
              expect(result.invoice).to be_present
              expect(result.invoice.invoice_type).to eq("subscription")
              expect(result.invoice).not_to eq(voided_invoice)
            end
          end

          it "copies invoice_subscriptions from voided_invoice" do
            subscription = create(:subscription, customer:)
            voided_invoice = create(:invoice, :voided, invoice_type: :subscription, organization:, customer:)
            invoice_subscription = create(:invoice_subscription, :boundaries, invoice: voided_invoice, subscription:)

            service = described_class.new(voided_invoice:, fees: [{id: fee.id}])
            result = service.call

            aggregate_failures do
              expect(result).to be_success
              expect(result.invoice.invoice_subscriptions.count).to eq(1)

              new_invoice_subscription = result.invoice.invoice_subscriptions.first
              expect(new_invoice_subscription.subscription).to eq(subscription)
              expect(new_invoice_subscription.timestamp).to eq(invoice_subscription.timestamp)
              expect(new_invoice_subscription.from_datetime).to eq(invoice_subscription.from_datetime)
              expect(new_invoice_subscription.to_datetime).to eq(invoice_subscription.to_datetime)
              expect(new_invoice_subscription.charges_from_datetime).to eq(invoice_subscription.charges_from_datetime)
              expect(new_invoice_subscription.charges_to_datetime).to eq(invoice_subscription.charges_to_datetime)
              expect(new_invoice_subscription.recurring).to eq(invoice_subscription.recurring)
              expect(new_invoice_subscription.invoicing_reason).to eq(invoice_subscription.invoicing_reason)
            end
          end
        end

        context "when invoice_type is one_off" do
          let(:voided_invoice) { create(:invoice, :voided, :one_off, organization:, customer:) }

          it "creates a new invoice with one_off type" do
            service = described_class.new(voided_invoice:, fees: [{id: fee.id}])
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
            service = described_class.new(voided_invoice:, fees: [{id: fee.id}])
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
    end
  end

  describe "activity logging" do
    before do
      allow(Utils::ActivityLog).to receive(:produce)
    end

    it "produces an activity log with invoice.regenerated_from_voided action and uses voided_invoice as record" do
      described_class.call(voided_invoice: voided_invoice, fees: [{id: fee.id}])

      expect(Utils::ActivityLog).to have_received(:produce).with(voided_invoice, "invoice.regenerated_from_voided")
    end
  end
end
