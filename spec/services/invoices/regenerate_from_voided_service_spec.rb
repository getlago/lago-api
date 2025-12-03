# frozen_string_literal: true

require "rails_helper"

describe "Regenerate From Voided Invoice Scenarios", :with_pdf_generation_stub, type: :request do
  subject(:regenerate_result) do
    Invoices::RegenerateFromVoidedService.call!(voided_invoice:, fees_params:)
  end

  let(:voided_invoice) { original_invoice }
  let(:organization) { create(:organization) }
  let(:tax) { create(:tax, :applied_to_billing_entity, organization:, rate: 20) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 1000, pay_in_advance: true) }

  let(:subscription) do
    travel_to(DateTime.new(2023, 1, 1)) do
      create_subscription(
        {external_customer_id: customer.external_id,
         external_id: "sub_#{customer.external_id}",
         plan_code: plan.code}
      )
    end

    customer.reload.subscriptions.first
  end

  let(:original_invoice) do
    travel_to(DateTime.new(2023, 1, 15)) { perform_billing }
    invoice = subscription.invoices.first
    invoice.update!(status: :voided)
    invoice
  end
  let(:fees_params) do
    [
      {
        id: original_fee.id,
        subscription_id: subscription.id,
        invoice_display_name: "new-dis-name",
        units: 10,
        unit_amount_cents: 50.50
      }
    ]
  end

  let(:original_fee) { original_invoice.fees.first }

  describe "#call" do
    before do
      stub_request(:post, organization.webhook_endpoints.first.webhook_url).to_return(status: 200, body: "")
      original_invoice
    end

    it "regenerates invoice with adjusted display name, units and unit amount" do
      regenerated_fee = regenerate_result.invoice.fees.first

      expect(regenerated_fee.invoice_display_name).to eq "new-dis-name"
      expect(regenerated_fee.units).to eq 10
      expect(regenerated_fee.unit_amount_cents).to eq 5050
      expect(regenerated_fee.amount_cents).to eq 10 * 5050
    end

    it "creates a payment" do
      allow(Invoices::Payments::CreateService).to receive(:call_async)

      regenerate_result

      expect(Invoices::Payments::CreateService).to have_received(:call_async).once
    end

    it "enqueues a SendWebhookJob for the invoice" do
      expect do
        regenerate_result
      end.to have_enqueued_job(SendWebhookJob).with("invoice.created", Invoice)
    end

    it "produces an activity log" do
      invoice = regenerate_result.invoice

      expect(Utils::ActivityLog).to have_produced("invoice.created").with(invoice)
    end

    it "produces segment event" do
      allow(Utils::SegmentTrack).to receive(:invoice_created).and_call_original

      regenerate_result

      expect(Utils::SegmentTrack).to have_received(:invoice_created)
    end

    it "enqueues GenerateDocumentsJob with email false" do
      expect do
        regenerate_result
      end.to have_enqueued_job(Invoices::GenerateDocumentsJob).with(hash_including(notify: false))
    end

    it_behaves_like "syncs invoice" do
      let(:service_call) { regenerate_result }
    end

    context "with updated units" do
      let(:fees_params) do
        [
          {
            id: original_fee.id,
            subscription_id: subscription.id,
            units: 3
          }
        ]
      end

      it "regenerates invoice" do
        regenerated_fee = regenerate_result.invoice.fees.first

        expect(regenerated_fee.invoice_display_name).to eq nil
        expect(regenerated_fee.units).to eq 3
        expect(regenerated_fee.unit_amount_cents).to eq original_fee.unit_amount_cents
        expect(regenerated_fee.amount_cents).to eq 3 * original_fee.unit_amount_cents
      end
    end

    context "with fixed charge fees" do
      let(:fixed_charge) do
        create(
          :fixed_charge,
          plan:,
          charge_model: "standard",
          properties: {amount: "10"}
        )
      end

      let(:original_invoice) do
        travel_to(DateTime.new(2023, 1, 15)) { perform_billing }
        invoice = subscription.invoices.first

        # Add a fixed charge fee to the invoice
        create(
          :fixed_charge_fee,
          invoice:,
          subscription:,
          fixed_charge:,
          amount_cents: 5000,
          precise_amount_cents: 5000.0,
          units: 5,
          unit_amount_cents: 1000,
          precise_unit_amount: 10,
          properties: {
            fixed_charges_from_datetime: subscription.started_at.beginning_of_day,
            fixed_charges_to_datetime: subscription.started_at.end_of_month.end_of_day
          }
        )

        invoice.update!(status: :voided)
        invoice
      end

      let(:fixed_charge_fee) { original_invoice.fees.find_by(fee_type: :fixed_charge) }

      context "when adjusting only display name" do
        let(:fees_params) do
          [
            {
              id: fixed_charge_fee.id,
              subscription_id: subscription.id,
              invoice_display_name: "Custom Fixed Charge Name",
              units: 5
            }
          ]
        end

        it "regenerates invoice with adjusted display name" do
          regenerated_fee = regenerate_result.invoice.fees.find_by(fixed_charge_id: fixed_charge.id)

          expect(regenerated_fee.invoice_display_name).to eq "Custom Fixed Charge Name"
          expect(regenerated_fee.units).to eq 5
          expect(regenerated_fee.unit_amount_cents).to eq 1000
          expect(regenerated_fee.amount_cents).to eq 5000
        end
      end

      context "when adjusting units" do
        let(:fees_params) do
          [
            {
              id: fixed_charge_fee.id,
              subscription_id: subscription.id,
              units: 10
            }
          ]
        end

        it "regenerates invoice with adjusted units" do
          regenerated_fee = regenerate_result.invoice.fees.find_by(fixed_charge_id: fixed_charge.id)

          expect(regenerated_fee.units).to eq 10
          expect(regenerated_fee.unit_amount_cents).to eq 1000
          expect(regenerated_fee.amount_cents).to eq 10_000
          expect(regenerated_fee.precise_amount_cents).to eq 10_000.0
        end
      end

      context "when adjusting unit amount" do
        let(:fees_params) do
          [
            {
              id: fixed_charge_fee.id,
              subscription_id: subscription.id,
              units: 5,
              unit_amount_cents: 15.50
            }
          ]
        end

        it "regenerates invoice with adjusted unit amount" do
          regenerated_fee = regenerate_result.invoice.fees.find_by(fixed_charge_id: fixed_charge.id)

          expect(regenerated_fee.units).to eq 5
          expect(regenerated_fee.unit_amount_cents).to eq 1550
          expect(regenerated_fee.amount_cents).to eq 7750
          expect(regenerated_fee.precise_amount_cents).to eq 7750.0
          expect(regenerated_fee.precise_unit_amount).to eq 15.50
        end
      end

      context "when adjusting both units and unit amount" do
        let(:fees_params) do
          [
            {
              id: fixed_charge_fee.id,
              subscription_id: subscription.id,
              invoice_display_name: "Adjusted Fixed Charge",
              units: 8,
              unit_amount_cents: 12.75
            }
          ]
        end

        it "regenerates invoice with all adjustments" do
          regenerated_fee = regenerate_result.invoice.fees.find_by(fixed_charge_id: fixed_charge.id)

          expect(regenerated_fee.invoice_display_name).to eq "Adjusted Fixed Charge"
          expect(regenerated_fee.units).to eq 8
          expect(regenerated_fee.unit_amount_cents).to eq 1275
          expect(regenerated_fee.amount_cents).to eq 10_200
          expect(regenerated_fee.precise_amount_cents).to eq 10_200.0
          expect(regenerated_fee.precise_unit_amount).to eq 12.75
        end
      end

      context "with graduated fixed charge" do
        let(:fixed_charge) do
          create(
            :fixed_charge,
            plan:,
            charge_model: "graduated",
            properties: {
              graduated_ranges: [
                {
                  from_value: 0,
                  to_value: 10,
                  per_unit_amount: "1",
                  flat_amount: "5"
                },
                {
                  from_value: 11,
                  to_value: nil,
                  per_unit_amount: "0.5",
                  flat_amount: "10"
                }
              ]
            }
          )
        end

        let(:original_invoice) do
          travel_to(DateTime.new(2023, 1, 15)) { perform_billing }
          invoice = subscription.invoices.first

          # Add a graduated fixed charge fee
          create(
            :fixed_charge_fee,
            invoice:,
            subscription:,
            fixed_charge:,
            amount_cents: 1500,
            precise_amount_cents: 1500.0,
            units: 10,
            unit_amount_cents: 150,
            precise_unit_amount: 1.5,
            amount_details: {
              "graduated_ranges" => [
                {
                  "from_value" => 0,
                  "to_value" => 10,
                  "per_unit_amount" => "1",
                  "flat_amount" => "5",
                  "per_unit_total_amount" => "10",
                  "total_with_flat_amount" => "15",
                  "units" => "10"
                }
              ]
            },
            properties: {
              fixed_charges_from_datetime: subscription.started_at.beginning_of_day,
              fixed_charges_to_datetime: subscription.started_at.end_of_month.end_of_day
            }
          )

          invoice.update!(status: :voided)
          invoice
        end

        context "when adjusting units" do
          let(:fees_params) do
            [
              {
                id: fixed_charge_fee.id,
                subscription_id: subscription.id,
                units: 15
              }
            ]
          end

          it "regenerates invoice applying graduated model to new units" do
            regenerated_fee = regenerate_result.invoice.fees.find_by(fixed_charge_id: fixed_charge.id)

            # Expected: 5 + (10 * 1) + 10 + (5 * 0.5) = 27.50
            expect(regenerated_fee.units).to eq 15
            expect(regenerated_fee.amount_cents).to eq 2750
            expect(regenerated_fee.precise_amount_cents).to eq 2750.0

            expect(regenerated_fee.amount_details).to be_present
            expect(regenerated_fee.amount_details).to eq(
              {
                "graduated_ranges" => [
                  {
                    "from_value" => 0,
                    "to_value" => 10,
                    "flat_unit_amount" => "5.0",
                    "per_unit_amount" => "1.0",
                    "per_unit_total_amount" => "10.0",
                    "total_with_flat_amount" => "15.0",
                    "units" => "10.0"
                  },
                  {
                    "from_value" => 11,
                    "to_value" => nil,
                    "flat_unit_amount" => "10.0",
                    "per_unit_amount" => "0.5",
                    "per_unit_total_amount" => "2.5",
                    "total_with_flat_amount" => "12.5",
                    "units" => "5.0"
                  }
                ]
              }
            )
          end
        end

        context "when adjusting unit amount" do
          let(:fees_params) do
            [
              {
                id: fixed_charge_fee.id,
                subscription_id: subscription.id,
                units: 10,
                unit_amount_cents: 3.00
              }
            ]
          end

          it "regenerates invoice with adjusted unit amount (not charge model)" do
            regenerated_fee = regenerate_result.invoice.fees.find_by(fixed_charge_id: fixed_charge.id)

            # Expected: 10 units * 3.00 = 30.00 (ignores graduated model)
            expect(regenerated_fee.units).to eq 10
            expect(regenerated_fee.unit_amount_cents).to eq 300
            expect(regenerated_fee.amount_cents).to eq 3000
            expect(regenerated_fee.precise_amount_cents).to eq 3000.0
            expect(regenerated_fee.precise_unit_amount).to eq 3.0
          end
        end
      end

      context "with volume fixed charge" do
        let(:fixed_charge) do
          create(
            :fixed_charge,
            plan:,
            charge_model: "volume",
            properties: {
              volume_ranges: [
                {
                  from_value: 0,
                  to_value: 10,
                  per_unit_amount: "2",
                  flat_amount: "5"
                },
                {
                  from_value: 11,
                  to_value: nil,
                  per_unit_amount: "1.5",
                  flat_amount: "15"
                }
              ]
            }
          )
        end

        let(:original_invoice) do
          travel_to(DateTime.new(2023, 1, 15)) { perform_billing }
          invoice = subscription.invoices.first

          # Add a volume fixed charge fee
          create(
            :fixed_charge_fee,
            invoice:,
            subscription:,
            fixed_charge:,
            amount_cents: 2500,
            precise_amount_cents: 2500.0,
            units: 10,
            unit_amount_cents: 250,
            precise_unit_amount: 2.5,
            amount_details: {
              "volume_ranges" => [
                {
                  "from_value" => 0,
                  "to_value" => 10,
                  "per_unit_amount" => "2",
                  "flat_amount" => "5",
                  "per_unit_total_amount" => "20",
                  "total_with_flat_amount" => "25",
                  "units" => "10"
                }
              ]
            },
            properties: {
              fixed_charges_from_datetime: subscription.started_at.beginning_of_day,
              fixed_charges_to_datetime: subscription.started_at.end_of_month.end_of_day
            }
          )

          invoice.update!(status: :voided)
          invoice
        end

        context "when adjusting units" do
          let(:fees_params) do
            [
              {
                id: fixed_charge_fee.id,
                subscription_id: subscription.id,
                units: 12
              }
            ]
          end

          it "regenerates invoice applying volume model to new units" do
            regenerated_fee = regenerate_result.invoice.fees.find_by(fixed_charge_id: fixed_charge.id)

            # Expected: 15 + (12 * 1.5) = 33.00 (uses second range)
            expect(regenerated_fee.units).to eq 12
            expect(regenerated_fee.amount_cents).to eq 3300
            expect(regenerated_fee.precise_amount_cents).to eq 3300.0

            expect(regenerated_fee.amount_details).to be_present
            expect(regenerated_fee.amount_details).to eq(
              {
                "flat_unit_amount" => "15.0",
                "per_unit_amount" => "1.5",
                "per_unit_total_amount" => "18.0"
              }
            )
          end
        end
      end
    end
  end
end
