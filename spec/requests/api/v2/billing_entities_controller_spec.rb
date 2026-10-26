# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::BillingEntitiesController, :premium do
  include_context "with mocked security logger"

  let_it_be(:organization, refind: true) { create_default(:organization, premium_integrations: %w[multi_entities_enterprise]) }

  describe "POST /api/v2/billing_entities" do
    subject(:request) { post_with_token(organization, "/api/v2/billing_entities", {billing_entity: attributes}) }

    let(:attributes) do
      {
        code: "entity.eu",
        name: "European entity",
        email: "billing@example.com",
        phone: "+33123456789",
        address_line1: "10 rue de Paris",
        address_line2: "Floor 2",
        city: "Paris",
        state: "Paris",
        zipcode: "75001",
        country: "FR",
        legal_name: "Example SAS",
        legal_number: "123456789",
        tax_identification_number: "FR12345678901",
        default_currency: "EUR",
        timezone: "Europe/Paris",
        finalize_zero_amount_invoice: false,
        document_numbering: "per_billing_entity",
        document_number_prefix: "EU",
        eu_tax_management: false,
        einvoicing: false,
        email_settings: ["invoice.finalized"],
        invoice_footer: "Payment information",
        invoice_grace_period: 3,
        periodic_invoice_issuing_date_anchor: "current_period_end",
        periodic_invoice_issuing_date_adjustment: "keep_anchor",
        document_locale: "fr"
      }
    end

    include_examples "requires API permission", "billing_entity", "write"

    it "creates a billing entity and returns flat settings" do
      expect { request }.to change(organization.all_billing_entities, :count).by(1)

      expect(response).to have_http_status(:ok)
      billing_entity = organization.all_billing_entities.find_by!(code: "entity.eu")
      expect(billing_entity).to have_attributes(
        **attributes.except(:periodic_invoice_issuing_date_anchor, :periodic_invoice_issuing_date_adjustment),
        subscription_invoice_issuing_date_anchor: "current_period_end",
        subscription_invoice_issuing_date_adjustment: "keep_anchor"
      )
      expect(json[:billing_entity][:lago_id]).to eq(billing_entity.id)
      expect(json[:billing_entity]).to include(
        invoice_grace_period: 3,
        document_locale: "fr",
        periodic_invoice_issuing_date_anchor: "current_period_end",
        periodic_invoice_issuing_date_adjustment: "keep_anchor"
      )
      expect(json[:billing_entity].keys & %i[billing_configuration net_payment_term taxes selected_invoice_custom_sections]).to eq([])
      expect(response.headers["X-Lago-Endpoint-Status"]).to eq("beta")
    end

    context "with removed and unknown parameters" do
      let(:attributes) do
        super().merge(
          net_payment_term: 99,
          unknown: "ignored",
          subscription_invoice_issuing_date_anchor: "next_period_start",
          subscription_invoice_issuing_date_adjustment: "align_with_finalization_date"
        )
      end

      it "does not persist them" do
        request

        expect(response).to have_http_status(:ok)
        billing_entity = organization.all_billing_entities.find_by!(code: "entity.eu")
        expect(billing_entity).to have_attributes(
          net_payment_term: 0,
          subscription_invoice_issuing_date_anchor: "current_period_end",
          subscription_invoice_issuing_date_adjustment: "keep_anchor"
        )
        expect(json[:billing_entity].keys).not_to include(:subscription_invoice_issuing_date_anchor, :subscription_invoice_issuing_date_adjustment)
      end
    end

    context "with tax codes and invoice custom section codes" do
      let(:tax) { create(:tax, organization:) }
      let(:section) { create(:invoice_custom_section, organization:) }
      let(:foreign_section) { create(:invoice_custom_section, organization: create(:organization), code: section.code) }
      let(:attributes) { super().merge(tax_codes: [tax.code], invoice_custom_section_codes: [section.code]) }

      before { foreign_section }

      it "applies the current organization's tax and section" do
        request

        expect(response).to have_http_status(:ok)
        billing_entity = organization.all_billing_entities.find_by!(code: attributes[:code])
        expect(billing_entity.taxes).to eq([tax])
        expect(billing_entity.selected_invoice_custom_sections).to eq([section])
      end

      context "with an unknown tax code" do
        let(:attributes) { super().merge(tax_codes: ["unknown"]) }

        it "returns not found without creating an entity" do
          expect { request }.not_to change(organization.all_billing_entities, :count)

          expect(response).to be_not_found_error("tax")
        end
      end
    end

    context "with an existing code" do
      before { create(:billing_entity, organization:, code: attributes[:code], name: "Existing") }

      it "rejects the duplicate without updating the existing entity" do
        expect { request }.not_to change(organization.all_billing_entities, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(organization.all_billing_entities.find_by!(code: attributes[:code]).name).to eq("Existing")
      end
    end

    [nil, "", " "].each do |code|
      context "when the code is #{code.inspect}" do
        let(:attributes) { super().merge(code:) }

        it "rejects a blank code without creating an entity" do
          expect { request }.not_to change(organization.all_billing_entities, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:error_details][:code]).to eq(["value_is_mandatory"])
        end
      end
    end

    context "when the code is omitted" do
      let(:attributes) { super().except(:code) }

      it "rejects a missing code without creating an entity" do
        expect { request }.not_to change(organization.all_billing_entities, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details][:code]).to eq(["value_is_mandatory"])
      end
    end

    context "with a string false for EU tax management" do
      let(:attributes) { super().merge(country: "US", eu_tax_management: "false") }

      it "casts the string boolean before checking EU eligibility" do
        request

        expect(response).to have_http_status(:ok)
        expect(organization.all_billing_entities.find_by!(code: attributes[:code]).eu_tax_management).to be(false)
      end
    end

    [nil, ""].each do |eu_tax_management|
      context "with an empty EU tax management value #{eu_tax_management.inspect}" do
        let(:attributes) { super().merge(eu_tax_management:) }

        it "returns a validation error without creating an entity" do
          expect { request }.not_to change(organization.all_billing_entities, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:error_details][:eu_tax_management]).to eq(["value_is_invalid"])
        end
      end
    end

    %i[einvoicing finalize_zero_amount_invoice].each do |field|
      context "with a null #{field}" do
        let(:attributes) { super().merge(field => nil) }

        it "returns a validation error without creating an entity" do
          expect { request }.not_to change(organization.all_billing_entities, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:error_details]).to eq(field => ["value_is_invalid"])
        end
      end
    end

    context "with a code used by another organization" do
      before { create(:billing_entity, organization: create(:organization), code: attributes[:code]) }

      it "allows the same code in the current organization" do
        request

        expect(response).to have_http_status(:ok)
        expect(organization.all_billing_entities.find_by!(code: attributes[:code])).to be_present
      end
    end

    context "with a logo" do
      let(:logo) { "data:image/png;base64,#{Base64.strict_encode64(File.binread(Rails.root.join("spec/factories/images/logo.png")))}" }
      let(:attributes) { super().merge(logo:) }

      it "attaches the logo and returns its URL" do
        request

        expect(response).to have_http_status(:ok)
        expect(organization.all_billing_entities.find_by!(code: attributes[:code]).logo).to be_attached
        expect(json[:billing_entity][:logo_url]).to be_present
      end
    end

    context "without multi-entity access" do
      before { organization.update!(premium_integrations: []) }

      it "keeps the existing creation restriction" do
        expect { request }.not_to change(organization.all_billing_entities, :count)

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "with an invalid logo" do
      let(:attributes) { super().merge(logo: "invalid") }

      it "returns a validation error without creating an entity" do
        expect { request }.not_to change(organization.all_billing_entities, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details][:logo]).to eq(["value_is_invalid"])
      end
    end

    context "with expansions" do
      subject(:request) do
        post_with_token(organization, "/api/v2/billing_entities?expands[]=taxes", {billing_entity: attributes})
      end

      it "rejects expansion before creating an entity" do
        expect { request }.not_to change(organization.all_billing_entities, :count)

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("expand_not_supported")
      end
    end

    context "with an invalid name" do
      let(:attributes) { super().merge(name: "") }

      it "returns a validation error" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details][:name]).to eq(["value_is_mandatory"])
      end
    end

    context "with invalid document numbering" do
      let(:attributes) { super().merge(document_numbering: "invalid") }

      it "returns 422 instead of raising an enum assignment error" do
        expect { request }.not_to change(organization.all_billing_entities, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details][:document_numbering]).to eq(["value_is_invalid"])
      end
    end

    [nil, [], "invalid"].each do |wrapper|
      context "with a #{wrapper.inspect} wrapper" do
        subject(:request) { post_with_token(organization, "/api/v2/billing_entities", {billing_entity: wrapper}) }

        it "returns the v2 missing parameter error" do
          request

          expect(response).to have_http_status(:bad_request)
          expect(json[:code]).to eq("missing_parameter")
        end
      end
    end

    [{document_locale: "de"}, [{document_locale: "de"}]].each do |billing_configuration|
      context "with the old billing configuration wrapper #{billing_configuration.inspect}" do
        let(:attributes) { super().merge(billing_configuration:) }

        it "ignores the wrapper and uses the flat fields" do
          request

          expect(response).to have_http_status(:ok)
          expect(organization.all_billing_entities.find_by!(code: attributes[:code]).document_locale).to eq("fr")
        end
      end
    end
  end

  %i[put patch].each do |http_method|
    describe "#{http_method.upcase} /api/v2/billing_entities/:code" do
      subject(:request) do
        public_send(:"#{http_method}_with_token", organization, "/api/v2/billing_entities/#{billing_entity.code}", {billing_entity: attributes})
      end

      let(:billing_entity) { create(:billing_entity, organization:, code: "entity.eu", net_payment_term: 30) }
      let(:attributes) { {name: "Updated", invoice_footer: "Updated footer", document_locale: "fr"} }

      include_examples "requires API permission", "billing_entity", "write"

      it "updates the entity without requiring its code in the body" do
        request

        expect(response).to have_http_status(:ok)
        expect(billing_entity.reload).to have_attributes(name: "Updated", invoice_footer: "Updated footer", document_locale: "fr", net_payment_term: 30)
        expect(json[:billing_entity].keys & %i[billing_configuration net_payment_term taxes selected_invoice_custom_sections]).to eq([])
      end

      context "with expansions" do
        subject(:request) do
          public_send(:"#{http_method}_with_token", organization, "/api/v2/billing_entities/#{billing_entity.code}?expands[]=taxes", {billing_entity: attributes})
        end

        it "rejects expansions before updating the entity" do
          expect { request }.not_to change { billing_entity.reload.attributes }

          expect(response).to have_http_status(:bad_request)
          expect(json[:error_details]).to eq(expands: {reason: "action_not_expandable", invalid_values: ["taxes"]})
        end
      end

      context "with only immutable or removed parameters" do
        let(:attributes) { {code: "renamed", net_payment_term: 99} }

        it "keeps the existing code and payment term" do
          request

          expect(response).to have_http_status(:ok)
          expect(billing_entity.reload).to have_attributes(code: "entity.eu", net_payment_term: 30)
        end
      end

      context "with an invalid enum" do
        let(:attributes) { {name: "Must not change", periodic_invoice_issuing_date_anchor: "invalid"} }

        it "returns a validation error under the REST field name without updating the entity" do
          expect { request }.not_to change { billing_entity.reload.attributes }

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:error_details]).to eq(periodic_invoice_issuing_date_anchor: ["value_is_invalid"])
        end
      end

      context "with a missing entity" do
        let(:billing_entity) { build_stubbed(:billing_entity) }

        it "does not create an entity" do
          expect { request }.not_to change(BillingEntity, :count)

          expect(response).to be_not_found_error("billing_entity")
        end
      end

      context "with flat invoice issuing settings" do
        let(:billing_entity) { create(:billing_entity, organization:, name: "Existing", net_payment_term: 30) }
        let(:attributes) do
          {
            invoice_grace_period: 5,
            periodic_invoice_issuing_date_anchor: "current_period_end",
            periodic_invoice_issuing_date_adjustment: "keep_anchor"
          }
        end

        it "updates the supplied settings and preserves omitted fields" do
          request

          expect(response).to have_http_status(:ok)
          expect(billing_entity.reload).to have_attributes(
            invoice_grace_period: 5,
            subscription_invoice_issuing_date_anchor: "current_period_end",
            subscription_invoice_issuing_date_adjustment: "keep_anchor",
            name: "Existing",
            net_payment_term: 30
          )
          expect(json[:billing_entity]).to include(attributes)
        end
      end

      context "when clearing the invoice footer" do
        let(:billing_entity) { create(:billing_entity, organization:, invoice_footer: "Old footer", document_locale: "fr") }
        let(:attributes) { {invoice_footer: nil} }

        it "preserves the explicit null and leaves omitted settings unchanged" do
          request

          expect(response).to have_http_status(:ok)
          expect(billing_entity.reload).to have_attributes(invoice_footer: nil, document_locale: "fr")
          expect(json[:billing_entity][:invoice_footer]).to be_nil
        end
      end

      context "with only the old billing configuration wrapper" do
        let(:attributes) { {billing_configuration: {invoice_footer: "Must not change"}} }

        it "ignores the nested fields" do
          expect { request }.not_to change { billing_entity.reload.invoice_footer }

          expect(response).to have_http_status(:ok)
        end
      end

      context "with an entity belonging to another organization" do
        let(:billing_entity) { create(:billing_entity, organization: create(:organization)) }

        it "does not modify the foreign entity" do
          expect { request }.not_to change { billing_entity.reload.attributes }

          expect(response).to be_not_found_error("billing_entity")
        end
      end

      context "with tax codes" do
        let(:tax) { create(:tax, organization:) }
        let(:attributes) { {tax_codes: [tax.code]} }

        it "assigns the organization's tax" do
          request

          expect(response).to have_http_status(:ok)
          expect(billing_entity.reload.taxes).to eq([tax])
        end

        [123, false].each do |invalid_code|
          context "with a non-string tax code #{invalid_code.inspect}" do
            let(:attributes) { {name: "Must not change", tax_codes: [tax.code, invalid_code]} }

            before { create(:billing_entity_applied_tax, organization:, billing_entity:, tax:) }

            it "rejects non-string tax codes without changing the entity or its taxes" do
              expect { request }.not_to change { billing_entity.reload.attributes }

              expect(response).to have_http_status(:unprocessable_content)
              expect(json[:error_details][:tax_codes]).to eq(["value_is_invalid"])
              expect(billing_entity.reload.taxes).to eq([tax])
            end
          end
        end

        context "with a foreign tax" do
          let(:tax) { create(:tax, organization: create(:organization)) }

          it "does not assign the foreign tax" do
            request

            expect(response).to be_not_found_error("tax")
            expect(billing_entity.reload.taxes).to be_empty
          end
        end

        context "with an empty list" do
          let(:attributes) { {tax_codes: []} }

          before { create(:billing_entity_applied_tax, organization:, billing_entity:, tax:) }

          it "removes the existing tax assignment" do
            request

            expect(response).to have_http_status(:ok)
            expect(billing_entity.reload.taxes).to be_empty
          end
        end
      end

      context "with a string false for EU tax management" do
        let(:billing_entity) { create(:billing_entity, organization:, country: "US", eu_tax_management: true) }
        let(:attributes) { {eu_tax_management: "false"} }

        it "casts the string boolean before checking EU eligibility" do
          request

          expect(response).to have_http_status(:ok)
          expect(billing_entity.reload.eu_tax_management).to be(false)
        end
      end

      context "with a null EU tax management value" do
        let(:attributes) { {eu_tax_management: nil} }

        it "returns a validation error without updating the entity" do
          expect { request }.not_to change { billing_entity.reload.attributes }

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:error_details][:eu_tax_management]).to eq(["value_is_invalid"])
        end
      end

      %i[einvoicing finalize_zero_amount_invoice].each do |field|
        [nil, ""].each do |value|
          context "with #{field} set to #{value.inspect}" do
            let(:attributes) { {field => value} }

            it "returns a validation error without updating the entity" do
              expect { request }.not_to change { billing_entity.reload.attributes }

              expect(response).to have_http_status(:unprocessable_content)
              expect(json[:error_details]).to eq(field => ["value_is_invalid"])
            end
          end
        end
      end

      context "with invoice custom section codes" do
        let(:section) { create(:invoice_custom_section, organization:) }
        let(:foreign_section) { create(:invoice_custom_section, organization: create(:organization), code: section.code) }
        let(:attributes) { {invoice_custom_section_codes: [section.code]} }

        before { foreign_section }

        it "assigns only the current organization's section even when codes overlap" do
          request

          expect(response).to have_http_status(:ok)
          expect(billing_entity.reload.selected_invoice_custom_sections).to eq([section])
          expect(foreign_section.billing_entity_applied_invoice_custom_sections).to be_empty
        end

        context "with an empty list" do
          let(:attributes) { {invoice_custom_section_codes: []} }

          before { create(:billing_entity_applied_invoice_custom_section, organization:, billing_entity:, invoice_custom_section: section) }

          it "removes the selected sections" do
            request

            expect(response).to have_http_status(:ok)
            expect(billing_entity.reload.selected_invoice_custom_sections).to be_empty
          end
        end

        context "with a foreign-only code" do
          let(:attributes) { {invoice_custom_section_codes: [foreign_section.code]} }
          let(:foreign_section) { create(:invoice_custom_section, organization: create(:organization)) }

          it "does not attach the foreign section" do
            request

            expect(response).to have_http_status(:ok)
            expect(billing_entity.reload.selected_invoice_custom_sections).to be_empty
          end
        end
      end
    end
  end

  describe "GET /api/v2/billing_entities/:code" do
    subject(:request) { get_with_token(organization, "/api/v2/billing_entities/#{billing_entity.code}", parameters) }

    let(:billing_entity) { create(:billing_entity, organization:, code: "entity.eu") }
    let(:parameters) { {} }

    include_examples "requires API permission", "billing_entity", "read"

    it "returns a flat entity without relationships" do
      request

      expect(response).to have_http_status(:ok)
      expect(json[:billing_entity][:lago_id]).to eq(billing_entity.id)
      expect(json[:billing_entity].keys & %i[billing_configuration net_payment_term taxes selected_invoice_custom_sections]).to eq([])
      expect(json[:billing_entity][:created_at]).to eq(billing_entity.created_at.iso8601(6))
      expect(json[:billing_entity][:updated_at]).to eq(billing_entity.updated_at.iso8601(6))
      expect(json[:billing_entity][:deleted_at]).to be_nil
    end

    context "with expansions" do
      let(:parameters) { {expands: %w[taxes selected_invoice_custom_sections]} }
      let(:tax) { create(:tax, organization:) }
      let(:section) { create(:invoice_custom_section, organization:) }

      before do
        create(:billing_entity_applied_tax, organization:, billing_entity:, tax:)
        create(:billing_entity_applied_invoice_custom_section, organization:, billing_entity:, invoice_custom_section: section)
      end

      it "returns the requested relationships" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:billing_entity][:taxes].pluck(:lago_id)).to eq([tax.id])
        expect(json[:billing_entity][:taxes].first).not_to have_key(:customers_count)
        expect(json[:billing_entity][:selected_invoice_custom_sections].pluck(:lago_id)).to eq([section.id])
        expect(json[:billing_entity][:selected_invoice_custom_sections].first).to have_key(:deleted_at)
        expect(json[:billing_entity][:selected_invoice_custom_sections].first).not_to have_key(:organization_id)
      end

      context "with whitespace, blanks and repeated names" do
        let(:parameters) { {expands: [" selected_invoice_custom_sections ", "taxes", "taxes", ""]} }

        it "normalizes the names and renders relationships in declaration order" do
          request

          expect(response).to have_http_status(:ok)
          expect(json[:billing_entity].keys.last(2)).to eq(%i[taxes selected_invoice_custom_sections])
          expect(json[:billing_entity][:taxes].pluck(:lago_id)).to eq([tax.id])
          expect(json[:billing_entity][:selected_invoice_custom_sections].pluck(:lago_id)).to eq([section.id])
        end
      end
    end

    context "with an unsupported expansion" do
      let(:parameters) { {expands: ["organization"]} }

      it "returns the v2 expansion error" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_expand")
        expect(json[:error_details]).to eq(expands: {
          invalid_values: ["organization"], allowed_values: %w[taxes selected_invoice_custom_sections]
        })
      end
    end

    context "with malformed expansions" do
      let(:parameters) { {expands: {taxes: true}} }

      it "returns a malformed expansion error" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_expand")
        expect(json[:error_details]).to eq(expands: {reason: "malformed", allowed_values: %w[taxes selected_invoice_custom_sections]})
      end
    end

    ["taxes", {"0" => "taxes"}].each do |expands|
      context "with expands as #{expands.inspect}" do
        let(:parameters) { {expands:} }

        it "requires an array" do
          request

          expect(response).to have_http_status(:bad_request)
          expect(json[:error_details]).to eq(expands: {reason: "malformed", allowed_values: %w[taxes selected_invoice_custom_sections]})
        end
      end
    end

    context "with an archived entity" do
      let(:billing_entity) { create(:billing_entity, :archived, organization:) }

      it "keeps the entity accessible by code" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:billing_entity][:lago_id]).to eq(billing_entity.id)
      end
    end

    context "with a deleted entity" do
      let(:billing_entity) { create(:billing_entity, :deleted, organization:) }

      it "returns not found" do
        request

        expect(response).to be_not_found_error("billing_entity")
      end
    end

    context "with a foreign entity" do
      let(:billing_entity) { create(:billing_entity, organization: create(:organization)) }

      it "does not expose the foreign entity" do
        request

        expect(response).to be_not_found_error("billing_entity")
      end
    end
  end

  describe "GET /api/v2/billing_entities" do
    subject(:request) { get_with_token(organization, "/api/v2/billing_entities", parameters) }

    let(:parameters) { {} }

    include_examples "requires API permission", "billing_entity", "read"

    it_behaves_like "a cursor paginated v2 endpoint", collection: :billing_entities, model: BillingEntity do
      let(:paginated_path) { "/api/v2/billing_entities" }
      let(:create_paginated_record) { ->(created_at) { create(:billing_entity, organization:, created_at:) } }
    end

    context "with foreign, archived and deleted entities", bullet: {n_plus_one_query: true, unused_eager_loading: false} do
      let(:billing_entity) { create(:billing_entity, organization:) }

      before do
        billing_entity
        create(:billing_entity, organization: create(:organization))
        create(:billing_entity, :deleted, organization:)
        create(:billing_entity, :archived, organization:)
      end

      it "lists only active entities of the current organization" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:billing_entities].pluck(:lago_id)).to match_array([billing_entity.id, organization.default_billing_entity.id])
        expect(json[:billing_entities].find { it[:lago_id] == organization.default_billing_entity.id }[:is_default]).to be(true)
        expect(json[:billing_entities].first.keys & %i[taxes selected_invoice_custom_sections net_payment_term]).to eq([])
      end
    end

    context "with expansions and an invalid cursor" do
      let(:parameters) { {expands: ["taxes"], after: "invalid"} }

      it "rejects expansion before checking pagination" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("expand_not_supported")
      end
    end

    context "without product catalog", product_catalog: false do
      it "returns feature unavailable" do
        request

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end
end
