# frozen_string_literal: true

require "rails_helper"

RSpec.describe DataExports::Csv::InvoiceFees do
  let(:customer) { create(:customer, timezone:) }
  let(:plan) { create(:plan, organization: customer.organization) }
  let(:subscription) { create(:subscription, customer:, plan:, organization: customer.organization) }
  let(:invoice) { create(:invoice, customer:, organization: customer.organization) }
  let(:to_utc) { "2024-06-06 12:48:59 UTC" }
  let(:from_utc) { "2024-05-08 00:00:00 UTC" }
  # The subscription period, which only differs from the usage window on advance-billed plans
  let(:subscription_from_utc) { from_utc }
  let(:subscription_to_utc) { to_utc }
  let(:timezone) { "UTC" }
  let(:data_export_part) do
    data_export.data_export_parts.create(index: 1, object_ids: [invoice.id], organization_id: data_export.organization_id)
  end
  let(:data_export) { create :data_export, :processing, resource_type: "invoice_fees", resource_query: {} }
  let(:serialized_fee) do
    {
      lago_id: "cc16e6d5-b5e1-4e2c-9ad3-62b3ee4be302",
      item: {
        type: "charge",
        code: "group",
        name: "group",
        description: "charge 1 description",
        invoice_display_name: "group",
        filter_invoice_display_name: "Converted to EUR",
        grouped_by: {models: "model_1"}
      },
      taxes_amount_cents: 50,
      total_amount_cents: 10000,
      total_amount_currency: "USD",
      units: "100.0",
      precise_unit_amount: "10.0",
      from_date: "2024-05-08T00:00:00+00:00",
      to_date: "2024-06-06T12:48:59+00:00"
    }
  end
  let(:serialized_invoice) do
    {
      lago_id: "292ef60b-9e0c-42e7-9f50-44d5af4162ec",
      number: "TWI-2B86-170-001",
      issuing_date: "2024-06-06"
    }
  end
  let(:fee_serializer) { instance_double("V1::FeeSerializer", serialize: serialized_fee) }
  let(:invoice_serializer) { instance_double("V1::InvoiceSerializer", serialize: serialized_invoice) }
  let(:fee_serializer_klass) { class_double("V1::FeeSerializer") }
  let(:invoice_serializer_klass) { class_double("V1::InvoiceSerializer") }

  describe ".base_headers" do
    it "uses timezone-agnostic column names" do
      expect(described_class.base_headers).to include("fee_from_date", "fee_to_date")
      expect(described_class.base_headers).not_to include("fee_from_date_utc", "fee_to_date_utc")
    end
  end

  describe "#call" do
    subject(:result) do
      described_class.new(data_export_part:, invoice_serializer_klass:, fee_serializer_klass:).call
    end

    let!(:fee) { create(:fee, invoice:, subscription:, organization: customer.organization, fee_type: :subscription) }

    before do
      create(:invoice_subscription,
        invoice:,
        subscription:,
        organization: customer.organization,
        timestamp: Time.zone.parse(subscription_from_utc),
        from_datetime: Time.zone.parse(subscription_from_utc),
        to_datetime: Time.zone.parse(subscription_to_utc),
        charges_from_datetime: Time.zone.parse(from_utc),
        charges_to_datetime: Time.zone.parse(to_utc),
        fixed_charges_from_datetime: Time.zone.parse(subscription_from_utc),
        fixed_charges_to_datetime: Time.zone.parse(subscription_to_utc))
      allow(invoice_serializer_klass).to receive(:new).and_return(invoice_serializer)
      allow(fee_serializer_klass).to receive(:new).and_return(fee_serializer)
    end

    it "generates the correct CSV output" do
      expected_csv = <<~CSV
        292ef60b-9e0c-42e7-9f50-44d5af4162ec,TWI-2B86-170-001,2024-06-06,cc16e6d5-b5e1-4e2c-9ad3-62b3ee4be302,charge,group,group,charge 1 description,group,Converted to EUR,"{models: ""model_1""}",#{fee.subscription.external_id},#{fee.subscription.plan.code},2024-05-08,2024-06-06,USD,100.0,10.0,50,10000
      CSV

      expect(result).to be_success

      file = result.csv_file
      generated_csv = file.read
      file.close
      File.unlink(file.path)

      expect(generated_csv).to eq(expected_csv)
    end

    shared_examples "exports fee dates in customer timezone" do
      it "exports fee dates in the customer's local timezone, not UTC" do
        result = described_class.new(data_export_part:).call

        file = result.csv_file
        csv_content = file.read
        file.close
        File.unlink(file.path)

        rows = CSV.parse(csv_content)
        expect(rows.first[13]).to eq(expected_from) # fee_from_date
        expect(rows.first[14]).to eq(expected_to)   # fee_to_date
      end
    end

    context "when the customer has a negative UTC offset" do
      # America/New_York is UTC-4 in summer. 2026-05-01 03:59 UTC = 2026-04-30 23:59 EDT.
      let(:timezone) { "America/New_York" }
      let(:from_utc) { "2026-04-01 04:00:00 UTC" }
      let(:to_utc) { "2026-05-01 03:59:59 UTC" }
      let(:expected_from) { "2026-04-01" }
      let(:expected_to) { "2026-04-30" }

      it_behaves_like "exports fee dates in customer timezone"
    end

    context "when the customer has a positive UTC offset" do
      # Asia/Tokyo is UTC+9. 2026-03-31 15:00 UTC = 2026-04-01 00:00 JST.
      let(:timezone) { "Asia/Tokyo" }
      let(:from_utc) { "2026-03-31 15:00:00 UTC" }
      let(:to_utc) { "2026-04-30 14:59:59 UTC" }
      let(:expected_from) { "2026-04-01" }
      let(:expected_to) { "2026-04-30" }

      it_behaves_like "exports fee dates in customer timezone"
    end

    context "when a fee is billed in advance for a period of its own" do
      # The invoice mixes an arrears usage block (charges_*: May 22 - Jun 21) with
      # advance-billed rows covering the next period (Jun 22 - Jul 21).
      let(:from_utc) { "2026-05-22 00:00:00 UTC" }
      let(:to_utc) { "2026-06-21 23:59:59 UTC" }

      let(:advance_boundaries) do
        {
          "from_datetime" => "2026-06-22T00:00:00Z",
          "to_datetime" => "2026-07-21T23:59:59Z",
          "fixed_charges_from_datetime" => "2026-06-22T00:00:00Z",
          "fixed_charges_to_datetime" => "2026-07-21T23:59:59Z"
        }
      end
      let(:exported_fee) { advance_fee }

      def exported_period
        result = described_class.new(data_export_part:).call

        file = result.csv_file
        csv_content = file.read
        file.close
        File.unlink(file.path)

        row = CSV.parse(csv_content).find { |r| r[3] == exported_fee.id }
        [row[13], row[14]]
      end

      context "with an advance-billed fixed charge fee" do
        let(:advance_fee) do
          create(:fixed_charge_fee,
            invoice:,
            subscription:,
            organization: customer.organization,
            pay_in_advance: true,
            properties: advance_boundaries)
        end

        before { advance_fee }

        it "exports the fee's own period rather than the usage window" do
          expect(exported_period).to eq(%w[2026-06-22 2026-07-21])
        end
      end

      context "with a subscription fee billed in advance" do
        let(:advance_fee) do
          create(:fee,
            invoice:,
            subscription:,
            organization: customer.organization,
            fee_type: :subscription,
            properties: advance_boundaries)
        end

        before { advance_fee }

        it "exports the fee's own period rather than the usage window" do
          expect(exported_period).to eq(%w[2026-06-22 2026-07-21])
        end

        context "when the customer is in a negative UTC offset timezone" do
          # America/New_York is UTC-4 in summer, so a Jun 22 - Jul 21 local period is
          # stored as 2026-06-22 04:00 UTC - 2026-07-22 03:59 UTC.
          let(:timezone) { "America/New_York" }
          let(:advance_boundaries) do
            {
              "from_datetime" => "2026-06-22T04:00:00Z",
              "to_datetime" => "2026-07-22T03:59:59Z"
            }
          end

          it "converts the fee's own period to the customer timezone" do
            expect(exported_period).to eq(%w[2026-06-22 2026-07-21])
          end
        end
      end

      context "with an arrears usage fee" do
        let(:charge) { create(:standard_charge, plan:) }
        let(:charge_boundaries) do
          {
            "charges_from_datetime" => "2026-05-22T00:00:00Z",
            "charges_to_datetime" => "2026-06-21T23:59:59Z"
          }
        end
        let(:charge_fee) do
          create(:charge_fee,
            invoice:,
            subscription:,
            charge:,
            organization: customer.organization,
            pay_in_advance: fee_pay_in_advance,
            properties: charge_boundaries)
        end
        let(:fee_pay_in_advance) { false }
        let(:exported_fee) { charge_fee }

        before { charge_fee }

        it "keeps exporting the usage window" do
          expect(exported_period).to eq(%w[2026-05-22 2026-06-21])
        end

        context "when the charge is pay in advance but the fee is billed in arrears" do
          let(:charge) { create(:standard_charge, :pay_in_advance, plan:) }
          let(:timezone) { "America/New_York" }
          let(:from_utc) { "2026-05-22 04:00:00 UTC" }
          let(:to_utc) { "2026-06-22 03:59:59 UTC" }
          let(:charge_boundaries) do
            {
              "charges_from_datetime" => "2026-05-22T04:00:00Z",
              "charges_to_datetime" => "2026-06-22T03:59:59Z"
            }
          end

          it "keeps exporting the usage window" do
            expect(exported_period).to eq(%w[2026-05-22 2026-06-21])
          end
        end

        context "when the fee is pay in advance in a negative UTC offset timezone" do
          let(:charge) { create(:standard_charge, :pay_in_advance, plan:) }
          let(:fee_pay_in_advance) { true }
          let(:timezone) { "America/New_York" }
          let(:from_utc) { "2026-05-22 04:00:00 UTC" }
          let(:to_utc) { "2026-06-22 03:59:59 UTC" }
          let(:charge_boundaries) do
            {
              "charges_from_datetime" => "2026-06-22T04:00:00Z",
              "charges_to_datetime" => "2026-07-22T03:59:59Z"
            }
          end

          it "exports the fee's own period without shifting it by one day" do
            expect(exported_period).to eq(%w[2026-06-22 2026-07-21])
          end
        end
      end

      context "with a commitment fee" do
        # A commitment fee carries the period it reconciles, which on a pay-in-advance
        # plan is the period preceding the invoice's usage window.
        let(:plan) { create(:plan, organization: customer.organization, pay_in_advance: true) }
        let(:commitment_boundaries) do
          {
            "from_datetime" => "2026-04-22T00:00:00Z",
            "to_datetime" => "2026-05-21T23:59:59Z"
          }
        end
        let(:advance_fee) do
          create(:minimum_commitment_fee,
            invoice:,
            subscription:,
            organization: customer.organization,
            properties: commitment_boundaries)
        end

        before { advance_fee }

        it "exports the reconciled period rather than the usage window" do
          expect(exported_period).to eq(%w[2026-04-22 2026-05-21])
        end

        context "without stored boundaries or a previous invoice subscription" do
          let(:commitment_boundaries) { {} }

          it "exports an empty period" do
            expect(exported_period).to eq([nil, nil])
          end
        end
      end

      context "with a subscription fee carrying no boundaries of its own" do
        # Legacy rows have empty properties: on a pay-in-advance plan the subscription
        # period is the next period, not the arrears usage window.
        let(:plan) { create(:plan, organization: customer.organization, pay_in_advance: true) }
        let(:subscription_from_utc) { "2026-06-22 00:00:00 UTC" }
        let(:subscription_to_utc) { "2026-07-21 23:59:59 UTC" }
        let(:advance_fee) do
          create(:fee,
            invoice:,
            subscription:,
            organization: customer.organization,
            fee_type: :subscription,
            properties: {})
        end

        before { advance_fee }

        it "falls back to the subscription period, not the usage window" do
          expect(exported_period).to eq(%w[2026-06-22 2026-07-21])
        end
      end

      context "with an add-on fee" do
        let(:add_on_boundaries) do
          {
            "from_datetime" => "2026-08-04T00:00:00Z",
            "to_datetime" => "2026-08-04T23:59:59Z"
          }
        end
        let(:exported_fee) { add_on_fee }

        shared_examples "exports the stored add-on period" do
          before { add_on_fee }

          it "exports the stored calendar dates in UTC" do
            expect(exported_period).to eq(%w[2026-08-04 2026-08-04])
          end

          context "when the customer has a negative UTC offset" do
            let(:timezone) { "America/New_York" }

            it "does not move the start date back one day" do
              expect(exported_period).to eq(%w[2026-08-04 2026-08-04])
            end
          end

          context "when the customer has a positive UTC offset" do
            let(:timezone) { "Asia/Tokyo" }

            it "does not move the end date forward one day" do
              expect(exported_period).to eq(%w[2026-08-04 2026-08-04])
            end
          end
        end

        context "with a one-off fee" do
          let(:add_on_fee) do
            create(:one_off_fee,
              invoice:,
              organization: customer.organization,
              properties: add_on_boundaries)
          end

          it_behaves_like "exports the stored add-on period"
        end

        context "with a legacy applied add-on fee" do
          let(:add_on_fee) do
            create(:add_on_fee,
              invoice:,
              organization: customer.organization,
              properties: add_on_boundaries)
          end

          it_behaves_like "exports the stored add-on period"
        end
      end
    end
  end
end
