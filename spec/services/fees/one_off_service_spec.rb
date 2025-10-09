# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::OneOffService do
  subject(:one_off_service) do
    described_class.new(invoice:, fees:)
  end

  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:billing_entity) { create(:billing_entity) }
  let(:organization) { billing_entity.organization }
  let(:customer) { create(:customer, organization:) }
  let(:tax) { create(:tax, :applied_to_billing_entity, organization:, billing_entity:) }
  let(:tax2) { create(:tax, organization:, applied_to_organization: false) }
  let(:add_on_first) { create(:add_on, organization:) }
  let(:add_on_second) { create(:add_on, amount_cents: 400, organization:) }
  let(:current_time) { DateTime.new(2023, 7, 19, 12, 12) }
  let(:fees) do
    [
      {
        add_on_code: add_on_first.code,
        unit_amount_cents: 1200,
        units: 2,
        description: "desc-123",
        tax_codes: [tax2.code]
      },
      {
        add_on_code: add_on_second.code
      }
    ]
  end

  before { tax }

  describe "create" do
    before { CurrentContext.source = "api" }

    it "creates fees" do
      travel_to(current_time) do
        result = one_off_service.call

        expect(result).to be_success

        first_fee = result.fees[0]
        second_fee = result.fees[1]

        expect(first_fee).to have_attributes(
          id: String,
          organization_id: organization.id,
          billing_entity_id: billing_entity.id,
          invoice_id: invoice.id,
          add_on_id: add_on_first.id,
          description: "desc-123",
          unit_amount_cents: 1200,
          precise_unit_amount: 12,
          units: 2,
          amount_cents: 2400,
          precise_amount_cents: 2400.0,
          amount_currency: "EUR",
          fee_type: "add_on",
          payment_status: "pending",
          properties: {
            "from_datetime" => current_time.to_time.utc.iso8601(3),
            "to_datetime" => current_time.to_time.utc.iso8601(3),
            "timestamp" => current_time
          }
        )
        expect(first_fee.taxes.map(&:code)).to contain_exactly(tax2.code)

        expect(second_fee).to have_attributes(
          id: String,
          organization_id: organization.id,
          billing_entity_id: billing_entity.id,
          invoice_id: invoice.id,
          add_on_id: add_on_second.id,
          description: add_on_second.description,
          unit_amount_cents: 400,
          precise_unit_amount: 4,
          units: 1,
          amount_cents: 400,
          precise_amount_cents: 400.0,
          amount_currency: "EUR",
          fee_type: "add_on",
          payment_status: "pending",
          properties: {
            "from_datetime" => current_time.to_time.utc.iso8601(3),
            "to_datetime" => current_time.to_time.utc.iso8601(3),
            "timestamp" => current_time
          }
        )
        expect(second_fee.taxes.map(&:code)).to contain_exactly(tax.code)
      end
    end

    context "with passed boundaries" do
      let(:fees) do
        [
          {
            add_on_code: add_on_first.code,
            unit_amount_cents: 1200,
            units: 2,
            description: "desc-123",
            from_datetime: "2022-01-01T00:00:00Z",
            to_datetime: "2022-01-31T23:59:59.123Z",
            tax_codes: [tax2.code]
          }
        ]
      end

      it "creates fees" do
        travel_to(current_time) do
          result = one_off_service.call

          expect(result).to be_success

          first_fee = result.fees[0]

          expect(first_fee).to have_attributes(
            id: String,
            organization_id: organization.id,
            billing_entity_id: billing_entity.id,
            invoice_id: invoice.id,
            add_on_id: add_on_first.id,
            description: "desc-123",
            unit_amount_cents: 1200,
            precise_unit_amount: 12,
            units: 2,
            amount_cents: 2400,
            precise_amount_cents: 2400.0,
            amount_currency: "EUR",
            fee_type: "add_on",
            payment_status: "pending",
            properties: {
              "from_datetime" => "2022-01-01T00:00:00.000+00:00",
              "to_datetime" => "2022-01-31T23:59:59.123+00:00",
              "timestamp" => current_time
            }
          )
          expect(first_fee.taxes.map(&:code)).to contain_exactly(tax2.code)
        end
      end
    end

    context "when add_on_code is invalid" do
      let(:fees) do
        [
          {
            add_on_code: add_on_first.code,
            unit_amount_cents: 1200,
            units: 2,
            description: "desc-123"
          },
          {
            add_on_code: "invalid"
          }
        ]
      end

      it "does not create an invalid fee" do
        one_off_service.call

        expect(Fee.find_by(description: add_on_second.description)).to be_nil
      end
    end

    context "when boundaries have invalid values" do
      let(:fees) do
        [
          {
            add_on_code: add_on_first.code,
            unit_amount_cents: 1200,
            units: 2,
            description: "desc-123",
            from_datetime: "2022-05-01T00:00:00Z",
            to_datetime: "2022-01-31T23:59:59Z",
            tax_codes: [tax2.code]
          }
        ]
      end

      it "does not create an invalid fee" do
        one_off_service.call

        expect(Fee.find_by(description: add_on_first.description)).to be_nil
      end

      it "returns validation failure" do
        result = one_off_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:boundaries]).to include("values_are_invalid")
      end
    end

    context "when one boundary has invalid format" do
      let(:fees) do
        [
          {
            add_on_code: add_on_first.code,
            unit_amount_cents: 1200,
            units: 2,
            description: "desc-123",
            from_datetime: "2022-01-01T00:00:00Z",
            to_datetime: "invalid",
            tax_codes: [tax2.code]
          }
        ]
      end

      it "does not create an invalid fee" do
        one_off_service.call

        expect(Fee.find_by(description: add_on_first.description)).to be_nil
      end

      it "returns validation failure" do
        result = one_off_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:boundaries]).to include("values_are_invalid")
      end
    end

    context "when one boundary is missing" do
      let(:fees) do
        [
          {
            add_on_code: add_on_first.code,
            unit_amount_cents: 1200,
            units: 2,
            description: "desc-123",
            from_datetime: "2022-01-01T00:00:00Z",
            tax_codes: [tax2.code]
          }
        ]
      end

      it "does not create an invalid fee" do
        one_off_service.call

        expect(Fee.find_by(description: add_on_first.description)).to be_nil
      end

      it "returns validation failure" do
        result = one_off_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:boundaries]).to include("values_are_invalid")
      end
    end

    context "when units is passed as string" do
      let(:fees) do
        [
          {
            add_on_code: add_on_first.code,
            unit_amount_cents: 1200,
            units: 2,
            description: "desc-123",
            tax_codes: [tax2.code]
          }
        ]
      end

      it "creates fees" do
        result = one_off_service.call

        expect(result).to be_success

        first_fee = result.fees[0]

        expect(first_fee).to have_attributes(
          id: String,
          invoice_id: invoice.id,
          add_on_id: add_on_first.id,
          description: "desc-123",
          unit_amount_cents: 1200,
          precise_unit_amount: 12,
          units: 2,
          amount_cents: 2400,
          precise_amount_cents: 2400.0,
          amount_currency: "EUR",
          fee_type: "add_on",
          payment_status: "pending"
        )
        expect(first_fee.taxes.map(&:code)).to contain_exactly(tax2.code)
      end
    end

    context "when there is tax provider integration" do
      let(:integration) { create(:anrok_integration, organization:) }
      let(:integration_customer) { create(:anrok_customer, integration:, customer:) }
      let(:response) { instance_double(Net::HTTPOK) }
      let(:lago_client) { instance_double(LagoHttpClient::Client) }
      let(:endpoint) { "https://api.nango.dev/v1/anrok/finalized_invoices" }
      let(:body) do
        p = Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/success_response_multiple_fees.json")
        json = File.read(p)

        # setting item_id based on the test example
        response = JSON.parse(json)
        response["succeededInvoices"].first["fees"].first["item_id"] = "fee_id_1"
        response["succeededInvoices"].first["fees"].first["tax_breakdown"].first["tax_amount"] = 240
        response["succeededInvoices"].first["fees"].last["item_id"] = "fee_id_2"
        response["succeededInvoices"].first["fees"].last["tax_breakdown"].first["tax_amount"] = 60

        response.to_json
      end
      let(:integration_collection_mapping) do
        create(
          :netsuite_collection_mapping,
          integration:,
          mapping_type: :fallback_item,
          settings: {external_id: "1", external_account_code: "11", external_name: ""}
        )
      end

      before do
        integration_collection_mapping
        integration_customer

        allow(LagoHttpClient::Client).to receive(:new)
          .with(endpoint, retries_on: [OpenSSL::SSL::SSLError])
          .and_return(lago_client)
        allow(lago_client).to receive(:post_with_response).and_return(response)
        allow(response).to receive(:body).and_return(body)
        allow_any_instance_of(Fee).to receive(:id).and_wrap_original do |m, *args| # rubocop:disable RSpec/AnyInstance
          fee = m.receiver
          if fee.add_on_id == add_on_first.id
            "fee_id_1"
          elsif fee.add_on_id == add_on_second.id
            "fee_id_2"
          else
            m.call(*args)
          end
        end
      end

      it "creates fees" do
        result = one_off_service.call
        first_fee = result.fees[0]
        second_fee = result.fees[1]

        expect(result).to be_success

        expect(first_fee).to have_attributes(
          id: String,
          invoice_id: invoice.id,
          add_on_id: add_on_first.id,
          description: "desc-123",
          unit_amount_cents: 1200,
          precise_unit_amount: 12,
          units: 2,
          amount_cents: 2400,
          amount_currency: "EUR",
          fee_type: "add_on",
          payment_status: "pending",
          taxes_rate: 10,
          taxes_base_rate: 1.0
        )
        expect(first_fee.applied_taxes.first.amount_cents).to eq(240)
        expect(first_fee.applied_taxes.first.precise_amount_cents).to eq(240.0)

        expect(second_fee).to have_attributes(
          id: String,
          invoice_id: invoice.id,
          add_on_id: add_on_second.id,
          description: add_on_second.description,
          unit_amount_cents: 400,
          precise_unit_amount: 4,
          units: 1,
          amount_cents: 400,
          precise_amount_cents: 400.0,
          amount_currency: "EUR",
          fee_type: "add_on",
          payment_status: "pending",
          taxes_rate: 15,
          taxes_base_rate: 1.0
        )
        expect(second_fee.applied_taxes.first.amount_cents).to eq(60)
        expect(second_fee.applied_taxes.first.precise_amount_cents).to eq(60.0)

        expect(invoice.reload.error_details.count).to eq(0)
      end

      context "when there is tax deduction" do
        let(:body) do
          p = Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/success_response_multiple_fees.json")
          json = File.read(p)

          # setting item_id based on the test example
          response = JSON.parse(json)
          response["succeededInvoices"].first["fees"].first["item_id"] = "fee_id_1"
          response["succeededInvoices"].first["fees"].first["tax_breakdown"].first["tax_amount"] = 192
          response["succeededInvoices"].first["fees"].last["item_id"] = "fee_id_2"
          response["succeededInvoices"].first["fees"].last["tax_breakdown"].first["tax_amount"] = 48

          response.to_json
        end

        it "creates fees" do
          result = one_off_service.call
          first_fee = result.fees[0]
          second_fee = result.fees[1]

          expect(result).to be_success

          expect(first_fee).to have_attributes(
            id: String,
            invoice_id: invoice.id,
            add_on_id: add_on_first.id,
            description: "desc-123",
            unit_amount_cents: 1200,
            precise_unit_amount: 12,
            units: 2,
            amount_cents: 2400,
            amount_currency: "EUR",
            fee_type: "add_on",
            payment_status: "pending",
            taxes_rate: 10,
            taxes_base_rate: 0.8
          )
          expect(first_fee.applied_taxes.first.amount_cents).to eq(192)
          expect(first_fee.applied_taxes.first.precise_amount_cents).to eq(192.0)

          expect(second_fee).to have_attributes(
            id: String,
            invoice_id: invoice.id,
            add_on_id: add_on_second.id,
            description: add_on_second.description,
            unit_amount_cents: 400,
            precise_unit_amount: 4,
            units: 1,
            amount_cents: 400,
            precise_amount_cents: 400.0,
            amount_currency: "EUR",
            fee_type: "add_on",
            payment_status: "pending",
            taxes_rate: 15,
            taxes_base_rate: 0.8
          )
          expect(second_fee.applied_taxes.first.amount_cents).to eq(48)
          expect(second_fee.applied_taxes.first.precise_amount_cents).to eq(48.0)

          expect(invoice.reload.error_details.count).to eq(0)
        end
      end

      context "when there is error received from the provider" do
        let(:body) do
          p = Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/failure_response.json")
          File.read(p)
        end

        it "returns tax error" do
          result = one_off_service.call

          expect(result).not_to be_success
          expect(result.error.code).to eq("tax_error")
          expect(result.error.error_message).to eq("taxDateTooFarInFuture")

          expect(invoice.reload.error_details.count).to eq(1)
          expect(invoice.reload.error_details.first.details["tax_error"]).to eq("taxDateTooFarInFuture")
        end

        context "with api limit error" do
          let(:body) do
            p = Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/api_limit_response.json")
            File.read(p)
          end

          it "returns and store proper error details" do
            result = one_off_service.call

            expect(result).not_to be_success
            expect(result.error.code).to eq("tax_error")
            expect(result.error.error_message).to eq("validationError")

            expect(invoice.reload.error_details.count).to eq(1)
            expect(invoice.reload.error_details.first.details["tax_error"]).to eq("validationError")
            expect(invoice.reload.error_details.first.details["tax_error_message"])
              .to eq("You've exceeded your API limit of 10 per second")
          end
        end
      end
    end
  end
end
