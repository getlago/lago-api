# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::CustomersController do
  let_it_be(:organization, refind: true) { create_default(:organization) }

  describe "POST /api/v2/customers" do
    subject(:request) { post_with_token(organization, "/api/v2/customers", {customer: attributes}) }

    let(:attributes) do
      {
        external_id: "customer.eu",
        name: "Example customer",
        currency: "EUR",
        billing_configuration: {document_locale: "fr"},
        shipping_address: {city: "Paris", country: "fr"},
        metadata: [{key: "reference", value: "123", display_on_invoice: true}]
      }
    end

    include_examples "requires API permission", "customer", "write"

    it "accepts nested settings and returns flat billing fields without expanded relationships" do
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
        expect(json[:error_details][:external_id]).to eq(["value_already_exist"])
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
        super().merge(net_payment_term: 60, metadata: [{key: "reference", value: "123", display_in_invoice: true}])
      end

      it "ignores removed fields" do
        request

        expect(response).to have_http_status(:ok)
        customer = organization.customers.find_by!(external_id: attributes[:external_id])
        expect(customer.net_payment_term).to be_nil
        expect(customer.metadata.sole.display_in_invoice).to be(false)
      end
    end

    context "without an external id" do
      let(:attributes) { super().except(:external_id) }

      it "returns a validation error without creating a customer" do
        expect { request }.not_to change(organization.customers, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details][:external_id]).to eq(["value_is_mandatory"])
      end
    end

    context "with a non-string enum value" do
      let(:attributes) { super().merge(finalize_zero_amount_invoice: false) }

      it "returns a validation error rather than an exception" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details][:finalize_zero_amount_invoice]).to eq(["invalid_value"])
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

    %i[billing_configuration shipping_address].each do |key|
      context "with an array instead of a #{key} object" do
        let(:attributes) { super().merge(key => [{city: "Paris"}]) }

        it "returns a parameter error without creating a customer" do
          expect { request }.not_to change(organization.customers, :count)

          expect(response).to have_http_status(:bad_request)
          expect(json[:code]).to eq("missing_parameter")
        end
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
        super().merge(billing_configuration: {
          payment_provider: "stripe",
          payment_provider_code: provider.code,
          sync_with_provider: true
        })
      end

      it "accepts nested provider settings and returns flat fields" do
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
        super().merge(billing_configuration: {
          payment_provider: "stripe",
          payment_provider_code: provider.code,
          provider_customer_id: "cus_example"
        })
      end

      it "returns the provider customer id at the top level" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:customer][:provider_customer_id]).to eq("cus_example")
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

          expect(response).to be_not_found_error("tax")
        end
      end
    end

    context "with nested invoice issuing settings", :premium do
      let(:attributes) do
        super().merge(billing_configuration: {
          invoice_grace_period: 3,
          document_locale: "fr",
          subscription_invoice_issuing_date_anchor: "current_period_end",
          subscription_invoice_issuing_date_adjustment: "keep_anchor"
        })
      end

      it "persists nested settings and returns their fields at the top level" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:customer]).to include(attributes[:billing_configuration])
        expect(json[:customer]).not_to have_key(:billing_configuration)
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
        expect(json[:error_details]).to eq(expands: {reason: "action_not_expandable", invalid_values: ["metadata"]})
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

      it "updates without requiring external_id in the body or changing omitted settings" do
        request

        expect(response).to have_http_status(:ok)
        expect(customer.reload).to have_attributes(name: "Updated", external_id: "existing.eu", document_locale: "fr", net_payment_term: 30)
        expect(json[:customer][:document_locale]).to eq("fr")
        expect(json[:customer]).not_to have_key(:billing_configuration)
        expect(json[:customer]).not_to have_key(:net_payment_term)
        expect(SendWebhookJob).to have_been_enqueued.with("customer.updated", customer)
      end

      context "when the customer does not exist" do
        let(:customer) { build_stubbed(:customer) }

        it "does not create a customer" do
          expect { request }.not_to change(organization.customers, :count)

          expect(response).to be_not_found_error("customer")
        end
      end

      context "when the customer belongs to another organization" do
        let(:customer) { create(:customer, organization: create(:organization)) }

        it "does not modify the foreign customer" do
          expect { request }.not_to change { customer.reload.attributes }

          expect(response).to be_not_found_error("customer")
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
          expect(json[:error_details][:external_id]).to eq(["value_already_exist"])
        end
      end

      context "with billing configuration changes", :premium do
        let(:attributes) { {billing_configuration: {invoice_grace_period: 4}} }

        it "changes only the supplied nested setting" do
          request

          expect(response).to have_http_status(:ok)
          expect(customer.reload).to have_attributes(invoice_grace_period: 4, document_locale: "fr")
          expect(json[:customer][:invoice_grace_period]).to eq(4)
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
        let(:attributes) { {net_payment_term: 60} }

        it "ignores the parameters instead of reporting a missing customer wrapper" do
          request

          expect(response).to have_http_status(:ok)
          expect(customer.reload.net_payment_term).to eq(30)
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
          expect(json[:error_details]).to eq(expands: {reason: "action_not_expandable", invalid_values: ["taxes"]})
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
        expect(json[:code]).to eq("invalid_expand")
        expect(json[:error_details]).to eq(expands: {invalid_values: ["unknown"], allowed_values: %w[metadata taxes integration_customers]})
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
          expect(json[:code]).to eq("invalid_expand")
          expect(json[:error_details]).to eq(expands: {reason: "malformed", allowed_values: %w[metadata taxes integration_customers]})
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

        expect(response).to be_not_found_error("customer")
      end
    end

    context "with a deleted customer" do
      before { customer.discard! }

      it "returns not found" do
        request

        expect(response).to be_not_found_error("customer")
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

        expect(response).to be_not_found_error("billing_entity")
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
      expect(json[:customer][:deleted_at]).to eq(customer.deleted_at.iso8601)
      expect(json[:customer][:shipping_address]).to eq(customer.shipping_address)
    end

    context "with expansions on delete" do
      subject(:request) { delete_with_token(organization, "/api/v2/customers/#{customer.external_id}?expands[]=taxes") }

      it "rejects the request without discarding the customer" do
        expect { request }.not_to change { customer.reload.deleted_at }

        expect(response).to have_http_status(:bad_request)
        expect(json[:error_details]).to eq(expands: {reason: "action_not_expandable", invalid_values: ["taxes"]})
      end
    end

    context "with a foreign customer" do
      let(:customer) { create(:customer, organization: create(:organization)) }

      it "does not discard it" do
        expect { request }.not_to change { customer.reload.deleted_at }

        expect(response).to be_not_found_error("customer")
      end
    end
  end
end
