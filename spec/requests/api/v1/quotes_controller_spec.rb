# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::QuotesController do
  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:customer) { create(:customer, organization:) }

  describe "GET /api/v1/quotes" do
    subject { get_with_token(organization, "/api/v1/quotes", params) }

    let(:params) { {} }
    let!(:quote) { create(:quote, organization:, customer:) }
    let!(:quote_version) { create(:quote_version, quote:, organization:) }

    include_examples "requires API permission", "quote", "read"

    it "returns a list of quotes" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json[:quotes].count).to eq(1)
      expect(json[:quotes].first[:lago_id]).to eq(quote.id)
      expect(json[:quotes].first[:current_version][:lago_id]).to eq(quote_version.id)
    end

    it "embeds a slim current version without sensitive or heavy fields" do
      subject

      expect(json[:quotes].first[:current_version].keys).not_to include(:share_token, :content, :billing_items)
    end

    # Every embedded version resolves a billing entity, and an amendment resolves it through the
    # target subscription, which resolves its own fallback in turn. Comparing one row against five is
    # the invariant that matters: the count has to stay flat rather than grow per row.
    it "resolves every embedded billing entity without a query per row" do
      count_lookups = lambda do
        seen = []
        counter = ->(_name, _start, _finish, _id, payload) do
          seen << payload[:sql] if payload[:sql]&.match?(/billing_entities|subscriptions/)
        end

        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          get_with_token(organization, "/api/v1/quotes", params)
        end

        seen.count
      end

      # One amendment on a pinned subscription, one on an inheriting subscription, one plain quote:
      # every fallback branch the serializer can take. Adding a constant number of preload queries
      # for a branch is fine, so the comparison holds the mix of rows fixed and only grows how many
      # there are.
      seed_every_branch = lambda do
        pinned = create(:billing_entity, organization:)

        [create(:subscription, organization:, customer:, billing_entity: pinned),
          create(:subscription, organization:, customer:)].each do |subscription|
          amendment = create(:quote, organization:, customer:, subscription:, order_type: :subscription_amendment)
          create(:quote_version, quote: amendment, organization:)
        end

        plain = create(:quote, organization:, customer:)
        create(:quote_version, quote: plain, organization:)
      end

      seed_every_branch.call
      one_of_each = count_lookups.call

      2.times { seed_every_branch.call }

      expect(count_lookups.call).to eq(one_of_each)
      expect(json[:quotes].count).to eq(10)
      expect(json[:quotes].last[:current_version][:billing_entity_code]).to eq(customer.billing_entity.code)
    end

    it "does not embed owners on the index" do
      subject

      expect(json[:quotes].first).not_to have_key(:owners)
    end

    context "when filtering by status" do
      subject { get_with_token(organization, "/api/v1/quotes", {status: "approved"}) }

      let!(:approved_quote) { create(:quote, organization:, customer:) }

      before { create(:quote_version, :approved, quote: approved_quote, organization:) }

      it "returns only quotes whose current version matches" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:quotes].count).to eq(1)
        expect(json[:quotes].first[:lago_id]).to eq(approved_quote.id)
      end
    end

    context "when filtering by order_type" do
      subject { get_with_token(organization, "/api/v1/quotes", {order_type: "one_off"}) }

      let!(:one_off_quote) { create(:quote, organization:, customer:, order_type: :one_off) }

      it "returns only matching quotes" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:quotes].count).to eq(1)
        expect(json[:quotes].first[:lago_id]).to eq(one_off_quote.id)
      end
    end

    context "when filtering by number" do
      subject { get_with_token(organization, "/api/v1/quotes", {number: quote.number}) }

      before { create(:quote, organization:, customer:) }

      it "returns only the matching quote" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:quotes].count).to eq(1)
        expect(json[:quotes].first[:lago_id]).to eq(quote.id)
      end
    end

    context "when filtering by external_customer_id" do
      subject { get_with_token(organization, "/api/v1/quotes", {external_customer_id: customer.external_id}) }

      before { create(:quote, organization:, customer: create(:customer, organization:)) }

      it "returns only that customer's quotes" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:quotes].count).to eq(1)
        expect(json[:quotes].first[:lago_id]).to eq(quote.id)
      end
    end

    context "when filtering by an unknown external_customer_id" do
      subject { get_with_token(organization, "/api/v1/quotes", {external_customer_id: "unknown"}) }

      it "returns an empty list with canonical pagination meta" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:quotes]).to be_empty
        expect(json[:meta]).to include(current_page: 0, total_pages: 0, total_count: 0)
      end
    end

    context "when filtering by owner_id" do
      subject { get_with_token(organization, "/api/v1/quotes", {owner_id: owner.id}) }

      let(:owner) { create(:membership, organization:).user }
      let!(:owned_quote) { create(:quote, organization:, customer:) }

      before { create(:quote_owner, quote: owned_quote, organization:, user: owner) }

      it "returns only quotes owned by that user" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:quotes].count).to eq(1)
        expect(json[:quotes].first[:lago_id]).to eq(owned_quote.id)
      end
    end

    context "with pagination" do
      subject { get_with_token(organization, "/api/v1/quotes", {page: 1, per_page: 1}) }

      before { create(:quote, organization:, customer:) }

      it "returns paginated quotes with meta data" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:quotes].count).to eq(1)
        expect(json[:meta]).to include(
          current_page: 1,
          next_page: 2,
          prev_page: nil,
          total_pages: 2,
          total_count: 2
        )
      end
    end

    context "when the order_forms feature flag is disabled" do
      let(:organization) { create(:organization) }

      it "returns forbidden" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end

  describe "GET /api/v1/quotes/:id" do
    subject { get_with_token(organization, "/api/v1/quotes/#{quote_id}") }

    let(:quote_id) { quote.id }
    let!(:quote) { create(:quote, organization:, customer:) }
    let!(:quote_version) { create(:quote_version, quote:, organization:) }

    include_examples "requires API permission", "quote", "read"

    it "returns the quote with its current version" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json[:quote][:lago_id]).to eq(quote.id)
      expect(json[:quote][:number]).to eq(quote.number)
      expect(json[:quote][:current_version][:lago_id]).to eq(quote_version.id)
    end

    it "includes the owners" do
      owner = create(:membership, organization:).user
      create(:quote_owner, quote:, organization:, user: owner)

      subject

      expect(json[:quote][:owners]).to eq([{lago_id: owner.id, email: owner.email}])
    end

    context "when the quote does not exist" do
      let(:quote_id) { SecureRandom.uuid }

      it "returns not found" do
        subject

        expect(response).to be_not_found_error("quote")
      end
    end

    context "when the quote belongs to another organization" do
      let(:quote) { create(:quote) }

      it "returns not found" do
        subject

        expect(response).to be_not_found_error("quote")
      end
    end

    context "when the order_forms feature flag is disabled" do
      let(:organization) { create(:organization) }

      it "returns forbidden" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end
end
