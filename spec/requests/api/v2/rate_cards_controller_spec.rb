# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::RateCardsController do
  let(:organization) { create(:organization) }
  let(:product) { create(:product, organization:) }
  let(:flat_keys) do
    %i[
      lago_id product_code product_filter_code name code description currency billing_timing proration
      display_on_invoice regroup_paid_fees applied_pricing_unit_code created_at updated_at deleted_at
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
      subject { post_with_token(organization, "/api/v2/rate_cards", {rate_card: create_params, expand: %w[taxes]}) }

      it "returns a not supported error and creates nothing" do
        expect { subject }.not_to change(RateCard, :count)

        expect(response).to have_http_status(:bad_request)
        expect(json[:error_details]).to eq(expand: {reason: "show_only", invalid_values: %w[taxes]})
      end
    end

    context "with taxes" do
      let(:tax1) { create(:tax, organization:) }
      let(:tax2) { create(:tax, organization:) }

      before { create_params[:tax_codes] = [tax1.code, tax2.code] }

      it "applies the taxes" do
        subject

        expect(response).to have_http_status(:success)
        expect(RateCard.find(json[:rate_card][:lago_id]).taxes.pluck(:code)).to match_array([tax1.code, tax2.code])
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
        expect(RateCard.find(json[:rate_card][:lago_id]).rates.count).to eq(2)
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

    context "with expand" do
      subject { put_with_token(organization, "/api/v2/rate_cards/#{rate_card.code}", {rate_card: update_params, expand: %w[taxes]}) }

      it "returns a not supported error and updates nothing" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:error_details]).to eq(expand: {reason: "show_only", invalid_values: %w[taxes]})
        expect(rate_card.reload.name).to eq("Before")
      end
    end

    context "with taxes" do
      let(:tax1) { create(:tax, organization:) }
      let(:tax2) { create(:tax, organization:) }
      let(:update_params) { {tax_codes: [tax2.code]} }

      before { create(:rate_card_applied_tax, rate_card:, tax: tax1, organization:) }

      it "replaces the taxes" do
        subject

        expect(response).to have_http_status(:success)
        expect(rate_card.reload.taxes.pluck(:code)).to eq([tax2.code])
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
          expect(rate_card.reload.taxes.pluck(:code)).to eq([tax1.code])
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
    let(:product_filter) { create(:product_filter, :with_values, organization:, product:) }
    let(:params) { {} }
    let(:tax) { create(:tax, organization:) }
    let(:rate_effective_from) { 1.day.ago.beginning_of_day }
    let!(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: rate_effective_from) }

    before { create(:rate_card_applied_tax, rate_card:, tax:, organization:) }

    include_examples "requires API permission", "rate_card", "read"

    it "returns the flat rate card" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_card]).to include(lago_id: rate_card.id, product_code: product.code, product_filter_code: product_filter.code, deleted_at: nil)
      expect(json[:rate_card].keys).to eq(flat_keys)
      expect(json[:rate_card]).to be_a_flat_v2_payload
    end

    # The show body before v2 went flat, less rates_count and the five tax counts, plus a
    # deleted_at on the card, its active rate and its taxes.
    context "with expand[]=active_rate&expand[]=taxes" do
      let(:params) { {expand: %w[active_rate taxes]} }
      let(:rate_keys) do
        %i[
          lago_id code effective_from status rate_model rate_properties min_amount_cents billing_interval_count
          billing_interval_unit applied_pricing_unit_conversion_rate created_at updated_at deleted_at
        ]
      end
      let(:tax_keys) { %i[lago_id name code rate description applied_to_organization created_at deleted_at] }

      it "returns the former show body, without its counts and with deleted_at" do
        subject

        expect(json[:rate_card].keys).to eq([*flat_keys, :active_rate, :taxes])
        expect(json[:rate_card][:active_rate].keys).to eq(rate_keys)
        expect(json[:rate_card][:active_rate]).to include(lago_id: rate.id, status: "active", deleted_at: nil)
        expect(json[:rate_card][:taxes].map(&:keys)).to eq([tax_keys])
        expect(json[:rate_card][:taxes].sole).to include(code: tax.code, deleted_at: nil)
      end
    end

    context "with expand[]=active_rate" do
      let(:params) { {expand: %w[active_rate]} }

      before { create(:rate_card_rate, organization:, rate_card:, effective_from: 2.months.from_now.beginning_of_day) }

      it "embeds the flat active rate as /rates lists it" do
        get_with_token(organization, "/api/v2/rate_cards/#{rate_card.code}/rates")
        listed = json[:rates].find { it[:lago_id] == rate.id }

        subject

        expect(listed).to include(status: "active")
        expect(json[:rate_card][:active_rate]).to eq(listed)
        expect(json[:rate_card][:active_rate]).to be_a_flat_v2_payload
        expect(json[:rate_card].keys.last).to eq(:active_rate)
      end

      context "when every rate is pending" do
        let(:rate_effective_from) { 1.month.from_now.beginning_of_day }

        it "renders a null active rate" do
          subject

          expect(json[:rate_card]).to include(active_rate: nil)
        end
      end
    end

    context "with expand[]=taxes" do
      let(:params) { {expand: %w[taxes]} }
      let(:created_at) { Time.zone.parse("2026-09-28T10:00:00.000001Z") }

      # Ties to the microsecond, created out of order, next to taxes neither list may show.
      before do
        [1, 0, 1, 0].each { create(:rate_card_applied_tax, rate_card:, created_at: created_at - it.seconds) }
        # Discarded directly: Taxes::DestroyService would delete the link as well.
        create(:rate_card_applied_tax, rate_card:, created_at:).tax.discard!
        create(:rate_card_applied_tax, rate_card: create(:rate_card, organization:), created_at:)
      end

      it "embeds every page of /taxes, in its order" do
        listed = []
        page_params = {limit: 2}
        while page_params
          get_with_token(organization, "/api/v2/rate_cards/#{rate_card.code}/taxes", page_params)
          listed.concat(json[:taxes])
          page_params = json[:meta][:next_cursor] && {limit: 2, after: json[:meta][:next_cursor]}
        end

        subject

        expect(listed.size).to eq(5)
        expect(json[:rate_card][:taxes]).to eq(listed)
        expect(json[:rate_card][:taxes]).to all(be_a_flat_v2_payload)
      end
    end

    context "with expand[]=rates" do
      let(:params) { {expand: %w[rates]} }

      # Appended after the rate above, which becomes terminated, next to rates neither list may show.
      before do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.current.beginning_of_day)
        create(:rate_card_rate, organization:, rate_card:, effective_from: 1.month.from_now.beginning_of_day)
        create(:rate_card_rate, organization:, rate_card:, effective_from: 2.months.from_now.beginning_of_day, deleted_at: Time.current)
        create(:rate_card_rate, organization:)
      end

      it "embeds the flat rates as /rates lists them" do
        get_with_token(organization, "/api/v2/rate_cards/#{rate_card.code}/rates")
        listed = json[:rates]

        subject

        expect(listed.pluck(:status)).to eq(%w[pending active terminated])
        expect(json[:rate_card][:rates]).to eq(listed)
        expect(json[:rate_card][:rates]).to all(be_a_flat_v2_payload)
      end
    end

    context "with expand[]=product" do
      let(:params) { {expand: %w[product]} }

      it "embeds the flat product as its own show renders it" do
        subject
        expanded = json[:rate_card]
        get_with_token(organization, "/api/v2/products/#{product.code}")

        expect(expanded[:product]).to eq(json[:product])
        expect(expanded[:product]).to be_a_flat_v2_payload
        expect(expanded.keys.last).to eq(:product)
      end
    end

    context "with expand[]=product_filter" do
      let(:params) { {expand: %w[product_filter]} }

      it "embeds the flat product filter as its own show renders it" do
        subject
        expanded = json[:rate_card]
        get_with_token(organization, "/api/v2/products/#{product.code}/filters/#{product_filter.code}")

        expect(expanded[:product_filter]).to eq(json[:filter])
        expect(expanded[:product_filter][:values]).to be_present
        expect(expanded[:product_filter]).to be_a_flat_v2_payload
        expect(expanded.keys.last).to eq(:product_filter)
      end

      context "without a product filter" do
        let(:product_filter) { nil }

        it "renders a null product filter" do
          subject

          expect(json[:rate_card]).to include(product_filter_code: nil, product_filter: nil)
        end
      end
    end

    context "with every expansion" do
      let(:params) { {expand: %w[active_rate taxes rates product product_filter]} }
      # The shape of the card above, with three of each listed item instead of one.
      let(:larger_rate_card) { create(:rate_card, organization:, product:, product_filter: create(:product_filter, :with_values, values_count: 3, organization:, product:)) }

      before do
        # In effective_from order, since a rate must start after the active one.
        [2.days.ago, 1.day.ago, 1.day.from_now].each do |effective_from|
          create(:rate_card_rate, organization:, rate_card: larger_rate_card, effective_from: effective_from.beginning_of_day)
        end
        create_list(:rate_card_applied_tax, 3, rate_card: larger_rate_card)
      end

      def show_queries(card)
        capture_counted_queries { get_with_token(organization, "/api/v2/rate_cards/#{card.code}", params) }
      end

      it "runs as many queries for a card of three items as for a card of one" do
        # A first request can run lookups the process then caches.
        show_queries(rate_card)

        one_item_queries = show_queries(rate_card)
        three_items_queries = show_queries(larger_rate_card)

        expect(json[:rate_card].values_at(:rates, :taxes).map(&:size)).to eq([3, 3])
        expect(json[:rate_card][:product_filter][:values].size).to eq(3)
        expect(three_items_queries.size).to eq(one_item_queries.size)
      end
    end

    %w[counts deleted_at Taxes rates.status taxes,rates].each do |value|
      context "with expand[]=#{value}" do
        let(:params) { {expand: [value]} }

        it "returns an invalid expand error listing the allowed expansions" do
          subject

          expect(response).to have_http_status(:bad_request)
          expect(json).to eq(
            status: 400,
            error: "Bad Request",
            code: "invalid_expand",
            error_details: {expand: {invalid_values: [value], allowed_values: %w[active_rate taxes rates product product_filter]}}
          )
        end
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

    context "with a rate and a tax on a rate card" do
      before do
        create(:rate_card_rate, organization:, rate_card:)
        create(:rate_card_applied_tax, rate_card:)
      end

      it "returns the flat rate cards" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:rate_cards].map { it[:lago_id] }).to match_array([rate_card.id, other.id])
        expect(json[:rate_cards].map(&:keys).uniq).to eq([flat_keys])
        expect(json[:rate_cards]).to all(be_a_flat_v2_payload)
      end
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :rate_cards, model: RateCard do
      let(:paginated_path) { "/api/v2/rate_cards" }
      let(:create_paginated_record) { ->(created_at) { create(:rate_card, :with_filter, organization:, created_at:) } }
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
      expect(json[:rate_card][:deleted_at]).to eq(rate_card.deleted_at.iso8601)
      expect(json[:rate_card].keys).to eq(flat_keys)
    end

    context "with expand" do
      subject { delete_with_token(organization, "/api/v2/rate_cards/#{rate_card.code}?expand[]=taxes") }

      it "returns a not supported error and keeps the rate card" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:error_details]).to eq(expand: {reason: "show_only", invalid_values: %w[taxes]})
        expect(rate_card.reload).not_to be_discarded
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

  # rates_count left the payload: the length of /rates, returned whole, replaces it.
  describe "GET /api/v2/rate_cards/:code/rates" do
    subject { get_with_token(organization, "/api/v2/rate_cards/#{rate_card.code}/rates") }

    let(:rate_card) { create(:rate_card, organization:, product:) }
    let(:activity_log_rates_count) { V2::RateCardSerializer.new(rate_card, includes: %i[counts]).serialize[:rates_count] }

    # In effective_from order, since a rate must start after the active one.
    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: 1.day.ago.beginning_of_day)
      create(:rate_card_rate, organization:, rate_card:, effective_from: 1.month.from_now.beginning_of_day)
      create(:rate_card_rate, organization:, rate_card:, effective_from: 2.months.from_now.beginning_of_day, deleted_at: Time.current)
      create(:rate_card_rate, organization:)
    end

    it "lists as many rates as the rates_count the activity log still renders" do
      subject

      expect(json[:rates].size).to eq(2)
      expect(json[:rates].size).to eq(activity_log_rates_count)
    end
  end
end
