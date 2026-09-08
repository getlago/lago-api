# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::Taxes::Invoices::CreateDraftService do
  subject(:service_call) { described_class.call(invoice:) }

  let(:integration) { create(:anrok_integration, organization:) }
  let(:integration_customer) { create(:anrok_customer, integration:, customer:) }
  let(:customer) { create(:customer, :with_shipping_address, organization:) }
  let(:organization) { create(:organization) }
  let(:endpoint) { "https://api.nango.dev/v1/anrok/draft_invoices" }
  let(:add_on) { create(:add_on, organization:) }
  let(:add_on_two) { create(:add_on, organization:) }
  let(:current_time) { Time.current }

  let(:integration_collection_mapping1) do
    create(
      :netsuite_collection_mapping,
      integration:,
      mapping_type: :fallback_item,
      settings: {external_id: "1", external_account_code: "11", external_name: ""}
    )
  end
  let(:integration_mapping_add_on) do
    create(
      :netsuite_mapping,
      integration:,
      mappable_type: "AddOn",
      mappable_id: add_on.id,
      settings: {external_id: "m1", external_account_code: "m11", external_name: ""}
    )
  end

  let(:invoice) do
    create(
      :invoice,
      customer:,
      organization:
    )
  end
  let(:fee_add_on) do
    create(
      :fee,
      invoice:,
      add_on:,
      created_at: current_time - 3.seconds
    )
  end
  let(:fee_add_on_two) do
    create(
      :fee,
      invoice:,
      add_on: add_on_two,
      created_at: current_time - 2.seconds
    )
  end

  let(:headers) do
    {
      "Connection-Id" => integration.connection_id,
      "Authorization" => "Bearer #{ENV["NANGO_SECRET_KEY"]}",
      "Provider-Config-Key" => "anrok"
    }
  end
  let(:response_status) { 200 }

  let(:params) do
    [
      {
        "issuing_date" => invoice.issuing_date,
        "currency" => invoice.currency,
        "contact" => {
          "external_id" => integration_customer.external_customer_id,
          "name" => customer.name,
          "address_line_1" => customer.shipping_address_line1,
          "city" => customer.shipping_city,
          "zip" => customer.shipping_zipcode,
          "country" => customer.shipping_country,
          "taxable" => false,
          "tax_number" => nil
        },
        "fees" => [
          {
            "item_key" => fee_add_on.item_key,
            "item_id" => fee_add_on.id,
            "item_code" => "m1",
            "amount_cents" => 200
          },
          {
            "item_key" => fee_add_on_two.item_key,
            "item_id" => fee_add_on_two.id,
            "item_code" => "1",
            "amount_cents" => 200
          }
        ],
        "tax_date" => invoice.issuing_date
      }
    ]
  end

  before do
    integration_customer
    integration_collection_mapping1
    integration_mapping_add_on
    fee_add_on
    fee_add_on_two

    stub_request(:post, endpoint).with(body: params.to_json, headers:)
      .and_return(status: response_status, body:)
  end

  describe "#call" do
    context "when service call is successful" do
      context "when taxes are successfully fetched" do
        let(:base_body) do
          path = Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/success_response.json")
          File.read(path)
        end
        let(:body) { base_body }

        it "returns fees" do
          result = service_call

          expect(result).to be_success
          expect(result.fees.first.tax_breakdown.first.rate).to eq("0.10")
          expect(result.fees.first.tax_breakdown.first.name).to eq("GST/HST")
          expect(result.fees.first.tax_breakdown.last.name).to eq("Reverse charge")
          expect(result.fees.first.tax_breakdown.last.type).to eq("exempt")
          expect(result.fees.first.tax_breakdown.last.rate).to eq("0.00")
        end

        context "when a fee has no amount" do
          let(:fee_add_on_two) do
            create(
              :fee,
              invoice:,
              add_on: add_on_two,
              amount_cents: 0,
              created_at: current_time - 2.seconds
            )
          end
          let(:params) { super().tap { |request_body| request_body.first["fees"] = [request_body.first["fees"].first] } }

          it "excludes it from the request" do
            service_call

            expect(WebMock).to have_requested(:post, endpoint).with(body: params.to_json)
          end
        end

        context "when the fees were not inserted in creation order" do
          let(:earlier_fee) { create(:fee, invoice:, add_on:, created_at: current_time - 4.seconds) }
          let(:requested_line_items) { [] }

          before do
            earlier_fee

            stub_request(:post, endpoint).with(headers:).to_return do |request|
              requested_line_items.concat(JSON.parse(request.body).first["fees"])

              {status: response_status, body:}
            end
          end

          it "orders the line items by fee creation" do
            service_call

            expect(requested_line_items.map { |item| item["item_id"] })
              .to eq([earlier_fee.id, fee_add_on.id, fee_add_on_two.id])
          end
        end

        context "when a charge is split over several fees" do
          let(:billable_metric) { create(:billable_metric, organization:) }
          let(:plan) { create(:plan, organization:) }
          let(:charge) { create(:standard_charge, organization:, plan:, billable_metric:) }
          let(:group_key) { "charge_#{charge.id}" }
          let(:charge_fee) do
            create(
              :charge_fee,
              invoice:,
              charge:,
              amount_cents: 300,
              precise_amount_cents: 300,
              created_at: current_time - 1.second
            )
          end
          let(:charge_fee_two) do
            create(
              :charge_fee,
              invoice:,
              charge:,
              amount_cents: 700,
              precise_amount_cents: 700,
              created_at: current_time
            )
          end
          let(:requested_line_items) { [] }
          let(:body) do
            {
              succeededInvoices: [{
                id: "inv_123",
                fees: [
                  {item_key: group_key, item_id: group_key, item_code: "1", amount_cents: 1000,
                   tax_amount_cents: 100, tax_breakdown: [{name: "VAT", rate: "0.10", tax_amount: 100, type: "tax"}]}
                ]
              }],
              failedInvoices: []
            }.to_json
          end

          before do
            charge_fee
            charge_fee_two

            stub_request(:post, endpoint).with(headers:).to_return do |request|
              requested_line_items.concat(JSON.parse(request.body).first["fees"])

              {status: response_status, body:}
            end
          end

          it "sends the charge as a single line item" do
            service_call

            expect(requested_line_items.size).to eq(3)
            expect(requested_line_items).to include(
              "item_key" => group_key, "item_id" => group_key, "item_code" => "1", "amount_cents" => 1000
            )
          end

          it "spreads the charge taxes back over its fees" do
            result = service_call

            expect(result).to be_success

            fee_taxes = result.fees.index_by(&:item_id)

            expect(fee_taxes[charge_fee.id])
              .to have_attributes(tax_amount_cents: 30, group_key:, group_tax_amount_cents: 100)
            expect(fee_taxes[charge_fee_two.id])
              .to have_attributes(tax_amount_cents: 70, group_key:, group_tax_amount_cents: 100)
          end
        end

        context "when a charge has a single fee" do
          let(:billable_metric) { create(:billable_metric, organization:) }
          let(:plan) { create(:plan, organization:) }
          let(:charge) { create(:standard_charge, organization:, plan:, billable_metric:) }
          let(:charge_fee) do
            create(
              :charge_fee,
              invoice:,
              charge:,
              amount_cents: 300,
              precise_amount_cents: 300,
              created_at: current_time - 1.second
            )
          end
          let(:requested_line_items) { [] }

          before do
            charge_fee

            stub_request(:post, endpoint).with(headers:).to_return do |request|
              requested_line_items.concat(JSON.parse(request.body).first["fees"])

              {status: response_status, body:}
            end
          end

          it "sends it under its own identity" do
            service_call

            expect(requested_line_items).to include(
              "item_key" => charge_fee.item_key, "item_id" => charge_fee.id, "item_code" => "1", "amount_cents" => 300
            )
          end
        end

        context "when no fee has an amount" do
          let(:fee_add_on) do
            create(
              :fee,
              invoice:,
              add_on:,
              amount_cents: 0,
              created_at: current_time - 3.seconds
            )
          end
          let(:fee_add_on_two) do
            create(
              :fee,
              invoice:,
              add_on: add_on_two,
              amount_cents: 0,
              created_at: current_time - 2.seconds
            )
          end

          let(:params) { super().tap { |body| body.first["fees"] = [body.first["fees"].first.merge("amount_cents" => 0)] } }

          it "still reports the invoice, standing it on a single fee" do
            service_call

            expect(WebMock).to have_requested(:post, endpoint).with(body: params.to_json)
          end
        end

        context "when special rules applied" do
          let(:body) do
            parsed_body = JSON.parse(base_body)
            parsed_body["succeededInvoices"].first["fees"].first["tax_amount_cents"] = 0
            parsed_body["succeededInvoices"].first["fees"].first["tax_breakdown"] = [
              {
                reason: "",
                type: rule
              }
            ]
            parsed_body.to_json
          end

          special_rules =
            [
              {received_type: "notCollecting", expected_name: "Not collecting"},
              {received_type: "productNotTaxed", expected_name: "Product not taxed"},
              {received_type: "jurisNotTaxed", expected_name: "Juris not taxed"},
              {received_type: "jurisHasNoTax", expected_name: "Juris has no tax"},
              {received_type: "specialUnknownRule", expected_name: "Special unknown rule"}
            ]

          special_rules.each do |specific_rule|
            context "when applied rule is #{specific_rule}" do
              let(:rule) { specific_rule[:received_type] }

              it "returns fee object with populated for the specific rule fields" do
                result = service_call

                expect(result).to be_success
                expect(result.fees.first.tax_breakdown.last.name).to eq(specific_rule[:expected_name])
                expect(result.fees.first.tax_breakdown.last.type).to eq(specific_rule[:received_type])
                expect(result.fees.first.tax_breakdown.last.rate).to eq("0.00")
                expect(result.fees.first.tax_breakdown.last.tax_amount).to eq(0)
              end
            end
          end
        end

        context "when taxes are paid by seller" do
          let(:body) do
            path = Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/success_response_seller_pays_taxes.json")
            File.read(path)
          end

          it "returns fee object with empty tax breakdown" do
            result = service_call

            expect(result).to be_success
            expect(result.fees.first.tax_breakdown.last.name).to eq("Tax")
            expect(result.fees.first.tax_breakdown.last.type).to eq("tax")
            expect(result.fees.first.tax_breakdown.last.rate).to eq("0.00")
            expect(result.fees.first.tax_breakdown.last.tax_amount).to eq(0)
          end
        end
      end

      context "when taxes are not successfully fetched" do
        let(:body) do
          path = Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/failure_response.json")
          File.read(path)
        end

        it "does not return fees" do
          result = service_call

          expect(result).not_to be_success
          expect(result.fees).to be(nil)
          expect(result.error).to be_a(BaseService::ServiceFailure)
          expect(result.error.code).to eq("taxDateTooFarInFuture")
        end

        it "delivers an error webhook" do
          expect { service_call }.to enqueue_job(SendWebhookJob)
            .with(
              "customer.tax_provider_error",
              customer,
              provider: "anrok",
              provider_code: integration.code,
              provider_error: {
                message: "Service failure",
                error_code: "taxDateTooFarInFuture"
              }
            )
        end

        context "when no integration mapping is defined" do
          let(:integration_collection_mapping1) { nil }
          let(:integration_mapping_add_on) { nil }
          let(:body) do
            path = Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/failure_response.json")
            body_string = File.read(path)
            body = JSON.parse(body_string)
            body["failedInvoices"].first["validation_errors"] = "Request body: \"lineItems\": 0: \"productExternalId\": String must contain at least 1 character(s)."
            body.to_json
          end

          before do
            params.first["fees"].each { |fee| fee["item_code"] = nil }
            stub_request(:post, endpoint).with(body: params.to_json, headers:)
              .and_return(status: response_status, body:)
          end

          it "sends request to anrok with empty link to fallback item" do
            result = service_call

            expect(result).not_to be_success
            expect(result.fees).to be(nil)
            expect(result.error).to be_a(BaseService::ServiceFailure)
            expect(result.error.code).to eq("validationError")
          end
        end

        context "when the body contains a bad gateway error" do
          let(:body) do
            path = Rails.root.join("spec/fixtures/integration_aggregator/bad_gateway_error.html")
            File.read(path)
          end

          it "raises an HTTP error" do
            expect { service_call }.to raise_error(Integrations::Aggregator::BadGatewayError)
          end
        end

        context "when it is an out of memory error" do
          let(:body) do
            {"succeededInvoices" => [], "failedInvoices" => [{"validation_errors" => "function_runtime_out_of_memory"}]}.to_json
          end

          it "raises OutOfMemoryError" do
            expect { service_call }.to raise_error(Integrations::Aggregator::OutOfMemoryError)
          end
        end

        context "when it is a server contention error" do
          let(:body) do
            {"succeededInvoices" => [], "failedInvoices" => [{"validation_errors" => "API limit exceeded"}]}.to_json
          end

          it "raises ServerContentionError" do
            expect { service_call }.to raise_error(Integrations::Aggregator::ServerContentionError)
          end
        end
      end
    end

    context "when service call is not successful" do
      let(:body) do
        path = Rails.root.join("spec/fixtures/integration_aggregator/error_response.json")
        File.read(path)
      end

      context "when the body contains a bad gateway error" do
        let(:response_status) { 200 }
        let(:body) do
          path = Rails.root.join("spec/fixtures/integration_aggregator/bad_gateway_error.html")
          File.read(path)
        end

        it "raises an HTTP error" do
          expect { service_call }.to raise_error(Integrations::Aggregator::BadGatewayError)
        end
      end

      context "when the error code is 502" do
        let(:response_status) { 502 }
        let(:body) { "" }

        it "raises an HTTP error" do
          expect { service_call }.to raise_error(Integrations::Aggregator::BadGatewayError)
        end
      end

      context "when it is a script error" do
        let(:response_status) { Faker::Number.between(from: 500, to: 599) }
        let(:body) do
          path = Rails.root.join("spec/fixtures/integration_aggregator/error_script_response.json")
          File.read(path)
        end

        it "returns an error" do
          result = service_call

          expect(result).not_to be_success
          expect(result.fees).to be(nil)
          expect(result.error).to be_a(BaseService::ServiceFailure)
          expect(result.error.code).to eq("action_script_failure")
        end
      end

      context "when it is another server error" do
        let(:response_status) { Faker::Number.between(from: 500, to: 599) }

        it "returns an error" do
          result = service_call

          expect(result).not_to be_success
          expect(result.fees).to be(nil)
          expect(result.error).to be_a(BaseService::ServiceFailure)
          expect(result.error.code).to eq("action_script_runtime_error")
        end
      end

      context "when it is a task in progress error" do
        let(:response_status) { 500 }
        let(:body) { {error: {code: "action_script_failure", message: "Task abc12345-1234-1234-1234-abc123456789 is in progress"}}.to_json }

        it "raises TaskInProgressError" do
          expect { service_call }.to raise_error(Integrations::Aggregator::TaskInProgressError)
        end
      end

      context "when it is a task expired error" do
        let(:response_status) { 500 }
        let(:body) { {error: {code: "action_script_failure", message: "Task abc12345-1234-1234-1234-abc123456789 expired"}}.to_json }

        it "raises TaskExpiredError" do
          expect { service_call }.to raise_error(Integrations::Aggregator::TaskExpiredError)
        end
      end

      context "when it is an orchestrator failure error" do
        let(:response_status) { 500 }
        let(:body) { {error: {code: "action_script_failure", message: "POST http://nango-orchestrator-svc.nango/v1/immediate failed"}}.to_json }

        it "raises OrchestratorFailureError" do
          expect { service_call }.to raise_error(Integrations::Aggregator::OrchestratorFailureError)
        end
      end

      context "when a network timeout occurs" do
        before { stub_request(:post, endpoint).to_raise(Net::ReadTimeout) }

        it "raises TimeoutError" do
          expect { service_call }.to raise_error(Integrations::Aggregator::TimeoutError)
        end
      end
    end
  end
end
