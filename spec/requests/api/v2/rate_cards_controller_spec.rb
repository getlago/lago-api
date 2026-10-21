# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::RateCardsController do
  let(:organization) { create(:organization) }
  let(:product) { create(:product, organization:) }
  let(:flat_keys) do
    %i[
      lago_id product_code product_filter_code name code description currency billing_timing proration display_on_invoice
      regroup_paid_fees applied_pricing_unit_code rates_count created_at updated_at deleted_at
    ]
  end

  describe "POST /api/v2/rate_cards" do
    subject { post_with_token(organization, "/api/v2/rate_cards", {rate_card: create_params}) }

    let(:create_params) do
      {
        product_code: product.code,
        name: "Standard",
        code: "standard",
        currency: "EUR"
      }
    end

    include_examples "requires API permission", "rate_card", "write"

    it "creates the rate card and returns it flat" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_card][:lago_id]).to be_present
      expect(json[:rate_card][:product_code]).to eq(product.code)
      expect(json[:rate_card][:code]).to eq("standard")
      expect(json[:rate_card][:currency]).to eq("EUR")
      expect(json[:rate_card].keys).to eq(flat_keys)
      expect(RateCard.find(json[:rate_card][:lago_id]).taxes).to be_empty
    end

    context "with expand" do
      subject { post_with_token(organization, "/api/v2/rate_cards?expand[]=taxes", {rate_card: create_params}) }

      it "creates nothing, as only show expands" do
        expect { subject }.not_to change(RateCard, :count)

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("expand_not_supported")
        expect(json[:error_details]).to eq(expand: {reason: "action_not_expandable", invalid_values: %w[taxes]})
      end
    end

    context "with taxes" do
      let(:tax1) { create(:tax, organization:) }
      let(:tax2) { create(:tax, organization:) }

      before { create_params[:tax_codes] = [tax1.code, tax2.code] }

      it "applies the taxes, which a show then expands" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:rate_card]).not_to have_key(:taxes)

        get_with_token(organization, "/api/v2/rate_cards/standard", {expand: %w[taxes]})

        expect(json[:rate_card][:taxes].pluck(:code)).to match_array([tax1.code, tax2.code])
      end

      context "when a tax belongs to another organization" do
        let(:other_tax) { create(:tax) }

        before { create_params[:tax_codes] = [other_tax.code] }

        it "returns a tax not found error" do
          expect { subject }.not_to change(RateCard, :count)

          expect(response).to be_not_found_error("tax")
        end
      end
    end

    context "when the product does not exist" do
      let(:create_params) { {product_code: "unknown", name: "Standard", code: "standard", currency: "EUR"} }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("product")
      end
    end

    context "with nested rates" do
      let(:create_params) do
        {
          product_code: product.code,
          name: "Standard",
          code: "standard",
          currency: "EUR",
          rates: [
            {
              code: "launch_price",
              effective_from: 1.minute.ago.to_date.iso8601,
              rate_model: "standard",
              rate_properties: {amount: "0.05"},
              billing_interval_count: 1,
              billing_interval_unit: "month"
            },
            {
              code: "standard_price",
              effective_from: 1.month.from_now.to_date.iso8601,
              rate_model: "standard",
              rate_properties: {amount: "0.07"},
              billing_interval_unit: "month"
            }
          ]
        }
      end

      it "creates the card with its rates in one call" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:rate_card][:rates_count]).to eq(2)
      end

      context "when a nested rate is invalid" do
        let(:create_params) do
          {
            product_code: product.code,
            name: "Standard",
            code: "standard",
            currency: "EUR",
            rates: [
              {code: "bad", effective_from: Time.current.to_date.iso8601, rate_model: "standard", rate_properties: {}, billing_interval_unit: "month"}
            ]
          }
        end

        it "rolls the whole create back with prefixed error keys" do
          subject

          expect(response).to have_http_status(:unprocessable_entity)
          expect(json.dig(:error_details, :"rates.rate_properties")).to be_present
          expect(RateCard.count).to eq(0)
        end
      end
    end

    context "with a product_filter_code" do
      let(:product_filter) { create(:product_filter, organization:, product:) }
      let(:create_params) do
        {
          product_code: product.code,
          product_filter_code: product_filter.code,
          name: "Standard",
          code: "standard",
          currency: "EUR"
        }
      end

      it "creates a filter-scoped rate card" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:rate_card][:product_filter_code]).to eq(product_filter.code)
      end

      context "when the filter does not exist" do
        let(:create_params) do
          {
            product_code: product.code,
            product_filter_code: "unknown",
            name: "Standard",
            code: "standard",
            currency: "EUR"
          }
        end

        it "returns a not found error" do
          subject

          expect(response).to be_not_found_error("product_filter")
        end
      end

      context "when the product_filter_code is null" do
        let(:create_params) do
          {
            product_code: product.code,
            product_filter_code: nil,
            name: "Standard",
            code: "standard",
            currency: "EUR"
          }
        end

        it "creates an unfiltered rate card" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:rate_card][:product_filter_code]).to be_nil
        end
      end
    end

    context "when the currency is invalid" do
      let(:create_params) { {product_code: product.code, name: "Standard", code: "standard", currency: "ABC"} }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when regroup_paid_fees is an invalid value" do
      let(:create_params) do
        {product_code: product.code, name: "Standard", code: "standard", currency: "EUR", regroup_paid_fees: "bogus"}
      end

      it "returns only the invalid-value error, not the pairing rule" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:error_details][:regroup_paid_fees]).to eq(["value_is_invalid"])
      end
    end

    context "when regroup_paid_fees is null" do
      let(:create_params) do
        {product_code: product.code, name: "Standard", code: "standard", currency: "EUR", regroup_paid_fees: nil}
      end

      it "round-trips as null instead of coercing to a string" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:rate_card][:regroup_paid_fees]).to be_nil
      end
    end
  end

  describe "PUT /api/v2/rate_cards/:code" do
    subject { put_with_token(organization, "/api/v2/rate_cards/#{rate_card.code}", {rate_card: update_params}) }

    let(:rate_card) { create(:rate_card, organization:, product:, name: "Before") }
    let(:update_params) { {name: "After"} }

    include_examples "requires API permission", "rate_card", "write"

    it "updates the rate card and returns it flat" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_card][:name]).to eq("After")
      expect(json[:rate_card].keys).to eq(flat_keys)
    end

    context "with taxes" do
      let(:tax1) { create(:tax, organization:) }
      let(:tax2) { create(:tax, organization:) }
      let(:update_params) { {tax_codes: [tax2.code]} }

      before { create(:rate_card_applied_tax, rate_card:, tax: tax1, organization:) }

      it "replaces the taxes" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:rate_card]).not_to have_key(:taxes)
        expect(rate_card.reload.taxes).to eq([tax2])
      end

      context "when tax codes are empty" do
        let(:update_params) { {tax_codes: []} }

        it "removes the tax override" do
          subject

          expect(response).to have_http_status(:success)
          expect(rate_card.reload.taxes).to be_empty
        end
      end

      context "when tax codes are null" do
        let(:update_params) { {tax_codes: nil} }

        it "keeps the existing tax" do
          subject

          expect(response).to have_http_status(:success)
          expect(rate_card.reload.taxes).to eq([tax1])
        end
      end

      context "when a tax belongs to another organization" do
        let(:other_tax) { create(:tax) }
        let(:update_params) { {tax_codes: [other_tax.code]} }

        it "returns a tax not found error and keeps the existing tax" do
          subject

          expect(response).to be_not_found_error("tax")
          expect(rate_card.reload.taxes).to eq([tax1])
        end
      end
    end

    context "when the rate card does not exist" do
      subject { put_with_token(organization, "/api/v2/rate_cards/unknown", {rate_card: update_params}) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("rate_card")
      end
    end
  end

  describe "GET /api/v2/rate_cards/:code" do
    subject { get_with_token(organization, "/api/v2/rate_cards/#{rate_card.code}", params) }

    let(:rate_card) { create(:rate_card, organization:, product:, product_filter:) }
    let(:product_filter) { nil }
    let(:params) { {} }
    let(:tax) { create(:tax, organization:) }
    let(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: rate_effective_from) }
    let(:rate_effective_from) { 1.day.ago.beginning_of_day }

    before do
      rate
      create(:rate_card_applied_tax, rate_card:, tax:)
    end

    include_examples "requires API permission", "rate_card", "read"

    it "returns the flat rate card, without its rates nor its taxes" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_card]).to eq(
        lago_id: rate_card.id,
        product_code: product.code,
        product_filter_code: nil,
        name: rate_card.name,
        code: rate_card.code,
        description: rate_card.description,
        currency: "EUR",
        billing_timing: "arrears",
        proration: false,
        display_on_invoice: true,
        regroup_paid_fees: nil,
        applied_pricing_unit_code: nil,
        rates_count: 1,
        created_at: rate_card.created_at.iso8601,
        updated_at: rate_card.updated_at.iso8601,
        deleted_at: nil
      )
    end

    context "with expand[]=active_rate" do
      let(:params) { {expand: %w[active_rate]} }

      # Pending, so that the rate above stays the active one.
      before { create(:rate_card_rate, organization:, rate_card:, effective_from: 1.month.from_now.beginning_of_day) }

      it "embeds the active rate as /rates lists it" do
        subject
        expanded = json[:rate_card]
        get_with_token(organization, "/api/v2/rate_cards/#{rate_card.code}/rates")

        expect(expanded.keys).to eq([*flat_keys, :active_rate])
        expect(expanded[:active_rate]).to eq(json[:rates].find { it[:lago_id] == rate.id })
        expect(expanded[:active_rate]).to include(status: "active")
      end

      context "when every rate is pending" do
        let(:rate_effective_from) { 1.day.from_now.beginning_of_day }

        it "renders it as null" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:rate_card]).to include(rates_count: 2, active_rate: nil)
        end
      end
    end

    context "with expand[]=taxes" do
      let(:params) { {expand: %w[taxes]} }
      let(:created_at) { Time.zone.parse("2026-09-28T10:00:00.000001Z") }
      let(:discarded_tax) { create(:tax, organization:) }
      # Taxes created after `tax` but linked before it, the first two at the same microsecond with
      # ascending ids, so that only the link order, then the id tiebreak, gives the list.
      let(:links) do
        tied_ids = Array.new(2) { SecureRandom.uuid }.sort
        [1, 1, 0].zip([*tied_ids, nil]).map do |age, id|
          create(:rate_card_applied_tax, **{id:}.compact, rate_card:, created_at: created_at - age.seconds)
        end
      end

      # Next to taxes that the rate card may not show.
      before do
        links
        create(:rate_card_applied_tax, rate_card:, tax: discarded_tax)
        # Discarded directly: Taxes::DestroyService would delete the link as well.
        discarded_tax.discard!
        create(:rate_card_applied_tax, rate_card: create(:rate_card, organization:))
      end

      it "embeds its kept taxes, latest linked first" do
        subject

        # `tax` is linked by the outer before, at the current time.
        listed = [tax, *links.reverse.map(&:tax)]

        expect(json[:rate_card][:taxes]).to eq(listed.map { V2::TaxSerializer.new(it).serialize })
        expect(json[:rate_card].keys).to eq([*flat_keys, :taxes])
      end
    end

    context "with expand[]=rates" do
      let(:params) { {expand: %w[rates]} }

      # Appended out of effective_from order after the rate above, which the second one
      # supersedes, next to rates that neither list may show.
      before do
        create(:rate_card_rate, organization:, rate_card:, effective_from: 2.months.from_now.beginning_of_day)
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.current.beginning_of_day)
        create(:rate_card_rate, organization:, rate_card:, effective_from: 1.month.from_now.beginning_of_day)
        create(:rate_card_rate, organization:, rate_card:, effective_from: 3.months.from_now.beginning_of_day, deleted_at: Time.current)
        create(:rate_card_rate, organization:)
      end

      it "embeds the rates as /rates lists them" do
        subject
        expanded = json[:rate_card]
        get_with_token(organization, "/api/v2/rate_cards/#{rate_card.code}/rates")

        expect(json[:rates].pluck(:status)).to eq(%w[pending pending active terminated])
        expect(expanded[:rates]).to eq(json[:rates])
        expect(expanded.keys).to eq([*flat_keys, :rates])
      end
    end

    context "with expand[]=product" do
      let(:params) { {expand: %w[product]} }

      it "embeds the product as its own show renders it" do
        subject
        expanded = json[:rate_card]
        get_with_token(organization, "/api/v2/products/#{product.code}")

        expect(expanded[:product]).to eq(json[:product])
        expect(expanded.keys).to eq([*flat_keys, :product])
      end
    end

    context "with expand[]=product_filter" do
      let(:params) { {expand: %w[product_filter]} }
      let(:product_filter) { create(:product_filter, :with_values, organization:, product:) }

      it "embeds the product filter as its own show renders it" do
        subject
        expanded = json[:rate_card]
        get_with_token(organization, "/api/v2/products/#{product.code}/filters/#{product_filter.code}")

        expect(expanded[:product_filter]).to eq(json[:filter])
        expect(expanded[:product_filter][:values]).to be_present
        expect(expanded.keys).to eq([*flat_keys, :product_filter])
      end

      context "when the rate card has no product filter" do
        let(:product_filter) { nil }

        it "renders it as null" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:rate_card]).to include(product_filter_code: nil, product_filter: nil)
        end
      end
    end

    context "with every expansion" do
      let(:params) { {expand: %w[product_filter rates product taxes active_rate]} }
      let(:product_filter) { create(:product_filter, :with_values, organization:, product:) }

      it "embeds them after the card, in the serializer's order" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:rate_card].keys).to eq([*flat_keys, :active_rate, :taxes, :rates, :product, :product_filter])
      end

      context "with a superseding and a pending rate" do
        before do
          create(:rate_card_rate, organization:, rate_card:, effective_from: Time.current.beginning_of_day)
          create(:rate_card_rate, organization:, rate_card:, effective_from: 1.month.from_now.beginning_of_day)
        end

        it "embeds the active rate of the embedded rates" do
          subject

          expect(json[:rate_card][:rates].pluck(:status)).to eq(%w[pending active terminated])
          expect(json[:rate_card][:active_rate]).to eq(json[:rate_card][:rates].second)
        end
      end

      context "with a rate card of 4 rates and 3 taxes" do
        let(:larger_rate_card) do
          create(:rate_card, organization:, product:, product_filter: create(:product_filter, :with_values, values_count: 3, organization:, product:))
        end

        before do
          # In effective_from order, since a rate must start after the active one.
          [3.days.ago, 2.days.ago, 1.day.ago, 1.month.from_now].each do |effective_from|
            create(:rate_card_rate, organization:, rate_card: larger_rate_card, effective_from: effective_from.beginning_of_day)
          end
          create_list(:rate_card_applied_tax, 3, rate_card: larger_rate_card)
        end

        def select_count(card)
          statements = capture_sql { get_with_token(organization, "/api/v2/rate_cards/#{card.code}", params) }
          statements.count { it.start_with?("SELECT") }
        end

        it "runs as many queries as for the card of 1 rate and 1 tax" do
          # A first request can run lookups that the process then caches.
          select_count(rate_card)

          one_of_each = select_count(rate_card)
          larger = select_count(larger_rate_card)

          expect(response).to have_http_status(:success)
          expect(json[:rate_card].values_at(:rates, :taxes).map(&:size)).to eq([4, 3])
          expect(json[:rate_card][:product_filter][:values].size).to eq(3)
          expect(larger).to eq(one_of_each)
        end
      end
    end

    context "with an unknown expansion" do
      # product_category expands a product, one level below the rate card.
      let(:params) { {expand: %w[taxes product_category]} }

      it "returns an invalid expand error listing the allowed expansions" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(
          status: 400,
          error: "Bad Request",
          code: "invalid_expand",
          error_details: {
            expands: {invalid_values: %w[product_category], allowed_values: %w[active_rate taxes rates product product_filter]}
          }
        )
      end
    end

    context "when the rate card belongs to another organization" do
      let(:rate_card) { create(:rate_card) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("rate_card")
      end
    end
  end

  describe "GET /api/v2/rate_cards" do
    subject { get_with_token(organization, "/api/v2/rate_cards#{query_params}") }

    let(:query_params) { "" }
    let!(:rate_card) { create(:rate_card, organization:, product:, name: "Matching") }
    let!(:other) { create(:rate_card, organization:, name: "Other") }

    include_examples "requires API permission", "rate_card", "read"

    it "returns the flat rate cards" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_cards].map { it[:lago_id] }).to match_array([rate_card.id, other.id])
      expect(json[:rate_cards].map(&:keys)).to eq([flat_keys, flat_keys])
    end

    context "with expand" do
      let(:query_params) { "?expand[]=taxes" }

      it "returns a not supported error, as lists never expand" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("expand_not_supported")
        expect(json[:error_details]).to eq(expand: {reason: "action_not_expandable", invalid_values: %w[taxes]})
      end
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :rate_cards, model: RateCard do
      let(:paginated_path) { "/api/v2/rate_cards" }
      let(:create_paginated_record) { ->(created_at) { create(:rate_card, organization:, created_at:) } }
    end

    context "with a product_id filter" do
      let(:query_params) { "?product_id=#{product.id}" }

      it "returns only the rate cards of that product" do
        subject

        expect(json[:rate_cards].map { it[:lago_id] }).to eq([rate_card.id])
      end
    end

    context "with a product_code filter" do
      let(:query_params) { "?product_code=#{product.code}" }

      it "returns only the rate cards of that product" do
        subject

        expect(json[:rate_cards].map { it[:lago_id] }).to eq([rate_card.id])
      end
    end

    context "with a search term" do
      let(:query_params) { "?search_term=Matching" }

      it "returns only the matching rate cards" do
        subject

        expect(json[:rate_cards].map { it[:lago_id] }).to eq([rate_card.id])
      end
    end
  end

  describe "DELETE /api/v2/rate_cards/:code" do
    subject { delete_with_token(organization, "/api/v2/rate_cards/#{rate_card.code}") }

    let(:rate_card) { create(:rate_card, organization:, product:) }

    include_examples "requires API permission", "rate_card", "write"

    it "soft deletes the rate card" do
      expect { subject }.to change { rate_card.reload.discarded? }.from(false).to(true)

      expect(response).to have_http_status(:success)
      expect(json[:rate_card][:lago_id]).to eq(rate_card.id)
      expect(json[:rate_card][:deleted_at]).to eq(rate_card.reload.deleted_at.iso8601)
      expect(json[:rate_card].keys).to eq(flat_keys)
    end

    context "when the rate card has assigned taxes" do
      let(:tax) { create(:tax, organization:) }

      before { create(:rate_card_applied_tax, rate_card:, tax:, organization:) }

      it "keeps the assigned taxes in the REST delete response and persisted record" do
        subject

        expect(json[:rate_card][:taxes].map { it[:lago_id] }).to eq([tax.id])
        expect(rate_card.applied_taxes.pluck(:tax_id)).to eq([tax.id])
      end
    end

    context "when the rate card does not exist" do
      subject { delete_with_token(organization, "/api/v2/rate_cards/unknown") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("rate_card")
      end
    end
  end
end
