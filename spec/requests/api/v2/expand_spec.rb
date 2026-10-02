# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API v2 expand" do
  let(:organization) { create(:organization) }

  # Every native v2 route, its path parameters filled with a code that matches nothing.
  native_routes = Rails.application.routes.routes.filter_map do |route|
    next unless route.defaults[:controller]&.start_with?("api/v2/")

    [route.verb, route.path.spec.to_s.delete_suffix("(.:format)").gsub(/:\w+/, "unknown"), route.defaults]
  end

  it "walks every native route" do
    expect(native_routes.size).to eq(63)
  end

  # Without a body and on records that do not exist: the expansion is rejected before any
  # lookup and before any required parameter is read, as the same request without it shows.
  native_routes.each do |verb, path, defaults|
    context "with #{verb} #{path}" do
      subject(:send_request) { public_send(:"#{verb.downcase}_with_token", organization, [path, query].compact.join("?")) }

      let(:query) { "expand[]=__nope__" }

      it "rejects the expansion in #{defaults[:controller]}##{defaults[:action]}" do
        send_request

        expect([controller.controller_path, controller.action_name]).to eq(defaults.values_at(:controller, :action))
        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_expand")
        expect(json[:error_details][:expand]).to include(invalid_values: ["__nope__"])
      end

      context "without expand" do
        let(:query) { nil }

        # Only a top-level list has neither a record to find nor a required parameter.
        if verb == "GET" && !path.include?("unknown")
          it "succeeds" do
            send_request

            expect(response).to have_http_status(:success)
          end
        else
          it "fails on a lookup or a required parameter instead" do
            send_request

            expect(json[:code]).to eq("missing_parameter").or end_with("_not_found")
          end
        end
      end
    end
  end

  # `expand[0]` without a value arrives as {"0" => nil}, unlike `expand[]`.
  %w[expand[x]=a expand[][]=a expand[][a]=b expand[0][x]=a expand[0]].each do |query|
    context "with the query #{query}" do
      subject(:send_request) { get_with_token(organization, "/api/v2/products/unknown?#{query}") }

      it "returns a malformed error" do
        send_request

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_expand")
        expect(json[:error_details][:expand]).to include(reason: "malformed")
      end
    end
  end

  # A key without a value arrives as nil, and `expand[]` as [nil], which Rails compacts to [].
  %w[expand expand= expand[]].each do |query|
    context "with the empty query #{query}" do
      subject(:send_request) { get_with_token(organization, "/api/v2/products?#{query}") }

      it "expands nothing" do
        send_request

        expect(response).to have_http_status(:success)
      end
    end
  end

  # Rack cannot parse a key sent both as a scalar and as a list or a hash: the framework
  # rejects the query before any callback, authentication included.
  %w[expand=a&expand[]=b expand[]=a&expand[x]=b].each do |query|
    context "with the conflicting query #{query}" do
      subject(:send_request) { get_with_token(organization, "/api/v2/products?#{query}") }

      it "returns a bad request error" do
        send_request

        expect(response).to have_http_status(:bad_request)
      end

      context "without a valid API key" do
        subject(:send_request) { get("/api/v2/products?#{query}", headers: {"Authorization" => "Bearer invalid"}) }

        it "returns a bad request error" do
          send_request

          expect(response).to have_http_status(:bad_request)
        end
      end
    end
  end

  context "without a valid API key" do
    subject(:send_request) { get("/api/v2/products?expand[]=__nope__", headers: {"Authorization" => "Bearer invalid"}) }

    it "authenticates before checking the expansion" do
      send_request

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "with an API key that cannot read rate cards", :premium do
    subject(:send_request) { get_with_token(organization, "/api/v2/rate_cards/unknown?expand[]=__nope__") }

    let(:organization) { create(:organization, premium_integrations: ["api_permissions"]) }

    before do
      api_key = organization.api_keys.first
      api_key.update!(permissions: api_key.permissions.merge("rate_card" => ["write"]))
    end

    it "authorizes before checking the expansion" do
      send_request

      expect(response).to have_http_status(:forbidden)
      expect(json[:code]).to eq("read_action_not_allowed_for_rate_card")
    end
  end

  context "when the organization is not on the product catalog", product_catalog: false do
    subject(:send_request) { get_with_token(organization, "/api/v2/products?expand[]=__nope__") }

    it "checks the catalog before the expansion" do
      send_request

      expect(response).to have_http_status(:forbidden)
      expect(json[:code]).to eq("feature_unavailable")
    end
  end

  {
    "after=not-a-cursor!" => "invalid_pagination_cursor",
    "page=2" => "invalid_pagination_parameter",
    "limit=0" => "invalid_pagination_limit"
  }.each do |pagination, code|
    context "with the invalid pagination parameter #{pagination}" do
      subject(:send_request) { get_with_token(organization, "/api/v2/products?#{[pagination, expand].compact.join("&")}") }

      let(:expand) { "expand[]=__nope__" }

      it "rejects the expansion first" do
        send_request

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_expand")
      end

      context "without expand" do
        let(:expand) { nil }

        it "rejects the pagination parameter instead" do
          send_request

          expect(json[:code]).to eq(code)
        end
      end
    end
  end

  context "with an expansion in the body of a create" do
    subject(:send_request) do
      post_with_token(organization, "/api/v2/plans", {plan: {name: "Growth", code: "growth", currency: "USD"}, expand: ["__nope__"]})
    end

    it "rejects it and creates nothing" do
      expect { send_request }.not_to change(CatalogPlan, :count)

      expect(response).to have_http_status(:bad_request)
      expect(json[:error_details]).to eq(expand: {invalid_values: ["__nope__"], allowed_values: []})
    end
  end
end
