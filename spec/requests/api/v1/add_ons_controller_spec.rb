# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::AddOnsController, type: :request do
  let(:organization) { create(:organization) }
  let(:tax) { create(:tax, organization:) }

  describe "create" do
    let(:create_params) do
      {
        name: "add_on1",
        invoice_display_name: "Addon 1 invoice name",
        code: "add_on1_code",
        amount_cents: 123,
        amount_currency: "EUR",
        description: "description",
        tax_codes: [tax.code]
      }
    end

    it "creates a add-on" do
      post_with_token(organization, "/api/v1/add_ons", {add_on: create_params})

      expect(response).to have_http_status(:success)

      expect(json[:add_on][:lago_id]).to be_present
      expect(json[:add_on][:code]).to eq(create_params[:code])
      expect(json[:add_on][:name]).to eq(create_params[:name])
      expect(json[:add_on][:invoice_display_name]).to eq(create_params[:invoice_display_name])
      expect(json[:add_on][:created_at]).to be_present
      expect(json[:add_on][:taxes].map { |t| t[:code] }).to contain_exactly(tax.code)
    end
  end

  describe "update" do
    let(:add_on) { create(:add_on, organization:) }
    let(:add_on_applied_tax) { create(:add_on_applied_tax, add_on:, tax:) }
    let(:code) { "add_on_code" }
    let(:tax2) { create(:tax, organization:) }
    let(:update_params) do
      {
        name: "add_on1",
        invoice_display_name: "Addon 1 updated invoice name",
        code:,
        amount_cents: 123,
        amount_currency: "EUR",
        description: "description",
        tax_codes: [tax2.code]
      }
    end

    before { add_on_applied_tax }

    it "updates an add-on" do
      put_with_token(
        organization,
        "/api/v1/add_ons/#{add_on.code}",
        {add_on: update_params}
      )

      expect(response).to have_http_status(:success)
      expect(json[:add_on][:lago_id]).to eq(add_on.id)
      expect(json[:add_on][:code]).to eq(update_params[:code])
      expect(json[:add_on][:invoice_display_name]).to eq(update_params[:invoice_display_name])
      expect(json[:add_on][:taxes].map { |t| t[:code] }).to contain_exactly(tax2.code)
    end

    context "when add-on does not exist" do
      it "returns not_found error" do
        put_with_token(organization, "/api/v1/add_ons/invalid", {add_on: update_params})

        expect(response).to have_http_status(:not_found)
      end
    end

    context "when add-on code already exists in organization scope (validation error)" do
      let(:add_on2) { create(:add_on, organization:) }
      let(:code) { add_on2.code }

      before { add_on2 }

      it "returns unprocessable_entity error" do
        put_with_token(
          organization,
          "/api/v1/add_ons/#{add_on.code}",
          {add_on: update_params}
        )

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "show" do
    let(:add_on) { create(:add_on, organization:) }

    it "returns a add-on" do
      get_with_token(
        organization,
        "/api/v1/add_ons/#{add_on.code}"
      )

      expect(response).to have_http_status(:success)
      expect(json[:add_on][:lago_id]).to eq(add_on.id)
      expect(json[:add_on][:invoice_display_name]).to eq(add_on.invoice_display_name)
      expect(json[:add_on][:code]).to eq(add_on.code)
    end

    context "when add-on does not exist" do
      it "returns not found" do
        get_with_token(organization, "/api/v1/add_ons/555")

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "destroy" do
    let(:add_on) { create(:add_on, organization:) }

    before { add_on }

    it "deletes a add-on" do
      expect { delete_with_token(organization, "/api/v1/add_ons/#{add_on.code}") }
        .to change(AddOn, :count).by(-1)
    end

    it "returns deleted add-on" do
      delete_with_token(organization, "/api/v1/add_ons/#{add_on.code}")

      expect(response).to have_http_status(:success)
      expect(json[:add_on][:lago_id]).to eq(add_on.id)
      expect(json[:add_on][:code]).to eq(add_on.code)
    end

    context "when add-on does not exist" do
      it "returns not_found error" do
        delete_with_token(organization, "/api/v1/add_ons/invalid")

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "index" do
    let(:add_on) { create(:add_on, organization:) }
    let(:add_on_applied_tax) { create(:add_on_applied_tax, add_on:, tax:) }

    before { add_on_applied_tax }

    it "returns add-ons" do
      get_with_token(organization, "/api/v1/add_ons")

      expect(response).to have_http_status(:success)
      expect(json[:add_ons].count).to eq(1)
      expect(json[:add_ons].first[:lago_id]).to eq(add_on.id)
      expect(json[:add_ons].first[:code]).to eq(add_on.code)
      expect(json[:add_ons].first[:invoice_display_name]).to eq(add_on.invoice_display_name)
      expect(json[:add_ons].first[:taxes].map { |t| t[:code] }).to contain_exactly(tax.code)
    end

    context "with pagination" do
      let(:add_on2) { create(:add_on, organization:) }

      before { add_on2 }

      it "returns add-ons with correct meta data" do
        get_with_token(organization, "/api/v1/add_ons?page=1&per_page=1")

        expect(response).to have_http_status(:success)
        expect(json[:add_ons].count).to eq(1)
        expect(json[:meta][:current_page]).to eq(1)
        expect(json[:meta][:next_page]).to eq(2)
        expect(json[:meta][:prev_page]).to eq(nil)
        expect(json[:meta][:total_pages]).to eq(2)
        expect(json[:meta][:total_count]).to eq(2)
      end
    end
  end
end
