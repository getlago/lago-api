# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::CustomersController, type: :request do
  describe "POST /api/v1/customers" do
    subject { post_with_token(organization, "/api/v1/customers", {customer: create_params}) }

    let(:organization) { stripe_provider.organization }
    let(:stripe_provider) { create(:stripe_provider) }
    let(:create_params) do
      {
        external_id: SecureRandom.uuid,
        name: "Foo Bar Inc.",
        firstname: "Foo",
        lastname: "Bar",
        customer_type: "company",
        currency: "EUR",
        timezone: "America/New_York",
        external_salesforce_id: "foobar"
      }
    end

    include_examples "requires API permission", "customer", "write"

    it "returns a success" do
      subject

      expect(response).to have_http_status(:success)

      expect(json[:customer][:lago_id]).to be_present
      expect(json[:customer][:external_id]).to eq(create_params[:external_id])
      expect(json[:customer][:name]).to eq(create_params[:name])
      expect(json[:customer][:firstname]).to eq(create_params[:firstname])
      expect(json[:customer][:lastname]).to eq(create_params[:lastname])
      expect(json[:customer][:customer_type]).to eq(create_params[:customer_type])
      expect(json[:customer][:created_at]).to be_present
      expect(json[:customer][:currency]).to eq(create_params[:currency])
      expect(json[:customer][:external_salesforce_id]).to eq(create_params[:external_salesforce_id])
      expect(json[:customer][:account_type]).to eq("customer")
    end

    context "with premium features" do
      around { |test| lago_premium!(&test) }

      let(:create_params) do
        {
          external_id: SecureRandom.uuid,
          name: "Foo Bar",
          timezone: "America/New_York"
        }
      end

      it "returns a success" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:customer][:timezone]).to eq(create_params[:timezone])
      end
    end

    context "with finalize_zero_amount_invoice" do
      let(:create_params) do
        {
          external_id: SecureRandom.uuid,
          finalize_zero_amount_invoice: "skip"
        }
      end

      it "returns a success" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:customer][:finalize_zero_amount_invoice]).to eq("skip")
      end
    end

    context "with billing configuration" do
      around { |test| lago_premium!(&test) }

      let(:create_params) do
        {
          external_id: SecureRandom.uuid,
          name: "Foo Bar",
          billing_configuration: {
            invoice_grace_period: 3,
            payment_provider: "stripe",
            payment_provider_code: stripe_provider.code,
            provider_customer_id: "stripe_id",
            document_locale: "fr",
            provider_payment_methods:
          }
        }
      end

      before do
        stub_request(:post, "https://api.stripe.com/v1/checkout/sessions")
          .to_return(status: 200, body: body.to_json, headers: {})

        allow(::Stripe::Checkout::Session).to receive(:create)
          .and_return({"url" => "https://example.com"})

        subject
      end

      context "when provider payment methods are not present" do
        let(:provider_payment_methods) { nil }

        it "returns a success" do
          expect(response).to have_http_status(:success)

          expect(json[:customer][:lago_id]).to be_present
          expect(json[:customer][:external_id]).to eq(create_params[:external_id])

          billing = json[:customer][:billing_configuration]
          aggregate_failures do
            expect(billing).to be_present
            expect(billing[:payment_provider]).to eq("stripe")
            expect(billing[:payment_provider_code]).to eq(stripe_provider.code)
            expect(billing[:provider_customer_id]).to eq("stripe_id")
            expect(billing[:invoice_grace_period]).to eq(3)
            expect(billing[:document_locale]).to eq("fr")
            expect(billing[:provider_payment_methods]).to eq(%w[card])
          end
        end
      end

      context "when both provider payment methods are set" do
        let(:provider_payment_methods) { %w[card sepa_debit] }

        it "returns a success" do
          expect(response).to have_http_status(:success)

          expect(json[:customer][:lago_id]).to be_present
          expect(json[:customer][:external_id]).to eq(create_params[:external_id])

          billing = json[:customer][:billing_configuration]
          aggregate_failures do
            expect(billing).to be_present
            expect(billing[:payment_provider]).to eq("stripe")
            expect(billing[:payment_provider_code]).to eq(stripe_provider.code)
            expect(billing[:provider_customer_id]).to eq("stripe_id")
            expect(billing[:invoice_grace_period]).to eq(3)
            expect(billing[:document_locale]).to eq("fr")
            expect(billing[:provider_payment_methods]).to eq(%w[card sepa_debit])
          end
        end
      end

      context "when provider payment methods contain only card" do
        let(:provider_payment_methods) { %w[card] }

        it "returns a success" do
          expect(response).to have_http_status(:success)

          expect(json[:customer][:lago_id]).to be_present
          expect(json[:customer][:external_id]).to eq(create_params[:external_id])

          billing = json[:customer][:billing_configuration]
          aggregate_failures do
            expect(billing).to be_present
            expect(billing[:payment_provider]).to eq("stripe")
            expect(billing[:payment_provider_code]).to eq(stripe_provider.code)
            expect(billing[:provider_customer_id]).to eq("stripe_id")
            expect(billing[:invoice_grace_period]).to eq(3)
            expect(billing[:document_locale]).to eq("fr")
            expect(billing[:provider_payment_methods]).to eq(%w[card])
          end
        end
      end

      context "when provider payment methods contain only sepa_debit" do
        let(:provider_payment_methods) { %w[sepa_debit] }

        it "returns a success" do
          expect(response).to have_http_status(:success)

          expect(json[:customer][:lago_id]).to be_present
          expect(json[:customer][:external_id]).to eq(create_params[:external_id])

          billing = json[:customer][:billing_configuration]
          aggregate_failures do
            expect(billing).to be_present
            expect(billing[:payment_provider]).to eq("stripe")
            expect(billing[:payment_provider_code]).to eq(stripe_provider.code)
            expect(billing[:provider_customer_id]).to eq("stripe_id")
            expect(billing[:invoice_grace_period]).to eq(3)
            expect(billing[:document_locale]).to eq("fr")
            expect(billing[:provider_payment_methods]).to eq(%w[sepa_debit])
          end
        end
      end
    end

    context "with account_type partner" do
      let(:organization) { create(:organization, premium_integrations: ["revenue_share"]) }

      let(:create_params) do
        {
          external_id: SecureRandom.uuid,
          name: "Foo Bar",
          account_type: "partner"
        }
      end

      around { |test| lago_premium!(&test) }

      it "returns a success" do
        subject
        expect(response).to have_http_status(:success)

        expect(json[:customer][:lago_id]).to be_present
        expect(json[:customer][:external_id]).to eq(create_params[:external_id])
        expect(json[:customer][:account_type]).to eq(create_params[:account_type])
      end
    end

    context "with metadata" do
      let(:create_params) do
        {
          external_id: SecureRandom.uuid,
          name: "Foo Bar",
          metadata: [
            {
              key: "Hello",
              value: "Hi",
              display_in_invoice: true
            }
          ]
        }
      end

      it "returns a success" do
        subject

        expect(response).to have_http_status(:success)

        expect(json[:customer][:lago_id]).to be_present
        expect(json[:customer][:external_id]).to eq(create_params[:external_id])

        metadata = json[:customer][:metadata]
        aggregate_failures do
          expect(metadata).to be_present
          expect(metadata.first[:key]).to eq("Hello")
          expect(metadata.first[:value]).to eq("Hi")
          expect(metadata.first[:display_in_invoice]).to eq(true)
        end
      end
    end

    context "with invalid params" do
      let(:create_params) do
        {name: "Foo Bar", currency: "invalid"}
      end

      it "returns an unprocessable_entity" do
        subject
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with invoice_custom_sections" do
      let(:create_params) do
        {
          external_id: SecureRandom.uuid,
          name: "Foo Bar",
          skip_invoice_custom_sections:,
          invoice_custom_section_codes:
        }
      end
      let(:invoice_custom_sections) { create_list(:invoice_custom_section, 2, organization: organization) }

      before do
        organization.selected_invoice_custom_sections = [invoice_custom_sections[0]]
        subject
      end

      context "when sending custom invoice_custom_sections" do
        let(:skip_invoice_custom_sections) { false }
        let(:invoice_custom_section_codes) { invoice_custom_sections.map(&:code) }

        it "returns a success" do
          expect(response).to have_http_status(:success)

          expect(json[:customer][:lago_id]).to be_present
          expect(json[:customer][:external_id]).to eq(create_params[:external_id])

          sections = json[:customer][:applicable_invoice_custom_sections]
          expect(sections).to be_present
          expect(sections.length).to eq(2)
          expect(sections.map { |sec| sec[:code] }).to match_array(invoice_custom_section_codes)
        end
      end

      context "when sending skip_invoice_custom_sections AND invoice_custom_section_codes" do
        let(:skip_invoice_custom_sections) { true }
        let(:invoice_custom_section_codes) { invoice_custom_sections.map(&:code) }

        it "returns an error" do
          expect(response).to have_http_status(:unprocessable_entity)

          expect(json[:error_details][:invoice_custom_sections]).to include("skip_sections_and_selected_ids_sent_together")
        end
      end
    end
  end

  describe "GET /api/v1/customers/:customer_external_id/portal_url" do
    subject { get_with_token(organization, "/api/v1/customers/#{external_id}/portal_url") }

    let(:customer) { create(:customer, organization:) }
    let(:organization) { create(:organization) }
    let(:external_id) { customer.external_id }

    include_examples "requires API permission", "customer", "read"

    it "returns the portal url" do
      subject

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:customer][:portal_url]).to include("/customer-portal/")
      end
    end

    context "when customer does not belongs to the organization" do
      let(:customer) { create(:customer) }

      it "returns not found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /api/v1/customers" do
    subject { get_with_token(organization, "/api/v1/customers", params) }

    let(:params) { {} }
    let(:organization) { create(:organization) }

    before { create_pair(:customer, organization:) }

    include_examples "requires API permission", "customer", "read"

    it "returns all customers from organization" do
      subject

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(json[:meta][:total_count]).to eq(2)
        expect(json[:customers][0][:taxes]).not_to be_nil
      end
    end

    context "with account_type filters" do
      let(:params) { {account_type: %w[partner]} }

      let(:partner) do
        create(:customer, organization:, account_type: "partner")
      end

      before { partner }

      it "returns partner customers" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:customers].count).to eq(1)
        expect(json[:customers].first[:lago_id]).to eq(partner.id)
      end
    end

    context "when filtering by billing_entity_code" do
      let(:billing_entity) { create(:billing_entity, organization:) }
      let(:customer) { create(:customer, organization:, billing_entity:) }
      let(:params) { {billing_entity_codes: [billing_entity.code]} }

      before { customer }

      it "returns customers for the specified billing entity" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:customers].count).to eq(1)
        expect(json[:customers].first[:lago_id]).to eq(customer.id)
      end

      context "when one of billing entities does not exist" do
        let(:params) { {billing_entity_codes: [billing_entity.code, "non_existent_code"]} }

        it "returns a not found error" do
          subject

          expect(response).to have_http_status(:not_found)
          expect(json[:code]).to eq("billing_entity_not_found")
        end
      end
    end
  end

  describe "GET /api/v1/customers/:customer_id" do
    subject { get_with_token(organization, "/api/v1/customers/#{external_id}") }

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:external_id) { customer.external_id }

    context "when customer exists" do
      include_examples "requires API permission", "customer", "read"

      it "returns the customer" do
        subject

        aggregate_failures do
          expect(response).to have_http_status(:ok)
          expect(json[:customer][:lago_id]).to eq(customer.id)
          expect(json[:customer][:taxes]).not_to be_nil
        end
      end
    end

    context "when customer does not exist" do
      let(:external_id) { SecureRandom.uuid }

      it "returns a not found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "DELETE /api/v1/customers/:customer_id" do
    subject { delete_with_token(organization, "/api/v1/customers/#{external_id}") }

    let(:organization) { create(:organization) }
    let!(:customer) { create(:customer, organization:) }
    let(:external_id) { customer.external_id }

    include_examples "requires API permission", "customer", "write"

    it "deletes a customer" do
      expect { subject }.to change(Customer, :count).by(-1)
    end

    it "returns deleted customer" do
      subject

      aggregate_failures do
        expect(response).to have_http_status(:success)

        expect(json[:customer][:lago_id]).to eq(customer.id)
        expect(json[:customer][:external_id]).to eq(customer.external_id)
      end
    end

    context "when customer does not exist" do
      let(:external_id) { SecureRandom.uuid }

      it "returns not_found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/v1/customers/:external_customer_id/checkout_url" do
    subject do
      post_with_token(organization, "/api/v1/customers/#{customer.external_id}/checkout_url")
    end

    let(:organization) { create(:organization) }
    let(:stripe_provider) { create(:stripe_provider, organization:) }
    let(:customer) { create(:customer, organization:) }

    before do
      create(
        :stripe_customer,
        customer_id: customer.id,
        payment_provider: stripe_provider
      )

      customer.update!(payment_provider: "stripe", payment_provider_code: stripe_provider.code)

      allow(::Stripe::Checkout::Session).to receive(:create)
        .and_return({"url" => "https://example.com"})
    end

    include_examples "requires API permission", "customer", "write"

    it "returns the new generated checkout url" do
      subject

      aggregate_failures do
        expect(response).to have_http_status(:success)

        expect(json[:customer][:checkout_url]).to eq("https://example.com")
      end
    end
  end
end
