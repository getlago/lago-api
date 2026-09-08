# frozen_string_literal: true

require "rails_helper"

RSpec.describe DataExports::Csv::ResolveFeeBillingPeriodService do
  subject(:result) { described_class.call(fee:, invoice_subscription:) }

  let(:fee) { instance_double(Fee, fee_type:, properties:, pay_in_advance?: pay_in_advance) }
  let(:fee_type) { "subscription" }
  let(:properties) { {} }
  let(:pay_in_advance) { false }
  let(:invoice_subscription) do
    instance_double(
      InvoiceSubscription,
      from_datetime: subscription_from_datetime,
      to_datetime: subscription_to_datetime
    )
  end
  let(:subscription_from_datetime) { Time.zone.parse("2026-06-22 00:00:00 UTC") }
  let(:subscription_to_datetime) { Time.zone.parse("2026-07-21 23:59:59 UTC") }

  describe "#call" do
    context "with a subscription fee" do
      let(:properties) do
        {
          "from_datetime" => "2026-08-22T00:00:00Z",
          "to_datetime" => "2026-09-21T23:59:59Z"
        }
      end

      it "returns the fee boundaries" do
        expect(result.from_datetime).to eq(Time.zone.parse("2026-08-22 00:00:00 UTC"))
        expect(result.to_datetime).to eq(Time.zone.parse("2026-09-21 23:59:59 UTC"))
      end

      context "when one fee boundary is missing" do
        let(:properties) { {"from_datetime" => "2026-08-22T00:00:00Z"} }

        it "falls back to the complete invoice subscription period" do
          expect(result.from_datetime).to eq(subscription_from_datetime)
          expect(result.to_datetime).to eq(subscription_to_datetime)
        end
      end
    end

    context "with a fixed charge fee" do
      let(:fee_type) { "fixed_charge" }
      let(:invoice_subscription) do
        instance_double(
          InvoiceSubscription,
          fixed_charges_from_datetime: fixed_charge_from_datetime,
          fixed_charges_to_datetime: fixed_charge_to_datetime
        )
      end
      let(:fixed_charge_from_datetime) { Time.zone.parse("2026-06-22 00:00:00 UTC") }
      let(:fixed_charge_to_datetime) { Time.zone.parse("2026-07-21 23:59:59 UTC") }

      it "falls back to the invoice subscription fixed charge period" do
        expect(result.from_datetime).to eq(fixed_charge_from_datetime)
        expect(result.to_datetime).to eq(fixed_charge_to_datetime)
      end

      context "when one fee boundary is missing" do
        let(:properties) { {"fixed_charges_from_datetime" => "2026-08-22T00:00:00Z"} }

        it "falls back to the complete invoice subscription fixed charge period" do
          expect(result.from_datetime).to eq(fixed_charge_from_datetime)
          expect(result.to_datetime).to eq(fixed_charge_to_datetime)
        end
      end
    end

    context "with a charge fee" do
      let(:fee_type) { "charge" }
      let(:properties) do
        {
          "charges_from_datetime" => "2026-06-22T00:00:00Z",
          "charges_to_datetime" => "2026-07-21T23:59:59Z"
        }
      end
      let(:invoice_subscription) do
        instance_double(
          InvoiceSubscription,
          charges_from_datetime: charges_from_datetime,
          charges_to_datetime: charges_to_datetime
        )
      end
      let(:charges_from_datetime) { Time.zone.parse("2026-05-22 00:00:00 UTC") }
      let(:charges_to_datetime) { Time.zone.parse("2026-06-21 23:59:59 UTC") }

      it "keeps using the invoice subscription charge period" do
        expect(result.from_datetime).to eq(charges_from_datetime)
        expect(result.to_datetime).to eq(charges_to_datetime)
      end

      context "when the fee is pay in advance" do
        let(:pay_in_advance) { true }

        it "returns the fee charge boundaries" do
          expect(result.from_datetime).to eq(Time.zone.parse("2026-06-22 00:00:00 UTC"))
          expect(result.to_datetime).to eq(Time.zone.parse("2026-07-21 23:59:59 UTC"))
        end

        context "when one fee charge boundary is missing" do
          let(:properties) { {"charges_from_datetime" => "2026-06-22T00:00:00Z"} }

          it "falls back to the complete invoice subscription charge period" do
            expect(result.from_datetime).to eq(charges_from_datetime)
            expect(result.to_datetime).to eq(charges_to_datetime)
          end
        end
      end
    end

    context "with a commitment fee" do
      let(:fee_type) { "commitment" }
      let(:properties) do
        {
          "from_datetime" => "2026-05-22T00:00:00Z",
          "to_datetime" => "2026-06-21T23:59:59Z"
        }
      end

      it "returns the stored reconciliation period" do
        expect(result.from_datetime).to eq(Time.zone.parse("2026-05-22 00:00:00 UTC"))
        expect(result.to_datetime).to eq(Time.zone.parse("2026-06-21 23:59:59 UTC"))
      end

      context "without stored boundaries on a pay-in-advance plan" do
        let(:properties) { {} }
        let(:plan) { instance_double(Plan, pay_in_advance?: true) }
        let(:subscription) { instance_double(Subscription, plan:) }
        let(:invoice_subscription) do
          instance_double(
            InvoiceSubscription,
            subscription:,
            previous_invoice_subscription:
          )
        end

        context "with a previous invoice subscription" do
          let(:previous_invoice_subscription) do
            instance_double(
              InvoiceSubscription,
              from_datetime: subscription_from_datetime,
              to_datetime: subscription_to_datetime
            )
          end

          it "returns the previous period" do
            expect(result.from_datetime).to eq(subscription_from_datetime)
            expect(result.to_datetime).to eq(subscription_to_datetime)
          end
        end

        context "without a previous invoice subscription" do
          let(:previous_invoice_subscription) { nil }

          it "returns an empty period" do
            expect(result.from_datetime).to be_nil
            expect(result.to_datetime).to be_nil
          end
        end
      end

      context "without stored boundaries on a pay-in-arrears plan" do
        let(:properties) { {} }
        let(:plan) { instance_double(Plan, pay_in_advance?: false) }
        let(:subscription) { instance_double(Subscription, plan:) }
        let(:invoice_subscription) do
          instance_double(
            InvoiceSubscription,
            subscription:,
            from_datetime: subscription_from_datetime,
            to_datetime: subscription_to_datetime
          )
        end

        it "returns the current invoice subscription period" do
          expect(result.from_datetime).to eq(subscription_from_datetime)
          expect(result.to_datetime).to eq(subscription_to_datetime)
        end
      end
    end

    context "with an add-on fee" do
      let(:fee_type) { "add_on" }
      let(:invoice_subscription) { nil }
      let(:properties) do
        {
          "from_datetime" => "2026-06-22T00:00:00Z",
          "to_datetime" => "2026-07-21T23:59:59Z"
        }
      end

      it "returns the stored fee boundaries" do
        expect(result.from_datetime).to eq(Time.zone.parse("2026-06-22 00:00:00 UTC"))
        expect(result.to_datetime).to eq(Time.zone.parse("2026-07-21 23:59:59 UTC"))
      end
    end
  end
end
