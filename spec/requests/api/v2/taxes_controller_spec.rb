# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::TaxesController do
  let_it_be(:organization, refind: true) { create_default(:organization) }

  describe "POST /api/v2/taxes" do
    subject(:request) { post_with_token(organization, "/api/v2/taxes", {tax: create_params}) }

    let(:create_params) { {name: "VAT", code: "vat", description: "Standard VAT", rate: 20} }

    include_examples "requires API permission", "tax", "write"

    it "creates a tax" do
      expect { request }.to change(organization.taxes, :count).by(1)

      expect(response).to have_http_status(:ok)
      tax = organization.taxes.find_by!(code: "vat")
      expect(tax).to have_attributes(name: "VAT", description: "Standard VAT", rate: 20)
      expect(json[:tax][:lago_id]).to eq(tax.id)
      expect(response.headers["X-Lago-Endpoint-Status"]).to eq("beta")
    end

    context "with applied_to_organization" do
      let(:create_params) { super().merge(applied_to_organization: true) }

      it "ignores the parameter without assigning the tax to the default billing entity" do
        request

        expect(response).to have_http_status(:ok)
        tax = organization.taxes.find_by!(code: "vat")
        expect(tax.applied_to_organization).to be(false)
        expect(tax.billing_entities).to be_empty
      end
    end

    context "with an invalid payload" do
      let(:create_params) { super().merge(name: "") }

      it "returns a validation error" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details][:name]).to eq(["value_is_mandatory"])
      end
    end

    context "when the tax wrapper is missing" do
      subject(:request) { post_with_token(organization, "/api/v2/taxes", create_params) }

      it "returns the v2 missing parameter error" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(
          status: 400,
          error: "Bad Request",
          code: "missing_parameter",
          error_details: {tax: {reason: "missing"}}
        )
      end
    end

    context "when the code is already used" do
      before { create(:tax, organization:, code: create_params[:code]) }

      it "returns a validation error" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details][:code]).to eq(["value_already_exist"])
      end
    end
  end

  %i[put patch].each do |http_method|
    describe "#{http_method.upcase} /api/v2/taxes/:code" do
      subject(:request) do
        public_send(:"#{http_method}_with_token", organization, "/api/v2/taxes/#{tax.code}", {tax: update_params})
      end

      let(:tax) { create(:tax, organization:) }
      let(:update_params) { {code: "updated-vat", name: "Reduced VAT", description: "Reduced rate", rate: 5} }

      include_examples "requires API permission", "tax", "write"

      it "updates the tax" do
        request

        expect(response).to have_http_status(:ok)
        expect(tax.reload).to have_attributes(**update_params)
        expect(json[:tax][:lago_id]).to eq(tax.id)
      end

      context "with applied_to_organization true" do
        let(:update_params) { super().merge(applied_to_organization: true) }

        it "ignores the parameter without assigning the tax to the default billing entity" do
          request

          expect(response).to have_http_status(:ok)
          expect(tax.reload).to have_attributes(name: "Reduced VAT", applied_to_organization: false)
          expect(tax.billing_entities).to be_empty
        end
      end

      context "with applied_to_organization false on an assigned tax" do
        let(:tax) { create(:tax, :applied_to_billing_entity, organization:, applied_to_organization: true) }
        let(:update_params) { super().merge(applied_to_organization: false) }

        it "ignores the parameter without removing the existing assignment" do
          request

          expect(response).to have_http_status(:ok)
          expect(tax.reload).to have_attributes(name: "Reduced VAT", applied_to_organization: true)
          expect(tax.billing_entities).to eq([organization.default_billing_entity])
        end
      end

      context "when the tax does not exist" do
        let(:tax) { build_stubbed(:tax) }

        it "returns a not found error" do
          request

          expect(response).to be_not_found_error("tax")
        end
      end

      context "when the tax belongs to another organization" do
        let(:other_organization) { create(:organization) }
        let(:tax) { create(:tax, organization: other_organization) }

        it "does not update the foreign tax" do
          expect { request }.not_to change { tax.reload.attributes }

          expect(response).to be_not_found_error("tax")
        end
      end
    end
  end

  describe "GET /api/v2/taxes/:code" do
    subject(:request) { get_with_token(organization, "/api/v2/taxes/#{tax.code}") }

    let(:tax) { create(:tax, :applied_to_billing_entity, organization:) }

    include_examples "requires API permission", "tax", "read"

    it "returns a flat tax without assignments or relationship counts" do
      request

      expect(response).to have_http_status(:ok)
      expect(json[:tax]).to eq(
        lago_id: tax.id,
        name: tax.name,
        code: tax.code,
        rate: tax.rate,
        description: tax.description,
        created_at: tax.created_at.iso8601,
        updated_at: tax.updated_at.iso8601,
        deleted_at: nil
      )
    end

    context "when the tax does not exist" do
      let(:tax) { build_stubbed(:tax) }

      it "returns a not found error" do
        request

        expect(response).to be_not_found_error("tax")
      end
    end

    context "when the tax belongs to another organization" do
      let(:other_organization) { create(:organization) }
      let(:tax) { create(:tax, organization: other_organization) }

      it "does not expose the foreign tax" do
        request

        expect(response).to be_not_found_error("tax")
      end
    end
  end

  describe "GET /api/v2/taxes" do
    subject(:request) { get_with_token(organization, "/api/v2/taxes", {limit: 1}) }

    before do
      create(:tax, organization:, name: "First tax", code: "first", created_at: 2.days.ago)
      create(:tax, organization:, name: "Second tax", code: "second", created_at: 1.day.ago)
      create(:tax, organization: create(:organization), name: "Foreign tax")
      create(:tax, organization:, deleted_at: Time.current)
    end

    include_examples "requires API permission", "tax", "read"

    it "returns the newest tax and a cursor, excluding foreign and deleted taxes" do
      request

      expect(response).to have_http_status(:ok)
      expect(json[:taxes].pluck(:code)).to eq(["second"])
      expect(json[:taxes].first.keys).to match_array(%i[lago_id name code rate description created_at updated_at deleted_at])
      expect(json[:meta][:next_cursor]).to be_present
      expect(json[:meta][:prev_cursor]).to be_nil
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :taxes, model: Tax do
      let(:paginated_path) { "/api/v2/taxes" }
      let(:create_paginated_record) { ->(created_at) { create(:tax, organization:, created_at:) } }
    end

    context "without product catalog enabled", product_catalog: false do
      it "requires the product catalog" do
        request

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
        expect(organization.reload).not_to be_product_catalog_enabled
      end
    end

    context "without an API key" do
      it "authenticates before validating pagination" do
        get "/api/v2/taxes", params: {limit: 0}

        expect(response).to have_http_status(:unauthorized)
        expect(response.headers["X-Lago-Endpoint-Status"]).to eq("beta")
      end
    end
  end

  describe "when the product catalog is disabled", product_catalog: false do
    let(:tax) { create(:tax, organization:) }

    before { tax }

    [
      [:get, "/api/v2/taxes"],
      [:post, "/api/v2/taxes"],
      [:get, "/api/v2/taxes/:code"],
      [:put, "/api/v2/taxes/:code"],
      [:patch, "/api/v2/taxes/:code"],
      [:delete, "/api/v2/taxes/:code"]
    ].each do |http_method, path|
      context "when using #{http_method.upcase} #{path}" do
        subject(:request) do
          public_send(
            :"#{http_method}_with_token",
            organization,
            path.sub(":code", tax.code),
            {expand: "counts", limit: 0, tax: {name: "Changed tax", code: "changed", rate: 5}}
          )
        end

        it "checks the feature before expansion, pagination or writes" do
          expect { request }.not_to change { tax.reload.attributes }

          expect(response).to have_http_status(:forbidden)
          expect(json[:code]).to eq("feature_unavailable")
        end
      end
    end
  end

  describe "expansion parameters" do
    subject(:request) { get_with_token(organization, "/api/v2/taxes/#{tax.code}", request_params) }

    let(:tax) { create(:tax, organization:) }
    let(:request_params) { {expand: "billing_entities"} }

    before { tax }

    it "rejects expansions because taxes have no expandable relationships" do
      request

      expect(response).to have_http_status(:bad_request)
      expect(json).to eq(
        status: 400,
        error: "Bad Request",
        code: "expand_not_supported",
        error_details: {expand: {reason: "not_expandable", invalid_values: ["billing_entities"]}}
      )
      expect(response.headers["X-Lago-Endpoint-Status"]).to eq("beta")
    end

    ["counts", "deleted_at", "billing_entities.taxes", "counts,deleted_at"].each do |value|
      context "with expand=#{value}" do
        let(:request_params) { {expand: value} }

        it "rejects the value without exposing internal options or nested expansions" do
          request

          expect(response).to have_http_status(:bad_request)
          expect(json[:code]).to eq("expand_not_supported")
          expect(json[:error_details]).to eq(expand: {reason: "not_expandable", invalid_values: [value]})
        end
      end
    end

    [[" counts ", "counts", "", "deleted_at"], {"0" => " counts ", "1" => "counts", "2" => "", "3" => "deleted_at"}].each do |value|
      context "with expand in #{value.class} form" do
        let(:request_params) { {expand: value} }

        it "trims and deduplicates the rejected values" do
          request

          expect(response).to have_http_status(:bad_request)
          expect(json[:error_details]).to eq(expand: {reason: "not_expandable", invalid_values: %w[counts deleted_at]})
        end
      end
    end

    [nil, " ", [], ["", " "], {"0" => " "}].each do |value|
      context "with an empty expand #{value.inspect}" do
        let(:request_params) { {expand: value} }

        it "returns the normal flat response" do
          request

          expect(response).to have_http_status(:ok)
          expect(json[:tax].keys).to match_array(%i[lago_id name code rate description created_at updated_at deleted_at])
        end
      end
    end

    [{"name" => "taxes"}, [{"name" => "taxes"}], {"0" => {"name" => "taxes"}}, {"0" => ["taxes"]}].each do |value|
      context "with malformed expand #{value.inspect}" do
        let(:request_params) { {expand: value} }

        it "returns an invalid_expand error" do
          request

          expect(response).to have_http_status(:bad_request)
          expect(json).to eq(
            status: 400,
            error: "Bad Request",
            code: "invalid_expand",
            error_details: {expand: {reason: "malformed", allowed_values: []}}
          )
        end
      end
    end

    %i[post put patch delete].each do |http_method|
      context "when using #{http_method.upcase}" do
        subject(:request) do
          path = (http_method == :post) ? "/api/v2/taxes" : "/api/v2/taxes/#{tax.code}"
          public_send(:"#{http_method}_with_token", organization, path, request_params)
        end

        let(:request_params) { {expand: "counts", tax: {name: "Changed tax", code: "changed", rate: 5}} }

        it "rejects expansion before performing the write" do
          expect { request }.not_to change { tax.reload.attributes }

          expect(response).to have_http_status(:bad_request)
          expect(json[:code]).to eq("expand_not_supported")
        end

        context "with a non-string JSON value" do
          let(:request_params) { {expand: [true]} }

          it "rejects the malformed value" do
            request

            expect(response).to have_http_status(:bad_request)
            expect(json[:code]).to eq("invalid_expand")
          end
        end
      end
    end

    context "when listing taxes with invalid pagination" do
      subject(:request) { get_with_token(organization, "/api/v2/taxes", request_params) }

      let(:request_params) { {expand: "counts", limit: 0} }

      it "validates expansion before pagination" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("expand_not_supported")
      end
    end

    context "with a scalar non-string JSON value" do
      subject(:request) { post_with_token(organization, "/api/v2/taxes", {expand: false}) }

      it "returns an invalid_expand error before checking the tax wrapper" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_expand")
      end
    end

    context "when the tax does not exist" do
      subject(:request) { get_with_token(organization, "/api/v2/taxes/missing", request_params) }

      it "validates expansion before looking up the tax" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("expand_not_supported")
      end
    end

    context "without an API key" do
      subject(:request) { get "/api/v2/taxes", params: request_params }

      it "authenticates before validating expansion" do
        request

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "without read permission", :premium do
      before do
        organization.update!(premium_integrations: organization.premium_integrations | ["api_permissions"])
        api_key = organization.api_keys.first
        api_key.update!(permissions: api_key.permissions.merge("tax" => ["write"]))
      end

      it "authorizes before validating expansion" do
        request

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("read_action_not_allowed_for_tax")
      end
    end
  end

  describe "DELETE /api/v2/taxes/:code" do
    subject(:request) { delete_with_token(organization, "/api/v2/taxes/#{tax.code}") }

    let(:tax) { create(:tax, organization:) }

    include_examples "requires API permission", "tax", "write"

    it "soft deletes the tax" do
      request

      expect(response).to have_http_status(:ok)
      expect(tax.reload).to be_discarded
      expect(json[:tax][:lago_id]).to eq(tax.id)
      expect(json[:tax][:deleted_at]).to eq(tax.deleted_at.iso8601)
    end

    context "when the tax does not exist" do
      let(:tax) { build_stubbed(:tax) }

      it "returns a not found error" do
        request

        expect(response).to be_not_found_error("tax")
      end
    end

    context "when the tax belongs to another organization" do
      let(:other_organization) { create(:organization) }
      let(:tax) { create(:tax, organization: other_organization) }

      it "does not discard the foreign tax" do
        request

        expect(response).to be_not_found_error("tax")
        expect(tax.reload).not_to be_discarded
      end
    end
  end
end
