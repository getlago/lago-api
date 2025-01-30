# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdjustedFees::CreateService, type: :service do
  subject(:create_service) { described_class.new(invoice:, params:) }

  let(:customer) { create(:customer) }
  let(:invoice) { create(:invoice, :subscription, :draft, customer:, subscriptions: [subscription], organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, plan:, customer:) }
  let(:organization) { customer.organization }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:charge) { create(:standard_charge, billable_metric:, plan: subscription.plan) }
  let(:charge_filter) { create(:charge_filter, charge:) }

  let(:fee) { create(:charge_fee, invoice:, subscription:, charge:, charge_filter:) }
  let(:code) { "tax_code" }
  let(:refresh_service) { instance_double(Invoices::RefreshDraftService) }
  let(:params) do
    {
      fee_id: fee.id,
      units: 5,
      unit_precise_amount: 12.002,
      invoice_display_name: "new-dis-name"
    }
  end

  describe "#call" do
    before do
      allow(Invoices::RefreshDraftService).to receive(:new).with(invoice: invoice).and_return(refresh_service)
      allow(refresh_service).to receive(:call).and_return(BaseService::Result.new)
    end

    context "when license is premium" do
      around { |test| lago_premium!(&test) }

      it "creates an adjusted fee" do
        expect { create_service.call }.to change(AdjustedFee, :count).by(1)
      end

      it "returns adjusted fee in the result" do
        result = create_service.call
        expect(result.adjusted_fee).to be_a(AdjustedFee)
      end

      it "returns fee in the result" do
        result = create_service.call
        expect(result.fee).to be_a(Fee)
      end

      it "calls the RefreshDraft service" do
        create_service.call

        expect(Invoices::RefreshDraftService).to have_received(:new)
        expect(refresh_service).to have_received(:call)
      end

      it "populates precise and not precise values for the created adjusted fee" do
        result = create_service.call
        expect(result.adjusted_fee).to have_attributes(
          units: 5,
          unit_amount_cents: 1200,
          unit_precise_amount_cents: 1200.2
        )
      end

      context "when invoice is NOT in draft status" do
        before { invoice.finalized! }

        it "returns forbidden status" do
          result = create_service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ForbiddenFailure)
            expect(result.error.code).to eq("feature_unavailable")
          end
        end
      end

      context "when there is invalid charge model but amount is adjusted" do
        let(:percentage_charge) { create(:percentage_charge) }
        let(:fee) { create(:charge_fee, invoice:, subscription:, charge: percentage_charge) }

        it "returns success response" do
          result = create_service.call

          expect(result).to be_success
        end
      end

      context "when there is invalid charge model and display name is adjusted" do
        let(:percentage_charge) { create(:percentage_charge) }
        let(:fee) { create(:charge_fee, invoice:, subscription:, charge: percentage_charge) }
        let(:params) do
          {
            fee_id: fee.id,
            invoice_display_name: "new-dis-name"
          }
        end

        it "returns success response" do
          result = create_service.call

          expect(result).to be_success
        end
      end

      context "when there is invalid charge model and units are adjusted" do
        let(:percentage_charge) { create(:percentage_charge) }
        let(:fee) { create(:charge_fee, invoice:, subscription:, charge: percentage_charge) }
        let(:params) do
          {
            fee_id: fee.id,
            units: 5,
            invoice_display_name: "new-dis-name"
          }
        end

        it "returns error" do
          result = create_service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:charge]).to eq(["invalid_charge_model"])
          end
        end
      end

      context "when fee belongs to another invoice" do
        let(:fee) { create(:charge_fee) }

        it "returns error" do
          result = create_service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::NotFoundFailure)
            expect(result.error.message).to eq("fee_not_found")
          end
        end
      end

      context "when adjusted fee already exists" do
        let(:adjusted_fee) { create(:adjusted_fee, fee:) }

        before { adjusted_fee }

        it "returns validation error" do
          result = create_service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:adjusted_fee]).to eq(["already_exists"])
          end
        end
      end

      context "when adjusting without fee" do
        let(:fee) { nil }
        let(:params) do
          {
            units: 5,
            unit_precise_amount: 12.002,
            invoice_display_name: "new-dis-name",
            subscription_id: subscription.id,
            charge_id: charge.id,
            charge_filter_id: charge_filter.id
          }
        end

        it "creates an adjusted fee and a fee" do
          expect { create_service.call }
            .to change(AdjustedFee, :count).by(1)
            .and change(Fee, :count).by(1)
        end

        it "returns adjusted fee in the result" do
          result = create_service.call
          expect(result.adjusted_fee)
            .to be_a(AdjustedFee)
            .and have_attributes(
              fee: Fee,
              invoice:,
              subscription:,
              charge:,
              adjusted_units: false,
              adjusted_amount: true,
              invoice_display_name: "new-dis-name",
              fee_type: "charge",
              units: 5,
              unit_amount_cents: 1200,
              unit_precise_amount_cents: 1200.2,
              grouped_by: {},
              charge_filter:
            )
        end

        it "returns fee in the result" do
          result = create_service.call
          expect(result.fee)
            .to be_a(Fee)
            .and have_attributes(
              organization:,
              invoice:,
              subscription:,
              invoiceable: charge,
              charge:,
              charge_filter:,
              grouped_by: {},
              fee_type: "charge",
              payment_status: "pending",
              events_count: 0,
              amount_currency: invoice.currency,
              amount_cents: 0,
              precise_amount_cents: 0.to_d,
              unit_amount_cents: 0,
              precise_unit_amount: 0.to_d,
              taxes_amount_cents: 0,
              taxes_precise_amount_cents: 0.to_d,
              units: 0,
              total_aggregated_units: 0,
              properties: Hash,
              amount_details: {}
            )
        end

        it "calls the RefreshDraft service" do
          create_service.call

          expect(Invoices::RefreshDraftService).to have_received(:new)
          expect(refresh_service).to have_received(:call)
        end

        context "when adjusting a dynamic charge" do
          let(:billable_metric) { create(:sum_billable_metric, organization:) }
          let(:charge) { create(:dynamic_charge, billable_metric:, plan: subscription.plan) }

          it "creates an adjusted fee and a fee" do
            expect { create_service.call }
              .to change(AdjustedFee, :count).by(1)
              .and change(Fee, :count).by(1)
          end
        end

        context "when a fee exists with the attributes" do
          let(:fee) { create(:charge_fee, invoice:, subscription:, charge:, charge_filter:) }
          let(:params) do
            {
              units: 5,
              unit_precise_amount: 12.002,
              invoice_display_name: "new-dis-name",
              subscription_id: subscription.id,
              charge_id: fee.charge_id,
              charge_filter_id: fee.charge_filter_id
            }
          end

          it "creates an adjusted fee for the fee" do
            result = create_service.call
            expect(result.adjusted_fee)
              .to be_a(AdjustedFee)
              .and have_attributes(fee:)
          end
        end

        context "when subscription_id does not belongs to the invoice" do
          let(:fee) { create(:charge_fee, invoice:, subscription:, charge:, charge_filter:) }
          let(:params) do
            {
              units: 5,
              unit_precise_amount: 12.002,
              invoice_display_name: "new-dis-name",
              subscription_id: "invalid_id",
              charge_id: fee.charge_id,
              charge_filter_id: fee.charge_filter_id
            }
          end

          it "returns a not found error" do
            result = create_service.call

            aggregate_failures do
              expect(result).not_to be_success
              expect(result.error).to be_a(BaseService::NotFoundFailure)
              expect(result.error.message).to eq("subscription_not_found")
            end
          end
        end

        context "when charge_id does not belongs to the invoice" do
          let(:fee) { create(:charge_fee, invoice:, subscription:, charge:, charge_filter:) }
          let(:params) do
            {
              units: 5,
              unit_precise_amount: 12.002,
              invoice_display_name: "new-dis-name",
              subscription_id: subscription.id,
              charge_id: "invalid_id",
              charge_filter_id: fee.charge_filter_id
            }
          end

          it "returns a not found error" do
            result = create_service.call

            aggregate_failures do
              expect(result).not_to be_success
              expect(result.error).to be_a(BaseService::NotFoundFailure)
              expect(result.error.message).to eq("charge_not_found")
            end
          end
        end

        context "when charge_filter_id does not belongs to the invoice" do
          let(:fee) { create(:charge_fee, invoice:, subscription:, charge:, charge_filter:) }
          let(:params) do
            {
              units: 5,
              unit_precise_amount: 12.002,
              invoice_display_name: "new-dis-name",
              subscription_id: subscription.id,
              charge_id: charge.id,
              charge_filter_id: "invalid_id"
            }
          end

          it "returns a not found error" do
            result = create_service.call

            aggregate_failures do
              expect(result).not_to be_success
              expect(result.error).to be_a(BaseService::NotFoundFailure)
              expect(result.error.message).to eq("charge_filter_not_found")
            end
          end
        end
      end
    end

    context "when license is not premium" do
      it "returns forbidden status" do
        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ForbiddenFailure)
          expect(result.error.code).to eq("feature_unavailable")
        end
      end
    end
  end
end
