# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::OrganizationsController do
  include_context "with mocked security logger"

  let_it_be(:organization, refind: true) { create_default(:organization) }
  let(:webhook_url) { Faker::Internet.url }

  describe "PUT /api/v1/organizations" do
    subject do
      put_with_token(
        organization,
        "/api/v1/organizations",
        {organization: update_params}
      )
    end

    let(:update_params) do
      {
        country: "pl",
        default_currency: "EUR",
        address_line1: "address1",
        address_line2: "address2",
        state: "state",
        zipcode: "10000",
        email: "mail@example.com",
        city: "test_city",
        legal_name: "test1",
        legal_number: "123",
        timezone: "Europe/Paris",
        webhook_url:,
        email_settings: ["invoice.finalized"],
        customer_portal_locked_fields: %w[name country],
        document_number_prefix: "ORG-2",
        finalize_zero_amount_invoice: false,
        document_url_expiration_days: 90,
        billing_configuration: {
          invoice_footer: "footer",
          invoice_grace_period: 3,
          document_locale: "fr"
        }
      }
    end

    include_examples "requires API permission", "organization", "write"

    it "updates an organization" do
      put_with_token(
        organization,
        "/api/v1/organizations",
        {organization: update_params}
      )

      expect(response).to have_http_status(:success)

      expect(json[:organization][:name]).to eq(organization.name)
      expect(json[:organization][:default_currency]).to eq("EUR")
      expect(json[:organization][:webhook_url]).to eq(webhook_url)
      expect(json[:organization][:webhook_urls]).to eq([webhook_url])
      expect(json[:organization][:customer_portal_locked_fields]).to eq(%w[name country])
      expect(json[:organization][:document_numbering]).to eq("per_customer")
      expect(json[:organization][:document_number_prefix]).to eq("ORG-2")
      expect(json[:organization][:finalize_zero_amount_invoice]).to eq(false)
      expect(json[:organization][:document_url_expiration_days]).to eq(90)
      # TODO(:timezone): Timezone update is turned off for now
      # expect(json[:organization][:timezone]).to eq(update_params[:timezone])

      billing = json[:organization][:billing_configuration]
      expect(billing[:invoice_footer]).to eq("footer")
      expect(billing[:document_locale]).to eq("fr")

      expect(json[:organization][:taxes]).not_to be_nil
    end

    context "when updating the webhook url" do
      let(:update_params) { {webhook_url:} }

      before { subject }

      it "updates the endpoint" do
        expect(response).to have_http_status(:success)
        expect(json[:organization][:webhook_url]).to eq(webhook_url)
        expect(json[:organization][:webhook_urls]).to eq([webhook_url])
        expect(organization.webhook_endpoints.order(:id).first.webhook_url).to eq(webhook_url)
      end

      it_behaves_like "produces a security log", "webhook_endpoint.updated"

      context "when the organization has no webhook endpoint" do
        let(:organization) { create(:organization, webhook_url: nil) }

        it "creates the endpoint" do
          expect(response).to have_http_status(:success)
          expect(json[:organization][:webhook_url]).to eq(webhook_url)
          expect(json[:organization][:webhook_urls]).to eq([webhook_url])
          expect(organization.webhook_endpoints.pluck(:webhook_url)).to eq([webhook_url])
        end

        it_behaves_like "produces a security log", "webhook_endpoint.created"
      end

      context "when the url is already set" do
        let(:organization) { create(:organization) }
        let(:webhook_url) { organization.webhook_endpoints.order(:id).first.webhook_url }

        it "does not produce a webhook endpoint security log" do
          expect(response).to have_http_status(:success)
          expect(json[:organization][:webhook_url]).to eq(webhook_url)
          expect(security_logger).not_to have_received(:produce).with(hash_including(log_type: "webhook_endpoint"))
        end
      end
    end

    context "when updating the webhook url of an organization with several webhook endpoints" do
      let(:organization) { create(:organization) }
      let(:webhook_url) { "https://hooks.example.com/new" }
      let(:update_params) { {webhook_url:} }
      let(:other_webhook_endpoint) { create(:webhook_endpoint, organization:) }
      let(:target_webhook_endpoint) { organization.webhook_endpoints.order(:id).first }
      let(:untouched_webhook_endpoint) { organization.webhook_endpoints.order(:id).last }
      let(:untouched_url) { untouched_webhook_endpoint.webhook_url }

      before do
        other_webhook_endpoint
        untouched_url

        # Loads the association before the update, as a caller that read the endpoints would.
        allow(Organizations::UpdateService).to receive(:call).and_wrap_original do |method, organization:, **kwargs|
          organization.webhook_endpoints.load
          method.call(organization:, **kwargs)
        end
      end

      it "updates only the endpoint with the lowest id" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:organization][:webhook_urls]).to match_array([webhook_url, untouched_url])
        expect(target_webhook_endpoint.reload.webhook_url).to eq(webhook_url)
        expect(untouched_webhook_endpoint.reload.webhook_url).to eq(untouched_url)
      end
    end

    context "with a refused webhook url" do
      let(:organization) { create(:organization) }
      let(:update_params) { {webhook_url:, legal_name: "Refused"} }

      [
        ["foobar", %w[url_is_invalid]],
        [nil, %w[value_is_mandatory url_is_invalid]]
      ].each do |refused_url, expected_messages|
        context "when the url is #{refused_url.inspect}" do
          let(:webhook_url) { refused_url }

          it "returns a validation error and saves nothing" do
            endpoints_before = organization.webhook_endpoints.order(:id).pluck(:id, :webhook_url)

            subject

            expect(response).to have_http_status(:unprocessable_content)
            expect(json[:error_details]).to eq({webhook_url: expected_messages})
            expect(organization.reload.legal_name).not_to eq("Refused")
            expect(organization.webhook_endpoints.order(:id).pluck(:id, :webhook_url)).to eq(endpoints_before)
            expect(security_logger).not_to have_received(:produce).with(hash_including(log_type: "webhook_endpoint"))
          end
        end
      end
    end

    context "with a document url expiration window above 120 days" do
      let(:update_params) { {document_url_expiration_days: 365} }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details][:document_url_expiration_days]).to eq(["value_is_out_of_range"])
      end
    end

    context "with premium features", :premium do
      it "updates an organization" do
        subject

        expect(response).to have_http_status(:success)

        expect(json[:organization][:timezone]).to eq(update_params[:timezone])
        expect(json[:organization][:email_settings]).to eq(update_params[:email_settings])

        billing = json[:organization][:billing_configuration]
        expect(billing[:invoice_grace_period]).to eq(3)
      end
    end
  end

  describe "GET /api/v1/organizations" do
    subject { get_with_token(organization, "/api/v1/organizations") }

    let(:tax) { create(:tax, organization:, applied_to_organization: true) }

    before { tax }

    include_examples "requires API permission", "organization", "read"

    it "returns the organization" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:organization][:name]).to eq(organization.name)
      expect(json[:organization][:taxes].map { it[:code] }).to contain_exactly(tax.code)
    end
  end
end
