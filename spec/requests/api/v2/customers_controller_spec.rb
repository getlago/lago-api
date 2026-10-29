# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::CustomersController do
  let_it_be(:organization, refind: true) { create_default(:organization) }

  shared_examples "payment provider synchronization" do
    let(:provider) { create(:stripe_provider, organization:) }
    let(:sync) { true }
    let(:attributes) do
      super().merge(payment_provider: "stripe", payment_provider_code: provider.code, sync_with_provider: true, sync:)
    end
    let(:provider_request) do
      stub_request(:post, "https://api.stripe.com/v1/customers")
        .to_return(status: 200, body: {id: "cus_sync"}.to_json, headers: {"Content-Type" => "application/json"})
    end

    before { provider_request }

    it "waits for the provider and returns its customer id" do
      request

      expect(response).to have_http_status(:ok)
      expect(provider_request).to have_been_requested.once
      expect(json[:customer][:provider_customer_id]).to eq("cus_sync")
      expect(SendWebhookJob).to have_been_enqueued.with("customer.payment_provider_created", an_instance_of(Customer))
      expect(PaymentProviderCustomers::StripeCreateJob).not_to have_been_enqueued
    end

    [false, "false"].each do |value|
      context "with sync set to #{value.inspect}" do
        let(:sync) { value }

        it "queues provider creation without calling the provider" do
          request

          expect(response).to have_http_status(:ok)
          expect(provider_request).not_to have_been_requested
          expect(json[:customer][:provider_customer_id]).to be_nil
          expect(PaymentProviderCustomers::StripeCreateJob).to have_been_enqueued.with(an_instance_of(PaymentProviderCustomers::StripeCustomer))
        end
      end
    end

    context "without sync" do
      let(:attributes) { super().except(:sync) }

      it "keeps background creation as the default" do
        request

        expect(response).to have_http_status(:ok)
        expect(provider_request).not_to have_been_requested
        expect(PaymentProviderCustomers::StripeCreateJob).to have_been_enqueued
      end
    end
  end

  describe "POST /api/v2/customers" do
    subject(:request) { post_with_token(organization, "/api/v2/customers", {customer: attributes}) }

    let(:attributes) do
      {
        external_id: "customer.eu",
        name: "Example customer",
        currency: "EUR",
        document_locale: "fr",
        shipping_address: {city: "Paris", country: "fr"},
        metadata: [{key: "reference", value: "123", display_on_invoice: true}]
      }
    end

    include_examples "requires API permission", "customer", "write"

    it_behaves_like "payment provider synchronization"

    it "accepts flat billing fields and returns them without expanded relationships" do
      expect { request }.to change(organization.customers, :count).by(1)

      expect(response).to have_http_status(:ok)
      customer = organization.customers.find_by!(external_id: "customer.eu")
      expect(customer).to have_attributes(name: "Example customer", document_locale: "fr", shipping_city: "Paris", shipping_country: "FR")
      expect(customer.metadata.sole).to have_attributes(key: "reference", value: "123", display_in_invoice: true)
      expect(json[:customer][:document_locale]).to eq("fr")
      expect(json[:customer][:shipping_address][:city]).to eq("Paris")
      expect(json[:customer]).not_to have_key(:billing_configuration)
      expect(json[:customer].keys & %i[metadata taxes integration_customers net_payment_term]).to eq([])
      expect(response.headers["X-Lago-Endpoint-Status"]).to eq("beta")
      expect(SendWebhookJob).to have_been_enqueued.with("customer.created", customer)
    end

    context "when the external id already exists" do
      let!(:existing_customer) { create(:customer, organization:, external_id: attributes[:external_id], name: "Existing") }

      it "rejects the duplicate without updating the existing customer" do
        expect { request }.not_to change(organization.customers, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_already_exist", field: "external_id", meta: {}}])
        expect(existing_customer.reload.name).to eq("Existing")
        expect(existing_customer.metadata).to be_empty
        expect(SendWebhookJob).not_to have_been_enqueued.with("customer.updated", existing_customer)
      end
    end

    context "when the id belongs to another organization" do
      before { create(:customer, organization: create(:organization), external_id: attributes[:external_id]) }

      it "allows the same external id in the current organization" do
        expect { request }.to change(organization.customers, :count).by(1)

        expect(response).to have_http_status(:ok)
      end
    end

    context "with removed parameters" do
      let(:attributes) do
        super().merge(
          net_payment_term: 60,
          metadata: [{key: "reference", value: "123", display_in_invoice: true}],
          subscription_invoice_issuing_date_anchor: "current_period_end",
          subscription_invoice_issuing_date_adjustment: "keep_anchor"
        )
      end

      it "ignores removed fields" do
        request

        expect(response).to have_http_status(:ok)
        customer = organization.customers.find_by!(external_id: attributes[:external_id])
        expect(customer).to have_attributes(
          net_payment_term: nil,
          subscription_invoice_issuing_date_anchor: nil,
          subscription_invoice_issuing_date_adjustment: nil
        )
        expect(customer.metadata.sole.display_in_invoice).to be(false)
        expect(json[:customer].keys).not_to include(:subscription_invoice_issuing_date_anchor, :subscription_invoice_issuing_date_adjustment)
      end
    end

    context "without an external id" do
      let(:attributes) { super().except(:external_id) }

      it "returns a validation error without creating a customer" do
        expect { request }.not_to change(organization.customers, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_mandatory", field: "external_id", meta: {}}])
      end
    end

    context "with a non-string enum value" do
      let(:attributes) { super().merge(finalize_zero_amount_invoice: false) }

      it "returns a validation error rather than an exception" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "invalid_value", field: "finalize_zero_amount_invoice", meta: {}}])
      end
    end

    context "with repeated integration types" do
      let(:attributes) { super().merge(integration_customers: [{integration_type: "anrok"}, {integration_type: "anrok"}]) }

      it "rejects the request without creating a customer" do
        expect { request }.not_to change(organization.customers, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(
          code: "validation_errors",
          details: [{code: "invalid_count_per_integration_type", field: "integration_customers", meta: {}}]
        )
      end
    end

    [nil, "bogus"].each do |integration_type|
      context "with #{integration_type.inspect} as integration type" do
        let(:attributes) { super().merge(integration_customers: [{integration_type:, integration_code: "netsuite"}.compact]) }

        it "rejects the request without creating a customer" do
          expect { request }.not_to change(organization.customers, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "integration_type", meta: {}}])
        end
      end
    end

    context "without the customer wrapper" do
      subject(:request) { post_with_token(organization, "/api/v2/customers", attributes) }

      it "returns a missing parameter error" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("missing_parameter")
      end
    end

    context "with an array instead of a shipping address object" do
      let(:attributes) { super().merge(shipping_address: [{city: "Paris"}]) }

      it "returns a parameter error without creating a customer" do
        expect { request }.not_to change(organization.customers, :count)

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("missing_parameter")
      end
    end

    context "with the old billing configuration wrapper" do
      let(:attributes) { super().merge(billing_configuration: {document_locale: "de", payment_provider: "stripe"}) }

      it "ignores the wrapper and uses the flat fields" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:customer]).to include(document_locale: "fr", payment_provider: nil)
      end
    end

    context "with an object instead of a metadata array" do
      let(:attributes) { super().merge(metadata: {key: "reference", value: "123"}) }

      it "filters out the malformed metadata" do
        request

        expect(response).to have_http_status(:ok)
        expect(Metadata::CustomerMetadata.where(organization:)).to be_empty
      end
    end

    context "with payment provider settings" do
      let(:provider) { create(:stripe_provider, organization:) }
      let(:attributes) do
        super().merge(
          payment_provider: "stripe",
          payment_provider_code: provider.code,
          sync_with_provider: true
        )
      end

      it "accepts flat provider settings and returns flat fields" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:customer]).to include(payment_provider: "stripe", payment_provider_code: provider.code)
        customer = organization.customers.find_by!(external_id: attributes[:external_id])
        expect(customer.stripe_customer).to have_attributes(payment_provider_id: provider.id, sync_with_provider: true)
      end
    end

    context "with a provider customer id" do
      let(:provider) { create(:stripe_provider, organization:) }
      let(:attributes) do
        super().merge(
          payment_provider: "stripe",
          payment_provider_code: provider.code,
          provider_customer_id: "cus_example",
          provider_payment_methods: %w[card]
        )
      end

      it "returns the provider customer id at the top level" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:customer][:provider_customer_id]).to eq("cus_example")
        expect(json[:customer][:provider_payment_methods]).to eq(%w[card])
      end
    end

    context "with an invalid provider configuration" do
      let(:attributes) { super().merge(payment_provider: "stripe", payment_provider_code: "unknown-provider", sync_with_provider: true) }
      let(:error_code) { "payment_provider_not_found" }

      it "returns 422 without creating a customer" do
        expect { request }.not_to change(organization.customers, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: error_code, field: "base", meta: {}}])
        expect(PaymentProviderCustomers::StripeCreateJob).not_to have_been_enqueued
      end

      context "when the code belongs to another organization" do
        let(:foreign_provider) { create(:stripe_provider, organization: create(:organization)) }
        let(:attributes) { super().merge(payment_provider_code: foreign_provider.code) }

        it "does not use the foreign provider" do
          expect { request }.not_to change(organization.customers, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json).to eq(code: "validation_errors", details: [{code: "payment_provider_not_found", field: "base", meta: {}}])
        end
      end

      context "when the provider code is required but omitted" do
        let(:attributes) { super().except(:payment_provider_code) }
        let(:error_code) { "payment_provider_code_missing" }

        before { create_list(:stripe_provider, 2, organization:) }

        it "returns a validation error before creating a customer" do
          expect { request }.not_to change(organization.customers, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json).to eq(code: "validation_errors", details: [{code: error_code, field: "base", meta: {}}])
        end
      end
    end

    context "with local taxes and invoice custom sections" do
      let(:tax) { create(:tax, organization:) }
      let(:section) { create(:invoice_custom_section, organization:) }
      let(:attributes) { super().merge(tax_codes: [tax.code], invoice_custom_section_codes: [section.code]) }

      it "assigns the requested objects" do
        request

        expect(response).to have_http_status(:ok)
        customer = organization.customers.find_by!(external_id: attributes[:external_id])
        expect(customer.taxes).to eq([tax])
        expect(customer.manual_selected_invoice_custom_sections).to eq([section])
      end

      context "with a foreign tax" do
        let(:tax) { create(:tax, organization: create(:organization)) }

        it "does not create the customer or attach the foreign tax" do
          expect { request }.not_to change(organization.customers, :count)

          expect(response).to be_v2_not_found_error("tax")
        end
      end
    end

    context "with flat invoice issuing settings", :premium do
      let(:attributes) do
        super().merge(
          invoice_grace_period: 3,
          document_locale: "fr",
          periodic_invoice_issuing_date_anchor: "current_period_end",
          periodic_invoice_issuing_date_adjustment: "keep_anchor"
        )
      end

      it "persists the flat settings and returns them at the top level" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:customer]).to include(
          attributes.slice(:invoice_grace_period, :document_locale, :periodic_invoice_issuing_date_anchor, :periodic_invoice_issuing_date_adjustment)
        )
        expect(json[:customer]).not_to have_key(:billing_configuration)
        customer = organization.customers.find_by!(external_id: attributes[:external_id])
        expect(customer).to have_attributes(
          subscription_invoice_issuing_date_anchor: "current_period_end",
          subscription_invoice_issuing_date_adjustment: "keep_anchor"
        )
      end
    end

    %i[periodic_invoice_issuing_date_anchor periodic_invoice_issuing_date_adjustment].each do |field|
      ["unknown", false].each do |value|
        context "with #{field} set to #{value.inspect}" do
          let(:attributes) { super().merge(field => value) }

          it "returns a validation error under the REST field name" do
            expect { request }.not_to change(organization.customers, :count)

            expect(response).to have_http_status(:unprocessable_content)
            expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: field.to_s, meta: {}}])
          end
        end
      end
    end

    context "without the product catalog feature", product_catalog: false do
      it "returns forbidden without creating a customer" do
        expect { request }.not_to change(organization.customers, :count)

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "with expansions on create" do
      subject(:request) do
        post_with_token(organization, "/api/v2/customers?expands[]=metadata", {customer: attributes})
      end

      it "rejects the request before creating a customer" do
        expect { request }.not_to change(organization.customers, :count)

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(
          code: "expand_not_supported",
          details: [{code: "action_not_expandable", field: "expands", meta: {invalid_values: ["metadata"]}}]
        )
      end
    end

    context "without authentication" do
      subject(:request) { post "/api/v2/customers", params: {customer: attributes}, as: :json }

      it "rejects the request without creating a customer" do
        expect { request }.not_to change(Customer, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  %i[put patch].each do |method|
    describe "#{method.upcase} /api/v2/customers/:external_id" do
      subject(:request) do
        public_send(:"#{method}_with_token", organization, "/api/v2/customers/#{customer.external_id}", {customer: attributes})
      end

      let(:customer) { create(:customer, organization:, external_id: "existing.eu", document_locale: "fr", net_payment_term: 30) }
      let(:attributes) { {name: "Updated", net_payment_term: 60} }

      include_examples "requires API permission", "customer", "write"

      it_behaves_like "payment provider synchronization"

      it "updates without requiring external_id in the body or changing omitted settings" do
        request

        expect(response).to have_http_status(:ok)
        expect(customer.reload).to have_attributes(name: "Updated", external_id: "existing.eu", document_locale: "fr", net_payment_term: 30)
        expect(json[:customer][:document_locale]).to eq("fr")
        expect(json[:customer]).not_to have_key(:billing_configuration)
        expect(json[:customer]).not_to have_key(:net_payment_term)
        expect(SendWebhookJob).to have_been_enqueued.with("customer.updated", customer)
      end

      context "with a foreign tax and other changes", :premium do
        let(:tax) { create(:tax, organization: create(:organization)) }
        let(:invoice) { create(:invoice, :draft, customer:, expected_finalization_date: 1.week.from_now) }
        let(:attributes) { {name: "Must not change", invoice_grace_period: 3, document_locale: "de", tax_codes: [tax.code]} }

        before { invoice }

        it "rolls back the whole update" do
          original_invoice_attributes = invoice.attributes

          expect { request }.not_to change { customer.reload.attributes }

          expect(response).to be_v2_not_found_error("tax")
          expect(invoice.reload.attributes).to eq(original_invoice_attributes)
          expect(Invoices::FinalizeJob).not_to have_been_enqueued.with(invoice)
          expect(SendWebhookJob).not_to have_been_enqueued.with("customer.updated", customer)
        end
      end

      context "when replacing the payment provider" do
        let(:customer) { create(:customer, :with_stripe_payment_provider, organization:) }
        let(:old_provider_customer) { customer.stripe_customer }
        let(:payment_method) { create(:payment_method, payment_provider_customer: old_provider_customer) }
        let(:provider) { create(:gocardless_provider, organization:) }
        let(:attributes) { {payment_provider: "gocardless", payment_provider_code: provider.code, sync_with_provider: true} }

        before { payment_method }

        it "uses the new provider and discards the old payment methods" do
          request

          expect(response).to have_http_status(:ok)
          expect(customer.reload).to have_attributes(payment_provider: "gocardless", payment_provider_code: provider.code)
          expect(customer.gocardless_customer.payment_provider_id).to eq(provider.id)
          expect(PaymentProviderCustomers::GocardlessCreateJob).to have_been_enqueued.with(customer.gocardless_customer)
          expect(payment_method.reload).to be_discarded
          expect(payment_method).not_to be_is_default
          expect(old_provider_customer.reload).not_to be_discarded
        end

        context "when keeping the same provider" do
          let(:attributes) { {payment_provider: "stripe", payment_provider_code: old_provider_customer.payment_provider.code} }

          it "keeps the existing payment methods" do
            request

            expect(response).to have_http_status(:ok)
            expect(payment_method.reload).not_to be_discarded
            expect(payment_method).to be_is_default
          end
        end

        context "when switching to another account of the same provider" do
          let(:provider) { create(:stripe_provider, organization:) }
          let(:attributes) { {payment_provider: "stripe", payment_provider_code: provider.code} }

          it "discards the payment methods of the old account" do
            request

            expect(response).to have_http_status(:ok)
            expect(customer.reload).to have_attributes(payment_provider: "stripe", payment_provider_code: provider.code)
            expect(payment_method.reload).to be_discarded
            expect(old_provider_customer.reload).not_to be_discarded
          end

          context "without the provider type" do
            let(:attributes) { {payment_provider_code: provider.code} }

            it "discards the payment methods of the old account" do
              request

              expect(response).to have_http_status(:ok)
              expect(customer.reload).to have_attributes(payment_provider: "stripe", payment_provider_code: provider.code)
              expect(payment_method.reload).to be_discarded
            end
          end
        end

        context "when only updating the name" do
          let(:attributes) { {name: "Updated"} }

          it "keeps the existing payment methods" do
            request

            expect(response).to have_http_status(:ok)
            expect(payment_method.reload).not_to be_discarded
            expect(payment_method).to be_is_default
          end
        end
      end

      context "when the provider fails on the provider customer id" do
        let(:customer) { create(:customer, :with_stripe_payment_provider, organization:) }
        let(:attributes) do
          {payment_provider: "stripe", payment_provider_code: customer.stripe_customer.payment_provider.code, provider_customer_id: "cus_unknown"}
        end
        let(:provider_response) do
          {status: 404, body: {error: {type: "invalid_request_error", code: "resource_missing", message: "No such customer: 'cus_unknown'"}}}
        end

        before do
          stub_request(:post, "https://api.stripe.com/v1/customers/cus_unknown")
            .to_return(**provider_response, body: provider_response[:body].to_json, headers: {"Content-Type" => "application/json"})
        end

        it "returns a provider error naming the provider, without its message" do
          request

          expect(response).to have_http_status(:unprocessable_content)
          expect(json).to eq(
            code: "provider_error",
            details: [{code: "provider_error", field: "base", meta: {provider_name: "stripe", provider_error_code: "resource_missing"}}]
          )
        end

        context "when the provider refuses the key of the organization" do
          let(:provider_response) { {status: 401, body: {error: {type: "invalid_request_error", message: "Invalid API Key provided"}}} }

          it "returns an unprocessable provider unauthorized error, apart from an invalid API key" do
            request

            expect(response).to have_http_status(:unprocessable_content)
            expect(json).to eq(code: "provider_unauthorized", details: [])
          end
        end
      end

      context "when removing the payment provider" do
        let(:customer) { create(:customer, :with_stripe_payment_provider, organization:) }
        let(:provider_customer) { customer.stripe_customer }
        let(:payment_method) { create(:payment_method, customer:, payment_provider_customer: provider_customer) }
        let(:attributes) { {payment_provider: nil} }

        before { payment_method }

        it "removes the provider and its payment methods" do
          request

          expect(response).to have_http_status(:ok)
          expect(customer.reload).to have_attributes(payment_provider: nil, payment_provider_code: nil)
          expect(provider_customer.reload).to be_discarded
          expect(payment_method.reload).to be_discarded
        end
      end

      context "with an invalid provider configuration" do
        let(:attributes) { {name: "Must not change", payment_provider: "stripe", payment_provider_code: "unknown-provider", sync_with_provider: true} }
        let(:error_code) { "payment_provider_not_found" }

        it "returns 422 without changing the customer" do
          expect { request }.not_to change { customer.reload.attributes }

          expect(response).to have_http_status(:unprocessable_content)
          expect(json).to eq(code: "validation_errors", details: [{code: error_code, field: "base", meta: {}}])
          expect(PaymentProviderCustomers::StripeCreateJob).not_to have_been_enqueued
          expect(SendWebhookJob).not_to have_been_enqueued.with("customer.updated", customer)
        end

        context "when the provider code is required but omitted" do
          let(:attributes) { super().except(:payment_provider_code) }
          let(:error_code) { "payment_provider_code_missing" }

          before { create_list(:stripe_provider, 2, organization:) }

          it "returns a validation error without modifying the customer" do
            expect { request }.not_to change { customer.reload.attributes }

            expect(response).to have_http_status(:unprocessable_content)
            expect(json).to eq(code: "validation_errors", details: [{code: error_code, field: "base", meta: {}}])
          end
        end
      end

      %i[periodic_invoice_issuing_date_anchor periodic_invoice_issuing_date_adjustment].each do |field|
        context "with an invalid #{field}" do
          let(:attributes) { {:name => "Must not change", field => "unknown"} }

          it "returns a validation error under the REST field name without modifying the customer" do
            expect { request }.not_to change { customer.reload.attributes }

            expect(response).to have_http_status(:unprocessable_content)
            expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: field.to_s, meta: {}}])
          end
        end
      end

      context "with an invalid finalize setting" do
        let(:attributes) { {name: "Must not change", finalize_zero_amount_invoice: false} }

        it "returns a validation error without modifying the customer" do
          expect { request }.not_to change { customer.reload.attributes }

          expect(response).to have_http_status(:unprocessable_content)
          expect(json).to eq(code: "validation_errors", details: [{code: "invalid_value", field: "finalize_zero_amount_invoice", meta: {}}])
        end
      end

      context "with repeated integration types" do
        let(:attributes) { {name: "Must not change", integration_customers: [{integration_type: "anrok"}, {integration_type: "anrok"}]} }

        it "rejects the request before modifying the customer" do
          expect { request }.not_to change { customer.reload.attributes }

          expect(response).to have_http_status(:unprocessable_content)
          expect(json).to eq(
            code: "validation_errors",
            details: [{code: "invalid_count_per_integration_type", field: "integration_customers", meta: {}}]
          )
        end
      end

      [nil, "bogus"].each do |integration_type|
        context "with #{integration_type.inspect} as integration type" do
          let(:attributes) { {name: "Must not change", integration_customers: [{integration_type:, integration_code: "netsuite"}.compact]} }
          let(:integration_customer) { create(:netsuite_customer, customer:) }

          before { integration_customer }

          it "rejects the request before modifying the customer or its integrations" do
            expect { request }.not_to change { customer.reload.attributes }

            expect(response).to have_http_status(:unprocessable_content)
            expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "integration_type", meta: {}}])
            expect(customer.integration_customers).to eq([integration_customer])
          end
        end
      end

      context "with invoice custom section codes" do
        let(:section) { create(:invoice_custom_section, organization:) }
        let(:attributes) { {invoice_custom_section_codes: [section.code]} }

        it "assigns the organization's sections by code" do
          request

          expect(response).to have_http_status(:ok)
          expect(customer.reload.manual_selected_invoice_custom_sections).to eq([section])
        end

        context "with an empty array" do
          let(:attributes) { {invoice_custom_section_codes: []} }

          before { create(:customer_applied_invoice_custom_section, organization:, customer:, invoice_custom_section: section) }

          it "removes the manual selections" do
            request

            expect(response).to have_http_status(:ok)
            expect(customer.reload.manual_selected_invoice_custom_sections).to be_empty
          end
        end

        context "with a foreign section" do
          let(:section) { create(:invoice_custom_section, organization: create(:organization)) }

          it "does not assign the foreign section" do
            request

            expect(response).to have_http_status(:ok)
            expect(customer.reload.manual_selected_invoice_custom_sections).to be_empty
          end
        end
      end

      context "when the customer does not exist" do
        let(:customer) { build_stubbed(:customer) }

        it "does not create a customer" do
          expect { request }.not_to change(organization.customers, :count)

          expect(response).to be_v2_not_found_error("customer")
        end
      end

      context "when the customer belongs to another organization" do
        let(:customer) { create(:customer, organization: create(:organization)) }

        it "does not modify the foreign customer" do
          expect { request }.not_to change { customer.reload.attributes }

          expect(response).to be_v2_not_found_error("customer")
        end
      end

      context "with an external id change" do
        let(:attributes) { {external_id: "renamed.eu"} }

        it "renames the customer addressed by the path" do
          request

          expect(response).to have_http_status(:ok)
          expect(customer.reload.external_id).to eq("renamed.eu")
        end
      end

      context "with a conflicting external id" do
        let(:attributes) { {external_id: "taken"} }

        before { create(:customer, organization:, external_id: "taken") }

        it "rejects the change without modifying either customer" do
          expect { request }.not_to change { customer.reload.external_id }

          expect(response).to have_http_status(:unprocessable_content)
          expect(json).to eq(code: "validation_errors", details: [{code: "value_already_exist", field: "external_id", meta: {}}])
        end
      end

      context "with billing configuration changes", :premium do
        let(:attributes) { {invoice_grace_period: 4} }

        it "changes only the supplied flat setting" do
          request

          expect(response).to have_http_status(:ok)
          expect(customer.reload).to have_attributes(invoice_grace_period: 4, document_locale: "fr")
          expect(json[:customer][:invoice_grace_period]).to eq(4)
        end

        context "when clearing the grace period" do
          let(:customer) { create(:customer, organization:, invoice_grace_period: 4, document_locale: "fr") }
          let(:attributes) { {invoice_grace_period: nil} }

          it "preserves the explicit null" do
            request

            expect(response).to have_http_status(:ok)
            expect(customer.reload).to have_attributes(invoice_grace_period: nil, document_locale: "fr")
            expect(json[:customer][:invoice_grace_period]).to be_nil
          end
        end
      end

      context "with a periodic invoice issuing date anchor" do
        let(:attributes) { {periodic_invoice_issuing_date_anchor: "current_period_end"} }

        it "updates the anchor" do
          request

          expect(response).to have_http_status(:ok)
          expect(customer.reload.subscription_invoice_issuing_date_anchor).to eq("current_period_end")
          expect(json[:customer][:periodic_invoice_issuing_date_anchor]).to eq("current_period_end")
        end

        context "when clearing it" do
          let(:customer) { create(:customer, organization:, subscription_invoice_issuing_date_anchor: "current_period_end") }
          let(:attributes) { {periodic_invoice_issuing_date_anchor: nil} }

          it "falls back to the billing entity setting" do
            request

            expect(response).to have_http_status(:ok)
            expect(customer.reload.subscription_invoice_issuing_date_anchor).to be_nil
            expect(json[:customer][:periodic_invoice_issuing_date_anchor]).to be_nil
          end
        end
      end

      context "with a periodic invoice issuing date adjustment" do
        let(:attributes) { {periodic_invoice_issuing_date_adjustment: "keep_anchor"} }

        it "updates the adjustment" do
          request

          expect(response).to have_http_status(:ok)
          expect(customer.reload.subscription_invoice_issuing_date_adjustment).to eq("keep_anchor")
          expect(json[:customer][:periodic_invoice_issuing_date_adjustment]).to eq("keep_anchor")
        end

        context "when clearing it" do
          let(:customer) { create(:customer, organization:, subscription_invoice_issuing_date_adjustment: "keep_anchor") }
          let(:attributes) { {periodic_invoice_issuing_date_adjustment: nil} }

          it "falls back to the billing entity setting" do
            request

            expect(response).to have_http_status(:ok)
            expect(customer.reload.subscription_invoice_issuing_date_adjustment).to be_nil
            expect(json[:customer][:periodic_invoice_issuing_date_adjustment]).to be_nil
          end
        end
      end

      context "with a flat document locale" do
        let(:attributes) { {document_locale: "de"} }

        it "updates the locale" do
          request

          expect(response).to have_http_status(:ok)
          expect(customer.reload.document_locale).to eq("de")
          expect(json[:customer][:document_locale]).to eq("de")
        end
      end

      context "with only the old billing configuration wrapper" do
        let(:attributes) { {billing_configuration: {document_locale: "de"}} }

        it "ignores the nested fields" do
          request

          expect(response).to have_http_status(:ok)
          expect(customer.reload.document_locale).to eq("fr")
        end
      end

      context "with metadata" do
        let(:metadata) { create(:customer_metadata, customer:, display_in_invoice: true) }
        let(:attributes) { {metadata: [{id: metadata.id, key: metadata.key, value: "changed", display_on_invoice: false}]} }

        it "can turn off display_on_invoice" do
          request

          expect(response).to have_http_status(:ok)
          expect(metadata.reload).to have_attributes(value: "changed", display_in_invoice: false)
        end
      end

      context "with only removed parameters" do
        let(:attributes) { {net_payment_term: 60, subscription_invoice_issuing_date_anchor: "current_period_end"} }

        it "ignores the parameters instead of reporting a missing customer wrapper" do
          request

          expect(response).to have_http_status(:ok)
          expect(customer.reload).to have_attributes(net_payment_term: 30, subscription_invoice_issuing_date_anchor: nil)
        end
      end

      context "with a malformed customer wrapper" do
        subject(:request) do
          public_send(:"#{method}_with_token", organization, "/api/v2/customers/#{customer.external_id}", {customer: [{name: "Updated"}]})
        end

        it "returns a missing parameter error without changing the customer" do
          expect { request }.not_to change { customer.reload.attributes }

          expect(response).to have_http_status(:bad_request)
          expect(json[:code]).to eq("missing_parameter")
        end
      end

      context "with expansions on update" do
        subject(:request) do
          public_send(:"#{method}_with_token", organization, "/api/v2/customers/#{customer.external_id}?expands[]=taxes", {customer: attributes})
        end

        it "rejects the request before changing the customer" do
          expect { request }.not_to change { customer.reload.attributes }

          expect(response).to have_http_status(:bad_request)
          expect(json).to eq(
            code: "expand_not_supported",
            details: [{code: "action_not_expandable", field: "expands", meta: {invalid_values: ["taxes"]}}]
          )
        end
      end
    end
  end

  describe "GET /api/v2/customers/:external_id" do
    subject(:request) { get_with_token(organization, "/api/v2/customers/#{customer.external_id}", parameters) }

    let(:customer) { create(:customer, organization:, external_id: "customer.eu") }
    let(:parameters) { {} }

    include_examples "requires API permission", "customer", "read"

    it "returns a customer without nested relationships" do
      request

      expect(response).to have_http_status(:ok)
      expect(json[:customer][:lago_id]).to eq(customer.id)
      expect(json[:customer][:created_at]).to eq(customer.created_at.iso8601(6))
      expect(json[:customer][:updated_at]).to eq(customer.updated_at.iso8601(6))
      expect(json[:customer][:document_locale]).to eq(customer.document_locale)
      expect(json[:customer][:shipping_address]).to eq(customer.shipping_address)
      expect(json[:customer]).not_to have_key(:billing_configuration)
      expect(json[:customer].keys & %i[taxes metadata integration_customers]).to eq([])
    end

    context "with expansions" do
      let(:parameters) { {expands: %w[taxes metadata integration_customers]} }
      let(:tax) { create(:tax, organization:) }
      let(:metadata) { create(:customer_metadata, customer:) }
      let(:integration_customer) { create(:anrok_customer, customer:) }

      before do
        create(:customer_applied_tax, customer:, tax:)
        metadata
        integration_customer
      end

      it "returns the requested relationships" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:customer][:taxes].map { it[:lago_id] }).to eq([tax.id])
        expect(json[:customer][:metadata].map { it[:display_on_invoice] }).to eq([true])
        expect(json[:customer][:metadata].first[:created_at]).to eq(metadata.created_at.iso8601(6))
        expect(json[:customer][:metadata].first[:updated_at]).to eq(metadata.updated_at.iso8601(6))
        expect(json[:customer][:taxes].first[:created_at]).to eq(tax.created_at.iso8601(6))
        expect(json[:customer][:metadata].first).not_to have_key(:display_in_invoice)
        expect(json[:customer][:integration_customers].map { it[:lago_id] }).to eq([integration_customer.id])
        expect(json[:customer][:shipping_address]).to eq(customer.shipping_address)
        expect(json[:customer].keys.last(3)).to eq(%i[metadata taxes integration_customers])
      end
    end

    context "with an unknown expansion" do
      let(:parameters) { {expands: ["unknown"]} }

      it "rejects it" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(
          code: "invalid_expand",
          details: [{code: "invalid_expand", field: "expands", meta: {invalid_values: ["unknown"], allowed_values: %w[metadata taxes integration_customers]}}]
        )
      end
    end

    context "with malformed expansions" do
      let(:parameters) { {expands: {taxes: "yes"}} }

      it "rejects them" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_expand")
      end
    end

    ["metadata", {"0" => "metadata"}].each do |expands|
      context "with expansions in the form #{expands.inspect}" do
        let(:parameters) { {expands:} }

        it "rejects a value that is not an array of strings" do
          request

          expect(response).to have_http_status(:bad_request)
          expect(json).to eq(
            code: "invalid_expand",
            details: [{code: "malformed", field: "expands", meta: {allowed_values: %w[metadata taxes integration_customers]}}]
          )
        end
      end
    end

    context "with whitespace and duplicate expansion names" do
      let(:parameters) { {expands: [" metadata ", "metadata", ""]} }
      let(:metadata) { create(:customer_metadata, customer:) }

      before { metadata }

      it "returns only the requested relationship once" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:customer][:metadata].pluck(:lago_id)).to eq([metadata.id])
        expect(json[:customer].keys & %i[taxes integration_customers]).to eq([])
      end
    end

    context "with an empty expansion list" do
      let(:parameters) { {expands: []} }

      it "keeps the response free of relationships" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:customer].keys & %i[metadata taxes integration_customers]).to eq([])
      end
    end

    context "with a foreign customer" do
      let(:customer) { create(:customer, organization: create(:organization)) }

      it "does not expose the customer" do
        request

        expect(response).to be_v2_not_found_error("customer")
      end
    end

    context "with a deleted customer" do
      before { customer.discard! }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("customer")
      end
    end
  end

  describe "GET /api/v2/customers" do
    subject(:request) { get_with_token(organization, "/api/v2/customers", parameters) }

    let(:parameters) { {} }

    include_examples "requires API permission", "customer", "read"

    it_behaves_like "a cursor paginated v2 endpoint", collection: :customers, model: Customer do
      let(:paginated_path) { "/api/v2/customers" }
      let(:create_paginated_record) { ->(created_at) { create(:customer, organization:, created_at:) } }
    end

    context "with customers of different organizations" do
      let!(:customer) { create(:customer, organization:) }

      before do
        create(:customer, organization: create(:organization))
        create(:customer, organization:, deleted_at: Time.current)
      end

      it "lists only the current organization's kept customers, without relationships" do
        request

        expect(json[:customers].map { it[:lago_id] }).to eq([customer.id])
        expect(json[:customers].sole[:document_locale]).to eq(customer.document_locale)
        expect(json[:customers].sole[:shipping_address]).to eq(customer.shipping_address)
        expect(json[:customers].sole).not_to have_key(:billing_configuration)
        expect(json[:customers].sole.keys & %i[taxes metadata integration_customers net_payment_term]).to eq([])
      end
    end

    context "with search and billing entity filters" do
      let(:entity) { create(:billing_entity, organization:) }
      let!(:matching_customer) { create(:customer, organization:, billing_entity: entity, name: "Searched customer") }
      let(:parameters) { {search_term: "Searched", billing_entity_codes: [entity.code]} }

      before { create(:customer, organization:, name: "Searched other entity") }

      it "applies both filters" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:customers].map { it[:lago_id] }).to eq([matching_customer.id])
      end
    end

    context "with a foreign billing entity code" do
      let(:entity) { create(:billing_entity, organization: create(:organization)) }
      let(:parameters) { {billing_entity_codes: [entity.code]} }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("billing_entity")
      end
    end

    context "with expansions" do
      let(:parameters) { {expands: ["taxes"], after: "invalid"} }

      it "rejects expansions before reading the cursor" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("expand_not_supported")
      end
    end

    context "with filters outside their allowed values" do
      let(:parameters) { {account_type: %w[bogus customer other], has_customer_type: "maybe"} }

      it "returns a validation error on each filter with the values it allows" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(
          code: "validation_errors",
          details: [
            {code: "value_is_invalid", field: "account_type", meta: {allowed_values: %w[customer partner]}},
            {code: "value_is_invalid", field: "has_customer_type", meta: {allowed_values: %w[true false]}}
          ]
        )
      end
    end

    context "with filters that contradict each other" do
      let(:parameters) { {has_customer_type: "false", customer_type: "company"} }

      it "returns a validation error on the refused filter" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "customer_type", meta: {}}])
      end
    end
  end

  describe "DELETE /api/v2/customers/:external_id" do
    subject(:request) { delete_with_token(organization, "/api/v2/customers/#{customer.external_id}") }

    let(:customer) { create(:customer, organization:) }

    include_examples "requires API permission", "customer", "write"

    it "discards the customer and returns the deletion timestamp" do
      request

      expect(response).to have_http_status(:ok)
      expect(customer.reload).to be_discarded
      expect(json[:customer]).not_to have_key(:billing_configuration)
      expect(json[:customer][:deleted_at]).to eq(customer.deleted_at.iso8601(6))
      expect(json[:customer][:shipping_address]).to eq(customer.shipping_address)
    end

    context "with expansions on delete" do
      subject(:request) { delete_with_token(organization, "/api/v2/customers/#{customer.external_id}?expands[]=taxes") }

      it "rejects the request without discarding the customer" do
        expect { request }.not_to change { customer.reload.deleted_at }

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(
          code: "expand_not_supported",
          details: [{code: "action_not_expandable", field: "expands", meta: {invalid_values: ["taxes"]}}]
        )
      end
    end

    context "with a foreign customer" do
      let(:customer) { create(:customer, organization: create(:organization)) }

      it "does not discard it" do
        expect { request }.not_to change { customer.reload.deleted_at }

        expect(response).to be_v2_not_found_error("customer")
      end
    end
  end
end
