# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::ContractsController do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }

  describe "POST /api/v2/contracts" do
    subject { post_with_token(organization, "/api/v2/contracts", {contract: create_params}) }

    let(:create_params) do
      {
        external_customer_id: customer.external_id,
        external_id: "contract-1",
        plan_code: catalog_plan.code
      }
    end

    include_examples "requires API permission", "contract", "write"

    it "creates the contract and returns it with its materialized rate cards" do
      rate_card = create(:rate_card, organization:)
      create(:plan_rate_card, organization:, catalog_plan:, rate_card:, units: 2)

      subject

      expect(response).to have_http_status(:success)
      expect(json[:contract][:external_id]).to eq("contract-1")
      expect(json[:contract][:plan_code]).to eq(catalog_plan.code)
      expect(json[:contract][:status]).to eq("active")
      expect(json[:contract][:applied_rate_cards_count]).to eq(1)
      expect(json[:contract][:applied_rate_cards].sole[:rate_card_code]).to eq(rate_card.code)
    end

    context "without a plan" do
      let(:create_params) { {external_customer_id: customer.external_id, external_id: "contract-1"} }

      it "creates a plan-less contract" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract][:plan_code]).to be_nil
        expect(json[:contract][:applied_rate_cards]).to be_empty
      end
    end

    context "when the customer does not exist" do
      let(:create_params) { super().merge(external_customer_id: "unknown") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("customer")
      end
    end

    context "when a live contract already uses the external id" do
      before { create(:contract, organization:, customer:, external_id: "contract-1") }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json.dig(:error_details, :external_id)).to eq(["value_already_exists"])
      end
    end
  end

  describe "GET /api/v2/contracts" do
    subject { get_with_token(organization, "/api/v2/contracts") }

    let!(:contract) { create(:contract, organization:, customer:, catalog_plan:) }

    include_examples "requires API permission", "contract", "read"

    it "lists active contracts with their card counts" do
      create(:contract_rate_card, organization:, contract:)
      # An ended attachment must not inflate the grouped count.
      create(:contract_rate_card, organization:, contract:, effective_date: 10.days.ago.to_date, ended_date: 1.day.ago.to_date)

      subject

      expect(response).to have_http_status(:success)
      result = json[:contracts].sole
      expect(result[:lago_id]).to eq(contract.id)
      expect(result[:applied_rate_cards_count]).to eq(1)
    end

    context "with a pending contract" do
      let!(:pending_contract) { create(:contract, :pending, organization:, customer:) }

      it "lists only active contracts by default" do
        subject

        expect(json[:contracts].map { |c| c[:lago_id] }).to eq([contract.id])
      end

      it "lists pending contracts when the status filter asks for them" do
        get_with_token(organization, "/api/v2/contracts?status[]=pending")

        expect(json[:contracts].map { |c| c[:lago_id] }).to eq([pending_contract.id])
      end

      it "accepts the scalar status form" do
        get_with_token(organization, "/api/v2/contracts?status=pending")

        expect(json[:contracts].map { |c| c[:lago_id] }).to eq([pending_contract.id])
      end
    end

    context "with a billing entity filter" do
      let(:billing_entity) { create(:billing_entity, organization:) }
      let!(:matching) { create(:contract, organization:, billing_entity:) }

      it "returns only contracts on that billing entity" do
        get_with_token(organization, "/api/v2/contracts?billing_entity_ids[]=#{billing_entity.id}")

        expect(json[:contracts].map { |c| c[:lago_id] }).to eq([matching.id])
      end
    end

    context "with a has_rate_overrides filter" do
      it "returns only contracts carrying a rate override" do
        card = create(:contract_rate_card, organization:, contract:)
        create(:rate_phase, organization:, plan_rate_card: nil, contract_rate_card: card, rate_override: create(:rate_override, organization:))

        get_with_token(organization, "/api/v2/contracts?has_rate_overrides=true")

        expect(json[:contracts].map { |c| c[:lago_id] }).to eq([contract.id])
      end
    end

    context "with a search term" do
      let!(:matching) { create(:contract, organization:, external_id: "needle-1") }

      it "returns only the matching contracts" do
        get_with_token(organization, "/api/v2/contracts?search_term=needle")

        expect(json[:contracts].map { |c| c[:lago_id] }).to eq([matching.id])
      end
    end
  end

  describe "GET /api/v2/contracts/:external_id" do
    subject { get_with_token(organization, "/api/v2/contracts/#{contract.external_id}") }

    let!(:contract) { create(:contract, organization:, customer:, catalog_plan:) }

    include_examples "requires API permission", "contract", "read"

    it "returns the contract with its rate cards" do
      card = create(:contract_rate_card, organization:, contract:)

      subject

      expect(response).to have_http_status(:success)
      expect(json[:contract][:lago_id]).to eq(contract.id)
      expect(json[:contract][:applied_rate_cards].sole[:lago_id]).to eq(card.id)
    end

    context "when the external id contains a dot" do
      let(:contract) { create(:contract, organization:, customer:, external_id: "contract.2026-01") }

      it "matches the full id instead of truncating at the format separator" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract][:external_id]).to eq("contract.2026-01")
      end
    end

    context "with an unknown status filter value" do
      it "falls back to the active contract instead of raising on the enum cast" do
        get_with_token(organization, "/api/v2/contracts/#{contract.external_id}?status=bogus")

        expect(response).to have_http_status(:success)
        expect(json[:contract][:lago_id]).to eq(contract.id)
      end
    end

    context "when the contract is pending" do
      let!(:contract) { create(:contract, :pending, organization:, customer:) }

      it "returns it without a status filter" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract][:lago_id]).to eq(contract.id)
        expect(json[:contract][:status]).to eq("pending")
      end
    end

    context "when reading a terminated contract by status" do
      let!(:contract) { create(:contract, :terminated, organization:, customer:) }

      it "returns it only with an explicit status filter" do
        subject
        expect(response).to be_not_found_error("contract")

        get_with_token(organization, "/api/v2/contracts/#{contract.external_id}?status=terminated")
        expect(response).to have_http_status(:success)
        expect(json[:contract][:lago_id]).to eq(contract.id)
      end
    end

    context "when it does not exist" do
      subject { get_with_token(organization, "/api/v2/contracts/unknown") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("contract")
      end
    end
  end

  describe "PUT /api/v2/contracts/:external_id" do
    subject { put_with_token(organization, "/api/v2/contracts/#{contract.external_id}", {contract: update_params}) }

    let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:) }
    let(:update_params) { {name: "Renamed"} }

    include_examples "requires API permission", "contract", "write"

    it "updates the contract and returns it" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:contract][:external_id]).to eq(contract.external_id)
      expect(json[:contract][:name]).to eq("Renamed")
    end

    context "when changing the plan" do
      let(:other_plan) { create(:catalog_plan, organization:) }
      let(:update_params) { {plan_code: other_plan.code} }

      it "re-materializes the rate cards from the new plan" do
        rate_card = create(:rate_card, organization:)
        create(:plan_rate_card, organization:, catalog_plan: other_plan, rate_card:, units: 4)

        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract][:plan_code]).to eq(other_plan.code)
        expect(json[:contract][:applied_rate_cards].sole[:rate_card_code]).to eq(rate_card.code)
      end
    end

    context "when the contract is already active" do
      let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }

      it "updates the fields that stay editable" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract][:name]).to eq("Renamed")
      end

      context "when changing the plan" do
        let(:other_plan) { create(:catalog_plan, organization:) }
        let(:update_params) { {plan_code: other_plan.code} }

        it "returns an unprocessable entity error" do
          subject

          expect(response).to have_http_status(:unprocessable_entity)
          expect(json[:error_details][:contract]).to eq(["contract_locked"])
        end
      end
    end

    context "when it does not exist" do
      subject { put_with_token(organization, "/api/v2/contracts/unknown", {contract: update_params}) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("contract")
      end
    end
  end

  describe "GET /api/v2/contracts/segments" do
    subject { get_with_token(organization, "/api/v2/contracts/#{contract.external_id}/segments", params) }

    let(:params) { {start_on: "2026-01-01", end_on: "2026-03-31"} }
    let(:customer) { create(:customer, organization:, timezone: "UTC") }
    let(:contract) { create(:contract, organization:, customer:, started_at: Time.zone.parse("2026-01-01")) }
    let(:rate_card) { create(:rate_card, organization:, billing_timing: "arrears") }

    let!(:contract_rate_card) do
      create(
        :contract_rate_card,
        organization:,
        contract:,
        rate_card:,
        effective_date: Date.new(2026, 1, 1),
        billing_anchor_date: Date.new(2026, 1, 1),
        next_billing_at: Time.zone.parse("2026-02-01")
      )
    end

    before do
      create(
        :rate_card_rate,
        organization:,
        rate_card:,
        effective_from: Time.zone.parse("2026-01-01"),
        billing_interval_unit: "month",
        billing_interval_count: 1
      )
    end

    include_examples "requires API permission", "contract", "read"

    context "when a date cannot be parsed" do
      let(:params) { {start_on: "2026-01-01", end_on: "2026-13-01"} }

      it "names the offending parameter instead of failing" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq({end_on: ["invalid_date"]})
      end
    end

    it "returns what the calendar would produce over the window" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:segments].map { it[:period_from] }).to eq(
        ["2026-01-01T00:00:00Z", "2026-02-01T00:00:00Z", "2026-03-01T00:00:00Z"]
      )
    end

    it "describes each segment well enough to check a price against it" do
      subject

      expect(json[:segments].first).to include(
        external_contract_id: contract.external_id,
        lago_applied_rate_card_id: contract_rate_card.id,
        applied_rate_card_code: rate_card.code,
        cycle_index: 1,
        period_to: "2026-01-31T23:59:59Z",
        billing_at: "2026-02-01T00:00:00Z"
      )
    end

    # The window ends on Mar 31; an arrears card bills a cycle at its close, so the next
    # instant anything bills is the end of the March cycle.
    it "reports the next instant anything bills after the window" do
      subject

      expect(json[:next_billing_at]).to eq("2026-04-01T00:00:00Z")
    end

    it "writes nothing" do
      expect { subject }.not_to change(BillingSegment, :count)
    end

    context "with the collection form" do
      subject { get_with_token(organization, "/api/v2/contracts/segments", params.merge(external_ids: [contract.external_id])) }

      # The route is declared before the resource; drawn after it, "segments" would reach
      # #show as an external id and answer 404.
      it "previews the contracts named in external_ids" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:segments].size).to eq(3)
      end
    end

    context "when one of the ids is unknown" do
      subject { get_with_token(organization, "/api/v2/contracts/segments", params.merge(external_ids: [contract.external_id, "nope"])) }

      it "answers not found rather than previewing the subset" do
        subject

        expect(response).to be_not_found_error("contract")
      end
    end
  end

  describe "POST /api/v2/contracts/:external_id/bill" do
    subject { post_with_token(organization, "/api/v2/contracts/#{contract.external_id}/bill", {end_on: "2026-02-01"}) }

    let(:customer) { create(:customer, organization:, timezone: "UTC", currency: "EUR") }
    let(:product) { create(:product, :fixed, organization:) }
    let(:contract) do
      create(:contract, organization:, customer:, billing_entity: organization.default_billing_entity,
        started_at: Time.zone.parse("2026-01-01"))
    end
    let(:rate_card) do
      create(:rate_card, organization:, product:, currency: "EUR", billing_timing: "arrears")
    end

    before do
      stub_pdf_generation

      create(:rate_card_rate, organization:, rate_card:,
        effective_from: Time.zone.parse("2026-01-01"),
        rate_model: "standard", rate_properties: {"amount" => "50"},
        billing_interval_count: 1, billing_interval_unit: "month")

      create(:contract_rate_card, organization:, contract:, rate_card:, units: 3,
        effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1),
        next_billing_at: Time.zone.parse("2026-02-01"))
    end

    include_examples "requires API permission", "contract", "write"

    context "when a date cannot be parsed" do
      it "names the offending parameter instead of failing" do
        post_with_token(organization, "/api/v2/contracts/#{contract.external_id}/bill", {end_on: "nope"})

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq({end_on: ["invalid_date"]})
      end
    end

    # The sibling preview endpoint takes one, so a caller will try it here too.
    context "with a start date" do
      it "refuses it rather than ignoring it" do
        post_with_token(
          organization,
          "/api/v2/contracts/#{contract.external_id}/bill",
          {start_on: "2026-01-01", end_on: "2026-02-01"}
        )

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq({start_on: ["value_is_invalid"]})
      end
    end

    it "produces the due segments and invoices them in one call" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:invoices].sole[:total_amount_cents]).to eq(15_000)
      expect(BillingSegment.where(customer:).sole).to have_attributes(status: "done")
    end

    # The fees are what a QA run actually reads. A segment-backed fee hangs off a product
    # rather than a subscription, so serializing one is what makes this payload answerable.
    it "returns the invoice fees carrying their product identity" do
      subject

      expect(json[:invoices].sole[:fees].sole[:item]).to include(
        type: "product",
        code: product.code,
        name: product.name,
        item_type: "Product",
        lago_item_id: product.id
      )
    end

    it "moves the clock on, so a second call bills nothing again" do
      subject

      expect { post_with_token(organization, "/api/v2/contracts/#{contract.external_id}/bill", {end_on: "2026-02-01"}) }
        .not_to change(BillingSegment, :count)
    end

    # Documented surprise: the consumer groups a customer's segments into as few invoices as
    # their contracts allow, so billing is customer-grained. Asking for one contract brings
    # the customer's others along, exactly as the clock would.
    context "when the customer holds another contract" do
      it "bills it in the same run" do
        sibling = create(:contract, organization:, customer:, external_id: "sibling",
          billing_entity: organization.default_billing_entity, started_at: Time.zone.parse("2026-01-01"))
        create(:contract_rate_card, organization:, contract: sibling, rate_card:, units: 1,
          effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1),
          next_billing_at: Time.zone.parse("2026-02-01"))

        subject

        expect(BillingSegment.where(contract: sibling).sole).to have_attributes(status: "done")
      end
    end

    context "when the contract is unknown" do
      it "answers not found" do
        post_with_token(organization, "/api/v2/contracts/nope/bill", {end_on: "2026-02-01"})

        expect(response).to be_not_found_error("contract")
      end
    end
  end

  describe "DELETE /api/v2/contracts/:external_id" do
    subject { delete_with_token(organization, "/api/v2/contracts/#{contract.external_id}") }

    let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }

    include_examples "requires API permission", "contract", "write"

    it "terminates the active contract and returns it" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:contract][:external_id]).to eq(contract.external_id)
      expect(json[:contract][:status]).to eq("terminated")
    end

    context "when the contract is pending" do
      let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:) }

      it "cancels it" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract][:status]).to eq("canceled")
      end
    end

    context "when a pending replacement coexists with the active contract" do
      it "terminates the active contract and leaves the replacement live" do
        replacement = create(:contract, :pending, organization:, customer:, catalog_plan:, external_id: contract.external_id)

        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract][:status]).to eq("terminated")
        expect(replacement.reload.status).to eq("pending")
      end
    end

    context "when no live contract matches the external id" do
      subject { delete_with_token(organization, "/api/v2/contracts/unknown") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("contract")
      end
    end
  end
end
