# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::OrganizationsController do
  let_it_be(:organization, refind: true) { create_default(:organization) }

  describe "GET /api/v2/organizations" do
    subject(:request) { get_with_token(organization, "/api/v2/organizations", parameters) }

    let(:parameters) { {} }

    include_examples "requires API permission", "organization", "read"

    it "returns the flat v2 payload without changing the organization" do
      expect { request }.not_to change { organization.reload.attributes }

      expect(response).to have_http_status(:ok)
      expect(json).to eq(organization: {
        lago_id: organization.id,
        name: organization.name,
        slug: organization.slug,
        email: organization.email,
        events_store: organization.events_store,
        created_at: organization.created_at.iso8601(6),
        updated_at: organization.updated_at.iso8601(6)
      })
      expect(response.headers["X-Lago-Endpoint-Status"]).to eq("beta")
    end

    context "with another organization's identifiers" do
      let(:other_organization) { create(:organization) }
      let(:parameters) { {id: other_organization.id, lago_id: other_organization.id, organization_id: other_organization.id} }

      it "returns only the organization identified by the API key" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:organization][:lago_id]).to eq(organization.id)
      end
    end

    context "without authentication" do
      subject(:request) { get "/api/v2/organizations", as: :json }

      it "returns unauthorized" do
        request

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "without the product catalog feature", product_catalog: false do
      it "returns forbidden" do
        request

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end

    context "with unsupported expansions" do
      let(:parameters) { {expands: ["taxes"]} }

      it "rejects the expansion" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("expand_not_supported")
      end
    end

    context "with malformed expansions" do
      let(:parameters) { {expands: "taxes"} }

      it "returns the v2 parameter error" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_expand")
      end
    end
  end

  describe "PUT /api/v2/organizations" do
    subject(:request) { put_with_token(organization, "/api/v2/organizations", {organization: attributes}) }

    let(:attributes) { {email: "billing@example.com", slug: "updated-organization"} }

    include_examples "requires API permission", "organization", "write"

    it "updates the organization and returns the flat v2 payload" do
      request

      expect(response).to have_http_status(:ok)
      expect(organization.reload).to have_attributes(**attributes)
      expect(json).to eq(organization: {
        lago_id: organization.id,
        name: organization.name,
        slug: "updated-organization",
        email: "billing@example.com",
        events_store: organization.events_store,
        created_at: organization.created_at.iso8601(6),
        updated_at: organization.updated_at.iso8601(6)
      })
      expect(response.headers["X-Lago-Endpoint-Status"]).to eq("beta")
    end

    context "when only updating the email" do
      let(:attributes) { {email: "contact@example.com"} }

      it "preserves the slug and existing default billing entity email synchronization" do
        expect { request }.not_to change { organization.reload.slug }

        expect(response).to have_http_status(:ok)
        expect(organization.reload.email).to eq("contact@example.com")
        expect(organization.default_billing_entity.reload.email).to eq("contact@example.com")
      end
    end

    context "when only updating the slug" do
      let(:attributes) { {slug: "  Updated-Organization  "} }

      it "normalizes the slug and preserves the email" do
        expect { request }.not_to change { organization.reload.email }

        expect(response).to have_http_status(:ok)
        expect(organization.reload.slug).to eq("updated-organization")
      end
    end

    context "with removed and unknown parameters", :premium do
      let(:attributes) do
        super().merge(
          name: "Must not change",
          country: "FR",
          address_line1: "New address",
          address_line2: "New address line 2",
          city: "Paris",
          state: "New state",
          zipcode: "75001",
          legal_name: "New legal name",
          legal_number: "123456789",
          tax_identification_number: "FR12345678901",
          default_currency: "EUR",
          timezone: "Europe/Paris",
          net_payment_term: 30,
          finalize_zero_amount_invoice: false,
          document_numbering: "per_organization",
          document_number_prefix: "NEW",
          webhook_url: "https://example.com/new-webhook",
          email_settings: ["invoice.finalized"],
          billing_configuration: {invoice_footer: "New footer", invoice_grace_period: 3, document_locale: "fr"},
          unknown: "ignored"
        )
      end

      it "changes only email and slug without applying removed settings to the billing entity" do
        original_attributes = organization.attributes.except("email", "slug", "updated_at")
        billing_entity = organization.default_billing_entity
        original_billing_attributes = billing_entity.attributes.except("email", "updated_at")

        expect { request }.not_to change { organization.webhook_endpoints.reload.pluck(:id, :webhook_url) }

        expect(response).to have_http_status(:ok)
        expect(organization.reload).to have_attributes(email: "billing@example.com", slug: "updated-organization")
        expect(organization.attributes.except("email", "slug", "updated_at")).to eq(original_attributes)
        expect(billing_entity.reload.attributes.except("email", "updated_at")).to eq(original_billing_attributes)
        expect(json[:organization].keys).to eq(%i[lago_id name slug email events_store created_at updated_at])
      end
    end

    context "when the slug is taken by another organization" do
      let(:other_organization) { create(:organization) }
      let(:attributes) { super().merge(slug: other_organization.slug) }

      it "returns a validation error without saving either field" do
        original_billing_email = organization.default_billing_entity.email

        expect { request }.not_to change { organization.reload.attributes }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details][:slug]).to eq(["value_already_exist"])
        expect(organization.default_billing_entity.reload.email).to eq(original_billing_email)
      end
    end

    [nil, "", "has spaces", "api", true, false, 123].each do |slug|
      context "with an invalid slug #{slug.inspect}" do
        let(:attributes) { super().merge(slug:) }

        it "returns a validation error without saving changes" do
          expect { request }.not_to change { organization.reload.attributes }

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:error_details][:slug]).to be_present
        end
      end
    end

    context "with an invalid email" do
      let(:attributes) { super().merge(email: "invalid") }

      it "returns a validation error without changing the slug" do
        expect { request }.not_to change { organization.reload.attributes }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details][:email]).to eq(["invalid_email_format"])
      end
    end

    context "with another organization's identifiers" do
      let(:other_organization) { create(:organization) }
      let(:attributes) { super().merge(id: other_organization.id, lago_id: other_organization.id, organization_id: other_organization.id) }

      it "updates only the organization identified by the API key" do
        expect { request }.not_to change { other_organization.reload.attributes }

        expect(response).to have_http_status(:ok)
        expect(organization.reload).to have_attributes(email: "billing@example.com", slug: "updated-organization")
        expect(json[:organization][:lago_id]).to eq(organization.id)
      end
    end

    context "without authentication" do
      subject(:request) { put "/api/v2/organizations", params: {organization: attributes}, as: :json }

      it "does not update the organization" do
        expect { request }.not_to change { organization.reload.attributes }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "without the product catalog feature", product_catalog: false do
      it "does not update the organization" do
        expect { request }.not_to change { organization.reload.attributes }

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end

    context "with unsupported expansions" do
      subject(:request) { put_with_token(organization, "/api/v2/organizations", {organization: attributes, expands: ["taxes"]}) }

      it "rejects the request before saving changes" do
        expect { request }.not_to change { organization.reload.attributes }

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("expand_not_supported")
      end
    end

    context "with malformed expansions" do
      subject(:request) { put_with_token(organization, "/api/v2/organizations", {organization: attributes, expands: "taxes"}) }

      it "returns a malformed parameter error before saving changes" do
        expect { request }.not_to change { organization.reload.attributes }

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_expand")
      end
    end

    [nil, {}, [], "invalid", true].each do |payload|
      context "with a missing or malformed organization #{payload.inspect}" do
        subject(:request) { put_with_token(organization, "/api/v2/organizations", {organization: payload}) }

        it "returns the v2 missing parameter error" do
          expect { request }.not_to change { organization.reload.attributes }

          expect(response).to have_http_status(:bad_request)
          expect(json).to eq(
            status: 400,
            error: "Bad Request",
            code: "missing_parameter",
            error_details: {organization: {reason: "missing"}}
          )
        end
      end
    end
  end
end
