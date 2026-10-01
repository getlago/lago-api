# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::ContractsController do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  # A contract is never deleted, so it renders no deleted_at.
  let(:flat_keys) do
    %i[
      lago_id external_id lago_customer_id external_customer_id name plan_code status billing_time
      consolidate_invoice purchase_order_number billing_anchor_date effective_billing_anchor_date started_at
      ended_at terminated_at canceled_at skip_invoice_custom_sections created_at updated_at
    ]
  end

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

    context "with a rate card on the plan" do
      let(:rate_card) { create(:rate_card, organization:) }

      before { create(:plan_rate_card, organization:, catalog_plan:, rate_card:, units: 2) }

      it "creates the contract with its materialized rate cards and returns it flat" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract][:external_id]).to eq("contract-1")
        expect(json[:contract][:plan_code]).to eq(catalog_plan.code)
        expect(json[:contract][:status]).to eq("active")
        expect(json[:contract].keys).to eq(flat_keys)
        expect(Contract.find(json[:contract][:lago_id]).applied_rate_cards.sole.rate_card).to eq(rate_card)
      end
    end

    context "with expand" do
      subject { post_with_token(organization, "/api/v2/contracts", {contract: create_params, expand: %w[applied_rate_cards]}) }

      it "returns a not supported error and creates nothing" do
        expect { subject }.not_to change(Contract, :count)

        expect(response).to have_http_status(:bad_request)
        expect(json[:error_details]).to eq(expand: {reason: "show_only", invalid_values: %w[applied_rate_cards]})
      end
    end

    context "with invoicing settings" do
      let(:create_params) { super().merge(consolidate_invoice: false, purchase_order_number: "PO-111") }

      it "persists and returns the settings used to group invoices" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract]).to include(consolidate_invoice: false, purchase_order_number: "PO-111")
        expect(organization.contracts.find_by!(external_id: "contract-1")).to have_attributes(
          consolidate_invoice: false, purchase_order_number: "PO-111"
        )
      end
    end

    context "with invoice custom sections" do
      let(:section) { create(:invoice_custom_section, organization:) }
      let(:create_params) { super().merge(invoice_custom_section: {invoice_custom_section_codes: [section.code]}) }

      it "attaches the sections, without embedding them" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract][:skip_invoice_custom_sections]).to be(false)
        expect(json[:contract].keys).to eq(flat_keys)
        expect(Contract.find(json[:contract][:lago_id]).selected_invoice_custom_sections).to eq([section])
      end
    end

    context "without a plan" do
      let(:create_params) { {external_customer_id: customer.external_id, external_id: "contract-1"} }

      it "creates a plan-less contract" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract][:plan_code]).to be_nil
        expect(Contract.find(json[:contract][:lago_id]).applied_rate_cards).to be_empty
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

    context "with an applied rate card" do
      before { create(:contract_rate_card, organization:, contract:) }

      it "lists the flat active contracts" do
        subject

        expect(response).to have_http_status(:success)
        result = json[:contracts].sole
        expect(result[:lago_id]).to eq(contract.id)
        expect(result.keys).to eq(flat_keys)
        expect(result).to be_a_flat_v2_payload
        expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil)
      end
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :contracts, model: Contract do
      let(:paginated_path) { "/api/v2/contracts" }
      # A customer and a plan per contract, so that a page missing their preload makes more queries.
      let(:create_paginated_record) do
        lambda do |created_at|
          create(:contract, organization:, customer: create(:customer, organization:), catalog_plan: create(:catalog_plan, organization:), created_at:)
        end
      end
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
    subject { get_with_token(organization, "/api/v2/contracts/#{contract.external_id}", params) }

    let!(:contract) { create(:contract, organization:, customer:, catalog_plan:) }
    let(:params) { {} }

    include_examples "requires API permission", "contract", "read"

    context "with invoicing settings" do
      let(:contract) do
        create(:contract, organization:, customer:, catalog_plan:, consolidate_invoice: false, purchase_order_number: "PO-222")
      end

      it "returns the persisted settings" do
        subject

        expect(json[:contract]).to include(consolidate_invoice: false, purchase_order_number: "PO-222")
      end
    end

    context "without a billing anchor" do
      let(:contract) { create(:contract, organization:, customer:, catalog_plan:, started_at: Time.zone.parse("2026-10-01")) }

      it "returns the start day as the effective anchor" do
        subject

        expect(json[:contract]).to include(billing_anchor_date: nil, effective_billing_anchor_date: "2026-10-01")
      end
    end

    context "with an applied rate card" do
      before { create(:contract_rate_card, organization:, contract:) }

      it "returns the flat contract" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract][:lago_id]).to eq(contract.id)
        expect(json[:contract].keys).to eq(flat_keys)
        expect(json[:contract]).to be_a_flat_v2_payload
      end
    end

    context "with expand[]=applied_rate_cards" do
      let(:params) { {expand: %w[applied_rate_cards]} }

      context "with an applied rate card" do
        let!(:applied_rate_card) { create(:contract_rate_card, organization:, contract:) }

        it "embeds the flat applied rate cards, with a null deleted_at" do
          subject

          expect(json[:contract].keys).to eq([*flat_keys, :applied_rate_cards])
          # A contract is never deleted, while its applied rate cards are.
          expect(json[:contract][:applied_rate_cards].sole).to include(lago_id: applied_rate_card.id, deleted_at: nil)
          expect(json[:contract][:applied_rate_cards]).to all(be_a_flat_v2_payload)
        end
      end

      context "with applied rate cards sharing created_at" do
        let(:created_at) { Time.zone.parse("2026-09-28T10:00:00.000001Z") }

        # Ties to the microsecond, created out of order, next to cards neither list may show.
        before do
          [1, 0, 2, 1, 0, 1].each { create(:contract_rate_card, organization:, contract:, created_at: created_at - it.seconds) }
          create(:contract_rate_card, organization:, contract:, created_at:).discard!
          create(:contract_rate_card, organization:, created_at:)
          sibling = create(:contract, :terminated, organization:, customer:, external_id: contract.external_id, started_at: 2.months.ago)
          create(:contract_rate_card, organization:, contract: sibling, created_at:)
        end

        it "embeds every page of /applied_rate_cards, in its order" do
          listed = []
          page_params = {limit: 2}
          while page_params
            get_with_token(organization, "/api/v2/contracts/#{contract.external_id}/applied_rate_cards", page_params)
            listed.concat(json[:applied_rate_cards])
            page_params = json[:meta][:next_cursor] && {limit: 2, after: json[:meta][:next_cursor]}
          end

          subject

          expect(listed.size).to eq(6)
          expect(json[:contract][:applied_rate_cards]).to eq(listed)
        end
      end
    end

    context "with expand[]=plan" do
      let(:params) { {expand: %w[plan]} }

      it "embeds the flat plan as its own show renders it, without its count" do
        subject
        expanded = json[:contract]
        get_with_token(organization, "/api/v2/plans/#{catalog_plan.code}")

        expect(expanded[:plan]).to eq(json[:plan])
        expect(expanded[:plan]).to include(lago_id: catalog_plan.id, deleted_at: nil)
        expect(expanded[:plan]).not_to have_key(:applied_rate_cards_count)
        expect(expanded[:plan]).to be_a_flat_v2_payload
        expect(expanded.keys.last).to eq(:plan)
      end

      context "when the plan is discarded" do
        before { catalog_plan.discard! }

        it "embeds it with its deleted_at" do
          subject

          expect(json[:contract][:plan]).to include(lago_id: catalog_plan.id, deleted_at: catalog_plan.reload.deleted_at.iso8601)
        end
      end

      context "without a plan" do
        let(:catalog_plan) { nil }

        it "renders a null plan" do
          subject

          expect(json[:contract]).to include(plan_code: nil, plan: nil)
        end
      end
    end

    context "with expand[]=customer" do
      let(:params) { {expand: %w[customer]} }
      # The v2 customer has no endpoint of its own, so its serializer is the reference.
      let(:customer_payload) { JSON.parse(V2::CustomerSerializer.new(customer, includes: %i[deleted_at]).serialize.to_json, symbolize_names: true) }

      it "embeds the flat customer, with a null deleted_at" do
        subject

        expect(json[:contract][:customer]).to eq(customer_payload)
        expect(json[:contract][:customer]).to include(lago_id: customer.id, external_id: customer.external_id, deleted_at: nil)
        expect(json[:contract][:customer]).to be_a_flat_v2_payload
        expect(json[:contract].keys.last).to eq(:customer)
      end

      context "when the customer is discarded" do
        before { customer.discard! }

        it "embeds it with its deleted_at" do
          subject

          expect(json[:contract][:customer]).to include(lago_id: customer.id, deleted_at: customer.reload.deleted_at.iso8601)
        end
      end
    end

    context "with expand[]=invoice_custom_sections" do
      let(:params) { {expand: %w[invoice_custom_sections]} }
      let(:sections) { create_list(:invoice_custom_section, 2, organization:) }

      # Selected in the reverse order of their creation, so that only the selection order passes.
      before do
        sections.reverse_each { create(:contract_applied_invoice_custom_section, organization:, contract:, invoice_custom_section: it) }
      end

      it "embeds the flat sections, the last selected first, with a null deleted_at" do
        subject

        expect(json[:contract][:invoice_custom_sections].pluck(:lago_id)).to eq(sections.map(&:id))
        expect(json[:contract][:invoice_custom_sections]).to all(be_a_flat_v2_payload.and(include(deleted_at: nil)))
        expect(json[:contract].keys).to eq([*flat_keys, :invoice_custom_sections])
      end

      context "with a section deleted while the contract still links it" do
        before { sections.last.discard! }

        it "leaves it out" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:contract][:invoice_custom_sections].pluck(:lago_id)).to eq([sections.first.id])
        end
      end
    end

    context "with every expansion" do
      let(:params) { {expand: %w[applied_rate_cards plan customer invoice_custom_sections]} }
      # The shape of the contract above, with three applied rate cards and sections instead of one.
      let(:larger_contract) { create(:contract, organization:, customer:, catalog_plan:) }

      before do
        create(:contract_rate_card, organization:, contract:)
        create(:contract_applied_invoice_custom_section, organization:, contract:)
        create_list(:contract_rate_card, 3, organization:, contract: larger_contract)
        create_list(:contract_applied_invoice_custom_section, 3, organization:, contract: larger_contract)
      end

      def show_queries(contract)
        capture_counted_queries { get_with_token(organization, "/api/v2/contracts/#{contract.external_id}", params) }
      end

      it "runs as many queries for a contract of three applied rate cards and sections as for one of each" do
        # A first request can run lookups the process then caches.
        show_queries(contract)

        one_card_queries = show_queries(contract)
        three_cards_queries = show_queries(larger_contract)

        expect(json[:contract].keys).to eq([*flat_keys, :applied_rate_cards, :plan, :customer, :invoice_custom_sections])
        expect(json[:contract][:applied_rate_cards].size).to eq(3)
        expect(json[:contract][:invoice_custom_sections].size).to eq(3)
        expect(three_cards_queries.size).to eq(one_card_queries.size)
      end
    end

    context "with expand[]=rates" do
      let(:params) { {expand: %w[rates]} }

      it "returns an invalid expand error listing the allowed expansions" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(
          status: 400,
          error: "Bad Request",
          code: "invalid_expand",
          error_details: {expand: {invalid_values: %w[rates], allowed_values: %w[applied_rate_cards plan customer invoice_custom_sections]}}
        )
      end
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

    it "updates the contract and returns it flat" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:contract][:external_id]).to eq(contract.external_id)
      expect(json[:contract][:name]).to eq("Renamed")
      expect(json[:contract].keys).to eq(flat_keys)
    end

    context "with expand" do
      subject { put_with_token(organization, "/api/v2/contracts/#{contract.external_id}", {contract: update_params, expand: %w[applied_rate_cards]}) }

      it "returns a not supported error and updates nothing" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:error_details]).to eq(expand: {reason: "show_only", invalid_values: %w[applied_rate_cards]})
        expect(contract.reload.name).to be_nil
      end
    end

    context "when skipping invoice custom sections" do
      let(:update_params) { {invoice_custom_section: {skip_invoice_custom_sections: true}} }

      before { create(:contract_applied_invoice_custom_section, organization:, contract:) }

      it "flags the contract and removes the attached sections" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract][:skip_invoice_custom_sections]).to be(true)
        expect(contract.reload.selected_invoice_custom_sections).to be_empty
      end
    end

    context "when changing the plan" do
      let(:other_plan) { create(:catalog_plan, organization:) }
      let(:update_params) { {plan_code: other_plan.code} }
      let(:rate_card) { create(:rate_card, organization:) }

      before { create(:plan_rate_card, organization:, catalog_plan: other_plan, rate_card:, units: 4) }

      it "re-materializes the rate cards from the new plan" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract][:plan_code]).to eq(other_plan.code)
        expect(contract.reload.applied_rate_cards.sole.rate_card).to eq(rate_card)
      end
    end

    context "when the contract is already active" do
      let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }

      it "updates the fields that stay editable" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract][:name]).to eq("Renamed")
      end

      context "with invoicing settings" do
        let(:update_params) { {consolidate_invoice: false, purchase_order_number: "PO-222"} }

        it "persists and returns both settings" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:contract]).to include(consolidate_invoice: false, purchase_order_number: "PO-222")
          expect(contract.reload).to have_attributes(consolidate_invoice: false, purchase_order_number: "PO-222")
        end

        context "when clearing the purchase order" do
          let(:contract) { create(:contract, organization:, customer:, catalog_plan:, purchase_order_number: "PO-111") }
          let(:update_params) { {purchase_order_number: nil} }

          it "clears the stored purchase order without changing consolidation" do
            subject

            expect(json[:contract]).to include(consolidate_invoice: true, purchase_order_number: nil)
            expect(contract.reload).to have_attributes(consolidate_invoice: true, purchase_order_number: nil)
          end
        end
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

  describe "DELETE /api/v2/contracts/:external_id" do
    subject { delete_with_token(organization, "/api/v2/contracts/#{contract.external_id}") }

    let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }

    include_examples "requires API permission", "contract", "write"

    it "terminates the active contract and returns it flat" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:contract][:external_id]).to eq(contract.external_id)
      expect(json[:contract][:status]).to eq("terminated")
      expect(json[:contract].keys).to eq(flat_keys)
    end

    context "with expand" do
      subject { delete_with_token(organization, "/api/v2/contracts/#{contract.external_id}?expand[]=applied_rate_cards") }

      it "returns a not supported error and keeps the contract active" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:error_details]).to eq(expand: {reason: "show_only", invalid_values: %w[applied_rate_cards]})
        expect(contract.reload).to be_active
      end
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

  # applied_rate_cards_count left the payload: the total count of the contract's applied rate cards replaces it.
  describe "GET /api/v2/contracts/:external_id/applied_rate_cards?include_total_count=true" do
    subject { get_with_token(organization, "/api/v2/contracts/#{contract.external_id}/applied_rate_cards", {include_total_count: true}) }

    let(:contract) { create(:contract, organization:, customer:) }
    # The count the payload rendered: the contract's kept applied rate cards.
    let(:former_applied_rate_cards_count) { contract.applied_rate_cards.count }

    before do
      create_list(:contract_rate_card, 2, organization:, contract:)
      create(:contract_rate_card, organization:, contract:).discard!
      create(:contract_rate_card, organization:)
      sibling = create(:contract, :terminated, organization:, customer:, external_id: contract.external_id, started_at: 2.months.ago)
      create(:contract_rate_card, organization:, contract: sibling)
    end

    it "equals the applied_rate_cards_count the payload rendered" do
      subject

      expect(json[:meta][:total_count]).to eq(2)
      expect(json[:meta][:total_count]).to eq(former_applied_rate_cards_count)
    end
  end
end
