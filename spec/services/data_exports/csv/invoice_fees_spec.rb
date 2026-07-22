# frozen_string_literal: true

require "rails_helper"

RSpec.describe DataExports::Csv::InvoiceFees do
  let(:customer) { create(:customer, timezone:) }
  let(:plan) { create(:plan, organization: customer.organization) }
  let(:subscription) { create(:subscription, customer:, plan:, organization: customer.organization) }
  let(:invoice) { create(:invoice, customer:, organization: customer.organization) }
  let(:to_utc) { "2024-06-06 12:48:59 UTC" }
  let(:from_utc) { "2024-05-08 00:00:00 UTC" }
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
        charges_from_datetime: Time.zone.parse(from_utc),
        charges_to_datetime: Time.zone.parse(to_utc))
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
  end
end
